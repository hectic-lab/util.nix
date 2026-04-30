# shellcheck shell=dash

HECTIC_NAMESPACE=test-db-tool-hydrate-hook

PG_WORKING_DIR=$(mktemp -d)
export PG_WORKING_DIR PG_DATABASE=testdb PG_PORT=5432 PG_SHARED_PRELOAD_LIBRARIES=''

cleanup() {
  postgres-cleanup >/dev/null 2>&1 || :
  rm -rf "$PG_WORKING_DIR" "$LOCAL_DIR"
}
trap 'cleanup' EXIT INT TERM

LOCAL_DIR=$(mktemp -d)
export LOCAL_DIR

mkdir -p "${LOCAL_DIR}/db/src"
: > "${LOCAL_DIR}/db/src/entrypoint.sql"

if ! postgres-init; then
  log error "postgres-init failed"
  exit 1
fi

PGURL="postgresql://$(id -un)@/testdb?host=${PG_WORKING_DIR}/sock&port=5432"
export PGURL

count_hectic_objects() {
  psql "$PGURL" -v ON_ERROR_STOP=1 -tAc \
    "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hectic';"
}

log notice "case 1: postgres-init alone does not create hectic schema"
got=$(psql "$PGURL" -v ON_ERROR_STOP=1 -tAc "SELECT count(*) FROM pg_namespace WHERE nspname='hectic';") || exit 1
[ "$got" = 0 ] || { log error "hectic schema must not exist after pure postgres-init (got: $got)"; exit 1; }

log notice "case 2: hydrate --no-hook does not apply bundle"
if ! database hydrate --no-hook; then
  log error "database hydrate --no-hook failed"
  exit 1
fi
got=$(psql "$PGURL" -v ON_ERROR_STOP=1 -tAc "SELECT count(*) FROM pg_namespace WHERE nspname='hectic';") || exit 1
[ "$got" = 0 ] || { log error "hectic schema unexpectedly created with --no-hook (got: $got)"; exit 1; }

log notice "case 3: hydrate (default) applies bundle"
if ! database hydrate; then
  log error "database hydrate failed"
  exit 1
fi
got=$(count_hectic_objects) || exit 1
[ "$got" -ge 6 ] || { log error "expected >=6 hectic objects after hydrate, got: $got"; exit 1; }

got=$(psql "$PGURL" -v ON_ERROR_STOP=1 -tAc "SELECT count(*) FROM hectic.version;") || exit 1
[ "$got" = 1 ] || { log error "hectic.version row missing (got: $got)"; exit 1; }

log notice "case 4: hydrate is idempotent"
if ! database hydrate; then
  log error "second database hydrate failed"
  exit 1
fi

log notice "case 5: HECTIC_DOTENV_FILE is honored"
dotenv_file=$(mktemp)
printf 'TEST_SECRET=hello-world\n' > "$dotenv_file"
HECTIC_DOTENV_FILE="$dotenv_file" database hydrate || {
  log error "hydrate with HECTIC_DOTENV_FILE failed"
  rm -f "$dotenv_file"
  exit 1
}
rm -f "$dotenv_file"

log notice "test passed"
