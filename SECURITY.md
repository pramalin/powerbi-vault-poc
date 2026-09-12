# Security scope

This repository is a local learning proof of concept, not a production deployment.

- Vault runs in development mode and is automatically unsealed.
- The development root token is stored in the untracked `.env` file.
- PostgreSQL and Vault ports bind only to Windows/WSL localhost.
- The helper that displays the reporting password exists only to configure Power BI Desktop manually.
- Never commit `.env`, a PBIX containing sensitive imported data, Vault tokens, passwords, or client information.

Production requires TLS, persistent highly available Vault storage, a non-root workload identity, least-privilege Vault policies, audit logging, protected bootstrap credentials, failure alerting, and an approved credential-rotation procedure.

