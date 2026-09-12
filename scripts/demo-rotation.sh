#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "1. Query with synchronized credential (expect HTTP 200)"
curl -fsS http://localhost:8080/report | jq .

echo "2. Rotate database password in Vault"
./scripts/rotate-credential.sh

echo "3. Query with stale simulated-gateway credential (expect HTTP 503)"
status="$(curl -sS -o /tmp/powerbi-vault-response.json -w '%{http_code}' http://localhost:8080/report)"
jq . /tmp/powerbi-vault-response.json
[[ "$status" == "503" ]] || { echo "Expected 503, received $status" >&2; exit 1; }

echo "4. Synchronize the new credential from Vault"
./scripts/sync-credential.sh

echo "5. Query again (expect HTTP 200)"
curl -fsS http://localhost:8080/report | jq .

echo "Rotation demonstration completed successfully."

