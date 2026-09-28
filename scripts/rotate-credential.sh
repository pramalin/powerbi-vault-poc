#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose exec -T vault sh -ec \
  'VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="$VAULT_DEV_ROOT_TOKEN_ID" vault write -force database/rotate-role/powerbi-reader >/dev/null'
echo "Vault rotated the database password."

# PostgreSQL keeps already-authenticated sessions alive after a password
# change, and the gateway pools connections. End the reporting account's open
# sessions so the next gateway request must authenticate with the new password.
docker compose exec -T postgres psql -U postgres -d reporting -qAtc \
  "SELECT count(pg_terminate_backend(pid)) FROM pg_stat_activity WHERE usename = 'powerbi_reader';" \
  | xargs -I{} echo "Closed {} existing powerbi_reader session(s)."
