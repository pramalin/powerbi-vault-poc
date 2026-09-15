#!/usr/bin/env bash
set -euo pipefail

until curl -fsS "$VAULT_ADDR/v1/sys/health" >/dev/null; do sleep 1; done

mounts="$(curl -fsS -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/sys/mounts")"
jq -e '.data["database/"].type == "database"' <<<"$mounts" >/dev/null || {
  echo "Missing database secrets engine at path database/." >&2
  exit 1
}

curl -fsS -H "X-Vault-Token: $VAULT_TOKEN" \
  "$VAULT_ADDR/v1/database/config/reporting-postgres" >/dev/null || {
  echo "Missing database connection reporting-postgres." >&2
  exit 1
}

role="$(curl -fsS -H "X-Vault-Token: $VAULT_TOKEN" \
  "$VAULT_ADDR/v1/database/static-roles/powerbi-reader")" || {
  echo "Missing static role powerbi-reader." >&2
  exit 1
}
jq -e '.data.username == "powerbi_reader"' <<<"$role" >/dev/null || {
  echo "Static role is not configured for powerbi_reader." >&2
  exit 1
}

credential="$(curl -fsS -H "X-Vault-Token: $VAULT_TOKEN" \
  "$VAULT_ADDR/v1/database/static-creds/powerbi-reader")"
jq -e '.data.username and .data.password' <<<"$credential" >/dev/null || {
  echo "Vault did not return the static role credential." >&2
  exit 1
}

echo "Vault UI configuration validated."

