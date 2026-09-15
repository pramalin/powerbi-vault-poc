#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
[[ -f .env ]] || { echo "Run ./scripts/start-ui-setup.sh first." >&2; exit 1; }

docker compose --profile tools run --rm toolbox /work/validate-vault-ui.sh
docker compose --profile tools run --rm toolbox /work/sync-credential.sh
docker compose up -d --build gateway-simulator

echo
echo "UI-guided setup is complete."
echo "Verify: curl http://localhost:8080/report"
echo "Rotate and resynchronize: ./scripts/demo-rotation.sh"

