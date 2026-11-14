// SPDX-License-Identifier: GPL-3.0-or-later

package store

import (
	"testing"

	"github.com/jackc/pgx/v5"

	"github.com/hlogue1/commonpoint/internal/platform/db/migratetest"
)

func billingRelease(t *testing.T, conn *pgx.Conn, system, version, validity string) string {
	t.Helper()
	v := newVersion(t, conn, system, version, validity)
	exec(t, conn, `INSERT INTO `+system+`_release (version_id) VALUES ($1)`, v)
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
