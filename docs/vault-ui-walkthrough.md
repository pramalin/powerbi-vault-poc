# Configure the Power BI credential with Vault UI

This optional workflow uses Vault's web UI for the parts exposed by Vault
Community Edition 1.20. The UI form does not expose every database connection
property, so the existing bootstrap script remains the reliable fallback.

Vault's UI is an administration interface. The gateway simulator still reads
credentials through Vault's API, as a production workload would.

## Understand the two different rotations

This POC involves two database accounts:

| Account | Purpose | Rotate during setup? |
|---|---|---|
| `postgres` | Administrative account used by the Vault connection | No |
| `powerbi_reader` | Read-only reporting account managed by the static role | Yes |

Do not invoke **Rotate root credentials** for the `reporting-postgres`
connection. Vault Community Edition automatically rotates a static role's
password when importing it so Vault knows the managed password. In the UI used
for this POC there is no separate **Rotate immediately** field on the role form;
the rotation happens automatically. Skipping that initial static-role rotation
is an Enterprise feature.

## 1. Reset and start from scratch

The reset removes this Compose project's containers and volumes. It leaves the
local `.env` file in place.

```bash
./scripts/reset.sh
chmod +x scripts/*.sh scripts/container/*.sh
./scripts/start-ui-setup.sh
./scripts/show-vault-ui-setup-values.sh
```

Keep the displayed local-only values available for the following steps.

## 2. Sign in

1. Open <http://localhost:8200/ui>.
2. Select **Token** as the authentication method.
3. Enter the token printed by `show-vault-ui-setup-values.sh`.

## 3. Enable the database secrets engine

1. Select **Secrets** in the left navigation.
2. Select **Secrets engines**.
3. Click **+ Enable new engine**.
4. Under **Infrastructure**, select **Databases**.
5. Keep the path as `database` and enable the engine.

## 4. Create the PostgreSQL connection

Open the `database` secrets engine and create a connection. Use the fields that
are present in the Vault 1.20 UI:

| Field | Value |
|---|---|
| Connection name | `reporting-postgres` |
| Database plugin | PostgreSQL |
| Connection URL | `postgresql://{{username}}:{{password}}@postgres:5432/reporting?sslmode=disable` |
| Username | `postgres` |
| Password | Value printed by `show-vault-ui-setup-values.sh` |
| Verify connection | Enabled |
| Rotation statements | Leave empty |

The connection form in this Vault UI does not display **Allowed roles**. Do not
put the `powerbi_reader` password rotation statement in the connection's
**Rotation statements** field: that field applies to the administrative
connection account.

Save the connection. If the UI separately offers to rotate root credentials,
do not perform that action. Rotating the `postgres` password would make it stop
matching `POSTGRES_ADMIN_PASSWORD` in `.env`.

## 5. Create the static reporting role

Open **Roles**, create a role, and use the fields shown by the Vault Community
Edition UI:

| Field | Value |
|---|---|
| Role name | `powerbi-reader` |
| Role type | Static |
| Database connection | `reporting-postgres` |
| Database username | `powerbi_reader` |
| Rotation period | `24h` or `86400` seconds |

The Community Edition form used for this POC did not display **Rotation
statements** or **Rotate immediately**. Leave them out. Vault automatically
rotates the static account when the role is created; the PostgreSQL plugin uses
its default password-rotation statement. This changes only the read-only
`powerbi_reader` password and lets Vault become its credential manager.

## 6. Validate and finish

```bash
./scripts/finish-ui-setup.sh
curl http://localhost:8080/report
```

The finish script verifies the engine, connection, static role, and credential
before starting the gateway simulator.

## If the UI rejects the role

First inspect the connection as Vault stored it:

```bash
docker compose exec -T vault sh -ec '
  export VAULT_ADDR=http://127.0.0.1:8200
  export VAULT_TOKEN="$VAULT_DEV_ROOT_TOKEN_ID"
  vault read database/config/reporting-postgres
'
```

If the error says that `powerbi-reader` is not allowed, the UI omitted the
connection's API-only `allowed_roles` property. Use the repository's existing
idempotent bootstrap script to configure the exact connection and role:

```bash
docker compose --profile tools run --rm toolbox /work/bootstrap-vault.sh
./scripts/finish-ui-setup.sh
```

Afterward, return to the UI to inspect `reporting-postgres` and
`powerbi-reader`. This hybrid workflow is still useful for learning the UI,
while the script supplies fields the UI does not expose.

