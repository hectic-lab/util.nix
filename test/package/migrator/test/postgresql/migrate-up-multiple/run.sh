#!/bin/dash

HECTIC_NAMESPACE=test-migrate-up-multiple

log notice "test case: ${WHITE}migrate up multiple steps"

# Create initial schema
psql "$DATABASE_URL" -c 'CREATE TABLE posts (id INTEGER PRIMARY KEY, title TEXT)'

# Initialize migrator
if ! migrator --db-url "$DATABASE_URL" init; then
  log error "test failed: ${WHITE}init failed"
  exit 1
fi

# Apply 3 migrations at once
if ! migrator --db-url "$DATABASE_URL" migrate up 3; then
  log error "test failed: ${WHITE}migrate up 3 failed"
  exit 1
fi

# Verify all 3 migrations were applied
applied_count=$(psql -Atc "SELECT COUNT(*) FROM hectic.migration" "$DATABASE_URL")
if [ "$applied_count" != "3" ]; then
  log error "test failed: ${WHITE}expected 3 migrations, got $applied_count"
  exit 1
fi

# Verify all columns were added
if ! psql -Atc "SELECT content, author, published_at FROM posts LIMIT 0" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}not all columns were added"
  exit 1
fi

log notice "test passed"

