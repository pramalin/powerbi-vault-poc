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

./scripts/create-postgres-cert.sh
docker compose up -d --build postgres vault
docker compose --profile tools run --rm toolbox /work/bootstrap-vault.sh
docker compose --profile tools build toolbox

echo
echo "PostgreSQL and Vault are ready."
echo "Next: connect the Power BI gateway (README: 'Use the real Power BI gateway'),"
echo "or run the offline simulator demo: ./scripts/simulator/demo-rotation.sh"
