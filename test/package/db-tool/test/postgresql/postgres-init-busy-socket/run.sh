# shellcheck shell=dash

HECTIC_NAMESPACE=test-db-tool-postgres-init-busy-socket

PG_WORKING_DIR=$(mktemp -d)
export PG_WORKING_DIR PG_DATABASE=testdb PG_PORT=5432 PG_SHARED_PRELOAD_LIBRARIES=''

trap 'pg_harness_stop; rm -rf "$PG_WORKING_DIR"' EXIT INT TERM

log notice "setup: creating initial postgres cluster"
if ! postgres-init; then
  log error "setup failed: initial postgres-init failed"
  exit 1
fi

log notice "setup: stopping postgres to free socket"
postgres-cleanup

log notice "setup: occupying socket with netcat"
pg_harness__start_busy_socket "$PG_WORKING_DIR/sock"
i=0
while [ "$i" -lt 50 ] && ! [ -S "$PG_HARNESS_BUSY_SOCKET_PATH" ]; do
  sleep 0.1
  i=$((i + 1))
done
[ -S "$PG_HARNESS_BUSY_SOCKET_PATH" ] || { log error "busy socket not ready"; exit 1; }
printf '%d\n' "$PG_HARNESS_BUSY_SOCKET_PID" > "${PG_HARNESS_BUSY_SOCKET_PATH}.lock"

log notice "test case: postgres-init fails when socket is pre-occupied"
PG_REUSE=1
export PG_REUSE
set +e
postgres-init
code=$?
set -e

if [ "$code" = 0 ]; then
  log error "test failed: postgres-init exited 0 with busy socket"
  exit 1
fi

log notice "test passed: exited $code"
