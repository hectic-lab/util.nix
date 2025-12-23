#!/bin/dash

HECTIC_NAMESPACE=test-sqlite-migration-failure-rollback

log notice "test case: ${WHITE}SQLite migration failure causes transaction rollback"

# Create SQLite database
SQLITE_DB="$PWD/test.db"
export DB_URL="sqlite://$SQLITE_DB"

log info "using SQLite database: $SQLITE_DB"

# Create initial schema
sqlite3 "$SQLITE_DB" "CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT)"

# Initialize migrator
if ! migrator --db-url "$DB_URL" init; then
  log error "test failed: ${WHITE}init failed"
  exit 1
fi

log info "setup complete"

### CASE 1: Failed migration doesn't create migration record
log notice "test case: ${WHITE}failed SQLite migration doesn't create record"

# Create migrations directory
mkdir -p migration

# Create first SUCCESSFUL migration
mig1="20250101000001-add-quantity"
mkdir -p "migration/${mig1}"
cat > "migration/${mig1}/up.sql" <<SQL
-- This should succeed
ALTER TABLE items ADD COLUMN quantity INTEGER DEFAULT 0;
SQL
echo "-- Note: SQLite ALTER TABLE DROP COLUMN not in old versions" > "migration/${mig1}/down.sql"

# Create second FAILING migration (syntax error)
mig2="20250101000002-broken-migration"
mkdir -p "migration/${mig2}"
cat > "migration/${mig2}/up.sql" <<SQL
-- This SQL is intentionally broken
ALTER TABLE items ADD COLUMN status TEXT;
THIS IS NOT VALID SQL;  -- <-- This will cause error
ALTER TABLE items ADD COLUMN tag TEXT;
SQL
echo "-- rollback" > "migration/${mig2}/down.sql"

# Apply first migration (should succeed)
if ! migrator --db-url "$DB_URL" migrate up; then
  log error "test failed: ${WHITE}first migration should succeed"
  exit 1
fi

# Verify first migration was recorded
count=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM hectic_migration")
if [ "$count" != "1" ]; then
  log error "test failed: ${WHITE}expected 1 migration, got $count"
  exit 1
fi

log info "first migration successful and recorded"

# Try to apply second migration (should fail)
set +e
migrator --db-url "$DB_URL" migrate up 2>&1
exit_code=$?
set -e

if [ "$exit_code" = "0" ]; then
  log error "test failed: ${WHITE}broken migration should have failed"
  exit 1
fi

log info "second migration failed as expected (exit code: $exit_code)"

# CRITICAL CHECK: Verify the failed migration was NOT recorded
count_after=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM hectic_migration")
if [ "$count_after" != "1" ]; then
  log error "test failed: ${WHITE}CRITICAL! Failed migration was recorded. Expected 1, got $count_after"
  log error "This means the transaction was not rolled back properly!"
  exit 1
fi

log info "✓ Failed migration was NOT recorded (transaction rolled back)"

# Verify the status column was NOT created (transaction rollback)
set +e
sqlite3 "$SQLITE_DB" "SELECT status FROM items LIMIT 0" >/dev/null 2>&1
status_exists=$?
set -e

if [ "$status_exists" = "0" ]; then
  log error "test failed: ${WHITE}CRITICAL! 'status' column exists after failed migration"
  log error "This means partial changes were committed!"
  exit 1
fi

log info "✓ No partial changes committed"

# Verify quantity column from first migration still exists
if ! sqlite3 "$SQLITE_DB" "SELECT quantity FROM items LIMIT 0" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}first migration's changes were lost"
  exit 1
fi

log info "✓ First migration's changes preserved"

### CASE 2: Multi-statement migration fails atomically
log notice "test case: ${WHITE}multi-statement SQLite migration fails atomically"

mig3="20250101000003-multi-statement-fail"
mkdir -p "migration/${mig3}"
cat > "migration/${mig3}/up.sql" <<SQL
-- First statement succeeds
ALTER TABLE items ADD COLUMN location TEXT;

