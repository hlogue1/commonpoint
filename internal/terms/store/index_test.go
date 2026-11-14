// SPDX-License-Identifier: GPL-3.0-or-later

package store

import (
	"testing"

	"github.com/hlogue1/commonpoint/internal/platform/db/migratetest"
)

// P2: every trigram index on an unpartitioned table leads with version_id; partitioned tables
// rely on pruning instead.
func TestTrigramIndexesScopedByVersion(t *testing.T) {
	conn := migrated(t).Connect(t, migratetest.RoleMigrations)
	rows, err := conn.Query(t.Context(), `
SELECT i.indexrelid::regclass::text
FROM pg_index i
JOIN pg_class t ON t.oid = i.indrelid
JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE n.nspname = 'public' AND t.relkind = 'r' AND NOT t.relispartition
  AND pg_get_indexdef(i.indexrelid) LIKE '%gin_trgm_ops%'
  AND pg_get_indexdef(i.indexrelid) NOT LIKE '%gin (version_id, %'
ORDER BY 1`)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	for rows.Next() {
		var name string
		_ = rows.Scan(&name)
		t.Errorf("trigram index %s is not scoped by version_id", name)
	}
}
