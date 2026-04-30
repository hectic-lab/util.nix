# db-tool

PostgreSQL development database management tool. Drop-in replacement for per-project database.sh / postgres-init.sh / postgres-cleanup.sh scripts. Provides database, postgres-init, and postgres-cleanup binaries.

## Provided Binaries

| Binary | Description |
| --- | --- |
| `database` | Main script for managing migrations, deployments, and logs. |
| `postgres-init` | Ephemeral PostgreSQL cluster initialization and startup. |
| `postgres-cleanup` | Graceful shutdown and cleanup of the PostgreSQL cluster. |

## Required Environment Variables

These variables must be set for `db-tool` to function.

| Variable | Description |
| --- | --- |
| `LOCAL_DIR` | Absolute path to the project root directory. |
| `DB_URL` | Full PostgreSQL connection string (e.g., `postgresql://user@localhost/dbname?host=$PG_WORKING_DIR`). |
| `PG_WORKING_DIR` | Directory where the PostgreSQL cluster data and sockets are stored. |

## Optional Environment Variables

| Variable | Default Value | Description |
| --- | --- | --- |
| `DATABASE_DIR` | `${LOCAL_DIR}/db` | Root directory for database-related files. |
| `MIGRATION_DIR` | `${DATABASE_DIR}/migration` | Directory containing SQL migration files. |
| `DATABASE_SOURCE` | `${DATABASE_DIR}/src` | Directory containing source SQL files for hydration. |
| `PG_URL_VAR` | `PGURL` | The name of the environment variable where the computed PG URL will be exported. |
| `PG_LOG_PATH` | (unset) | Path to redirect PostgreSQL server logs. |
| `PG_CONF_FILE` | (unset) | Path to a `postgresql.conf` file. When set, replaces the script-generated config entirely on fresh init. `port` and `unix_socket_directories` are still appended at runtime (always overridden). When set, `PG_DISABLE_LOGGING` and `PG_SHARED_PRELOAD_LIBRARIES` are ignored. |
| `PG_SHARED_PRELOAD_LIBRARIES` | `pg_cron` | Comma-separated `shared_preload_libraries` value. Set to empty string to disable. Ignored when `PG_CONF_FILE` is set. |
| `PG_DISABLE_LOGGING` | `0` | Set to `1` to disable PostgreSQL logging collector. Ignored when `PG_CONF_FILE` is set. |
| `HECTIC_DOTENV_FILE` | (unset) | Optional dotenv file. When set and readable, `database hydrate` passes its contents to `hectic.load_secrets_from_env(...)` after applying the bundle. Falls back to `${LOCAL_DIR}/.env.${ENVIRONMENT}` when unset. |
| `PATCH_LOG` | (stdout) | Path to log the output of database patches. |
| `HYDRATE_LOG` | (stdout) | Path to log the output of database hydration. |

## Postgres Package Override

By default, `db-tool`/`postgres-init`/`postgres-cleanup` use plain `postgresql_17` from nixpkgs. If you need extensions (e.g. `pg_cron`), override the postgres package per-output:

```nix
let
  myPg = pkgs.postgresql_17.withJIT.withPackages (_: [
    pkgs.postgresql_17.pkgs.pg_cron
  ]);
in {
  packages = [
    (pkgs.hectic."db-tool".override          { postgresql = myPg; })
    (pkgs.hectic."postgres-init".override    { postgresql = myPg; })
    (pkgs.hectic."postgres-cleanup".override { postgresql = myPg; })
  ];
}
```

## pull_staging Contract

The `pull_staging` subcommand allows importing data from a remote staging environment into the local `test-data.sql` file. This functionality requires four specific environment variables to be defined:

1. `STAGING_SSH_HOST`: The SSH destination for the staging server.
2. `STAGING_DB_URL`: The PostgreSQL connection string for the remote staging database.
3. `STAGING_DUMP_TABLES`: A space-separated list of tables to include in the data dump.
4. `STAGING_DUMP_FLAGS`: Additional flags to pass to `pg_dump` (e.g., `--column-inserts`).

If any of these variables are missing when `pull_staging` is invoked, the tool will exit with code 3 and print the name of the missing variable to stderr.

## Subcommands

- `deploy`: Execute the full deployment flow (hydrate + patch). Supports `--cleanup` to teardown after success.
- `log`: Inspect database logs. Supports `list` and index-based selection.
- `test`: Execute database tests located in `${DATABASE_DIR}/test/test.sql`.
- `check`: Run a deployment validation in an isolated, temporary PostgreSQL cluster.
- `cleanup`: Stop the local database cluster and remove the `PG_WORKING_DIR`.
- `pull_staging`: Import data from the staging environment based on the env contract.
- `init`: Wrapper around `postgres-init` to start the cluster.
- `migrator`: Directly invoke the migration tool with the correct environment context.

## shellHook Example

To use `db-tool` in a Nix development shell, add the following to your `flake.nix` or `shell.nix`:

