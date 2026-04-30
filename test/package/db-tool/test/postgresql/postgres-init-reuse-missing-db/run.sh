# shellcheck shell=dash

HECTIC_NAMESPACE=test-db-tool-postgres-init-reuse-missing-db

PG_WORKING_DIR=$(mktemp -d)
export PG_WORKING_DIR PG_DATABASE=testdb PG_PORT=5432 PG_SHARED_PRELOAD_LIBRARIES=''

cleanup() {
  postgres-cleanup >/dev/null 2>&1 || :
  rm -rf "$PG_WORKING_DIR"
}
trap 'cleanup' EXIT INT TERM

log notice "step 1: fresh init creates testdb"
if ! postgres-init; then
  log error "initial postgres-init failed"
  exit 1
fi

log notice "step 2: drop testdb to simulate stale-state cluster"
sockdir="$PG_WORKING_DIR/sock"
if ! dropdb -h "$sockdir" -p "$PG_PORT" -U "$(id -un)" testdb; then
  log error "dropdb failed"
  exit 1
fi

log notice "step 3: stop cluster (simulate prior devshell exit)"
postgres-cleanup >/dev/null 2>&1 || :

log notice "step 4: re-init with PG_REUSE=1 must recreate missing testdb"
export PG_REUSE=1
if ! postgres-init; then
  log error "postgres-init with PG_REUSE=1 and missing DB failed"
  exit 1
fi
unset PG_REUSE

log notice "step 5: verify testdb is reachable"
pgurl="postgresql://$(id -un)@/testdb?host=${sockdir}&port=5432"
if ! psql "$pgurl" -c 'SELECT 1;' >/dev/null 2>&1; then
  log error "testdb not reachable after reuse-create"
  exit 1
fi

log notice "test passed"
