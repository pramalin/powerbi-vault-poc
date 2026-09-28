# Security scope

This repository is a local learning proof of concept, not a production deployment.

- Vault runs in development mode and is automatically unsealed.
- The development root token is stored in the untracked `.env` file.
- PostgreSQL and Vault ports bind only to Windows/WSL localhost.
- The helper that displays the reporting password exists only to configure Power BI Desktop manually.
- `.env` may also hold `POWERBI_CLIENT_SECRET`; the device-code sign-in token cache lives in the `powerbi-auth` Docker volume. `./scripts/reset.sh` removes that volume.
- The sync job never prints the credential. It encrypts it with the gateway's public key before calling the Power BI API.
- The PostgreSQL TLS key in `postgres/tls/` is generated locally, is ignored by Git, and is trusted only on your own machine by `scripts/windows/gateway-network.ps1`.
- Use a disposable Power BI test tenant or a client-provided test account, never a production tenant.
- Never commit `.env`, a PBIX containing sensitive imported data, Vault tokens, passwords, or client information.

Production requires TLS, persistent highly available Vault storage, a non-root workload identity, least-privilege Vault policies, audit logging, protected bootstrap credentials, failure alerting, and an approved credential-rotation procedure.

