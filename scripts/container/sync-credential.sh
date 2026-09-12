#!/usr/bin/env bash
set -euo pipefail

mkdir -p /run/powerbi-creds
response="$(curl -fsS -H "X-Vault-Token: $VAULT_TOKEN" \
  "$VAULT_ADDR/v1/database/static-creds/powerbi-reader")"

jq -e '.data.username and .data.password' <<<"$response" >/dev/null
temp_file="$(mktemp /run/powerbi-creds/credential.json.XXXXXX)"
jq -c '{username:.data.username,password:.data.password}' <<<"$response" >"$temp_file"
chown 65534:65534 "$temp_file"
chmod 600 "$temp_file"
mv "$temp_file" /run/powerbi-creds/credential.json
echo "Gateway simulator credential synchronized from Vault."
