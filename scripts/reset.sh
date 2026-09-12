#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo "This removes only this POC's containers and named volumes."
docker compose --profile tools down --volumes --remove-orphans

