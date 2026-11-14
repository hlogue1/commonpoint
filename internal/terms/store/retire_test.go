// SPDX-License-Identifier: GPL-3.0-or-later

package store

import (
	"context"
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

// snomedAttachOrder is the dependency order from docs/terms/partition-lifecycle.md: referenced
// tables first, then the tables with no FK into another partitioned table.
var snomedAttachOrder = []string{
	"snomed_concept", "snomed_description", "snomed_relationship", "snomed_extended_map",
	"snomed_core_problem_list", "snomed_language_member",
	"snomed_relationship_concrete", "snomed_refset_member", "snomed_closure", "snomed_history",
}

// installSnomed attaches a partition of every SNOMED table for v, as the loader would, with one
// synthetic concept, description and language member so the FKs have rows to protect.
func installSnomed(t *testing.T, conn *pgx.Conn, v string) {
	t.Helper()
	exec(t, conn, `INSERT INTO snomed_release (version_id) VALUES ($1)`, v)
	for _, table := range snomedAttachOrder {
		p := partitionName(table, v)
		exec(t, conn, `CREATE TABLE `+p+` (LIKE `+table+` INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING GENERATED)`)
		exec(t, conn, `ALTER TABLE `+p+` ADD CHECK (version_id = '`+v+`')`)
		switch table {
		case "snomed_concept":
			exec(t, conn, `INSERT INTO `+p+` (version_id, id, active, module_id, fully_defined, fsn, preferred_term_en_us, semantic_tag, effective_time)
			    VALUES ($1, 138875005, true, 138875005, false, 'Synthetic root (synthetic)', 'Synthetic root', 'synthetic', '2026-09-01')`, v)
			exec(t, conn, `ALTER TABLE `+p+` ADD PRIMARY KEY (version_id, id)`)
			exec(t, conn, `ALTER TABLE `+p+` ADD CONSTRAINT `+p+`_module_fk FOREIGN KEY (version_id, module_id)
			    REFERENCES `+p+` (version_id, id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED`)
		case "snomed_description":
			exec(t, conn, `INSERT INTO `+p+` (version_id, id, concept_id, active, module_id, language_code, type, term, case_significance_id, effective_time)
			    VALUES ($1, 1000001011, 138875005, true, 138875005, 'en', 'synonym', 'Synthetic root', 900000000000448009, '2026-09-01')`, v)
		case "snomed_language_member":
			exec(t, conn, `INSERT INTO `+p+` (version_id, refset_id, description_id, acceptability, effective_time)
			    VALUES ($1, 900000000000509007, 1000001011, 'preferred', '2026-09-01')`, v)
		}
		exec(t, conn, `ALTER TABLE `+table+` ATTACH PARTITION `+p+` FOR VALUES IN ('`+v+`')`)
	}
}

func snomedPartitionCount(t *testing.T, conn *pgx.Conn, v string) int {
	t.Helper()
	return scalar[int](t, conn, `SELECT count(*) FROM pg_class
	    WHERE relname LIKE 'snomed\_%' AND relname LIKE '%' || replace($1, '-', '')`, v)
}

// T1: retiring by detaching every partition first and dropping afterwards fails; per table,
// in reverse dependency order, DETACH then DROP immediately succeeds and leaves nothing behind.
func TestSnomedRetireOrder(t *testing.T) {
	ctx := context.Background()
	db := migrated(t)
	imp := db.Connect(t, migratetest.RoleImport)
	v := newVersion(t, imp, "snomed", "20260901", "")
	installSnomed(t, imp, v)

	// The broken recipe, in a transaction we roll back.
	tx, err := imp.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	var detachErr error
	for i := len(snomedAttachOrder) - 1; i >= 0 && detachErr == nil; i-- {
		table := snomedAttachOrder[i]
		_, detachErr = tx.Exec(ctx, `ALTER TABLE `+table+` DETACH PARTITION `+partitionName(table, v))
	}
	_ = tx.Rollback(ctx)
	if detachErr == nil {
		t.Fatal("detach-all-then-drop succeeded; finding T1 no longer reproduces, revisit the recipe")
	}
	t.Logf("detach-all-then-drop fails as documented: %v", detachErr)

	// Dropping an attached, referenced partition fails too.
	execErr(t, imp, "", `DROP TABLE `+partitionName("snomed_concept", v))

	// The documented order.
	for i := len(snomedAttachOrder) - 1; i >= 0; i-- {
		table := snomedAttachOrder[i]
		p := partitionName(table, v)
		exec(t, imp, `ALTER TABLE `+table+` DETACH PARTITION `+p)
		exec(t, imp, `DROP TABLE `+p)
	}
	if n := snomedPartitionCount(t, imp, v); n != 0 {
		t.Fatalf("%d SNOMED partitions left", n)
	}
	exec(t, imp, `DELETE FROM code_system_version WHERE id = $1`, v)
	if n := scalar[int](t, imp, `SELECT count(*) FROM snomed_release`); n != 0 {
		t.Fatalf("snomed_release rows left: %d", n)
	}
}
