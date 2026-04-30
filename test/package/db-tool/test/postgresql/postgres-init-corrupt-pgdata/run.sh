# shellcheck shell=dash

HECTIC_NAMESPACE=test-db-tool-postgres-init-corrupt-pgdata

pg_harness_start_corrupt_dir

export PG_WORKING_DIR="$PG_HARNESS_PGDATA_OVERRIDE"
export PG_SHARED_PRELOAD_LIBRARIES=''

trap 'pg_harness_stop' EXIT INT TERM

log notice "test case: postgres-init fails when PG_WORKING_DIR is a regular file"
set +e
postgres-init
code=$?
set -e

if [ "$code" = 0 ]; then
  log error "test failed: postgres-init exited 0 with corrupt dir"
  exit 1
fi

log notice "test passed: exited $code"
