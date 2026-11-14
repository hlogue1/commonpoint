// SPDX-License-Identifier: GPL-3.0-or-later

// Package migratetest runs a migration set against a throwaway PostgreSQL 18 container.
//
// One Cluster (container) is started per test binary. Each test gets its own database, created
// from a template that already has the migrations applied, so tests are isolated and fast.
// The cluster is bootstrapped with deploy/db/terms-bootstrap.sql, so the cp_terms_* roles exist
// exactly as in a real deployment; the harness only adds throwaway passwords so it can log in
// as each role.
//
// The container runtime is found through testcontainers-go. With Podman on macOS, set
//
//	DOCKER_HOST=unix://$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}')
//	TESTCONTAINERS_RYUK_DISABLED=true
//
// (`make test-db` does this). Without a reachable runtime the tests skip, unless CI is set,
// in which case they fail.
package migratetest

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/tern/v2/migrate"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
	"github.com/testcontainers/testcontainers-go/wait"
)

// Image is the pinned PostgreSQL image. Keep the minor version in step with deploy/db/compose.yaml.
const Image = "docker.io/library/postgres:18.7"

// Roles created by deploy/db/terms-bootstrap.sql.
const (
	RoleMigrations = "cp_terms_migrations"
	RoleImport     = "cp_terms_import"
	RoleApp        = "cp_terms_app"
	RoleSuper      = "postgres"
)

// VersionTable is the tern version table for the terminology migrations (see deploy/db/tern-terms.conf).
const VersionTable = "public.schema_version"

const testPassword = "migratetest"

// Cluster is a running PostgreSQL container with the terminology roles bootstrapped.
type Cluster struct {
	container *postgres.PostgresContainer
	host      string
	port      string

	mu       sync.Mutex
	template string // name of the fully migrated template database, once built
	seq      int
}

var (
	shared     *Cluster
	sharedErr  error
	sharedOnce sync.Once
)

// Shared returns the cluster for this test binary, starting it on first use. It skips the test
// when no container runtime is available and CI is unset.
func Shared(t testing.TB) *Cluster {
	t.Helper()
	sharedOnce.Do(func() {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
		defer cancel()
		shared, sharedErr = start(ctx)
	})
	if sharedErr != nil {
		if os.Getenv("CI") == "" && isProviderError(sharedErr) {
			t.Skipf("no container runtime for PostgreSQL tests: %v", sharedErr)
		}
		t.Fatalf("start PostgreSQL: %v", sharedErr)
	}
	return shared
}

// Terminate stops the shared cluster. Call it from TestMain after m.Run.
func Terminate() {
	if shared != nil {
		_ = testcontainers.TerminateContainer(shared.container)
	}
}

func isProviderError(err error) bool {
	s := err.Error()
	return strings.Contains(s, "Cannot connect to the Docker daemon") ||
		strings.Contains(s, "docker host") || strings.Contains(s, "rootless Docker") ||
		strings.Contains(s, "failed to create Docker provider") || strings.Contains(s, "provider")
}

func start(ctx context.Context) (c *Cluster, err error) {
	defer func() {
		if r := recover(); r != nil { // testcontainers panics when no provider is found
			err = fmt.Errorf("container provider: %v", r)
		}
	}()
	pc, err := postgres.Run(ctx, Image,
		postgres.WithDatabase("postgres"),
		postgres.WithUsername(RoleSuper),
		postgres.WithPassword(testPassword),
		testcontainers.WithWaitStrategy(
			wait.ForLog("database system is ready to accept connections").WithOccurrence(2).
				WithStartupTimeout(2*time.Minute)),
	)
	if err != nil {
		return nil, fmt.Errorf("container provider: %w", err)
	}
	c = &Cluster{container: pc}
	if c.host, err = pc.Host(ctx); err != nil {
		return nil, err
	}
	p, err := pc.MappedPort(ctx, "5432/tcp")
	if err != nil {
		return nil, err
	}
	c.port = p.Port()

	boot, err := os.ReadFile(filepath.Join(RepoRoot(), "deploy", "db", "terms-bootstrap.sql"))
	if err != nil {
		return nil, err
	}
	conn, err := pgx.Connect(ctx, c.dsn("postgres", RoleSuper))
	if err != nil {
		return nil, err
	}
	defer conn.Close(ctx)
	if _, err := conn.Exec(ctx, string(boot)); err != nil {
		return nil, fmt.Errorf("bootstrap: %w", err)
	}
	for _, r := range []string{RoleMigrations, RoleImport, RoleApp} {
		if _, err := conn.Exec(ctx, fmt.Sprintf("ALTER ROLE %s PASSWORD '%s'", r, testPassword)); err != nil {
			return nil, err
		}
	}
	return c, nil
}

func (c *Cluster) dsn(db, role string) string {
	return fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=disable", role, testPassword, c.host, c.port, db)
}

// RepoRoot returns the module root, found from this source file's location.
func RepoRoot() string {
	_, file, _, _ := runtime.Caller(0)
	return filepath.Clean(filepath.Join(filepath.Dir(file), "..", "..", "..", ".."))
}

// MigrationsDir is migrations/terminology.
func MigrationsDir() string { return filepath.Join(RepoRoot(), "migrations", "terminology") }

// DB is one test database.
type DB struct {
	Name    string
	cluster *Cluster
}

// DSN returns a connection string for role on this database.
func (d *DB) DSN(role string) string { return d.cluster.dsn(d.Name, role) }

