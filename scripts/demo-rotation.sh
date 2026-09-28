#!/usr/bin/env bash
# Rotation demo against the real Power BI on-premises data gateway.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

refresh() {
  if [[ -n "${POWERBI_DATASET_ID:-}" ]]; then
    ./scripts/powerbi.sh refresh
  else
    echo "(POWERBI_DATASET_ID not set; skipping semantic-model refresh)"
  fi
}

echo "1. Gateway connection with the synchronized credential (expect OK)"
./scripts/powerbi.sh status
refresh

echo "2. Rotate the database password in Vault"
./scripts/rotate-credential.sh

echo "3. Gateway still holds the old password (expect FAILED)"
./scripts/powerbi.sh status --expect-failure

echo "4. Encrypt the new Vault credential for the gateway and update the data source"
./scripts/powerbi.sh sync

echo "5. Gateway connection again (expect OK)"
./scripts/powerbi.sh status
refresh

echo "Rotation demonstration against the real gateway completed successfully."
