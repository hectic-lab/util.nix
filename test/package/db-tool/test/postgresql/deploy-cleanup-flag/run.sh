# shellcheck shell=dash

HECTIC_NAMESPACE=test-db-tool-deploy-cleanup-flag
export HECTIC_NAMESPACE

PG_WORKING_DIR=$(mktemp -d)
export PG_WORKING_DIR PG_DATABASE=testdb PG_PORT=5432 PG_SHARED_PRELOAD_LIBRARIES=''

LOCAL_DIR=$(mktemp -d)
export LOCAL_DIR

log notice "test case: database deploy --no-hydrate --no-patch --cleanup exits 0"
if ! database deploy --no-hydrate --no-patch --cleanup; then
  log error "database deploy --cleanup failed"
  exit 1
fi

log notice "test passed"
