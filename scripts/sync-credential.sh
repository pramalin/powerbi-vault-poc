#!/usr/bin/env bash
# Push the current Vault credential into the real Power BI gateway data source.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/powerbi.sh sync
./scripts/powerbi.sh status
