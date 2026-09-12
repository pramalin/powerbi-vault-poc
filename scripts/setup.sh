#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  umask 077
  admin_password="$(openssl rand -hex 24)"
  vault_token="$(openssl rand -hex 24)"
  printf 'POSTGRES_ADMIN_PASSWORD=%s\nVAULT_DEV_ROOT_TOKEN_ID=%s\n' \
    "$admin_password" "$vault_token" > .env
  echo "Created local .env (excluded from Git)."
else
  echo ".env already exists; leaving it unchanged."
fi

docker compose up -d --build postgres vault
docker compose --profile tools run --rm toolbox /work/bootstrap-vault.sh
docker compose --profile tools run --rm toolbox /work/sync-credential.sh
docker compose up -d --build gateway-simulator

echo
echo "POC is ready. Run: ./scripts/demo-rotation.sh"
echo "Gateway simulator: http://localhost:8080/report"
