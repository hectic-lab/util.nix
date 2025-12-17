#!/bin/dash

HECTIC_NAMESPACE=test-migrate-existing-with-conflicts

log notice "test case: ${WHITE}migrator with conflicting existing schema"

# Create a database that already has a 'hectic' schema (potential conflict)
log info "creating existing database with hectic schema"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL
-- User already has something in hectic schema
CREATE SCHEMA hectic;

CREATE TABLE hectic.user_data (
  id SERIAL PRIMARY KEY,
  data TEXT
);

INSERT INTO hectic.user_data (data) VALUES ('important data');
SQL

# Verify existing hectic data
existing_data=$(psql -Atc "SELECT data FROM hectic.user_data" "$DATABASE_URL")
if [ "$existing_data" != "important data" ]; then
  log error "test failed: ${WHITE}existing hectic data not created"
  exit 1
fi

log info "existing hectic schema contains user_data table"

# Initialize migrator (should handle existing hectic schema gracefully)
log info "initializing migrator with existing hectic schema"
if ! migrator --db-url "$DATABASE_URL" init; then
  log error "test failed: ${WHITE}init failed with existing hectic schema"
  exit 1
fi

# Verify migrator tables were created
if ! psql -Atc "SELECT COUNT(*) FROM hectic.migration" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}hectic.migration not created"
  exit 1
fi

if ! psql -Atc "SELECT COUNT(*) FROM hectic.version" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}hectic.version not created"
  exit 1
fi

# Verify existing user data still intact
existing_data_after=$(psql -Atc "SELECT data FROM hectic.user_data" "$DATABASE_URL")
if [ "$existing_data_after" != "$existing_data" ]; then
  log error "test failed: ${WHITE}existing hectic.user_data was corrupted"
  exit 1
fi

log info "existing hectic.user_data preserved"

# Apply a migration
if ! migrator --db-url "$DATABASE_URL" migrate up; then
  log error "test failed: ${WHITE}migration failed"
  exit 1
fi

# Verify both user table and migrator tables coexist
tables_in_hectic=$(psql -Atc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'hectic'" "$DATABASE_URL")
if [ "$tables_in_hectic" -lt 4 ]; then
  log error "test failed: ${WHITE}expected at least 4 tables in hectic schema (user_data, migration, version, test_table), got $tables_in_hectic"
  exit 1
fi

log info "hectic schema contains $tables_in_hectic tables (user + migrator tables)"

log notice "test passed: migrator coexists with existing hectic schema"

