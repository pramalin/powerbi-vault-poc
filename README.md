# Power BI and HashiCorp Vault credential-rotation POC

This local proof of concept demonstrates how HashiCorp Vault can manage and rotate a read-only database credential used by a Power BI-like gateway. PostgreSQL, Vault, and the gateway simulator run in Docker Compose under WSL. Power BI Desktop runs natively on Windows and connects to PostgreSQL through `localhost`.

It is deliberately independent of an AWS console, client VDI, and Power BI tenant so the core security behavior can be demonstrated from a personal laptop.

## What this proves

1. A dedicated `powerbi_reader` account can query only reporting data.
2. Vault manages that account as a static database role.
3. After Vault rotates the password, a consumer holding the old password fails.
4. A synchronization job retrieves the current credential from Vault.
5. The consumer succeeds again without placing the password in source control.

The gateway simulator represents the credential cache in the real Microsoft on-premises data gateway. It is not Microsoft gateway software.

## Prerequisites

- Windows 10 or 11 with WSL 2
- Docker Desktop with WSL integration, or Docker Engine inside WSL
- Power BI Desktop (optional for the Compose-only test)
- `bash`, `openssl`, and `curl` in WSL

Run all shell commands from a WSL terminal.

## Start the POC

```bash
chmod +x scripts/*.sh scripts/container/*.sh
./scripts/setup.sh
```

The first run downloads and builds the container images, starts PostgreSQL and Vault, configures Vault's PostgreSQL secrets engine, synchronizes the credential, and starts the gateway simulator.

Verify the simulated report:

```bash
curl http://localhost:8080/report
```

## Demonstrate rotation

```bash
./scripts/demo-rotation.sh
```

The demonstration performs a successful query, rotates the password, proves the cached credential fails, synchronizes the replacement credential, and proves queries work again.

Individual operations are also available:

```bash
./scripts/rotate-credential.sh
./scripts/sync-credential.sh
```

## Connect Power BI Desktop

Display the current local reporting credential:

```bash
./scripts/show-powerbi-credentials.sh
```

This command intentionally reveals the password and is for the isolated local POC only.

In Power BI Desktop on Windows:

1. Select **Get data > PostgreSQL database**.
2. Set **Server** to `localhost:5432`.
3. Set **Database** to `reporting`.
4. Select **Import** mode.
5. Choose database authentication and enter `powerbi_reader` plus the displayed password.
6. Select the `sales.monthly_sales` table and load it.
7. Create a visual using `month`, `region`, and `revenue`.
8. Save the PBIX outside this repository, or keep it ignored by Git.

If `localhost` does not reach WSL, run `hostname -I` in WSL and use its first IP address as the server. Windows firewall policy may also affect connectivity.

### Observe Power BI behavior

1. Refresh the report successfully in Power BI Desktop.
2. Run `./scripts/rotate-credential.sh`.
3. Refresh again; it should fail because Desktop cached the previous password.
4. Run `./scripts/show-powerbi-credentials.sh`.
5. In Power BI Desktop, open **File > Options and settings > Data source settings**, edit permissions for the PostgreSQL source, and enter the new password.
6. Refresh again successfully.

This demonstrates that putting a credential in Vault is not enough. Every credential consumer must receive the rotated value.

## Local endpoints

| Endpoint | Purpose |
|---|---|
| `http://localhost:8080/report` | Execute a reporting query through the simulator |
| `http://localhost:8080/health` | Simulator health check |
| `http://localhost:8200` | Local Vault development API/UI |
| `localhost:5432` | PostgreSQL for Power BI Desktop |

All published ports bind to `127.0.0.1` in `compose.yaml`.

## Mapping to the client environment

| POC | Production equivalent |
|---|---|
| PostgreSQL container | Client reporting database in AWS |
| Vault development container | Client-managed HashiCorp Vault cluster |
| `powerbi_reader` | Dedicated least-privilege reporting identity |
| Gateway simulator | Microsoft on-premises data gateway on managed Windows EC2 |
| Credential-sync script | Approved automation using Vault and Power BI APIs |
| `/report` query | Semantic-model refresh or DirectQuery operation |

In production, the synchronization job authenticates to Vault with a workload identity, reads the static-role credential, encrypts it using the gateway public key, and calls the Power BI REST API to update the gateway data source. No Vault root token is used.

## Power BI credential lifecycle

- **Desktop authoring:** the developer's Windows Power BI Desktop stores a local data-source credential.
- **Import after publishing:** viewers query imported data; the service/gateway credential is used during refresh.
- **DirectQuery after publishing:** interactive report operations can query the database through the gateway.
- **Rotation:** Power BI does not automatically retrieve a replacement password from Vault; approved automation must synchronize it.

## Reset

```bash
./scripts/reset.sh
```

This removes this Compose project's containers and named volumes. It does not remove images or unrelated Docker resources. Run `./scripts/setup.sh` to create a fresh environment.

## Public-repository checklist

Before committing:

```bash
git status --short
git check-ignore .env
git grep -nEi 'password|token|secret'
```

Review matches: documentation and variable names are expected, but literal client credentials are not. Do not commit `.env`, PBIX files with client data, screenshots containing identifiers, internal URLs, or client configuration.

## Production considerations

This POC intentionally uses Vault development mode. A production design must add:

- TLS and a highly available, persistent Vault deployment
- A narrowly scoped machine identity and Vault policy
- Protected bootstrap and database-administration credentials
- Auditing and monitoring without secret values in logs
- Rotation retry, rollback, and outage handling
- A Windows gateway cluster rather than a single unmanaged host
- Power BI API permissions approved by the tenant administrator
- Separate development, test, and production identities and Vault paths

See [SECURITY.md](SECURITY.md) before presenting or extending the project.
