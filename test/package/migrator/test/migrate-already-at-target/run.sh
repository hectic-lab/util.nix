#!/bin/dash

HECTIC_NAMESPACE=test-migrate-already-at-target

log notice "test case: ${WHITE}migrate when already at target"

# Create initial schema
psql "$DATABASE_URL" -c 'CREATE TABLE tags (id INTEGER PRIMARY KEY)'

# Initialize migrator
if ! migrator --db-url "$DATABASE_URL" init; then
  log error "test failed: ${WHITE}init failed"
  exit 1
fi

# Apply migration
if ! migrator --db-url "$DATABASE_URL" migrate up; then
  log error "test failed: ${WHITE}first migrate up failed"
  exit 1
fi

# Try to migrate to same position (should be no-op)
if ! migrator --db-url "$DATABASE_URL" migrate to 20250101000001-add-name; then
  log error "test failed: ${WHITE}migrate to same position failed"
  exit 1
fi

# Verify still only 1 migration
applied_count=$(psql -Atc "SELECT COUNT(*) FROM hectic.migration" "$DATABASE_URL")
if [ "$applied_count" != "1" ]; then
  log error "test failed: ${WHITE}expected 1 migration, got $applied_count"
  exit 1
fi

# Try migrate up when no more migrations available
set +e
migrator --db-url "$DATABASE_URL" migrate up
exit_code=$?
set -e

if [ "$exit_code" = "0" ]; then
  log error "test failed: ${WHITE}should error when no migrations left"
  exit 1
fi

log notice "test passed"

