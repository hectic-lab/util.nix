#!/bin/dash

HECTIC_NAMESPACE=test-migrate-up-single

log notice "test case: ${WHITE}migrate up single step"

# Create initial schema
psql "$DATABASE_URL" -c 'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)'

# Initialize migrator
if ! migrator --db-url "$DATABASE_URL" init; then
  log error "test failed: ${WHITE}init failed"
  exit 1
fi

# Apply first migration
if ! migrator --db-url "$DATABASE_URL" migrate up; then
  log error "test failed: ${WHITE}migrate up failed"
  exit 1
fi

# Verify migration was applied
applied_count=$(psql -Atc "SELECT COUNT(*) FROM hectic.migration" "$DATABASE_URL")
if [ "$applied_count" != "1" ]; then
  log error "test failed: ${WHITE}expected 1 migration, got $applied_count"
  exit 1
fi

# Verify column was added
if ! psql -Atc "SELECT email FROM users LIMIT 0" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}email column not added"
  exit 1
fi

log notice "test passed"

