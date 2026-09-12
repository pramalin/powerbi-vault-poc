#!/usr/bin/env bash
set -euo pipefail

until curl -fsS "$VAULT_ADDR/v1/sys/health" >/dev/null; do sleep 1; done

if ! curl -fsS -H "X-Vault-Token: $VAULT_TOKEN" \
  "$VAULT_ADDR/v1/sys/mounts" | jq -e '.data["database/"]' >/dev/null; then
  curl -fsS -X POST -H "X-Vault-Token: $VAULT_TOKEN" \
    -d '{"type":"database"}' "$VAULT_ADDR/v1/sys/mounts/database" >/dev/null
fi

connection_url='postgresql://{{username}}:{{password}}@postgres:5432/reporting?sslmode=disable'
curl -fsS -X POST -H "X-Vault-Token: $VAULT_TOKEN" \
  -H 'Content-Type: application/json' \
  -d "$(jq -n --arg url "$connection_url" --arg password "$POSTGRES_ADMIN_PASSWORD" '{plugin_name:"postgresql-database-plugin",allowed_roles:["powerbi-reader"],connection_url:$url,username:"postgres",password:$password}')" \
  "$VAULT_ADDR/v1/database/config/reporting-postgres" >/dev/null

rotation_statement="ALTER USER \"{{name}}\" WITH PASSWORD '{{password}}';"
curl -fsS -X POST -H "X-Vault-Token: $VAULT_TOKEN" \
  -H 'Content-Type: application/json' \
  -d "$(jq -n --arg statement "$rotation_statement" '{db_name:"reporting-postgres",username:"powerbi_reader",rotation_period:"24h",rotation_statements:[$statement]}')" \
  "$VAULT_ADDR/v1/database/static-roles/powerbi-reader" >/dev/null

echo "Vault database engine and static reporting role configured."
