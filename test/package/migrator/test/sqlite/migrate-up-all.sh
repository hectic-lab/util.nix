#!/bin/dash

HECTIC_NAMESPACE=test-sqlite-migrate-up-all

log notice "test case: ${WHITE}SQLite migrate up all - comprehensive test"

# Create SQLite database
SQLITE_DB="$PWD/test.db"
export DB_URL="sqlite://$SQLITE_DB"

log info "using SQLite database: $SQLITE_DB"

# Create initial schema
sqlite3 "$SQLITE_DB" "CREATE TABLE inventory (id INTEGER PRIMARY KEY, name TEXT)"

# Initialize migrator
if ! migrator --db-url "$DB_URL" init; then
  log error "test failed: ${WHITE}init failed"
  exit 1
fi

# Verify tables were created
if ! sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM hectic_migration" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}hectic_migration table not created"
  exit 1
fi

log info "migrator initialized successfully"

# Create migrations directory with 5 migrations
mkdir -p migration
log info "creating 5 test migrations"

for i in 1 2 3 4 5; do
  mig_name="2025010100000${i}-add-field-${i}"
  mkdir -p "migration/${mig_name}"
  
  echo "ALTER TABLE inventory ADD COLUMN field${i} TEXT;" > "migration/${mig_name}/up.sql"
  
  # Simple down migration (comment only for this test)
  cat > "migration/${mig_name}/down.sql" <<SQL
-- Revert: Remove field${i}
-- Note: In production, this would properly handle the column removal
SQL
done

log info "migrations created"

### CASE 1: Fresh database - migrate up all
log notice "test case: ${WHITE}migrate up all from fresh state"

if ! migrator --db-url "$DB_URL" migrate up all; then
  log error "test failed: ${WHITE}migrate up all failed"
  exit 1
fi

# Verify all 5 migrations were applied
applied_count=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM hectic_migration")
if [ "$applied_count" != "5" ]; then
  log error "test failed: ${WHITE}expected 5 migrations, got $applied_count"
  exit 1
fi

log info "all 5 migrations applied successfully"

# Verify all columns exist
for i in 1 2 3 4 5; do
  if ! sqlite3 "$SQLITE_DB" "SELECT field${i} FROM inventory LIMIT 0" >/dev/null 2>&1; then
    log error "test failed: ${WHITE}field${i} column not added"
    exit 1
  fi
done

log info "all columns verified"

### CASE 2: Already at latest - should be no-op
log notice "test case: ${WHITE}migrate up all when already at latest (no-op)"

if ! migrator --db-url "$DB_URL" migrate up all; then
  log error "test failed: ${WHITE}migrate up all (no-op) failed"
  exit 1
fi

# Count should still be 5
applied_count=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM hectic_migration")
if [ "$applied_count" != "5" ]; then
  log error "test failed: ${WHITE}expected 5 migrations after no-op, got $applied_count"
  exit 1
fi

log info "no-op successful - count still 5"

### CASE 3: Insert data, then verify migrations preserve it
log notice "test case: ${WHITE}migrations don't corrupt existing data"

sqlite3 "$SQLITE_DB" <<SQL
INSERT INTO inventory (name, field1, field2, field3, field4, field5) 
VALUES ('Item1', 'val1', 'val2', 'val3', 'val4', 'val5');
INSERT INTO inventory (name, field1, field2) 
VALUES ('Item2', 'a', 'b');
SQL

data_count=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM inventory")
if [ "$data_count" != "2" ]; then
  log error "test failed: ${WHITE}test data not inserted properly"
  exit 1
fi

log info "test data inserted: $data_count rows"

# Create additional migration
mig_name="20250101000006-add-field-6"
mkdir -p "migration/${mig_name}"
echo "ALTER TABLE inventory ADD COLUMN field6 TEXT DEFAULT 'default6';" > "migration/${mig_name}/up.sql"
echo "-- Revert field6" > "migration/${mig_name}/down.sql"

# Apply new migration
if ! migrator --db-url "$DB_URL" migrate up all; then
  log error "test failed: ${WHITE}migrate up all with new migration failed"
  exit 1
fi

# Verify data still exists
data_count_after=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM inventory")
if [ "$data_count_after" != "$data_count" ]; then
  log error "test failed: ${WHITE}data corrupted after migration, had $data_count, now $data_count_after"
  exit 1
fi

# Verify new column has default value
field6_value=$(sqlite3 "$SQLITE_DB" "SELECT field6 FROM inventory WHERE name = 'Item1'")
if [ "$field6_value" != "default6" ]; then
  log error "test failed: ${WHITE}new column default value not applied, got: $field6_value"
  exit 1
fi

log info "data preserved after migration, new column added with default"

### CASE 4: Verify migration tracking metadata
log notice "test case: ${WHITE}migration metadata is correct"

applied_count=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM hectic_migration")
if [ "$applied_count" != "6" ]; then
  log error "test failed: ${WHITE}expected 6 migrations in total, got $applied_count"
  exit 1
fi

# Verify migrations are in order
first_mig=$(sqlite3 "$SQLITE_DB" "SELECT name FROM hectic_migration ORDER BY id ASC LIMIT 1")
if [ "$first_mig" != "20250101000001-add-field-1" ]; then
  log error "test failed: ${WHITE}first migration not correct, got: $first_mig"
  exit 1
fi

last_mig=$(sqlite3 "$SQLITE_DB" "SELECT name FROM hectic_migration ORDER BY id DESC LIMIT 1")
if [ "$last_mig" != "20250101000006-add-field-6" ]; then
  log error "test failed: ${WHITE}last migration not correct, got: $last_mig"
  exit 1
fi

# Verify hashes are tracked
hash_count=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM hectic_migration WHERE hash IS NOT NULL AND hash != ''")
if [ "$hash_count" != "6" ]; then
  log error "test failed: ${WHITE}not all migrations have hashes, got $hash_count/6"
  exit 1
fi

log info "migration metadata verified"

### CASE 5: Verify version table
log notice "test case: ${WHITE}version table is correct"

version=$(sqlite3 "$SQLITE_DB" "SELECT version FROM hectic_version WHERE name = 'migrator'")
if [ "$version" != "0.0.1" ]; then
  log error "test failed: ${WHITE}version not correct, got: $version"
  exit 1
fi

log info "version table verified"

log notice "test passed: all SQLite 'migrate up all' scenarios work correctly"

