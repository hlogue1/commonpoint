// SPDX-License-Identifier: GPL-3.0-or-later

package store

import (
	"testing"

	"github.com/hlogue1/commonpoint/internal/platform/db/migratetest"
)

// T8/C6: every SNOMED RF2 component table stores effective_time.
func TestSnomedEffectiveTime(t *testing.T) {
	conn := migrated(t).Connect(t, migratetest.RoleMigrations)
	for _, table := range []string{"snomed_concept", "snomed_description", "snomed_relationship",
		"snomed_relationship_concrete", "snomed_language_member", "snomed_refset_member",
		"snomed_history", "snomed_extended_map"} {
		got := scalar[string](t, conn, `SELECT data_type || ' ' || is_nullable FROM information_schema.columns
		    WHERE table_schema = 'public' AND table_name = $1 AND column_name = 'effective_time'`, table)
		if got != "date NO" {
			t.Errorf("%s.effective_time: %q", table, got)
		}
	}
}
