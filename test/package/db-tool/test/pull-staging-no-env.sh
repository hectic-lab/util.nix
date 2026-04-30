# shellcheck shell=dash

HECTIC_NAMESPACE=test-db-tool-pull-staging

export PGURL=""
unset STAGING_SSH_HOST STAGING_DB_URL STAGING_USER STAGING_HOST 2>/dev/null || true

log notice "test case: database pull_staging exits 3 without STAGING_SSH_HOST"
set +e
database pull_staging 2>/build/staging-err.txt
code=$?
set -e

if [ "$code" != 3 ]; then
  log error "test failed: expected exit 3, got $code"
  exit 1
fi

if ! grep -q 'STAGING_SSH_HOST' /build/staging-err.txt; then
  log error "test failed: stderr does not mention STAGING_SSH_HOST"
  exit 1
fi

log notice "test passed"

log notice "test passed"
