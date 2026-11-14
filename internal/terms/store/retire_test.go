// SPDX-License-Identifier: GPL-3.0-or-later

package store

import (
	"strings"
	"testing"

	"github.com/jackc/pgx/v5"

	"github.com/hlogue1/commonpoint/internal/platform/db/migratetest"
)

// partitionName is the loader's naming convention: <table>_<version id without dashes>.
func partitionName(table, versionID string) string {
	return table + "_" + strings.ReplaceAll(versionID, "-", "")
}

// attachEmptyPartition creates and attaches an empty partition of table for versionID,
// following the load pattern in 002_snomed.sql (minus COPY).
func attachEmptyPartition(t *testing.T, conn *pgx.Conn, table, versionID string) string {
	t.Helper()
	p := partitionName(table, versionID)
	exec(t, conn, `CREATE TABLE `+p+` (LIKE `+table+` INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING GENERATED)`)
	exec(t, conn, `ALTER TABLE `+p+` ADD CHECK (version_id = '`+versionID+`')`)
	exec(t, conn, `ALTER TABLE `+table+` ATTACH PARTITION `+p+` FOR VALUES IN ('`+versionID+`')`)
	return p
}

// T2: deleting a version with attached partitions is refused; once they're retired it succeeds.
func TestVersionDeleteRefusedWhilePartitionsExist(t *testing.T) {
	conn := migrated(t).Connect(t, migratetest.RoleMigrations)
	v := newVersion(t, conn, "snomed", "20260901", "")
	exec(t, conn, `INSERT INTO snomed_release (version_id) VALUES ($1)`, v)
	p := attachEmptyPartition(t, conn, "snomed_closure", v)

	execErr(t, conn, "retire it via ctl terms clean", `DELETE FROM code_system_version WHERE id = $1`, v)

	exec(t, conn, `ALTER TABLE snomed_closure DETACH PARTITION `+p)
	exec(t, conn, `DROP TABLE `+p)
	exec(t, conn, `DELETE FROM code_system_version WHERE id = $1`, v)
}

// T2: unpartitioned small systems still retire by deleting the version, which cascades.
func TestVersionDeleteCascadesForUnpartitionedSystem(t *testing.T) {
	conn := migrated(t).Connect(t, migratetest.RoleMigrations)
	v := newVersion(t, conn, "cvx", "2026-11", "")
	exec(t, conn, `INSERT INTO cvx_release (version_id) VALUES ($1)`, v)
	exec(t, conn, `INSERT INTO cvx_vaccine (version_id, code, short_desc, full_name, status) VALUES ($1, '999', 'test', 'test vaccine', 'active')`, v)
	exec(t, conn, `DELETE FROM code_system_version WHERE id = $1`, v)
	if n := scalar[int](t, conn, `SELECT count(*) FROM cvx_vaccine`); n != 0 {
		t.Fatalf("cvx_vaccine rows left: %d", n)
	}
}
