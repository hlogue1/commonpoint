// SPDX-License-Identifier: GPL-3.0-or-later

package store

import (
	"testing"

	"github.com/hlogue1/commonpoint/internal/platform/db/migratetest"
)

// T7: every code system has an enablement row; open tiers are enabled, restricted ones aren't,
// and enabling a restricted system needs a license reference.
func TestEnablementSeedAndLicenseGate(t *testing.T) {
	db := migrated(t)
	owner := db.Connect(t, migratetest.RoleMigrations)
	app := db.Connect(t, migratetest.RoleApp)

	if n := scalar[int](t, owner, `SELECT count(*) FROM code_system cs
	    LEFT JOIN code_system_enablement e ON e.code_system_id = cs.id
	    WHERE e.code_system_id IS NULL OR e.enabled <> (cs.license_tier_id = 'open')`); n != 0 {
		t.Fatalf("%d code systems are missing or mis-seeded", n)
	}
	if !scalar[bool](t, owner, `SELECT enabled FROM code_system_enablement WHERE code_system_id = 'loinc'`) {
		t.Fatal("loinc (open) is not enabled")
	}
	if scalar[bool](t, owner, `SELECT enabled FROM code_system_enablement WHERE code_system_id = 'cpt'`) {
		t.Fatal("cpt (ama_cpt) is enabled")
	}

	execErr(t, app, "requires a license_reference", `SELECT set_enablement('cpt', true, NULL)`)
	execErr(t, app, "requires a license_reference", `SELECT set_enablement('cpt', true, '  ')`)
	exec(t, app, `SELECT set_enablement('cpt', true, 'AMA license 2026-123')`)
	exec(t, app, `SELECT set_enablement('cpt', false, NULL)`)
}

// T7: lookup() answers for an enabled open system once a version is active.
func TestLookupAfterSeed(t *testing.T) {
	conn := migrated(t).Connect(t, migratetest.RoleMigrations)
	v := newVersion(t, conn, "cvx", "2026-11", "")
	exec(t, conn, `INSERT INTO cvx_release (version_id) VALUES ($1)`, v)
	exec(t, conn, `INSERT INTO cvx_vaccine (version_id, code, short_desc, full_name, status) VALUES ($1, '999', 'test', 'Synthetic test vaccine', 'active')`, v)
	exec(t, conn, `SELECT activate_version($1)`, v)
	if got := scalar[string](t, conn, `SELECT display FROM lookup('cvx', '999')`); got != "Synthetic test vaccine" {
		t.Fatalf("lookup display = %q", got)
	}
}

// C4: NANDA-I and NIC/NOC are tracked under their own licensors' tiers.
func TestNursingLicenseTiers(t *testing.T) {
	conn := migrated(t).Connect(t, migratetest.RoleMigrations)
	got := scalar[string](t, conn, `SELECT string_agg(id || '=' || license_tier_id, ',' ORDER BY id) FROM code_system WHERE id IN ('nanda', 'nic', 'noc')`)
	if got != "nanda=nanda_i,nic=elsevier,noc=elsevier" {
		t.Fatalf("tiers: %s", got)
	}
	if n := scalar[int](t, conn, `SELECT count(*) FROM license_tier_option WHERE id = 'nanda_elsevier'`); n != 0 {
		t.Fatal("nanda_elsevier tier still exists")
	}
}
