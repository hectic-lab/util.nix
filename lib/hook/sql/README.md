# hectic SQL bundle

Single source of truth for every object created in the `hectic` PostgreSQL
schema. Consumed by:

- `package/migrator` — applies the bundle on `migrator init` (mandatory).
- `package/db-tool` — applies the bundle in `database hydrate` (default; opt
  out with `--no-hook`).
- External consumers (e.g. `proxydoe`) — invoke `psql -f` directly against the
  paths exposed via `self.lib.hectic.*.path`.

## Layout

| File | Purpose |
| --- | --- |
| `HECTIC_VERSION` | Single version string for the whole bundle (e.g. `0.1.0`). Read via `lib.fileContents`. |
| `hectic-version.sql` | Templated. Creates `hectic.version`, inserts the current `versionString`, raises on mismatch. |
| `hectic-secret.sql` | Creates `hectic.secret`, `hectic.load_secrets_from_env(text)`, `hectic.get_secret(text)`. |
| `hectic-migration.sql` | Creates the `hectic.migration` table and supporting domains/triggers used by `migrator`. |
| `hectic-inheritance.sql` | Creates `hectic.created_at`, `hectic.updated_at`, `hectic.immutable` parent tables and the DDL event triggers that enforce inheritance, attach `BEFORE UPDATE` triggers, and block DML on immutable tables outside `migration_mode`. |

`hectic-version.sql` is templated at Nix evaluation time: `@HECTIC_VERSION@`
is substituted with the contents of `HECTIC_VERSION`. All other files are
applied verbatim.

## Apply order

The bundle MUST be applied in this order (enforced by
`apply-hectic-bundle.sh`):

1. `hectic-version.sql` — version check first; aborts the rest on mismatch.
2. `hectic-secret.sql`
3. `hectic-migration.sql`
4. `hectic-inheritance.sql`

Re-applying the bundle is idempotent — every CREATE uses
`IF NOT EXISTS` / `CREATE OR REPLACE`, and the version check accepts a row
that already matches.

## Nix API (`self.lib.hectic`)

```nix
self.lib.hectic = {
  versionString;          # e.g. "0.1.0"
  version     = { sql; };           # templated
  secret      = { sql; path; };
  migration   = { sql; path; };
  inheritance = { sql; path; };
  applyBundleScript;                # ./hook/apply-hectic-bundle.sh
};
```

`.sql` is the file contents as a string. `.path` is the Nix store path of the
verbatim source (only available on non-templated entries; consumers needing a
materialized version of `version.sql` must do
`pkgs.runCommand "hectic-version.sql" { text = self.lib.hectic.version.sql; passAsFile = ["text"]; } ''cp "$textPath" "$out"''`).

## Shell helper (`apply-hectic-bundle.sh`)

`lib/hook/apply-hectic-bundle.sh` is a dash-compatible helper sourced by both
`migrator` and `db-tool`. Public entry point:

```sh
apply_hectic_bundle <PGURL> [<DOTENV_CONTENT>]
```

- `<PGURL>` — full PostgreSQL connection string.
- `<DOTENV_CONTENT>` — optional. When present, after applying the bundle the
  helper invokes `hectic.load_secrets_from_env(<dotenv>)` inside a
  dollar-quoted (`$ps_env$`) string so secret values cannot terminate the
  literal.

Required environment (paths to the SQL files):

- `HECTIC_VERSION_SQL`
- `HECTIC_SECRET_SQL`
- `HECTIC_MIGRATION_SQL`
- `HECTIC_INHERITANCE_SQL`

`migrator` and `db-tool` set these via Nix at build time. External consumers
typically invoke `psql -f` against the paths directly instead of sourcing the
helper.

## Adding a new SQL file

1. Add `lib/hook/sql/hectic-<name>.sql`.
2. Wire it into `lib/default.nix` under `lib.hectic.<name>`.
3. Inject `HECTIC_<NAME>_SQL` in both `package/migrator/default.nix` and
   `package/db-tool/default.nix`.
4. Append a `psql -f "$HECTIC_<NAME>_SQL"` step to
   `lib/hook/apply-hectic-bundle.sh` in the correct order.
5. Bump `HECTIC_VERSION` if the new content changes existing semantics.
6. Update tests in `test/package/migrator/test/postgresql/init-hectic-bundle/`
   and `test/package/db-tool/test/postgresql/hydrate-hook/`.

## Versioning

`HECTIC_VERSION` is a single global version for the bundle, not per-file.
Bump it on any breaking change to the schema. `hectic-version.sql` raises an
exception when the database row diverges from the bundle version, forcing a
deliberate migration before the rest of the bundle runs.
