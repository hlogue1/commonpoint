// SPDX-License-Identifier: GPL-3.0-or-later

package store

import (
	"testing"

	"github.com/hlogue1/commonpoint/internal/platform/db/migratetest"
)

// T4: an untyped code-system-id literal resolves through version_for_date_by_id instead of
// silently selecting the URI overload; the URI variant still works.
func TestVersionForDateByIDAndURI(t *testing.T) {
	conn := migrated(t).Connect(t, migratetest.RoleMigrations)
	v := newVersion(t, conn, "icd10cm", "2027", "[2026-10-01,2027-10-01)")
	exec(t, conn, `SELECT activate_version($1)`, v)

	if got := scalar[string](t, conn, `SELECT version_for_date_by_id('icd10cm', '2027-05-01')::text`); got != v {
		t.Fatalf("by_id = %s, want %s", got, v)
	}
	if got := scalar[string](t, conn, `SELECT version_for_date_by_uri('http://hl7.org/fhir/sid/icd-10-cm', '2027-05-01')::text`); got != v {
		t.Fatalf("by_uri = %s, want %s", got, v)
	}
	if n := scalar[int](t, conn, `SELECT count(*) FROM pg_proc WHERE proname = 'version_for_date'`); n != 0 {
		t.Fatalf("version_for_date overloads still exist: %d", n)
	}
}
