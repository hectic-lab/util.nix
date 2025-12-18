#!/bin/dash

HECTIC_NAMESPACE=test-sqlite-migrate-to-latest

log notice "test case: ${WHITE}SQLite migrate to latest migration"

# Create SQLite database
SQLITE_DB="$PWD/test.db"
export DB_URL="sqlite://$SQLITE_DB"

# Create initial schema
sqlite3 "$SQLITE_DB" "CREATE TABLE posts (id INTEGER PRIMARY KEY)"

# Initialize migrator
if ! migrator --db-url "$DB_URL" init; then
  log error "test failed: ${WHITE}init failed"
  exit 1
fi

# Create migrations directory with 3 migrations
mkdir -p migration
for i in 1 2 3; do
  mig_name="2025010100000${i}-migration-${i}"
  mkdir -p "migration/${mig_name}"
  
  echo "ALTER TABLE posts ADD COLUMN field${i} TEXT;" > "migration/${mig_name}/up.sql"
  # Note: SQLite DROP COLUMN requires table recreation before 3.35.0
  cat > "migration/${mig_name}/down.sql" <<SQL
-- Simplified: just note the revert in comment
-- In production, this would recreate the table without field${i}
SQL
done

### CASE 1: migrate up all
log notice "test case: ${WHITE}migrate up all (SQLite)"

if ! migrator --db-url "$DB_URL" migrate up all; then
  log error "test failed: ${WHITE}migrate up all failed"
  exit 1
fi

# Verify all 3 migrations were applied
applied_count=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM hectic_migration")
if [ "$applied_count" != "3" ]; then
  log error "test failed: ${WHITE}expected 3 migrations, got $applied_count"
  exit 1
fi

# Verify all columns exist
if ! sqlite3 "$SQLITE_DB" "SELECT field1, field2, field3 FROM posts LIMIT 0" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}not all columns were added"
  exit 1
fi

log info "migrate up all: success"

### CASE 2: migrate to latest when already at latest
log notice "test case: ${WHITE}migrate to latest when already at latest (SQLite)"

if ! migrator --db-url "$DB_URL" migrate to latest; then
  log error "test failed: ${WHITE}migrate to latest (no-op) failed"
  exit 1
fi

applied_count=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM hectic_migration")
if [ "$applied_count" != "3" ]; then
  log error "test failed: ${WHITE}expected 3 migrations, got $applied_count"
  exit 1
fi

log notice "test passed"

