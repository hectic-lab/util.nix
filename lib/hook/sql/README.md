# hectic SQL bundle

Single source of truth for every object created in the `hectic` PostgreSQL
schema. Consumed by:

- `package/migrator` — applies the bundle on `migrator init` (mandatory).
- `package/db-tool` — applies the bundle in `db-dev` / `database hydrate`
  (default; opt out with `--no-hook`) and in `db-ops secrets load`.
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
  version     = { sql; path; };     # templated
  secret      = { sql; path; };
  migration   = { sql; path; };
  inheritance = { sql; path; };
  bundleFiles;                      # ordered bundle file paths
  applyBundleScript;                # generated helper shell source with paths embedded
};
```

`.sql` is the file contents as a string. `.path` is the Nix store path of the
materialized file to pass to `psql -f`. `version.path` is generated at Nix
evaluation time from the templated SQL; the other `*.path` entries point at the
verbatim source files in the store.

## Shell helper (`apply-hectic-bundle.sh`)

`lib/hook/apply-hectic-bundle.sh` is a dash-compatible helper template.
`self.lib.hectic.applyBundleScript` is the generated shell source with concrete
SQL paths embedded at Nix evaluation time. `migrator`, `db-dev`, and `db-ops` splice that
shell source directly into their generated scripts. Public entry point:

```sh
apply_hectic_bundle <PGURL> [<DOTENV_CONTENT>]
```

- `<PGURL>` — full PostgreSQL connection string.
- `<DOTENV_CONTENT>` — optional. When present, after applying the bundle the
  helper invokes `hectic.load_secrets_from_env(<dotenv>)` inside a
  dollar-quoted (`$ps_env$`) string so secret values cannot terminate the
  literal.

The SQL file paths are embedded into the helper at Nix evaluation time, so
callers only need to source the generated script and call the function.
External consumers that do not want to source the helper can still invoke
`psql -f` against `self.lib.hectic.bundleFiles` or the individual
`self.lib.hectic.*.path` entries directly.

## Adding a new SQL file

1. Add `lib/hook/sql/hectic-<name>.sql`.
2. Wire it into `lib/default.nix` under `lib.hectic.<name>`.
3. Add its `.path` to `lib.hectic.bundleFiles` in the correct order.
4. Add a matching placeholder/replacement in `lib.hectic.applyBundleScript` and
   update `lib/hook/apply-hectic-bundle.sh` to apply the file.
5. Bump `HECTIC_VERSION` if the new content changes existing semantics.
6. Update tests in `test/package/migrator/test/postgresql/init-hectic-bundle/`,
   `test/package/db-tool/test/postgresql/hydrate-hook/`, and any `db-ops`
   bundle-loading coverage.

## Versioning

`HECTIC_VERSION` is a single global version for the bundle, not per-file.
Bump it on any breaking change to the schema. `hectic-version.sql` raises an
exception when the database row diverges from the bundle version, forcing a
deliberate migration before the rest of the bundle runs.
