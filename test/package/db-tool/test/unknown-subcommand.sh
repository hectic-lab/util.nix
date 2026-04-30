# shellcheck shell=dash

HECTIC_NAMESPACE=test-db-tool-unknown

log notice "test case: database nonsense exits non-zero (expected 1)"
set +e
database nonsense 2>/dev/null
code=$?
set -e

if [ "$code" = 0 ]; then
  log error "test failed: database nonsense exited 0 (should be non-zero)"
  exit 1
fi

log notice "test passed: exited $code"
