#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose exec -T vault sh -ec \
  'VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="$VAULT_DEV_ROOT_TOKEN_ID" vault write -force database/rotate-role/powerbi-reader >/dev/null'
echo "Vault rotated the database password."
