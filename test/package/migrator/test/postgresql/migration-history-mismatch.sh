#!/bin/dash

HECTIC_NAMESPACE=test-migration-history-mismatch

log notice "test case: ${WHITE}migration history mismatch detection"

# Initialize database
psql "$DATABASE_URL" -c 'CREATE TABLE test_table (id INTEGER PRIMARY KEY)'

if ! migrator --db-url "$DATABASE_URL" init; then
  log error "test failed: ${WHITE}init failed"
  exit 1
fi

# Create migration directory with 3 migrations
mkdir -p migration
for i in 1 2 3; do
  mig_name="2025010100000${i}-migration-${i}"
  mkdir -p "migration/${mig_name}"
  echo "ALTER TABLE test_table ADD COLUMN col${i} TEXT;" > "migration/${mig_name}/up.sql"
  echo "ALTER TABLE test_table DROP COLUMN col${i};" > "migration/${mig_name}/down.sql"
done

# Apply all migrations
migrator --db-url "$DATABASE_URL" migrate up all

applied_count=$(psql -Atc "SELECT COUNT(*) FROM hectic.migration" "$DATABASE_URL")
if [ "$applied_count" != "3" ]; then
  log error "test failed: ${WHITE}setup failed, expected 3 migrations"
  exit 1
fi

log info "setup complete: 3 migrations applied"

### CASE 1: Remove a migration file (causes mismatch)
log notice "test case: ${WHITE}detect removed migration file"

# Remove the second migration directory
rm -rf "migration/20250101000002-migration-2"

# Try to migrate (should fail with detailed error)
set +e
output=$(migrator --db-url "$DATABASE_URL" migrate up 2>&1)
exit_code=$?
set -e

if [ "$exit_code" != "2" ]; then
  log error "test failed: ${WHITE}expected exit code 2, got $exit_code"
  exit 1
fi

# Check that error message contains helpful information
if ! printf '%s' "$output" | grep -q "Migration history mismatch"; then
  log error "test failed: ${WHITE}error message doesn't contain 'Migration history mismatch'"
  exit 1
fi

if ! printf '%s' "$output" | grep -q "Database has:"; then
  log error "test failed: ${WHITE}error message doesn't show database migration"
  exit 1
fi

if ! printf '%s' "$output" | grep -q "Filesystem has:"; then
  log error "test failed: ${WHITE}error message doesn't show filesystem migration"
  exit 1
fi

if ! printf '%s' "$output" | grep -q "Full filesystem migrations"; then
  log error "test failed: ${WHITE}error message doesn't list all filesystem migrations"
  exit 1
fi

if ! printf '%s' "$output" | grep -q "Full database migrations"; then
  log error "test failed: ${WHITE}error message doesn't list all database migrations"
  exit 1
fi

log info "detailed error message verified"

### CASE 2: Verify --force flag works
log notice "test case: ${WHITE}--force flag bypasses check"

# Try again with --force (should work)
set +e
output=$(migrator --db-url "$DATABASE_URL" --force migrate up 2>&1)
exit_code=$?
set -e

# Note: It will still fail because migration file is missing, but it should bypass the tree check
if [ "$exit_code" = "2" ]; then
  log error "test failed: ${WHITE}--force didn't bypass tree check (exit code still 2)"
  exit 1
fi

# Check that we got past the tree check
if printf '%s' "$output" | grep -q "Migration history mismatch detected but.*--force.*specified"; then
  log info "--force flag bypassed tree check as expected"
else
  # It might have proceeded to file not found error, which is fine
  log info "--force flag behavior verified (proceeded past tree check)"
fi

log notice "test passed"

