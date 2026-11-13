#!/usr/bin/env bash
# Generates .env with random secrets. Refuses to overwrite an existing .env,
# because rotating DB passwords or encryption keys after first start breaks things.
set -euo pipefail
cd "$(dirname "$0")"

if [[ -f .env ]]; then
  echo ".env already exists — not overwriting." >&2
  exit 1
fi

# URL-safe random strings (no / + = so they're safe inside DSNs)
rand() { openssl rand -base64 64 | tr -dc 'A-Za-z0-9' | head -c "$1"; }

umask 077
cat > .env <<EOF
# Generated $(date -u +%Y-%m-%dT%H:%M:%SZ) — do not commit.

# Image versions (pin these; check release notes before bumping)
ORY_VERSION=v26.2.0
TALOS_VERSION=v26.2.0
POLIS_VERSION=26.2.0
OPENFGA_VERSION=latest

# Postgres
POSTGRES_PASSWORD=$(rand 32)
HYDRA_DB_PASSWORD=$(rand 32)
KRATOS_DB_PASSWORD=$(rand 32)
POLIS_DB_PASSWORD=$(rand 32)
OPENFGA_DB_PASSWORD=$(rand 32)
TALOS_DB_PASSWORD=$(rand 32)

# Hydra
HYDRA_SECRETS_SYSTEM=$(rand 48)
HYDRA_PAIRWISE_SALT=$(rand 32)

# Kratos (cipher secret must be exactly 32 characters)
KRATOS_SECRETS_COOKIE=$(rand 48)
KRATOS_SECRETS_CIPHER=$(rand 32)

# Polis
POLIS_NEXTAUTH_SECRET=$(rand 48)
POLIS_API_KEY=$(rand 40)
POLIS_DB_ENCRYPTION_KEY=$(rand 32)
POLIS_ADMIN_EMAIL=admin@idp.local
POLIS_ADMIN_PASSWORD=$(rand 24)

# OpenFGA
OPENFGA_PRESHARED_KEY=$(rand 40)

# Talos (min 32 characters)
TALOS_HMAC_SECRET=$(rand 48)
EOF

echo "Wrote .env"
