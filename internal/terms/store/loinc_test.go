// SPDX-License-Identifier: GPL-3.0-or-later

package store

import (
	"slices"
	"testing"

	"github.com/hlogue1/commonpoint/internal/platform/db/migratetest"
)

func primaryKey(t *testing.T, table string) []string {
	t.Helper()
	conn := migrated(t).Connect(t, migratetest.RoleMigrations)
	return scalar[[]string](t, conn, `
SELECT array_agg(a.attname::text ORDER BY k.ord)
FROM pg_constraint c
CROSS JOIN LATERAL unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord)
JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum
WHERE c.conrelid = $1::regclass AND c.contype = 'p'`, table)
}

// T8/C12: loinc_panel_member is keyed by the file's row id, so a sub-panel shared between
// top-level panels doesn't collide on (panel, sequence).
func TestLoincPanelMemberRekey(t *testing.T) {
	if pk := primaryKey(t, "loinc_panel_member"); !slices.Equal(pk, []string{"version_id", "row_id"}) {
		t.Fatalf("loinc_panel_member PK = %v", pk)
	}
}

// C11: the LOINC hierarchy and closure are content tables the loader can install, and
// loinc_subsumes answers from the closure (non-reflexive, like SNOMED).
func TestLoincHierarchy(t *testing.T) {
	db := migrated(t)
	imp := db.Connect(t, migratetest.RoleImport)
	v := newVersion(t, imp, "loinc", "2.82", "")
	exec(t, imp, `INSERT INTO loinc_release (version_id) VALUES ($1)`, v)
	attachEmptyPartition(t, imp, "loinc_hierarchy", v)
	attachEmptyPartition(t, imp, "loinc_closure", v)
	exec(t, imp, `INSERT INTO loinc_hierarchy (version_id, path_to_root, sequence, immediate_parent, code, code_text) VALUES
	    ($1, '', 1, NULL, 'LP0000-1', 'Synthetic root'),
	    ($1, 'LP0000-1', 1, 'LP0000-1', 'LP0001-9', 'Synthetic group'),
	    ($1, 'LP0000-1.LP0001-9', 1, 'LP0001-9', '99999-9', 'Synthetic term')`, v)
	exec(t, imp, `INSERT INTO loinc_closure (version_id, ancestor, descendant, depth) VALUES
	    ($1, 'LP0000-1', 'LP0001-9', 1), ($1, 'LP0000-1', '99999-9', 2), ($1, 'LP0001-9', '99999-9', 1)`, v)

	app := db.Connect(t, migratetest.RoleApp)
	for _, c := range []struct {
		a, d string
		want bool
	}{{"LP0000-1", "99999-9", true}, {"99999-9", "99999-9", true}, {"99999-9", "LP0000-1", false}} {
		if got := scalar[bool](t, app, `SELECT loinc_subsumes($1, $2, $3)`, v, c.a, c.d); got != c.want {
			t.Errorf("loinc_subsumes(%s, %s) = %v", c.a, c.d, got)
		}
	}
}
