# shellcheck shell=dash

HECTIC_NAMESPACE=test-db-tool-deploy-basic

pg_harness_start

LOCAL_DIR=$(mktemp -d)
export LOCAL_DIR
mkdir -p "$LOCAL_DIR/devshell"
printf '#!/bin/dash\nexit 0\n' > "$LOCAL_DIR/devshell/postgres-init.sh"
chmod +x "$LOCAL_DIR/devshell/postgres-init.sh"

log notice "test case: database deploy --no-hydrate --no-patch exits 0"
if ! database deploy --no-hydrate --no-patch; then
  log error "database deploy failed"
  exit 1
fi

log notice "test passed"