## Demonstrate credential rotation

```bash
./scripts/demo-rotation.sh
```

### Observed result

The following result was captured from the completed local POC. Transient
Docker progress lines and the second copy of the unchanged six-row result are
condensed because container names differ between runs.

```text
1. Query with synchronized credential (expect HTTP 200)
{
  "status": "ok",
  "rows": [
    {"month": "2026-01", "region": "East", "revenue": 125000},
    {"month": "2026-01", "region": "West", "revenue": 142500},
    {"month": "2026-02", "region": "East", "revenue": 131200},
    {"month": "2026-02", "region": "West", "revenue": 151750},
    {"month": "2026-03", "region": "East", "revenue": 138900},
    {"month": "2026-03", "region": "West", "revenue": 158300}
  ]
}

2. Rotate database password in Vault
Vault rotated the database password.

3. Query with stale simulated-gateway credential (expect HTTP 503)
{
  "status": "database authentication failed"
}

4. Synchronize the new credential from Vault
Gateway simulator credential synchronized from Vault.

5. Query again (expect HTTP 200)
{
  "status": "ok",
  "rows": [
    {"month": "2026-01", "region": "East", "revenue": 125000},
    {"month": "2026-01", "region": "West", "revenue": 142500},
    {"month": "2026-02", "region": "East", "revenue": 131200},
    {"month": "2026-02", "region": "West", "revenue": 151750},
    {"month": "2026-03", "region": "East", "revenue": 138900},
    {"month": "2026-03", "region": "West", "revenue": 158300}
  ]
}
Rotation demonstration completed successfully.
```

This proves the behavior the POC is intended to demonstrate:

1. The gateway simulator can query PostgreSQL using the credential synchronized
   from Vault.
2. Vault rotates the `powerbi_reader` database password.
3. The simulator's cached old credential immediately fails authentication.
4. Synchronization retrieves the current credential from Vault.
5. The same report query succeeds again without storing a password in source
   control.

You can inspect `database/static-creds/powerbi-reader` in the Vault UI. Avoid
displaying or copying its password outside this isolated local POC.

## Production database credential boundary

This POC gives Vault the PostgreSQL `postgres` administrator credential to keep
the local demonstration small and easy to reset. That is a POC simplification,
not the recommended production design.

In production, Vault needs a database identity with enough authority to rotate
the accounts assigned to it, but it should not normally receive the actual
PostgreSQL superuser password. A DBA should create a separate account such as
`vault_db_admin` and grant it only the privileges needed to manage explicitly
approved reporting identities.

| Credential | Used by | Responsibility |
|---|---|---|
| `postgres` superuser | DBA/bootstrap process only | Initial role creation and controlled emergency administration |
| `vault_db_admin` | Vault only | Rotate approved managed database accounts |
| `powerbi_reader` | Power BI gateway | Read approved reporting schemas, views, or stored procedures |

A typical production onboarding sequence is:

1. A DBA creates `vault_db_admin` and the read-only `powerbi_reader` account.
2. The DBA grants `vault_db_admin` only the authority needed to change the
   password of `powerbi_reader` and any other explicitly managed accounts.
3. An approved provisioning process supplies the initial `vault_db_admin`
   credential to Vault through a protected runtime channel. It must not be
   committed to source control, written to logs, or passed as an exposed
   command-line argument.
4. Vault stores the connection credential encrypted and manages the reporting
   account according to the configured rotation policy.
5. The credential-sync automation reads only the `powerbi_reader` credential
   and updates the Power BI gateway. Power BI never receives the Vault database
   administrator credential.

The production design must also define recovery procedures before allowing
Vault to rotate its own database connection credential. After root-credential
rotation, Vault does not reveal that password to an administrator. Recovery,
break-glass access, auditing, TLS, durable Vault storage, backups, and separation
of development, test, and production identities must therefore be reviewed
with the database and security teams.

Vault Enterprise offers a rootless PostgreSQL static-role workflow that can
manage a static account without retaining one shared privileged database
administrator connection. If the client has Vault Enterprise, that option
should be evaluated separately.

Recommended production statement:

> Vault will not be provided with the PostgreSQL superuser credential. A
> dedicated, least-privileged Vault database-administration account will be
> created with permission to rotate only approved reporting identities.

## Reset again

```bash
./scripts/reset.sh
```

Vault runs in development mode. Its data is intentionally temporary and is not
suitable for production.
