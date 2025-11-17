#!/bin/dash

HECTIC_NAMESPACE=test-init-migrator

### CASE 1
log notice "test case: ${WHITE}dry run"

if ! migration_table_sql="$(migrator init --dry-run)"; then
  log error "test failed: ${WHITE}error on migration table init dry run"
  exit 1
fi

### CASE 3
log notice "test case: ${WHITE}error: not provided --db-url"
set +e
migrator init
error_code=$?
set -e

if [ "$error_code" = 0 ]; then
  log error "test failed: ${WHITE}no error handler"
  exit 1
elif [ "$error_code" != 3 ]; then
  log error "test failed: ${WHITE}unexpected error code"
  exit 1
fi

### CASE 4
log notice "test case: ${WHITE}normal"

if ! migrator --db-url "$DATABASE_URL" init; then
  log error "test failed: ${WHITE}error on init sql"
  exit 1
fi

if ! psql -v ON_ERROR_STOP=1 "$DATABASE_URL" -c 'SELECT * FROM hectic.migration'; then
  log error "test failed: ${WHITE} tabe hectic.migration was not created"
  exit 1
fi

### CASE 5
log notice "test case: ${WHITE}reinit (must just be ignored)"

if ! migrator init --db-url "$DATABASE_URL"; then
  log error "test failed: ${WHITE}error on init sql"
  exit 1
fi

if ! psql -v ON_ERROR_STOP=1 "$DATABASE_URL" -c 'SELECT * FROM hectic.migration'; then
  log error "test failed: ${WHITE} tabe hectic.migration was not created"
  exit 1
fi

log notice "test passed"
