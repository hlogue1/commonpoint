// SPDX-License-Identifier: GPL-3.0-or-later

package migratetest

import (
	"context"
	"os"
	"testing"
)

func TestMain(m *testing.M) {
	code := m.Run()
	Terminate()
	os.Exit(code)
}

// TestTerminologyRoundTrip applies migrations/terminology up, down to 0 and up again, and
// checks that nothing is left behind in between.
func TestTerminologyRoundTrip(t *testing.T) {
	ctx := context.Background()
	db := Shared(t).NewEmptyDatabase(t)

	if err := db.MigrateTo(ctx, -1); err != nil {
		t.Fatalf("up: %v", err)
	}
	if err := db.MigrateTo(ctx, 0); err != nil {
		t.Fatalf("down to 0: %v", err)
	}
	left, err := Leftovers(ctx, db.Connect(t, RoleSuper))
	if err != nil {
		t.Fatal(err)
	}
	if len(left) > 0 {
		t.Fatalf("objects left after down to 0: %v", left)
	}
	if err := db.MigrateTo(ctx, -1); err != nil {
		t.Fatalf("up again: %v", err)
	}
}
