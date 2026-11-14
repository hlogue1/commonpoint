// SPDX-License-Identifier: GPL-3.0-or-later

package store

import (
	"context"
	"os"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5"

	"github.com/hlogue1/commonpoint/internal/platform/db/migratetest"
)

func TestMain(m *testing.M) {
	code := m.Run()
	migratetest.Terminate()
	os.Exit(code)
}

// migrated returns a fresh database with every terminology migration applied.
func migrated(t *testing.T) *migratetest.DB {
	t.Helper()
	return migratetest.Shared(t).NewMigratedDatabase(t)
}

func exec(t *testing.T, conn *pgx.Conn, sql string, args ...any) {
	t.Helper()
	if _, err := conn.Exec(context.Background(), sql, args...); err != nil {
		t.Fatalf("%s: %v", firstLine(sql), err)
	}
}

// execErr runs sql and fails the test unless it errors with a message containing want.
func execErr(t *testing.T, conn *pgx.Conn, want, sql string, args ...any) {
	t.Helper()
	_, err := conn.Exec(context.Background(), sql, args...)
	if err == nil {
		t.Fatalf("%s: expected error containing %q, got none", firstLine(sql), want)
	}
	if !strings.Contains(err.Error(), want) {
		t.Fatalf("%s: expected error containing %q, got %v", firstLine(sql), want, err)
	}
}

func scalar[T any](t *testing.T, conn *pgx.Conn, sql string, args ...any) T {
	t.Helper()
	var v T
	if err := conn.QueryRow(context.Background(), sql, args...).Scan(&v); err != nil {
		t.Fatalf("%s: %v", firstLine(sql), err)
	}
	return v
}

func firstLine(s string) string {
	s = strings.TrimSpace(s)
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		return s[:i]
	}
	return s
}

// fakeSHA is a syntactically valid source_sha256 derived from a label.
func fakeSHA(label string) string {
	const hex = "0123456789abcdef"
	b := make([]byte, 64)
	for i := range b {
		b[i] = hex[(int(label[i%len(label)])+i)%16]
	}
	return string(b)
}

// newVersion inserts a ready, validated, staged version and returns its id. validity is a daterange
// literal, or "" for an undated code system.
func newVersion(t *testing.T, conn *pgx.Conn, system, version, validity string) string {
	t.Helper()
	var v any
	if validity != "" {
		v = validity
	}
	return scalar[string](t, conn, `
INSERT INTO code_system_version (code_system_id, version, validity, load_status, source_sha256, validated_at)
VALUES ($1, $2, $3::daterange, 'ready', $4, '2026-11-01 00:00:00+00')
RETURNING id::text`, system, version, v, fakeSHA(system+version))
}
