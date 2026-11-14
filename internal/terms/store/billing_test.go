// SPDX-License-Identifier: GPL-3.0-or-later

package store

import (
	"testing"

	"github.com/jackc/pgx/v5"

	"github.com/hlogue1/commonpoint/internal/platform/db/migratetest"
)

// releaseTable maps a code system to its <prefix>_release table where the prefix differs.
var releaseTable = map[string]string{"icd10cm": "icd10_release", "icd10pcs": "icd_pcs_release"}

func billingRelease(t *testing.T, conn *pgx.Conn, system, version, validity string) string {
	t.Helper()
	v := newVersion(t, conn, system, version, validity)
	table, ok := releaseTable[system]
	if !ok {
		table = system + "_release"
	}
	exec(t, conn, `INSERT INTO `+table+` (version_id) VALUES ($1)`, v)
	return v
}

// C8: Administrative MAAA codes have their own category, and every category matches its code shape.
func TestCPTCategories(t *testing.T) {
	conn := migrated(t).Connect(t, migratetest.RoleMigrations)
	v := billingRelease(t, conn, "cpt", "2027", "[2027-01-01,2028-01-01)")
	const ins = `INSERT INTO cpt_code (version_id, code, category, long_descriptor) VALUES ($1, $2, $3, 'Synthetic descriptor')`
	for _, ok := range [][2]string{{"99999", "I"}, {"9999F", "II"}, {"9999T", "III"}, {"9999U", "PLA"}, {"9999M", "MAAA"}} {
		exec(t, conn, ins, v, ok[0], ok[1])
	}
	execErr(t, conn, "cpt_code_category_matches_code", ins, v, "9998M", "I")
	execErr(t, conn, "cpt_code_category_matches_code", ins, v, "99998", "MAAA")
}

// C9: CDT content (D-codes) can't be stored under HCPCS.
func TestHCPCSRejectsCDTCodes(t *testing.T) {
	conn := migrated(t).Connect(t, migratetest.RoleMigrations)
	v := billingRelease(t, conn, "hcpcs", "2027-01", "[2027-01-01,2027-04-01)")
	const ins = `INSERT INTO hcpcs_code (version_id, code, short_desc, long_desc) VALUES ($1, $2, 'Synthetic', 'Synthetic code')`
	exec(t, conn, ins, v, "A9999")
	execErr(t, conn, "hcpcs_code_not_cdt", ins, v, "D9999")
}

// C10: a 3-character category belongs to a section, so membership in a block like E08-E13
// is answerable through parent_code -> section; the loader (import role) can write them.
func TestICD10Sections(t *testing.T) {
	db := migrated(t)
	imp := db.Connect(t, migratetest.RoleImport)
	v := billingRelease(t, imp, "icd10cm", "2027", "[2026-10-01,2027-10-01)")
	exec(t, imp, `INSERT INTO icd10_chapter (version_id, chapter, first_code, last_code, title) VALUES ($1, 4, 'E00', 'E89', 'Synthetic chapter')`, v)
	exec(t, imp, `INSERT INTO icd10_section (version_id, id, chapter, title) VALUES ($1, 'E08-E13', 4, 'Synthetic block')`, v)
	exec(t, imp, `INSERT INTO icd10_code (version_id, code, billable, short_desc, long_desc, chapter, section_id) VALUES ($1, 'E11', false, 's', 'Synthetic category', 4, 'E08-E13')`, v)
	exec(t, imp, `INSERT INTO icd10_code (version_id, code, billable, short_desc, long_desc, parent_code, chapter) VALUES ($1, 'E11.9', true, 's', 'Synthetic code', 'E11', 4)`, v)
	execErr(t, imp, "icd10_code_section_on_category",
		`INSERT INTO icd10_code (version_id, code, billable, short_desc, long_desc, chapter, section_id) VALUES ($1, 'E11.8', true, 's', 'x', 4, 'E08-E13')`, v)

	in := scalar[string](t, db.Connect(t, migratetest.RoleApp), `
WITH RECURSIVE up AS (
    SELECT code, parent_code, section_id FROM icd10_code WHERE version_id = $1 AND code = 'E11.9'
    UNION ALL
    SELECT c.code, c.parent_code, c.section_id FROM icd10_code c JOIN up ON c.code = up.parent_code AND c.version_id = $1)
SELECT s.id || ' ' || s.first_code || '..' || s.last_code
FROM up JOIN icd10_section s ON s.version_id = $1 AND s.id = up.section_id`, v)
	if in != "E08-E13 E08..E13" {
		t.Fatalf("E11.9 section = %q", in)
	}
}
