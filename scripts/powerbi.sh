#!/usr/bin/env bash
# Run a Power BI gateway command in the toolbox container.
# Usage: ./scripts/powerbi.sh login|discover|sync|status|refresh
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose --profile tools run --rm toolbox python3 /work/powerbi_gateway.py "$@"
