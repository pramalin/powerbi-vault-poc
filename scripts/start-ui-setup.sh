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

echo
echo "Vault UI is ready at http://localhost:8200/ui"
echo "Run ./scripts/show-vault-ui-setup-values.sh for the local setup values."
echo "Follow docs/vault-ui-walkthrough.md, then run ./scripts/finish-ui-setup.sh."

