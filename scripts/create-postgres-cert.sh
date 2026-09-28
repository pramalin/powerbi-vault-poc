#!/usr/bin/env bash
# Create a self-signed TLS certificate for the local PostgreSQL container.
# The certificate names 127.0.0.1, the server name used by Power BI.
set -euo pipefail
cd "$(dirname "$0")/.."
dir=postgres/tls
if [[ -f "$dir/server.crt" && -f "$dir/server.key" ]]; then
  echo "PostgreSQL TLS certificate already exists; leaving it unchanged."
  exit 0
fi
mkdir -p "$dir"
umask 077
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -subj "/CN=127.0.0.1" -addext "subjectAltName=IP:127.0.0.1,DNS:localhost" \
  -keyout "$dir/server.key" -out "$dir/server.crt" 2>/dev/null
chmod 644 "$dir/server.crt"
echo "Created $dir/server.crt (trust it on Windows with scripts/windows/gateway-network.ps1)."
