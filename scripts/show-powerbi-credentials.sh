#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "LOCAL POC ONLY: enter this credential in Power BI Desktop."
docker compose exec -T vault sh -ec \
  'VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN="$VAULT_DEV_ROOT_TOKEN_ID" vault read -format=json database/static-creds/powerbi-reader' \
  | jq '{server:"localhost:5432",database:"reporting",username:.data.username,password:.data.password}'
