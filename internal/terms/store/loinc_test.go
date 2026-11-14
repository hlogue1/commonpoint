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
