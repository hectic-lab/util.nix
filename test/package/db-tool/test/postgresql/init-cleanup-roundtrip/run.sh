# shellcheck shell=dash

HECTIC_NAMESPACE=test-db-tool-init-cleanup-roundtrip

PG_WORKING_DIR=$(mktemp -d)
export PG_WORKING_DIR PG_DATABASE=testdb PG_PORT=5432 PG_SHARED_PRELOAD_LIBRARIES=''

cleanup() {
  postgres-cleanup
  rm -rf "$PG_WORKING_DIR"
}
trap 'cleanup' EXIT INT TERM

log notice "test case: postgres-init starts cluster"
if ! postgres-init; then
  log error "postgres-init failed"
  exit 1
fi

pgurl="postgresql://$(id -un)@/testdb?host=${PG_WORKING_DIR}/sock&port=5432"
log notice "verifying connection"
if ! psql "$pgurl" -c 'SELECT 1;' >/dev/null 2>&1; then
  log error "connection failed after postgres-init"
  exit 1
fi

log notice "test case: postgres-cleanup stops cluster"
postgres-cleanup

log notice "verifying cluster stopped"
if pg_isready -h "${PG_WORKING_DIR}/sock" -p 5432 >/dev/null 2>&1; then
  log error "postgres still running after cleanup"
  exit 1
fi

log notice "test passed"
