#!/bin/bash
# Creates (or updates) one role + database per service. Safe to run on every
# `compose up`: existing roles/databases are left in place, and passwords are
# re-synced from .env so a changed password never silently locks a service out.
#
# Runs in its own one-shot container and connects over TCP, so it doesn't depend
# on the Postgres image's /docker-entrypoint-initdb.d behaviour or on the volume
# being empty.
set -euo pipefail

: "${PGHOST:?}" "${PGUSER:?}"
export PGPASSWORD="$(cat "${POSTGRES_PASSWORD_FILE:?}")"
export PGDATABASE=postgres

# Wait until the server accepts TCP logins (the image's own init server
# is socket-only, so this also waits out first-boot initialisation).
for _ in $(seq 1 60); do
  psql -qtAc 'select 1' >/dev/null 2>&1 && break
  sleep 1
done
psql -qtAc 'select 1' >/dev/null

ensure_db() {
  local name="$1" password="$2"
  if [[ -z "$password" ]]; then
    echo "ERROR: password for '$name' is empty (is it in .env?)" >&2
    exit 1
  fi
  echo "Ensuring role and database: ${name}"
  # Values go in as psql variables and are quoted with format(%I/%L),
  # so passwords with any characters are handled safely.
  psql -v ON_ERROR_STOP=1 -q -v name="$name" -v pw="$password" <<'EOSQL'
SELECT format('CREATE ROLE %I LOGIN', :'name')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'name') \gexec
SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'name', :'pw') \gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'name', :'name')
 WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'name') \gexec
SELECT format('ALTER DATABASE %I OWNER TO %I', :'name', :'name') \gexec
SELECT format('REVOKE ALL ON DATABASE %I FROM PUBLIC', :'name') \gexec
SELECT format('GRANT CONNECT, TEMPORARY ON DATABASE %I TO %I', :'name', :'name') \gexec
EOSQL
}

ensure_db hydra   "${HYDRA_DB_PASSWORD:-}"
ensure_db kratos  "${KRATOS_DB_PASSWORD:-}"
ensure_db polis   "${POLIS_DB_PASSWORD:-}"
ensure_db openfga "${OPENFGA_DB_PASSWORD:-}"
ensure_db talos   "${TALOS_DB_PASSWORD:-}"

echo "Database setup complete."