// Connect opens a connection as role. It is closed when the test ends.
func (d *DB) Connect(t testing.TB, role string) *pgx.Conn {
	t.Helper()
	ctx := context.Background()
	conn, err := pgx.Connect(ctx, d.DSN(role))
	if err != nil {
		t.Fatalf("connect %s as %s: %v", d.Name, role, err)
	}
	t.Cleanup(func() { _ = conn.Close(context.Background()) })
	return conn
}

// NewEmptyDatabase creates an empty database owned by the migrations role, dropped when the test ends.
func (c *Cluster) NewEmptyDatabase(t testing.TB) *DB {
	t.Helper()
	return c.newDatabase(t, "template0")
}

// NewMigratedDatabase creates a database with every migration applied.
func (c *Cluster) NewMigratedDatabase(t testing.TB) *DB {
	t.Helper()
	tmpl, err := c.migratedTemplate()
	if err != nil {
		t.Fatalf("build migrated template: %v", err)
	}
	return c.newDatabase(t, tmpl)
}

func (c *Cluster) nextName(prefix string) string {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.seq++
	return fmt.Sprintf("%s_%d_%d", prefix, os.Getpid(), c.seq)
}

func (c *Cluster) createDatabase(name, template string) error {
	ctx := context.Background()
	conn, err := pgx.Connect(ctx, c.dsn("postgres", RoleSuper))
	if err != nil {
		return err
	}
	defer conn.Close(ctx)
	_, err = conn.Exec(ctx, fmt.Sprintf("CREATE DATABASE %s OWNER %s TEMPLATE %s", name, RoleMigrations, template))
	return err
}

func (c *Cluster) newDatabase(t testing.TB, template string) *DB {
	t.Helper()
	name := c.nextName("t")
	if err := c.createDatabase(name, template); err != nil {
		t.Fatalf("create database: %v", err)
	}
	t.Cleanup(func() {
		ctx := context.Background()
		conn, err := pgx.Connect(ctx, c.dsn("postgres", RoleSuper))
		if err != nil {
			return
		}
		defer conn.Close(ctx)
		_, _ = conn.Exec(ctx, fmt.Sprintf("DROP DATABASE IF EXISTS %s WITH (FORCE)", name))
	})
	return &DB{Name: name, cluster: c}
}

func (c *Cluster) migratedTemplate() (string, error) {
	c.mu.Lock()
	if c.template != "" {
		defer c.mu.Unlock()
		return c.template, nil
	}
	c.mu.Unlock()

	name := c.nextName("tmpl")
	if err := c.createDatabase(name, "template0"); err != nil {
		return "", err
	}
	db := &DB{Name: name, cluster: c}
	ctx := context.Background()
	if err := db.MigrateTo(ctx, -1); err != nil {
		return "", err
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.template == "" {
		c.template = name
	}
	return c.template, nil
}

// Migrator returns a tern migrator connected as the migrations role. The caller closes conn.
func (d *DB) Migrator(ctx context.Context) (*migrate.Migrator, *pgx.Conn, error) {
	conn, err := pgx.Connect(ctx, d.DSN(RoleMigrations))
	if err != nil {
		return nil, nil, err
	}
	m, err := migrate.NewMigrator(ctx, conn, VersionTable)
	if err != nil {
		_ = conn.Close(ctx)
		return nil, nil, err
	}
	if err := m.LoadMigrations(os.DirFS(MigrationsDir())); err != nil {
		_ = conn.Close(ctx)
		return nil, nil, err
	}
	return m, conn, nil
}

// MigrateTo migrates to version target; a negative target means the latest migration.
func (d *DB) MigrateTo(ctx context.Context, target int32) error {
	m, conn, err := d.Migrator(ctx)
	if err != nil {
		return err
	}
	defer conn.Close(ctx)
	if target < 0 {
		target = int32(len(m.Migrations))
	}
	if err := m.MigrateTo(ctx, target); err != nil {
		var pgErr migrate.MigrationPgError
		if errors.As(err, &pgErr) {
			return fmt.Errorf("%s: %w", pgErr.MigrationName, err)
		}
		return err
	}
	return nil
}

// LatestVersion is the number of migrations in MigrationsDir.
func LatestVersion(ctx context.Context, d *DB) (int32, error) {
	m, conn, err := d.Migrator(ctx)
	if err != nil {
		return 0, err
	}
	defer conn.Close(ctx)
	return int32(len(m.Migrations)), nil
}

// Leftovers lists objects in the public schema that are neither extension members nor the
// version table. After migrating down to 0 it must be empty.
func Leftovers(ctx context.Context, conn *pgx.Conn) ([]string, error) {
	rows, err := conn.Query(ctx, `
SELECT kind || ' ' || name FROM (
    SELECT 'relation' AS kind, c.relname AS name, c.oid, 'pg_class'::regclass AS cls
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname NOT IN ('schema_version', 'schema_version_pkey')
    UNION ALL
    SELECT 'function', p.proname, p.oid, 'pg_proc'::regclass
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
    UNION ALL
    SELECT 'type', t.typname, t.oid, 'pg_type'::regclass
    FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public' AND t.typtype IN ('e', 'd', 'r', 'm')
    UNION ALL
    SELECT 'default acl', d.defaclrole::regrole::text, d.oid, 'pg_default_acl'::regclass
    FROM pg_default_acl d
) o
WHERE NOT EXISTS (SELECT 1 FROM pg_depend dep
                  WHERE dep.classid = o.cls AND dep.objid = o.oid AND dep.deptype = 'e')
ORDER BY 1`)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, pgx.RowTo[string])
}