-- Second statement succeeds  
CREATE TABLE temp_table (id INTEGER);

-- Third statement FAILS
ALTER TABLE nonexistent_table ADD COLUMN foo TEXT;

-- Fourth statement would succeed if we got here
ALTER TABLE items ADD COLUMN notes TEXT;
SQL
echo "-- rollback" > "migration/${mig3}/down.sql"

# Try to apply migration (should fail)
set +e
migrator --db-url "$DB_URL" migrate up 2>&1
exit_code=$?
set -e

if [ "$exit_code" = "0" ]; then
  log error "test failed: ${WHITE}multi-statement broken migration should have failed"
  exit 1
fi

log info "multi-statement migration failed as expected"

# Verify migration was NOT recorded
count_after_multi=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM hectic_migration")
if [ "$count_after_multi" != "1" ]; then
  log error "test failed: ${WHITE}failed multi-statement migration was recorded"
  exit 1
fi

log info "✓ Failed migration was NOT recorded"

# Verify NO partial changes were committed
set +e
sqlite3 "$SQLITE_DB" "SELECT location FROM items LIMIT 0" >/dev/null 2>&1
location_exists=$?
set -e

if [ "$location_exists" = "0" ]; then
  log error "test failed: ${WHITE}CRITICAL! 'location' column exists (partial commit in failed migration)"
  exit 1
fi

log info "✓ No partial changes from multi-statement migration"

# Verify temp_table was NOT created
set +e
sqlite3 "$SQLITE_DB" "SELECT * FROM temp_table LIMIT 0" >/dev/null 2>&1
temp_exists=$?
set -e

if [ "$temp_exists" = "0" ]; then
  log error "test failed: ${WHITE}temp_table exists (partial commit in failed migration)"
  exit 1
fi

log info "✓ No tables created from failed migration"

### CASE 3: Constraint violation rolls back transaction
log notice "test case: ${WHITE}SQLite constraint violation rolls back transaction"

mig4="20250101000004-constraint-violation"
mkdir -p "migration/${mig4}"
cat > "migration/${mig4}/up.sql" <<SQL
-- Add column with UNIQUE constraint
ALTER TABLE items ADD COLUMN code TEXT;
CREATE UNIQUE INDEX items_code_unique ON items(code);

-- Try to insert duplicate data (will violate UNIQUE constraint)
INSERT INTO items (name, quantity, code) VALUES ('Item A', 10, 'CODE001');
INSERT INTO items (name, quantity, code) VALUES ('Item B', 20, 'CODE001');  -- DUPLICATE!
SQL
echo "-- rollback" > "migration/${mig4}/down.sql"

# Try to apply (should fail due to constraint violation)
set +e
migrator --db-url "$DB_URL" migrate up 2>&1
exit_code=$?
set -e

if [ "$exit_code" = "0" ]; then
  log error "test failed: ${WHITE}constraint violation migration should have failed"
  exit 1
fi

log info "constraint violation migration failed as expected"

# Verify migration was NOT recorded
final_count=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM hectic_migration")
if [ "$final_count" != "1" ]; then
  log error "test failed: ${WHITE}constraint violation migration was recorded"
  exit 1
fi

log info "✓ Constraint violation migration was NOT recorded"

# Verify code column was NOT added (full rollback)
set +e
sqlite3 "$SQLITE_DB" "SELECT code FROM items LIMIT 0" >/dev/null 2>&1
code_exists=$?
set -e

if [ "$code_exists" = "0" ]; then
  log error "test failed: ${WHITE}code column exists after constraint violation"
  exit 1
fi

log info "✓ All changes rolled back after constraint violation"

# Verify no data was committed
final_row_count=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM items")
if [ "$final_row_count" != "0" ]; then
  log error "test failed: ${WHITE}data exists after constraint violation rollback (got $final_row_count rows)"
  exit 1
fi

log info "✓ No data committed after constraint violation"

log notice "test passed: all SQLite migration failures properly roll back transactions"

