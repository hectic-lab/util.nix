#!/bin/dash
# Applies the full hectic SQL bundle to a PostgreSQL database, in order:
#   1. version    (hard-fails on version mismatch)
#   2. secret     (hectic.secret table + load_secrets_from_env + get_secret)
#   3. migration  (hectic.migration table + domains + sha256_lower trigger)
#   4. inheritance (created_at/updated_at/immutable enforcement triggers)
#
# Idempotent: each SQL file uses IF NOT EXISTS / CREATE OR REPLACE.
#
# Required env (caller injects from Nix):
#   HECTIC_VERSION_SQL      - path to hectic-version.sql (substituted)
#   HECTIC_SECRET_SQL       - path to hectic-secret.sql
#   HECTIC_MIGRATION_SQL    - path to hectic-migration.sql
#   HECTIC_INHERITANCE_SQL  - path to hectic-inheritance.sql
#
# Usage:
#   apply_hectic_bundle <PGURL> [<DOTENV_CONTENT>]
#
# If DOTENV_CONTENT is non-empty, it is loaded into hectic.secret via
# hectic.load_secrets_from_env() after the bundle is applied.

apply_hectic_bundle() {
  pgurl="${1:-}"
  env_content="${2:-}"

  if [ -z "$pgurl" ]; then
    printf '%s\n' 'apply-hectic-bundle: PGURL is required (arg 1)' >&2
    return 3
  fi

  for var in HECTIC_VERSION_SQL HECTIC_SECRET_SQL HECTIC_MIGRATION_SQL HECTIC_INHERITANCE_SQL; do
    eval "val=\${$var:-}"
    if [ -z "$val" ]; then
      printf '%s\n' "apply-hectic-bundle: $var not set" >&2
      return 3
    fi
    if [ ! -r "$val" ]; then
      printf '%s\n' "apply-hectic-bundle: $var not readable: $val" >&2
      return 1
    fi
  done

  psql "$pgurl" -v ON_ERROR_STOP=1 -f "$HECTIC_VERSION_SQL"     || return 1
  psql "$pgurl" -v ON_ERROR_STOP=1 -f "$HECTIC_SECRET_SQL"      || return 1
  psql "$pgurl" -v ON_ERROR_STOP=1 -f "$HECTIC_MIGRATION_SQL"   || return 1
  psql "$pgurl" -v ON_ERROR_STOP=1 -f "$HECTIC_INHERITANCE_SQL" || return 1

  if [ -n "$env_content" ]; then
    # Dollar-quote with $ps_env$ tag to preserve all content verbatim.
    psql "$pgurl" -v ON_ERROR_STOP=1 <<SQL || return 1
SELECT hectic.load_secrets_from_env(\$ps_env\$
$env_content
\$ps_env\$);
SQL
  fi

  return 0
}
