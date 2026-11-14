// SPDX-License-Identifier: GPL-3.0-or-later

package store

import (
	"testing"

	"github.com/jackc/pgx/v5"

	"github.com/hlogue1/commonpoint/internal/platform/db/migratetest"
)

func resolveICD(t *testing.T, conn *pgx.Conn, date string) string {
	t.Helper()
	return scalar[string](t, conn, `SELECT COALESCE(version_for_date_by_id('icd10cm', $1::date)::text, '')`, date)
}

func status(t *testing.T, conn *pgx.Conn, id string) string {
	t.Helper()
	return scalar[string](t, conn, `SELECT status::text || ' ' || COALESCE(validity::text, '-') FROM code_system_version WHERE id = $1`, id)
}

// T3: May 2027 resolves to FY2027 after rolling back the April update, and the April update
// can be activated again afterwards.
func TestRollbackRestoresPublishedValidity(t *testing.T) {
	conn := migrated(t).Connect(t, migratetest.RoleMigrations)
	fy26 := newVersion(t, conn, "icd10cm", "2026", "[2025-10-01,2026-10-01)")
	fy27 := newVersion(t, conn, "icd10cm", "2027", "[2026-10-01,2027-10-01)")
	apr := newVersion(t, conn, "icd10cm", "2027-04", "[2027-04-01,2027-10-01)")

	exec(t, conn, `SELECT activate_version($1)`, fy26)
	exec(t, conn, `SELECT activate_version($1)`, fy27)
	exec(t, conn, `SELECT activate_version($1)`, apr)
	if got := resolveICD(t, conn, "2027-05-01"); got != apr {
		t.Fatalf("after April update, May 2027 -> %s, want 2027-04", got)
	}
	if got := status(t, conn, fy27); got != "superseded [2026-10-01,2027-04-01)" {
		t.Fatalf("FY2027 after April update: %s", got)
	}

	back := scalar[string](t, conn, `SELECT rollback_version('icd10cm')::text`)
	if back != fy27 {
		t.Fatalf("rollback re-activated %s, want FY2027", back)
	}
	if got := resolveICD(t, conn, "2027-05-01"); got != fy27 {
		t.Fatalf("after rollback, May 2027 -> %s, want FY2027 (%s)", got, fy27)
	}
	if got := resolveICD(t, conn, "2026-05-01"); got != fy26 {
		t.Fatalf("after rollback, May 2026 -> %s, want FY2026", got)
	}
	if got := status(t, conn, fy27); got != "active [2026-10-01,2027-10-01)" {
		t.Fatalf("FY2027 after rollback: %s", got)
	}
	if got := status(t, conn, apr); got != "staged [2027-04-01,2027-10-01)" {
		t.Fatalf("2027-04 after rollback: %s", got)
	}
	if n := scalar[int](t, conn, `SELECT count(*) FROM version_activation_log
	    WHERE action = 'rollback' AND from_version_id = $1 AND to_version_id = $2`, apr, fy27); n != 1 {
		t.Fatalf("rollback log rows = %d", n)
	}

	// Activate the April update again: same answers as the first time.
	exec(t, conn, `SELECT activate_version($1)`, apr)
	if got := resolveICD(t, conn, "2027-05-01"); got != apr {
		t.Fatalf("after re-activation, May 2027 -> %s, want 2027-04", got)
	}
	if got := resolveICD(t, conn, "2027-01-15"); got != fy27 {
		t.Fatalf("after re-activation, Jan 2027 -> %s, want FY2027", got)
	}

	// Rolling back twice walks back through the activations: 2027-04 -> FY2027 -> FY2026.
	exec(t, conn, `SELECT rollback_version('icd10cm')`)
	exec(t, conn, `SELECT rollback_version('icd10cm')`)
	if got := resolveICD(t, conn, "2026-05-01"); got != fy26 {
		t.Fatalf("after second rollback, May 2026 -> %s, want FY2026", got)
	}
	if got := status(t, conn, fy26); got != "active [2025-10-01,2026-10-01)" {
		t.Fatalf("FY2026 after second rollback: %s", got)
	}
	execErr(t, conn, "nothing to roll back to", `SELECT rollback_version('icd10cm')`)
}

// T3: published_validity is set at insert and never changes; validity stays inside it.
func TestPublishedValidityImmutable(t *testing.T) {
	conn := migrated(t).Connect(t, migratetest.RoleMigrations)
	v := newVersion(t, conn, "icd10cm", "2027", "[2026-10-01,2027-10-01)")
	if got := scalar[string](t, conn, `SELECT published_validity::text FROM code_system_version WHERE id = $1`, v); got != "[2026-10-01,2027-10-01)" {
		t.Fatalf("published_validity = %s", got)
	}
	execErr(t, conn, "immutable", `UPDATE code_system_version SET published_validity = '[2026-10-01,2028-10-01)' WHERE id = $1`, v)
	execErr(t, conn, "code_system_version_published_validity", `UPDATE code_system_version SET validity = '[2026-01-01,2027-10-01)' WHERE id = $1`, v)
}

// T3: rollback on an undated system works the same way.
func TestRollbackUndated(t *testing.T) {
	conn := migrated(t).Connect(t, migratetest.RoleMigrations)
	a := newVersion(t, conn, "loinc", "2.80", "")
	b := newVersion(t, conn, "loinc", "2.81", "")
	execErr(t, conn, "no active version", `SELECT rollback_version('loinc')`)
	exec(t, conn, `SELECT activate_version($1)`, a)
	exec(t, conn, `SELECT activate_version($1)`, b)
	exec(t, conn, `SELECT rollback_version('loinc')`)
	if got := scalar[string](t, conn, `SELECT version_for_date_by_id('loinc', '2027-01-01')::text`); got != a {
		t.Fatalf("after rollback loinc -> %s, want 2.80", got)
	}
	if got := status(t, conn, b); got != "staged -" {
		t.Fatalf("2.81 after rollback: %s", got)
	}
}

// B4: a version that hasn't passed validation can't be activated.
func TestActivationRequiresValidation(t *testing.T) {
	conn := migrated(t).Connect(t, migratetest.RoleMigrations)
	v := newVersion(t, conn, "loinc", "2.82", "")
	exec(t, conn, `UPDATE code_system_version SET validated_at = NULL WHERE id = $1`, v)
	execErr(t, conn, "has not passed validation", `SELECT activate_version($1)`, v)
	exec(t, conn, `UPDATE code_system_version SET validated_at = '2026-11-02 00:00:00+00' WHERE id = $1`, v)
	exec(t, conn, `SELECT activate_version($1)`, v)
}
