# shellcheck shell=dash

HECTIC_NAMESPACE=test-db-tool-log-subcommand

PG_WORKING_DIR=$(mktemp -d)
LOCAL_DIR=$(mktemp -d)
export PG_WORKING_DIR LOCAL_DIR PGURL='postgresql://localhost/db'
mkdir -p "$PG_WORKING_DIR/data/log"

trap 'rm -rf "$PG_WORKING_DIR" "$LOCAL_DIR"' EXIT INT TERM

log notice "test case: database log list exits 0 with empty log dir"
if ! database log list; then
  log error "database log list failed"
  exit 1
fi

log notice "test passed"
