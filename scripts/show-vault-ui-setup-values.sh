#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
[[ -f .env ]] || { echo "Run ./scripts/start-ui-setup.sh first." >&2; exit 1; }

set -a
source .env
set +a

cat <<EOF
Local learning environment only:

Vault UI:               http://localhost:8200/ui
Vault login token:      $VAULT_DEV_ROOT_TOKEN_ID
Connection name:        reporting-postgres
Connection URL:         postgresql://{{username}}:{{password}}@postgres:5432/reporting?sslmode=disable
Database admin user:    postgres
Database admin password: $POSTGRES_ADMIN_PASSWORD
Allowed role:           powerbi-reader
Static database user:   powerbi_reader
Rotation period:        24h
Rotation statement:     ALTER USER \"{{name}}\" WITH PASSWORD '{{password}}';
EOF

