#!/bin/dash

HECTIC_NAMESPACE=test-migrate-multi-file

log notice "test case: ${WHITE}migrate up with multi-file layout (up/entrypoint.sql)"

# Initialize migrator
if ! migrator --db-url "$DATABASE_URL" init; then
  log error "test failed: ${WHITE}init failed"
  exit 1
fi

# Apply first migration (up/entrypoint.sql)
if ! migrator --db-url "$DATABASE_URL" migrate up; then
  log error "test failed: ${WHITE}first migrate up failed"
  exit 1
fi

# Verify migration was applied
applied_count=$(psql -Atc "SELECT COUNT(*) FROM hectic.migration" "$DATABASE_URL")
if [ "$applied_count" != "1" ]; then
  log error "test failed: ${WHITE}expected 1 migration, got $applied_count"
  exit 1
fi

# Verify table was created
if ! psql -Atc "SELECT COUNT(*) FROM items" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}items table not created"
  exit 1
fi

log info "first migration applied successfully"

# Apply second migration
if ! migrator --db-url "$DATABASE_URL" migrate up; then
  log error "test failed: ${WHITE}second migrate up failed"
  exit 1
fi

# Verify both columns were added
if ! psql -Atc "SELECT description FROM items LIMIT 0" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}description column not added"
  exit 1
fi

if ! psql -Atc "SELECT price FROM items LIMIT 0" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}price column not added"
  exit 1
fi

log info "second migration applied successfully"

# Migrate down one step
if ! migrator --db-url "$DATABASE_URL" migrate down; then
  log error "test failed: ${WHITE}migrate down failed"
  exit 1
fi

# Verify only 1 migration remains
applied_count=$(psql -Atc "SELECT COUNT(*) FROM hectic.migration" "$DATABASE_URL")
if [ "$applied_count" != "1" ]; then
  log error "test failed: ${WHITE}expected 1 migration after down, got $applied_count"
  exit 1
fi

# Verify columns were removed
if psql -Atc "SELECT description FROM items LIMIT 0" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}description column should be removed"
  exit 1
fi

# Migrate down to clean state
if ! migrator --db-url "$DATABASE_URL" migrate down; then
  log error "test failed: ${WHITE}second migrate down failed"
  exit 1
fi

# Verify items table was dropped
if psql -Atc "SELECT COUNT(*) FROM items" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}items table should be dropped"
  exit 1
fi

log notice "test passed: multi-file migration layout works correctly"
