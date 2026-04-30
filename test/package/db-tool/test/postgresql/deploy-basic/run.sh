# shellcheck shell=dash

HECTIC_NAMESPACE=test-db-tool-deploy-basic
export HECTIC_NAMESPACE

PG_WORKING_DIR=$(mktemp -d)
export PG_WORKING_DIR PG_DATABASE=testdb PG_PORT=5432 PG_SHARED_PRELOAD_LIBRARIES=''

cleanup() { postgres-cleanup; rm -rf "$PG_WORKING_DIR"; }
trap 'cleanup' EXIT INT TERM

LOCAL_DIR=$(mktemp -d)
export LOCAL_DIR

log notice "test case: database deploy --no-hydrate --no-patch exits 0"
if ! database deploy --no-hydrate --no-patch; then
  log error "database deploy failed"
  exit 1
fi

log notice "test passed"
