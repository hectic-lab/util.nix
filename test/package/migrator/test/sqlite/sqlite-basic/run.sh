#!/bin/dash

HECTIC_NAMESPACE=test-sqlite-basic

log notice "test case: ${WHITE}SQLite basic migration"

# Create SQLite database
SQLITE_DB="$PWD/test.db"
export DB_URL="sqlite://$SQLITE_DB"

log info "using SQLite database: $SQLITE_DB"

# Initialize migrator with SQLite
if ! migrator --db-url "$DB_URL" init; then
  log error "test failed: ${WHITE}init failed for SQLite"
  exit 1
fi

# Verify tables were created
if ! sqlite3 "$SQLITE_DB" "SELECT name FROM hectic_version WHERE name = 'migrator'" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}hectic_version table not created"
  exit 1
fi

if ! sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM hectic_migration" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}hectic_migration table not created"
  exit 1
fi

log info "migrator tables created successfully"

# Apply first migration
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
if ! sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM users" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}users table not created"
  exit 1
fi

log info "first migration applied successfully"

# Apply second migration
if ! migrator --db-url "$DB_URL" migrate up; then
  log error "test failed: ${WHITE}second migration failed"
  exit 1
fi

# Verify email column exists
if ! sqlite3 "$SQLITE_DB" "SELECT email FROM users LIMIT 0" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}email column not added"
  exit 1
fi

# Migrate down
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

# Verify email column removed
if sqlite3 "$SQLITE_DB" "SELECT email FROM users LIMIT 0" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}email column should be removed"
  exit 1
fi

log notice "test passed: SQLite support works correctly"


