#!/bin/dash

HECTIC_NAMESPACE=test-migrate-existing-data-migration

log notice "test case: ${WHITE}data migration on existing populated table"

# Create existing table with data
log info "creating existing table with data"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL
CREATE TABLE products (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  price_cents INTEGER NOT NULL
);

INSERT INTO products (name, price_cents) VALUES
  ('Widget', 1000),
  ('Gadget', 2500),
  ('Gizmo', 500);
SQL

# Verify initial data
product_count=$(psql -Atc "SELECT COUNT(*) FROM products" "$DATABASE_URL")
if [ "$product_count" != "3" ]; then
  log error "test failed: ${WHITE}initial data not created"
  exit 1
fi

# Initialize migrator
if ! migrator --db-url "$DATABASE_URL" init; then
  log error "test failed: ${WHITE}init failed"
  exit 1
fi

# Apply migration that does data transformation
log info "applying data migration"
if ! migrator --db-url "$DATABASE_URL" migrate up; then
  log error "test failed: ${WHITE}data migration failed"
  exit 1
fi

# Verify new columns exist
if ! psql -Atc "SELECT price_dollars, price_display FROM products LIMIT 0" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}new columns not added"
  exit 1
fi

# Verify data was transformed correctly
widget_price=$(psql -Atc "SELECT price_dollars FROM products WHERE name = 'Widget'" "$DATABASE_URL")
widget_display=$(psql -Atc "SELECT price_display FROM products WHERE name = 'Widget'" "$DATABASE_URL")

if [ "$widget_price" != "10.00" ]; then
  log error "test failed: ${WHITE}price_dollars not calculated correctly, got: $widget_price"
  exit 1
fi

if [ "$widget_display" != "\$10.00" ]; then
  log error "test failed: ${WHITE}price_display not formatted correctly, got: $widget_display"
  exit 1
fi

log info "data transformation successful"

# Verify all products were transformed
transformed_count=$(psql -Atc "SELECT COUNT(*) FROM products WHERE price_dollars IS NOT NULL" "$DATABASE_URL")
if [ "$transformed_count" != "3" ]; then
  log error "test failed: ${WHITE}not all products transformed, got: $transformed_count"
  exit 1
fi

# Test rollback of data migration
log info "rolling back data migration"
if ! migrator --db-url "$DATABASE_URL" migrate down; then
  log error "test failed: ${WHITE}rollback failed"
  exit 1
fi

# Verify columns removed
if psql -Atc "SELECT price_dollars FROM products LIMIT 0" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}columns should be removed after rollback"
  exit 1
fi

# Verify original data still intact
original_count=$(psql -Atc "SELECT COUNT(*) FROM products WHERE price_cents IS NOT NULL" "$DATABASE_URL")
if [ "$original_count" != "3" ]; then
  log error "test failed: ${WHITE}original data corrupted after rollback"
  exit 1
fi

widget_original=$(psql -Atc "SELECT price_cents FROM products WHERE name = 'Widget'" "$DATABASE_URL")
if [ "$widget_original" != "1000" ]; then
  log error "test failed: ${WHITE}original price data corrupted, got: $widget_original"
  exit 1
fi

log notice "test passed: data migration works on existing populated tables"

