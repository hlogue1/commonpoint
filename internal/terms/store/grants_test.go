// SPDX-License-Identifier: GPL-3.0-or-later

package store

import (
	"testing"

	"github.com/hlogue1/commonpoint/internal/platform/db/migratetest"
)

// T6: the app role reads, and changes versions and enablement only through the functions.
func TestAppRoleGrants(t *testing.T) {
	db := migrated(t)
	owner := db.Connect(t, migratetest.RoleMigrations)
	app := db.Connect(t, migratetest.RoleApp)
	v := newVersion(t, owner, "loinc", "2.80", "")

	execErr(t, app, "permission denied", `UPDATE code_system_version SET status = 'active' WHERE id = $1`, v)
	execErr(t, app, "permission denied", `DELETE FROM code_system_version WHERE id = $1`, v)
	execErr(t, app, "permission denied", `INSERT INTO code_system_enablement (code_system_id, enabled) VALUES ('ucum', true)`)
	execErr(t, app, "permission denied", `INSERT INTO terms_audit_event (source, actor, action, target_table, target) VALUES ('api', '{}', 'x', 'x', '{}')`)
	execErr(t, app, "permission denied", `SELECT terms_activate($1, 'activate')`, v)

	exec(t, app, `SELECT activate_version($1)`, v)
	if got := scalar[string](t, app, `SELECT version FROM active_version WHERE code_system_id = 'loinc'`); got != "2.80" {
		t.Fatalf("active loinc = %s", got)
	}
	exec(t, app, `SELECT set_enablement('ucum', false, NULL)`)
	exec(t, app, `SELECT record_denied_attempt('{"subject":"x"}', 'r', 'AdminService/InstallVersion', 'missing scope')`)

	// SECURITY DEFINER doesn't hide the caller: the audit row names the app's session role.
	if got := scalar[string](t, owner, `SELECT actor ->> 'db_role' FROM terms_audit_event
	    WHERE target_table = 'code_system_enablement' AND target ->> 'code_system_id' = 'ucum'
	    ORDER BY at DESC LIMIT 1`); got != migratetest.RoleApp {
		t.Fatalf("enablement change attributed to %q", got)
	}
}

// T6: the import role registers versions, owns partitions it creates, and can't change status.
func TestImportRoleLifecycle(t *testing.T) {
	db := migrated(t)
	imp := db.Connect(t, migratetest.RoleImport)
	app := db.Connect(t, migratetest.RoleApp)

	v := newVersion(t, imp, "snomed", "20260901", "")
	exec(t, imp, `UPDATE code_system_version SET validated_at = now() WHERE id = $1`, v)
	execErr(t, imp, "permission denied", `UPDATE code_system_version SET status = 'active' WHERE id = $1`, v)

	exec(t, imp, `INSERT INTO snomed_release (version_id) VALUES ($1)`, v)
	p := attachEmptyPartition(t, imp, "snomed_closure", v)
	exec(t, imp, `INSERT INTO snomed_closure (version_id, ancestor_id, descendant_id, depth) VALUES ($1, 138875005, 404684003, 1)`, v)
	execErr(t, imp, "permission denied", `TRUNCATE snomed_closure`)
	execErr(t, imp, "permission denied", `UPDATE cvx_vaccine SET full_name = 'x'`)

	if n := scalar[int](t, app, `SELECT count(*) FROM snomed_closure WHERE version_id = $1`, v); n != 1 {
		t.Fatalf("app sees %d closure rows via the parent", n)
	}
	if n := scalar[int](t, app, `SELECT count(*) FROM `+p); n != 1 {
		t.Fatalf("app sees %d rows in the partition", n)
	}

	exec(t, imp, `ALTER TABLE snomed_closure DETACH PARTITION `+p)
	exec(t, imp, `DROP TABLE `+p)
	exec(t, imp, `DELETE FROM code_system_version WHERE id = $1`, v)
}
