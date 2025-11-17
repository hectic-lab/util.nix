log notice "test case: ${WHITE}error: ambiguous command"
set +e
migrator --inherits tablename --inherits 'table name' list migrate
error_code=$?
set -e

if [ "$error_code" = 0 ]; then
  log error "test failed: ${WHITE}no error handler"
  exit 1
elif [ "$error_code" != 2 ]; then
  log error "test failed: ${WHITE}unexpected error code"
  exit 1
fi

log notice "test case: ${WHITE}error: ambiguous migrate command"
set +e
migrator --inherits tablename --inherits 'table name' migrate to up
error_code=$?
set -e

if [ "$error_code" = 0 ]; then
  log error "test failed: ${WHITE}no error handler"
  exit 1
elif [ "$error_code" != 2 ]; then
  log error "test failed: ${WHITE}unexpected error code"
  exit 1
fi
