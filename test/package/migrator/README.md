# Migrator Test Suite

This directory contains comprehensive tests for the database migration tool supporting both PostgreSQL and SQLite.

## Test Structure

```
test/package/migrator/
├── default.nix          # Nix test builder - auto-detects test type
├── lauch.sh             # PostgreSQL test launcher
├── lauch-sqlite.sh      # SQLite test launcher
├── util.sh              # Shared test utilities
└── test/                # Test cases
    ├── <test-name>/     # PostgreSQL tests (default)
    └── sqlite-<name>/   # SQLite tests (prefix with "sqlite-")
```

## Test Types

### PostgreSQL Tests (Default)

Any test directory or `.sh` file in `test/` will use PostgreSQL by default:
- Automatic PostgreSQL setup (initdb, pg_ctl, createdb)
- `DATABASE_URL` set to PostgreSQL connection string
- Requires: `pkgs.postgresql`

**Examples:**
- `migrate-up-single/`
- `migrate-down-multiple/`
- `init-migrator.sh`

### SQLite Tests

Tests with names starting with `sqlite-` use SQLite:
- Simple file-based database
- `DATABASE_URL` set to `sqlite:///path/to/test.db`
- Requires: `pkgs.sqlite`

**Examples:**
- `sqlite-basic/`
- `sqlite-migration-test/`

## Test Categories

### Core Functionality
- `init-migrator.sh` - Initialization
- `init-migrator-with-inherits.sh` - PostgreSQL INHERITS feature
- `migrate-up-single/` - Single step up migration
- `migrate-up-multiple/` - Multiple step up migrations
- `migrate-down-single/` - Single step down migration
- `migrate-down-multiple/` - Multiple step down migrations
- `migrate-to-forward/` - Migrate to specific version (forward)
- `migrate-to-backward/` - Migrate to specific version (backward)
- `migrate-already-at-target/` - Edge case: no-op migration

### Existing Database Support
- `migrate-existing-database/` - Add migrator to production DB
- `migrate-existing-with-conflicts/` - Handle schema conflicts
- `migrate-existing-data-migration/` - Transform existing data

### SQLite Support
- `sqlite-basic/` - Basic SQLite functionality

### Helper Functions
- `function-index-of.sh` - Test index_of helper
- `function-migration-list.sh` - Test migration_list helper
- `function-generate-word.sh` - Test word generator

### Utilities
- `create-migration.sh` - Test migration creation
- `migrations-list/` - Test migration listing
- `arguments.sh` - Test argument parsing

## Creating New Tests

### PostgreSQL Test

```bash
mkdir -p test/<test-name>/migration/<timestamp>-<name>
cat > test/<test-name>/run.sh <<'EOF'
#!/bin/dash
HECTIC_NAMESPACE=test-my-test
log notice "test case: ${WHITE}my test"

# $DATABASE_URL is automatically set to PostgreSQL
migrator --db-url "$DATABASE_URL" init
# ... your test code ...

log notice "test passed"
EOF

# Create up.sql and down.sql migration files
```

### SQLite Test

Same as above, but prefix the directory name with `sqlite-`:

```bash
mkdir -p test/sqlite-<test-name>/migration/<timestamp>-<name>
# ... rest is the same
```

## Running Tests

Tests are built and run via Nix:

```bash
# Run all tests
nix build .#checks.x86_64-linux

# Run specific test
nix build .#checks.x86_64-linux.migrator-test-<test-name>

# Run SQLite tests
nix build .#checks.x86_64-linux.migrator-test-sqlite-basic
```

## Test Isolation

Each test runs in complete isolation:
- **PostgreSQL**: Fresh PostgreSQL cluster per test
- **SQLite**: Fresh database file per test
- Clean working directory
- Independent environment variables

## Available Test Utilities

From `util.sh`:
- `columns(table)` - Get column names from table
- `is_number(var)` - Check if variable is numeric

From test environment:
- `log <level> <message>` - Logging (trace, debug, info, notice, error)
- `migrator` - The migrator binary under test
- `$DATABASE_URL` - Database connection string (auto-configured)

## Test Conventions

1. **Naming**: Use descriptive names with hyphens
2. **Logging**: Use `log` for output, not `echo`
3. **Exit codes**: 
   - 0 = success
   - 1 = test failure
   - Other = specific error conditions
4. **Cleanup**: Tests are automatically cleaned up by Nix
5. **Assertions**: Explicit checks with meaningful error messages

## Database-Specific Notes

### PostgreSQL
- Full schema support (`hectic.migration`)
- Domains with regex validation
- Triggers and functions
- INHERITS support
- TIMESTAMPTZ support

### SQLite
- Simple table names (`hectic_migration`)
- CHECK constraints instead of domains
- No triggers needed
- TEXT timestamps with datetime()
- Table recreation for column removal (older SQLite versions)