```nix
{
  # ...
  devShells.default = pkgs.mkShell {
    packages = [
      pkgs.hectic.db-tool
      pkgs.hectic.postgres-init
      pkgs.hectic.postgres-cleanup
    ];

    shellHook = ''
      export LOCAL_DIR="$PWD"
      export DATABASE_DIR="$LOCAL_DIR/db"
      export MIGRATION_DIR="$DATABASE_DIR/migration"
      export DATABASE_SOURCE="$DATABASE_DIR/src"
      export PG_WORKING_DIR="$LOCAL_DIR/focus/postgresql"
      export DB_URL="postgresql://user@localhost/dbname?host=$PG_WORKING_DIR&port=5432"
      
      # for other non-db scripts (deploy.sh, task.sh, etc.):
      export HECTIC_LIB="${pkgs.hectic.helpers.posix-shell.log}"

      # Initialize and start the ephemeral database cluster
      . ${pkgs.hectic.postgres-init}/bin/postgres-init
    '';
  };
}
```

## hectic Bundle

`db-tool` and `migrator` apply a single bundle of SQL files that bootstrap the
`hectic` schema. The bundle lives in
[`lib/hook/sql/`](../../lib/hook/sql/README.md) — see that README for full
contract, file layout, and the `self.lib.hectic.*` Nix API.

The bundle creates:

- `hectic.version` — single version row for the entire hectic system.
  Mismatch between database and bundle raises an exception.
- `hectic.secret` + `hectic.load_secrets_from_env(text)` +
  `hectic.get_secret(text)` — encrypted secret storage and dotenv loader.
- `hectic.migration` — table consumed by `migrator`.
- `hectic.created_at` / `hectic.updated_at` / `hectic.immutable` parent tables
  and the DDL event triggers that enforce inheritance, attach
  `BEFORE UPDATE` triggers, and block DML on immutable tables outside
  `migration_mode`.

Inheritance details:

- `hectic.created_at(created_at TIMESTAMPTZ NOT NULL DEFAULT NOW())` — every
  user table must `INHERITS (hectic.created_at)`. The event trigger
  `hectic_enforce_created_at_inheritance` raises on `CREATE TABLE` otherwise.
- `hectic.updated_at(updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW())` —
  optional. Any inheriting table automatically gets a
  `BEFORE UPDATE FOR EACH ROW` trigger calling `hectic.set_updated_at()`.
- `hectic.immutable()` — pure marker. Inheriting tables are blocked from
  `INSERT`/`UPDATE`/`DELETE`/`TRUNCATE` outside migration mode. To allow DML
  inside a migration, wrap it in a transaction:

  ```sql
  BEGIN;
  SET LOCAL hectic.migration_mode = 'on';
  INSERT INTO public.frozen (id, label) VALUES (1, 'x');
  COMMIT;
  ```

  `SET LOCAL` is required so the permission cannot leak past `COMMIT`.

Always-exempt schemas: `hectic`, `information_schema`, anything matching
`pg_*`. Declarative partitions (`relispartition = true`) and temporary tables
are also auto-exempt.

Per-database opt-out for additional schemas via the
`hectic.inheritance_extra_excluded_schemas` GUC (comma-separated):

```sql
ALTER DATABASE mydb SET hectic.inheritance_extra_excluded_schemas = 'legacy,etl';
```

### Responsibility split

| Component | Applies bundle? |
| --- | --- |
| `postgres-init` | **No.** Pure PostgreSQL provisioner — starts a vanilla cluster, nothing more. |
| `migrator init` | **Yes, mandatory.** The bundle is a hard prerequisite for `hectic.migration`. |
| `database hydrate` | **Yes, by default.** Re-applied on every hydrate. Skip with `--no-hook`. After applying the bundle, hydrate also calls `hectic.load_secrets_from_env(<dotenv>)` if `HECTIC_DOTENV_FILE` (or `${LOCAL_DIR}/.env.${ENVIRONMENT}`) is readable. |

The bundle is idempotent — repeated application is safe.

### `db-tool diff` and immutable tables

`database diff` already includes immutable tables in its schema-level
comparison (via `pg_dump --schema-only`). On top of that, when a `hectic`
schema is present in either side, it appends an
`--- IMMUTABLE TABLE DATA ---` section to the diff with a per-table unified
diff of the rows of every table inheriting `hectic.immutable`. Drift in
"frozen" reference data therefore surfaces in the same pager view as schema
drift, and the subcommand exits non-zero when either differs.

### Apply manually via `psql`

For external consumers (e.g. NixOS modules) bypass the helper and call `psql`
directly against the paths exposed by `self.lib.hectic.*.path`:

```nix
services.postgresql.initialScript = pkgs.writeText "hectic-init.sql" ''
  \i ${self.lib.hectic.secret.path}
  \i ${self.lib.hectic.migration.path}
  \i ${self.lib.hectic.inheritance.path}
'';
```

The version file (`self.lib.hectic.version`) is templated and only exposes
`.sql` (a string). Materialize it with `pkgs.writeText` if a path is needed.

## Exit Codes

| Code | Meaning |
| --- | --- |
| 1 | Generic error. |
| 2 | Ambiguous arguments or state. |
| 3 | Missing required argument or environment variable. |
| 5 | Provided table does not exist. |
| 9 | Argument or command not found. |
| 13 | Program bug or unexpected system state. |
| 127 | Command not found (missing dependency). |
