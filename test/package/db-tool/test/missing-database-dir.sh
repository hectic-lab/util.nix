# shellcheck shell=dash

HECTIC_NAMESPACE=test-db-tool-missing-dir

export PGURL=""
unset LOCAL_DIR DATABASE_DIR DB_URL 2>/dev/null || true

log notice "test case: database deploy fails without LOCAL_DIR"
set +e
database deploy 2>/tmp/missing-err.txt
code=$?
set -e

if [ "$code" = 0 ]; then
  log error "test failed: database deploy exited 0 without LOCAL_DIR"
  exit 1
fi

log notice "test passed: exited $code"
