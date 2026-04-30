# shellcheck shell=dash

HECTIC_NAMESPACE=test-db-tool-postgres-cleanup-stale-pidfile

PG_WORKING_DIR=$(mktemp -d)
export PG_WORKING_DIR

mkdir -p "$PG_WORKING_DIR/data"
printf '99999999\n' > "$PG_WORKING_DIR/data/postmaster.pid"

trap 'rm -rf "$PG_WORKING_DIR"' EXIT INT TERM

log notice "test case: postgres-cleanup exits 0 with stale pidfile"
if ! postgres-cleanup; then
  log error "postgres-cleanup failed with stale pidfile"
  exit 1
fi

log notice "test passed"
