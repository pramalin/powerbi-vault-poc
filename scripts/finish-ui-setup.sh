#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
[[ -f .env ]] || { echo "Run ./scripts/start-ui-setup.sh first." >&2; exit 1; }

docker compose --profile tools run --rm toolbox /work/validate-vault-ui.sh
docker compose --profile tools build toolbox

echo
echo "UI-guided setup is complete."
echo "Next: connect the Power BI gateway (README: 'Use the real Power BI gateway'),"
echo "or run the offline simulator demo: ./scripts/simulator/demo-rotation.sh"

