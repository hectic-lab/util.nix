#!/bin/dash

HECTIC_NAMESPACE=test-migrate-to-latest

log notice "test case: ${WHITE}migrate to latest migration"

# Create initial schema
psql "$DATABASE_URL" -c 'CREATE TABLE articles (id INTEGER PRIMARY KEY)'

# Initialize migrator
if ! migrator --db-url "$DATABASE_URL" init; then
  log error "test failed: ${WHITE}init failed"
  exit 1
fi

# Create migrations directory with 4 migrations
mkdir -p migration
for i in 1 2 3 4; do
  mig_name="2025010100000${i}-migration-${i}"
  mkdir -p "migration/${mig_name}"
  
  echo "ALTER TABLE articles ADD COLUMN col${i} TEXT;" > "migration/${mig_name}/up.sql"
  echo "ALTER TABLE articles DROP COLUMN col${i};" > "migration/${mig_name}/down.sql"
done

### CASE 1: migrate up all
log notice "test case: ${WHITE}migrate up all"

if ! migrator --db-url "$DATABASE_URL" migrate up all; then
  log error "test failed: ${WHITE}migrate up all failed"
  exit 1
fi

# Verify all 4 migrations were applied
applied_count=$(psql -Atc "SELECT COUNT(*) FROM hectic.migration" "$DATABASE_URL")
if [ "$applied_count" != "4" ]; then
  log error "test failed: ${WHITE}expected 4 migrations, got $applied_count"
  exit 1
fi

# Verify all columns exist
if ! psql -Atc "SELECT col1, col2, col3, col4 FROM articles LIMIT 0" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}not all columns were added"
  exit 1
fi

log info "migrate up all: success"

# Revert all migrations for next test
migrator --db-url "$DATABASE_URL" migrate down 4

### CASE 2: migrate to latest
log notice "test case: ${WHITE}migrate to latest"

if ! migrator --db-url "$DATABASE_URL" migrate to latest; then
  log error "test failed: ${WHITE}migrate to latest failed"
  exit 1
fi

# Verify all 4 migrations were applied
applied_count=$(psql -Atc "SELECT COUNT(*) FROM hectic.migration" "$DATABASE_URL")
if [ "$applied_count" != "4" ]; then
  log error "test failed: ${WHITE}expected 4 migrations, got $applied_count"
  exit 1
fi

log info "migrate to latest: success"

# Revert for next test
migrator --db-url "$DATABASE_URL" migrate down 4

### CASE 3: migrate to head (alias)
log notice "test case: ${WHITE}migrate to head (alias)"

if ! migrator --db-url "$DATABASE_URL" migrate to head; then
  log error "test failed: ${WHITE}migrate to head failed"
  exit 1
fi

applied_count=$(psql -Atc "SELECT COUNT(*) FROM hectic.migration" "$DATABASE_URL")
if [ "$applied_count" != "4" ]; then
  log error "test failed: ${WHITE}expected 4 migrations, got $applied_count"
  exit 1
fi

log info "migrate to head: success"

# Revert for next test
migrator --db-url "$DATABASE_URL" migrate down 4

### CASE 4: migrate up latest (alias)
log notice "test case: ${WHITE}migrate up latest"

if ! migrator --db-url "$DATABASE_URL" migrate up latest; then
  log error "test failed: ${WHITE}migrate up latest failed"
  exit 1
fi

applied_count=$(psql -Atc "SELECT COUNT(*) FROM hectic.migration" "$DATABASE_URL")
if [ "$applied_count" != "4" ]; then
  log error "test failed: ${WHITE}expected 4 migrations, got $applied_count"
  exit 1
fi

log info "migrate up latest: success"

### CASE 5: migrate to latest when already at latest (should be no-op)
log notice "test case: ${WHITE}migrate to latest when already at latest"

if ! migrator --db-url "$DATABASE_URL" migrate to latest; then
  log error "test failed: ${WHITE}migrate to latest (no-op) failed"
  exit 1
fi

applied_count=$(psql -Atc "SELECT COUNT(*) FROM hectic.migration" "$DATABASE_URL")
if [ "$applied_count" != "4" ]; then
  log error "test failed: ${WHITE}expected 4 migrations, got $applied_count"
  exit 1
fi

log info "migrate to latest (no-op): success"

### CASE 6: Partial migration then up all
log notice "test case: ${WHITE}partial migration then up all"

# Revert to first migration only
migrator --db-url "$DATABASE_URL" migrate down 3

applied_count=$(psql -Atc "SELECT COUNT(*) FROM hectic.migration" "$DATABASE_URL")
if [ "$applied_count" != "1" ]; then
  log error "test failed: ${WHITE}expected 1 migration after down 3, got $applied_count"
  exit 1
fi

# Now apply all remaining
if ! migrator --db-url "$DATABASE_URL" migrate up all; then
  log error "test failed: ${WHITE}migrate up all from partial state failed"
  exit 1
fi

applied_count=$(psql -Atc "SELECT COUNT(*) FROM hectic.migration" "$DATABASE_URL")
if [ "$applied_count" != "4" ]; then
  log error "test failed: ${WHITE}expected 4 migrations after up all, got $applied_count"
  exit 1
fi

log notice "test passed"

