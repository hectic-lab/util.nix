#!/bin/dash

HECTIC_NAMESPACE=test-migrate-down-multiple

log notice "test case: ${WHITE}migrate down multiple steps"

# Create initial schema
psql "$DATABASE_URL" -c 'CREATE TABLE orders (id INTEGER PRIMARY KEY)'

# Initialize migrator
if ! migrator --db-url "$DATABASE_URL" init; then
  log error "test failed: ${WHITE}init failed"
  exit 1
fi

# Apply 4 migrations
if ! migrator --db-url "$DATABASE_URL" migrate up 4; then
  log error "test failed: ${WHITE}migrate up failed"
  exit 1
fi

# Verify all columns exist
if ! psql -Atc "SELECT user_id, total, status, created_at FROM orders LIMIT 0" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}not all columns added"
  exit 1
fi

# Migrate down 3 steps (should leave only first migration)
if ! migrator --db-url "$DATABASE_URL" migrate down 3; then
  log error "test failed: ${WHITE}migrate down 3 failed"
  exit 1
fi

# Verify only 1 migration remains
applied_count=$(psql -Atc "SELECT COUNT(*) FROM hectic.migration" "$DATABASE_URL")
if [ "$applied_count" != "1" ]; then
  log error "test failed: ${WHITE}expected 1 migration, got $applied_count"
  exit 1
fi

# Verify only user_id column remains
if ! psql -Atc "SELECT user_id FROM orders LIMIT 0" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}user_id should still exist"
  exit 1
fi

if psql -Atc "SELECT total FROM orders LIMIT 0" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}total column should be removed"
  exit 1
fi

log notice "test passed"

