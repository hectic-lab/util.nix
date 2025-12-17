#!/bin/dash

HECTIC_NAMESPACE=test-migrate-to-forward

log notice "test case: ${WHITE}migrate to (forward) specific migration"

# Create initial schema
psql "$DATABASE_URL" -c 'CREATE TABLE comments (id INTEGER PRIMARY KEY)'

# Initialize migrator
if ! migrator --db-url "$DATABASE_URL" init; then
  log error "test failed: ${WHITE}init failed"
  exit 1
fi

# Migrate to second migration (skipping intermediate)
if ! migrator --db-url "$DATABASE_URL" migrate to 20250101000002-add-user-id; then
  log error "test failed: ${WHITE}migrate to failed"
  exit 1
fi

# Verify 2 migrations were applied
applied_count=$(psql -Atc "SELECT COUNT(*) FROM hectic.migration" "$DATABASE_URL")
if [ "$applied_count" != "2" ]; then
  log error "test failed: ${WHITE}expected 2 migrations, got $applied_count"
  exit 1
fi

# Verify both columns exist
if ! psql -Atc "SELECT content, user_id FROM comments LIMIT 0" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}columns not added"
  exit 1
fi

log notice "test passed"

