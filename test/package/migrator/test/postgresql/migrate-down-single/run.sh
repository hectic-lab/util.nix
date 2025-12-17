#!/bin/dash

HECTIC_NAMESPACE=test-migrate-down-single

log notice "test case: ${WHITE}migrate down single step"

# Create initial schema
psql "$DATABASE_URL" -c 'CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT)'

# Initialize migrator
if ! migrator --db-url "$DATABASE_URL" init; then
  log error "test failed: ${WHITE}init failed"
  exit 1
fi

# Apply 2 migrations
if ! migrator --db-url "$DATABASE_URL" migrate up 2; then
  log error "test failed: ${WHITE}migrate up failed"
  exit 1
fi

# Verify both columns exist
if ! psql -Atc "SELECT price, description FROM products LIMIT 0" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}columns not added"
  exit 1
fi

# Migrate down one step
if ! migrator --db-url "$DATABASE_URL" migrate down; then
  log error "test failed: ${WHITE}migrate down failed"
  exit 1
fi

# Verify only 1 migration remains
applied_count=$(psql -Atc "SELECT COUNT(*) FROM hectic.migration" "$DATABASE_URL")
if [ "$applied_count" != "1" ]; then
  log error "test failed: ${WHITE}expected 1 migration, got $applied_count"
  exit 1
fi

# Verify description column was removed but price remains
if psql -Atc "SELECT description FROM products LIMIT 0" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}description column should be removed"
  exit 1
fi

if ! psql -Atc "SELECT price FROM products LIMIT 0" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}price column should still exist"
  exit 1
fi

log notice "test passed"

