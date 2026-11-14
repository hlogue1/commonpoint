// SPDX-License-Identifier: GPL-3.0-or-later

package store

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/hlogue1/commonpoint/internal/platform/db/migratetest"
)

const testActor = `{"issuer":"https://idp.test","subject":"user-a","client_id":"ctl","display":"User A","scopes":["terms.activate"]}`

// T5: an activation made through the API path records the actor, before/after status, a
// DB-clock timestamp and an activation-log row.
func TestAuditActivationRecordsActor(t *testing.T) {
	ctx := context.Background()
	conn := migrated(t).Connect(t, migratetest.RoleMigrations)
	v1 := newVersion(t, conn, "loinc", "2.80", "")

	tx, err := conn.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	start := scalar[time.Time](t, conn, `SELECT clock_timestamp()`)
	for k, v := range map[string]string{"terms.actor": testActor, "terms.request_id": "req-1", "terms.reason": "go live"} {
		if _, err := tx.Exec(ctx, `SELECT set_config($1, $2, true)`, k, v); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := tx.Exec(ctx, `SELECT activate_version($1)`, v1); err != nil {
		t.Fatal(err)
	}
	if err := tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}

	var (
		source, requestID, reason, before, after string
		actor, target                            json.RawMessage
		at                                       time.Time
	)
	err = conn.QueryRow(ctx, `
SELECT source, actor, request_id, reason, target, before ->> 'status', after ->> 'status', at
FROM terms_audit_event
WHERE target_table = 'code_system_version' AND action = 'update' AND after ->> 'status' = 'active'`).
		Scan(&source, &actor, &requestID, &reason, &target, &before, &after, &at)
	if err != nil {
		t.Fatal(err)
	}
	if source != "api" || requestID != "req-1" || reason != "go live" || before != "staged" || after != "active" {
		t.Fatalf("got source=%s request_id=%s reason=%s status %s->%s", source, requestID, reason, before, after)
	}
	var a map[string]any
	_ = json.Unmarshal(actor, &a)
	if a["subject"] != "user-a" {
		t.Fatalf("actor = %s", actor)
	}
	var tg map[string]any
	_ = json.Unmarshal(target, &tg)
	if tg["code_system_id"] != "loinc" || tg["version"] != "2.80" || tg["source_sha256"] == nil || tg["id"] != nil {
		t.Fatalf("target = %s", target)
	}
	if at.Before(start) {
		t.Fatalf("at %v is before the transaction started (%v)", at, start)
	}

	if n := scalar[int](t, conn, `
SELECT count(*) FROM version_activation_log
WHERE to_version_id = $1 AND action = 'activate' AND actor ->> 'subject' = 'user-a' AND request_id = 'req-1'`, v1); n != 1 {
		t.Fatalf("activation log rows = %d, want 1", n)
	}
	if s := scalar[string](t, conn, `SELECT activated_by ->> 'subject' FROM code_system_version WHERE id = $1`, v1); s != "user-a" {
		t.Fatalf("activated_by subject = %q", s)
	}
}

// T5: a change made outside the API (no terms.actor, e.g. psql) is still captured, as source
// 'db' with the DB role as the actor.
func TestAuditDirectChangeRecordsDBRole(t *testing.T) {
	conn := migrated(t).Connect(t, migratetest.RoleSuper)
	exec(t, conn, `INSERT INTO code_system_enablement (code_system_id, enabled, license_reference)
	               VALUES ('cpt', true, 'AMA agreement 42')
	               ON CONFLICT (code_system_id) DO UPDATE SET enabled = true, license_reference = 'AMA agreement 42'`)

	var source, role string
	if err := conn.QueryRow(context.Background(), `
SELECT source, actor ->> 'db_role' FROM terms_audit_event
WHERE target_table = 'code_system_enablement' AND target ->> 'code_system_id' = 'cpt'
ORDER BY at DESC LIMIT 1`).Scan(&source, &role); err != nil {
		t.Fatal(err)
	}
	if source != "db" || role != migratetest.RoleSuper {
		t.Fatalf("source=%s role=%s", source, role)
	}
}

// T5: terms_audit_event is append-only for every role, including the owner.
func TestAuditEventIsAppendOnly(t *testing.T) {
	db := migrated(t)
	owner := db.Connect(t, migratetest.RoleMigrations)
	newVersion(t, owner, "loinc", "2.80", "")

	for _, role := range []string{migratetest.RoleMigrations, migratetest.RoleImport, migratetest.RoleApp} {
		conn := db.Connect(t, role)
		for _, sql := range []string{
			`UPDATE terms_audit_event SET reason = 'x'`,
			`DELETE FROM terms_audit_event`,
			`TRUNCATE terms_audit_event`,
		} {
			if _, err := conn.Exec(context.Background(), sql); err == nil {
				t.Errorf("%s as %s: succeeded, want an error", sql, role)
			}
		}
	}
	if n := scalar[int](t, owner, `SELECT count(*) FROM terms_audit_event`); n == 0 {
		t.Fatal("audit rows disappeared")
	}
}

// T5: denied attempts are recorded through record_denied_attempt.
func TestAuditDeniedAttempt(t *testing.T) {
	conn := migrated(t).Connect(t, migratetest.RoleMigrations)
	exec(t, conn, `SELECT record_denied_attempt($1::jsonb, 'req-9', 'AdminService/ActivateVersion', 'missing scope terms.activate')`, testActor)
	if n := scalar[int](t, conn, `SELECT count(*) FROM terms_audit_event
	    WHERE outcome = 'denied' AND target ->> 'rpc' = 'AdminService/ActivateVersion' AND actor ->> 'subject' = 'user-a'`); n != 1 {
		t.Fatalf("denied rows = %d", n)
	}
}

// T5: a new version must carry its source checksum, and its natural identity can't change.
func TestVersionIdentity(t *testing.T) {
	conn := migrated(t).Connect(t, migratetest.RoleMigrations)
	execErr(t, conn, "source_sha256_required",
		`INSERT INTO code_system_version (code_system_id, version) VALUES ('loinc', '2.81')`)
	execErr(t, conn, "check constraint",
		`INSERT INTO code_system_version (code_system_id, version, source_sha256) VALUES ('loinc', '2.81', 'nothex')`)
	v := newVersion(t, conn, "loinc", "2.81", "")
	execErr(t, conn, "immutable", `UPDATE code_system_version SET source_sha256 = $2 WHERE id = $1`, v, fakeSHA("other"))
	execErr(t, conn, "immutable", `UPDATE code_system_version SET version = '2.82' WHERE id = $1`, v)
}
