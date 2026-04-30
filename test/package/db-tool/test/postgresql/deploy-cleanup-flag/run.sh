# shellcheck shell=dash

HECTIC_NAMESPACE=test-db-tool-deploy-cleanup-flag

pg_harness_start

LOCAL_DIR=$(mktemp -d)
export LOCAL_DIR
mkdir -p "$LOCAL_DIR/devshell"
printf '#!/bin/dash\nexit 0\n' > "$LOCAL_DIR/devshell/postgres-init.sh"
printf '#!/bin/dash\nexit 0\n' > "$LOCAL_DIR/devshell/postgres-cleanup.sh"
chmod +x "$LOCAL_DIR/devshell/postgres-init.sh" "$LOCAL_DIR/devshell/postgres-cleanup.sh"

log notice "test case: database deploy --no-hydrate --no-patch --cleanup exits 0"
if ! database deploy --no-hydrate --no-patch --cleanup; then
  log error "database deploy --cleanup failed"
  exit 1
fi

log notice "test passed"
