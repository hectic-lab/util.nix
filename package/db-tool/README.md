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
| `PATCH_LOG` | (stdout) | Path to log the output of database patches. |
| `HYDRATE_LOG` | (stdout) | Path to log the output of database hydration. |

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
