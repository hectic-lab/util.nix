#!/bin/dash

HECTIC_NAMESPACE=test-sqlite-multi-file

log notice "test case: ${WHITE}SQLite multi-file migration layout"

# Create SQLite database
SQLITE_DB="$PWD/test.db"
export DB_URL="sqlite://$SQLITE_DB"

log info "using SQLite database: $SQLITE_DB"

# Initialize migrator
if ! migrator --db-url "$DB_URL" init; then
  log error "test failed: ${WHITE}init failed for SQLite"
  exit 1
fi

# Apply first migration (up/entrypoint.sql)
if ! migrator --db-url "$DB_URL" migrate up; then
  log error "test failed: ${WHITE}first migration failed"
  exit 1
fi

# Verify migration was applied
migration_count=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM hectic_migration")
if [ "$migration_count" != "1" ]; then
  log error "test failed: ${WHITE}expected 1 migration, got $migration_count"
  exit 1
fi

# Verify table was created
if ! sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM items" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}items table not created"
  exit 1
fi

log info "first migration applied successfully"

# Apply second migration
if ! migrator --db-url "$DB_URL" migrate up; then
  log error "test failed: ${WHITE}second migration failed"
  exit 1
fi

# Verify columns were added
if ! sqlite3 "$SQLITE_DB" "SELECT description FROM items LIMIT 0" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}description column not added"
  exit 1
fi

if ! sqlite3 "$SQLITE_DB" "SELECT price FROM items LIMIT 0" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}price column not added"
  exit 1
fi

log info "second migration applied successfully"

# Migrate down one step
if ! migrator --db-url "$DB_URL" migrate down; then
  log error "test failed: ${WHITE}migrate down failed"
  exit 1
fi

# Verify only 1 migration remains
migration_count=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM hectic_migration")
if [ "$migration_count" != "1" ]; then
  log error "test failed: ${WHITE}expected 1 migration after down, got $migration_count"
  exit 1
fi

# Verify columns were removed (table recreated without extra columns)
if sqlite3 "$SQLITE_DB" "SELECT description FROM items LIMIT 0" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}description column should be removed"
  exit 1
fi

# Migrate down to clean state
if ! migrator --db-url "$DB_URL" migrate down; then
  log error "test failed: ${WHITE}second migrate down failed"
  exit 1
fi

# Verify items table was dropped
if sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM items" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}items table should be dropped"
  exit 1
fi

log notice "test passed: SQLite multi-file migration layout works correctly"
