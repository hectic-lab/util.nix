#!/bin/dash

HECTIC_NAMESPACE=test-migration-failure-rollback

log notice "test case: ${WHITE}migration failure causes transaction rollback"

# Create initial schema
psql "$DATABASE_URL" -c 'CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT)'

# Initialize migrator
if ! migrator --db-url "$DATABASE_URL" init; then
  log error "test failed: ${WHITE}init failed"
  exit 1
fi

log info "setup complete"

### CASE 1: Successful migration followed by failed migration
log notice "test case: ${WHITE}failed migration doesn't create migration record"

# Create migrations directory
mkdir -p migration

# Create first SUCCESSFUL migration
mig1="20250101000001-add-price"
mkdir -p "migration/${mig1}"
cat > "migration/${mig1}/up.sql" <<SQL
-- This should succeed
ALTER TABLE products ADD COLUMN price DECIMAL(10,2);
SQL
echo "ALTER TABLE products DROP COLUMN price;" > "migration/${mig1}/down.sql"

# Create second FAILING migration (syntax error)
mig2="20250101000002-broken-migration"
mkdir -p "migration/${mig2}"
cat > "migration/${mig2}/up.sql" <<SQL
-- This SQL is intentionally broken to cause failure
ALTER TABLE products ADD COLUMN description TEXT;
THISISNOTVALIDSQL;  -- <-- This will cause error
ALTER TABLE products ADD COLUMN category TEXT;
SQL
echo "-- rollback" > "migration/${mig2}/down.sql"

# Apply first migration (should succeed)
if ! migrator --db-url "$DATABASE_URL" migrate up; then
  log error "test failed: ${WHITE}first migration should succeed"
  exit 1
fi

# Verify first migration was recorded
count=$(psql -Atc "SELECT COUNT(*) FROM hectic.migration" "$DATABASE_URL")
if [ "$count" != "1" ]; then
  log error "test failed: ${WHITE}expected 1 migration, got $count"
  exit 1
fi

log info "first migration successful and recorded"

# Try to apply second migration (should fail)
set +e
migrator --db-url "$DATABASE_URL" migrate up 2>&1
exit_code=$?
set -e

if [ "$exit_code" = "0" ]; then
  log error "test failed: ${WHITE}broken migration should have failed"
  exit 1
fi

log info "second migration failed as expected (exit code: $exit_code)"

# CRITICAL CHECK: Verify the failed migration was NOT recorded
count_after=$(psql -Atc "SELECT COUNT(*) FROM hectic.migration" "$DATABASE_URL")
if [ "$count_after" != "1" ]; then
  log error "test failed: ${WHITE}CRITICAL! Failed migration was recorded. Expected 1, got $count_after"
  log error "This means the transaction was not rolled back properly!"
  exit 1
fi

log info "✓ Failed migration was NOT recorded (transaction rolled back)"

# Verify the description column was NOT created (transaction rollback)
if psql -Atc "SELECT description FROM products LIMIT 0" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}CRITICAL! 'description' column exists after failed migration"
  log error "This means partial changes were committed!"
  exit 1
fi

log info "✓ No partial changes committed"

# Verify price column from first migration still exists
if ! psql -Atc "SELECT price FROM products LIMIT 0" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}first migration's changes were lost"
  exit 1
fi

log info "✓ First migration's changes preserved"

### CASE 2: Failed migration in the middle of a transaction
log notice "test case: ${WHITE}multi-statement migration fails atomically"

# Create migration with multiple statements, one fails in the middle
mig3="20250101000003-multi-statement-fail"
mkdir -p "migration/${mig3}"
cat > "migration/${mig3}/up.sql" <<SQL
-- First statement succeeds
ALTER TABLE products ADD COLUMN stock INTEGER DEFAULT 0;

-- Second statement succeeds
INSERT INTO products (name, price, stock) VALUES ('Test Product', 10.00, 5);

-- Third statement FAILS
ALTER TABLE nonexistent_table ADD COLUMN foo TEXT;

-- Fourth statement would succeed if we got here
ALTER TABLE products ADD COLUMN discount DECIMAL(5,2);
SQL
echo "-- rollback" > "migration/${mig3}/down.sql"

# Try to apply migration (should fail)
set +e
migrator --db-url "$DATABASE_URL" migrate up 2>&1
exit_code=$?
set -e

if [ "$exit_code" = "0" ]; then
  log error "test failed: ${WHITE}multi-statement broken migration should have failed"
  exit 1
fi

log info "multi-statement migration failed as expected"

# Verify migration was NOT recorded
count_after_multi=$(psql -Atc "SELECT COUNT(*) FROM hectic.migration" "$DATABASE_URL")
if [ "$count_after_multi" != "1" ]; then
  log error "test failed: ${WHITE}failed multi-statement migration was recorded"
  exit 1
fi

log info "✓ Failed migration was NOT recorded"

# Verify NO partial changes were committed
if psql -Atc "SELECT stock FROM products LIMIT 0" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}CRITICAL! 'stock' column exists (partial commit in failed migration)"
  exit 1
fi

log info "✓ No partial changes from multi-statement migration"

# Verify no data was inserted
row_count=$(psql -Atc "SELECT COUNT(*) FROM products" "$DATABASE_URL")
if [ "$row_count" != "0" ]; then
  log error "test failed: ${WHITE}data was inserted despite migration failure"
  exit 1
fi

log info "✓ No data inserted from failed migration"

### CASE 3: Migration with constraint violation
log notice "test case: ${WHITE}constraint violation rolls back transaction"

mig4="20250101000004-constraint-violation"
mkdir -p "migration/${mig4}"
cat > "migration/${mig4}/up.sql" <<SQL
-- Add column
ALTER TABLE products ADD COLUMN sku TEXT UNIQUE;

-- Try to insert duplicate data (will violate UNIQUE constraint)
INSERT INTO products (name, price, sku) VALUES ('Product A', 10.00, 'SKU001');
INSERT INTO products (name, price, sku) VALUES ('Product B', 20.00, 'SKU001');  -- DUPLICATE!
SQL
echo "-- rollback" > "migration/${mig4}/down.sql"

# Try to apply (should fail due to constraint violation)
set +e
migrator --db-url "$DATABASE_URL" migrate up 2>&1
exit_code=$?
set -e

if [ "$exit_code" = "0" ]; then
  log error "test failed: ${WHITE}constraint violation migration should have failed"
  exit 1
fi

log info "constraint violation migration failed as expected"

# Verify migration was NOT recorded
final_count=$(psql -Atc "SELECT COUNT(*) FROM hectic.migration" "$DATABASE_URL")
if [ "$final_count" != "1" ]; then
  log error "test failed: ${WHITE}constraint violation migration was recorded"
  exit 1
fi

log info "✓ Constraint violation migration was NOT recorded"

# Verify sku column was NOT added (full rollback)
if psql -Atc "SELECT sku FROM products LIMIT 0" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}sku column exists after constraint violation"
  exit 1
fi

log info "✓ All changes rolled back after constraint violation"

# Verify no data was committed
final_row_count=$(psql -Atc "SELECT COUNT(*) FROM products" "$DATABASE_URL")
if [ "$final_row_count" != "0" ]; then
  log error "test failed: ${WHITE}data exists after constraint violation rollback"
  exit 1
fi

log info "✓ No data committed after constraint violation"

log notice "test passed: all migration failures properly roll back transactions"

