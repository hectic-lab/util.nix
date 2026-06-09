# shellcheck shell=dash

HECTIC_NAMESPACE=test-db-ops-secrets-load

PG_WORKING_DIR=$(mktemp -d)
export PG_WORKING_DIR PG_DATABASE=testdb PG_PORT=5432 PG_SHARED_PRELOAD_LIBRARIES=''

cleanup() {
  postgres-cleanup >/dev/null 2>&1 || :
  rm -rf "$PG_WORKING_DIR"
}
trap 'cleanup' EXIT INT TERM

if ! postgres-init; then
  log error "postgres-init failed"
  exit 1
fi

PGURL="postgresql://$(id -un)@/testdb?host=${PG_WORKING_DIR}/sock&port=5432"
export PGURL

dotenv_file=$(mktemp)
printf 'TEST_SECRET=hello-world\nQUOTED_SECRET="quoted value"\nDELIMITER_SECRET=before$ps_env$after\n' > "$dotenv_file"

if ! db-ops secrets load --dotenv-file "$dotenv_file"; then
  log error "db-ops secrets load failed"
  rm -f "$dotenv_file"
  exit 1
fi
rm -f "$dotenv_file"

secret_value=$(psql "$PGURL" -v ON_ERROR_STOP=1 -tAc "SELECT value FROM hectic.secret WHERE key = 'TEST_SECRET';") || exit 1
[ "$secret_value" = "hello-world" ] || {
  log error "expected TEST_SECRET to be loaded, got: $secret_value"
  exit 1
}

quoted_value=$(psql "$PGURL" -v ON_ERROR_STOP=1 -tAc "SELECT value FROM hectic.secret WHERE key = 'QUOTED_SECRET';") || exit 1
[ "$quoted_value" = "quoted value" ] || {
  log error "expected QUOTED_SECRET to strip outer quotes, got: $quoted_value"
  exit 1
}

delimiter_value=$(psql "$PGURL" -v ON_ERROR_STOP=1 -tAc "SELECT value FROM hectic.secret WHERE key = 'DELIMITER_SECRET';") || exit 1
[ "$delimiter_value" = 'before$ps_env$after' ] || {
  log error "expected DELIMITER_SECRET to preserve dollar-quote delimiter text, got: $delimiter_value"
  exit 1
}

hectic_schema=$(psql "$PGURL" -v ON_ERROR_STOP=1 -tAc "SELECT count(*) FROM pg_namespace WHERE nspname='hectic';") || exit 1
[ "$hectic_schema" = 1 ] || {
  log error "expected hectic schema to exist, got: $hectic_schema"
  exit 1
}

log notice "test passed"
