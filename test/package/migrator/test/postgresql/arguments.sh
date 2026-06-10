log notice "test case: ${WHITE}error: ambiguous command"
set +e
migrator --inherits tablename --inherits 'table name' list migrate >/tmp/migrator-arguments-1.out 2>&1
error_code=$?
set -e

if [ "$error_code" = 0 ]; then
  log error "test failed: ${WHITE}no error handler"
  exit 1
elif [ "$error_code" != 2 ]; then
  log error "test failed: ${WHITE}unexpected error code"
  exit 1
fi

if ! grep -q 'ambiguous subcommand' /tmp/migrator-arguments-1.out; then
  log error "test failed: ${WHITE}missing ambiguous subcommand diagnostic"
  exit 1
fi

log notice "test case: ${WHITE}error: ambiguous migrate command"
set +e
migrator --inherits tablename --inherits 'table name' migrate to up >/tmp/migrator-arguments-2.out 2>&1
error_code=$?
set -e

if [ "$error_code" = 0 ]; then
  log error "test failed: ${WHITE}no error handler"
  exit 1
elif [ "$error_code" != 2 ]; then
  log error "test failed: ${WHITE}unexpected error code"
  exit 1
fi

if ! grep -q 'ambiguous migrate subcommand' /tmp/migrator-arguments-2.out; then
  log error "test failed: ${WHITE}missing ambiguous migrate diagnostic"
  exit 1
fi

log notice "test case: ${WHITE}error: init invalid argument is logged"
set +e
migrator init --wat >/tmp/migrator-arguments-3.out 2>&1
error_code=$?
set -e

if [ "$error_code" != 9 ]; then
  log error "test failed: ${WHITE}expected exit code 9 for invalid init argument, got $error_code"
  exit 1
fi

if ! grep -q 'init argument .*--wat.* does not exists' /tmp/migrator-arguments-3.out; then
  log error "test failed: ${WHITE}missing init invalid argument diagnostic"
  exit 1
fi

log notice "test case: ${WHITE}error: list invalid argument is logged with correct command name"
set +e
migrator list --wat >/tmp/migrator-arguments-4.out 2>&1
error_code=$?
set -e

if [ "$error_code" != 9 ]; then
  log error "test failed: ${WHITE}expected exit code 9 for invalid list argument, got $error_code"
  exit 1
fi

if ! grep -q 'list argument .*--wat.* does not exists' /tmp/migrator-arguments-4.out; then
  log error "test failed: ${WHITE}missing list invalid argument diagnostic"
  exit 1
fi
