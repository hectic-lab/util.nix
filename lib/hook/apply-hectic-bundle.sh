#!/bin/dash
# Applies the full hectic SQL bundle to a PostgreSQL database, in order:
#   1. version    (hard-fails on version mismatch)
#   2. secret     (hectic.secret table + load_secrets_from_env + get_secret)
#   3. migration  (hectic.migration table + domains + sha256_lower trigger)
#   4. inheritance (created_at/updated_at/immutable enforcement triggers)
#
# Idempotent: each SQL file uses IF NOT EXISTS / CREATE OR REPLACE.
#
# Usage:
#   apply_hectic_bundle <PGURL> [<DOTENV_CONTENT>]
#
# If DOTENV_CONTENT is non-empty, it is base64-encoded and then loaded into
# hectic.secret via hectic.load_secrets_from_env() after the bundle is applied.
# SQL file paths are substituted by Nix evaluation time.

apply_hectic_bundle() {
  pgurl="${1:-}"
  env_content="${2:-}"

  if [ -z "$pgurl" ]; then
    printf '%s\n' 'apply-hectic-bundle: PGURL is required (arg 1)' >&2
    return 3
  fi

  set -- \
    "@HECTIC_VERSION_SQL@" \
    "@HECTIC_SECRET_SQL@" \
    "@HECTIC_MIGRATION_SQL@" \
    "@HECTIC_INHERITANCE_SQL@"

  for sql_path do
    if [ ! -r "$sql_path" ]; then
      printf '%s\n' "apply-hectic-bundle: SQL file not readable: $sql_path" >&2
      return 1
    fi
  done

  for sql_path do
    psql "$pgurl" -v ON_ERROR_STOP=1 -f "$sql_path" || return 1
  done

  if [ -n "$env_content" ]; then
    env_content_b64="$(printf '%s' "$env_content" | base64 | tr -d '\n')" || return 1
    psql "$pgurl" -v ON_ERROR_STOP=1 <<SQL || return 1
SELECT hectic.load_secrets_from_env(convert_from(decode('$env_content_b64', 'base64'), 'UTF8'));
SQL
  fi

  return 0
}
