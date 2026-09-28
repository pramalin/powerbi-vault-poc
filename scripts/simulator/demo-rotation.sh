#!/usr/bin/env bash
# Offline demo using the gateway simulator (no Power BI tenant needed).
set -euo pipefail
cd "$(dirname "$0")/../.."

sync_sim() { docker compose --profile tools run --rm toolbox /work/sync-simulator-credential.sh; }

sync_sim
docker compose --profile simulator up -d --build gateway-simulator
until curl -fsS http://localhost:8080/health >/dev/null 2>&1; do sleep 1; done

echo "1. Query with synchronized credential (expect HTTP 200)"
curl -fsS http://localhost:8080/report | jq .

echo "2. Rotate database password in Vault"
./scripts/rotate-credential.sh

echo "3. Query with stale simulated-gateway credential (expect HTTP 503)"
status="$(curl -sS -o /tmp/powerbi-vault-response.json -w '%{http_code}' http://localhost:8080/report)"
jq . /tmp/powerbi-vault-response.json
[[ "$status" == "503" ]] || { echo "Expected 503, received $status" >&2; exit 1; }

echo "4. Synchronize the new credential from Vault"
sync_sim

echo "5. Query again (expect HTTP 200)"
curl -fsS http://localhost:8080/report | jq .

echo "Simulator rotation demonstration completed successfully."
