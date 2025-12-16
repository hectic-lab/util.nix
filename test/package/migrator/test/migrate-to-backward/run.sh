#!/bin/dash

HECTIC_NAMESPACE=test-migrate-to-backward

log notice "test case: ${WHITE}migrate to (backward) specific migration"

# Create initial schema
psql "$DATABASE_URL" -c 'CREATE TABLE sessions (id INTEGER PRIMARY KEY)'

# Initialize migrator
if ! migrator --db-url "$DATABASE_URL" init; then
  log error "test failed: ${WHITE}init failed"
  exit 1
fi

# Apply all 3 migrations
if ! migrator --db-url "$DATABASE_URL" migrate up 3; then
  log error "test failed: ${WHITE}migrate up failed"
  exit 1
fi

# Verify all 3 columns exist
if ! psql -Atc "SELECT user_id, token, expires_at FROM sessions LIMIT 0" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}not all columns added"
  exit 1
fi

# Migrate back to first migration
if ! migrator --db-url "$DATABASE_URL" migrate to 20250101000001-add-user-id; then
  log error "test failed: ${WHITE}migrate to (backward) failed"
  exit 1
fi

# Verify only 1 migration remains
applied_count=$(psql -Atc "SELECT COUNT(*) FROM hectic.migration" "$DATABASE_URL")
if [ "$applied_count" != "1" ]; then
  log error "test failed: ${WHITE}expected 1 migration, got $applied_count"
  exit 1
fi

# Verify only user_id exists
if ! psql -Atc "SELECT user_id FROM sessions LIMIT 0" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}user_id should exist"
  exit 1
fi

if psql -Atc "SELECT token FROM sessions LIMIT 0" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}token should be removed"
  exit 1
fi

log notice "test passed"

