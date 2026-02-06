#!/bin/dash

#version="$(psql "$DB_URL" -c "SELECT version FROM hectic.version WHERE name = 'migrator';")"

# error codes
#   1   - generic error
#   2   - ambiguous, when you try to use something that cannot be used in same time
#   3   - missing required argument / variable
#   4   -
#   5   - provided table that not exists
#   9   - argument or command not found
#   13  - program bug / unexpected system / database incompatibles
#   127 - command not found (dependency)

set -eu

VERSION='0.0.1'
MIGRATION_DIR="${MIGRATION_DIR:-migration}"
DB_URL="${DB_URL:-DB_URL}"
REMAINING_ARS=

quote() { printf "'%s'" "$(printf %s "$1" | sed "s/'/'\\\\''/g")"; }

# cat filename | sha256sum()
# sha256sum(filename)
sha256sum() {
  local file
  file="${1:-'-'}"
  cksum --algorithm=sha256 --untagged "$file" | awk '{printf $1}'
}

# detect_db_type()
# Returns: "postgresql" or "sqlite"
detect_db_type() {
  if ! [ "${DB_URL+x}" ]; then
    log error "no ${WHITE}DB_URL${NC} or ${WHITE}--db-url${NC} specified"
    exit 3
  fi

  case "$DB_URL" in
    postgresql://*|postgres://*)
      printf 'postgresql'
      ;;
    sqlite://*|*.db|*.sqlite|*.sqlite3)
      printf 'sqlite'
      ;;
    *)
      log error "unsupported database URL format: ${WHITE}$DB_URL${NC}"
      log error "supported formats: postgresql://... or sqlite://... or *.db"
      exit 3
      ;;
  esac
}

# get_sqlite_path()
get_sqlite_path() {
  case "$DB_URL" in
    sqlite://*)
      printf '%s' "$DB_URL" | sed 's|^sqlite://||'
      ;;
    *)
      printf '%s' "$DB_URL"
      ;;
  esac
}

# db_exec(sql)
db_exec() {
  local sql="$1"
  local db_type
  db_type=$(detect_db_type)
  
  case "$db_type" in
    postgresql)
      local psql_args
      psql_args="$(form_psql_args)"
      # shellcheck disable=SC2086
      printf '%s' "$sql" | psql $psql_args "$DB_URL"
      ;;
    sqlite)
      local db_path
      db_path=$(get_sqlite_path)
      # Use -batch for non-interactive execution
      printf '%s' "$sql" | sqlite3 -batch "$db_path"
      ;;
  esac
}

# db_query(sql)
db_query() {
  local sql="$1"
  local db_type
  db_type=$(detect_db_type)
  
  case "$db_type" in
    postgresql)
      psql "$DB_URL" --no-align --tuples-only --quiet --command "$sql" | awk NF
      ;;
    sqlite)
      local db_path
      db_path=$(get_sqlite_path)
      # Use -noheader -list for clean output (one value per line, no formatting)
      sqlite3 -bail -noheader -list "$db_path" "$sql" | awk NF
      ;;
  esac
}

# db_exec_file(file_path)
db_exec_file() {
  local file_path="$1"
  local db_type
  db_type=$(detect_db_type)
  
  case "$db_type" in
    postgresql)
      local psql_args escaped_path
      psql_args="$(form_psql_args)"
      escaped_path=$(printf '%s' "$file_path" | sed "s/'/''/g")
      # shellcheck disable=SC2086
      psql $psql_args "$DB_URL" <<SQL
BEGIN;
\i '$escaped_path'
COMMIT;
SQL
      ;;
    sqlite)
      local db_path
      db_path=$(get_sqlite_path)
      sqlite3 -bail -batch "$db_path" <<SQL
BEGIN;
.read $file_path
COMMIT;
SQL
      ;;
  esac
}

# shellcheck disable=SC2120
init() {
  while [ $# -gt 0 ]; do
    case $1 in
      --dry-run)
        INIT_DRY_RUN=1
        shift
      ;;
      --db-url|-u)
        DB_URL="$2"
        shift 2
      ;;
      --set|-v)
        VARIABLE_LIST="${VARIABLE_LIST+$VARIABLE_LIST }$2"
        shift 2
      ;;
      --*|-*)
        printf 'init argument %s does not exists' "$1"
        exit 9
      ;;
      *)
        printf 'init command %s does not exists' "$1"
        exit 9
      ;;
    esac
  done

  [ "${INIT_DRY_RUN+x}" ] && { printf '%s\n' "$(init_sql)"; exit; }

  error_handler_no_db_url

  db_type=$(detect_db_type)

  # INHERITS is PostgreSQL-only feature
  [ ${INHERITS_LIST+x} ] && {
    if [ "$db_type" != "postgresql" ]; then
      log error "INHERITS is only supported for PostgreSQL"
      exit 1
    fi

    oldIFS="$IFS"
    IFS=','
    check_inherits=
    for table in $INHERITS_LIST; do
      check_inherits="$(printf '%s\nSELECT 1 FROM %s LIMIT 1;' "$check_inherits" "$table")"
    done
    IFS="$oldIFS"

    check_inherits=$(printf '%s\n' \
      'BEGIN;' \
      "$check_inherits" \
      'COMMIT;')

    if ! db_exec "$check_inherits"; then
      log error "init failed: ${WHITE}one of inherits table does not exists: ${CYAN}$INHERITS_LIST"
      exit 5
    fi
  }

  if ! db_exec "$(init_sql)"; then
    log error "init failed"
    exit 13
  fi
}

# error_handler_no_db_url()
error_handler_no_db_url() {
  [ "${DB_URL+x}" ] || { log error "no ${WHITE}DB_URL${NC} or ${WHITE}--db-url${NC} specified"; exit 3; }
  check_db_dependencies
}

init_sql_postgresql() {
  local sql inherits

  inherits=
  [ ${INHERITS_LIST+x} ] && inherits="$(printf 'INHERITS(%s)' "$INHERITS_LIST")"

  sql="$(cat <<EOF
BEGIN;

DO \$\$
DECLARE
  version TEXT;
BEGIN
  CREATE SCHEMA IF NOT EXISTS hectic;
    
  -- NOTE(yukkop): check version table exists
  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = 'version'
      AND n.nspname = 'hectic'
      AND c.relkind = 'r'
  ) THEN
    SELECT hectic.version.version FROM hectic.version  WHERE name = 'migrator' INTO version;
    IF version != '$VERSION' THEN
      RAISE EXCEPTION 'Incompatible migrator versions: % and $VERSION', version;
    END IF;
  ELSE
    CREATE DOMAIN hectic.migration_name AS TEXT CHECK (VALUE ~ '^[0-9]{14}-.*');
    CREATE DOMAIN hectic.sha256 AS CHAR(64) CHECK (VALUE ~ '^[0-9a-f]{64}\$');

    CREATE FUNCTION hectic.sha256_lower() RETURNS trigger AS \$fn\$
    BEGIN
      NEW.hash = lower(NEW.hash);
      RETURN NEW;
    END;
    \$fn\$ LANGUAGE plpgsql;

    CREATE TABLE hectic.version (
        name          TEXT                 PRIMARY KEY,
        version       TEXT                 NOT NULL,
        installed_at  TIMESTAMPTZ          NOT NULL DEFAULT NOW()
    )$inherits;

    INSERT INTO hectic.version (name, version) VALUES ('migrator', '$VERSION');

    CREATE TABLE hectic.migration (
        id          SERIAL                 PRIMARY KEY,
        name        hectic.migration_name  UNIQUE NOT NULL,
        hash        hectic.sha256          UNIQUE NOT NULL,
        applied_at  TIMESTAMPTZ            NOT NULL DEFAULT NOW()
    )$inherits;

    CREATE TRIGGER hectic_t_sha256_lower
    BEFORE INSERT OR UPDATE ON hectic.migration
    FOR EACH ROW EXECUTE FUNCTION hectic.sha256_lower();
  END IF;
END;
\$\$;

COMMIT;
EOF
  )"

  printf '%s' "$sql"
}

init_sql_sqlite() {
  local sql

  sql="$(cat <<'EOF'
BEGIN;

CREATE TABLE IF NOT EXISTS hectic_version (
    name          TEXT PRIMARY KEY,
    version       TEXT NOT NULL,
    installed_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS hectic_migration (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT UNIQUE NOT NULL CHECK (name GLOB '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-*'),
    hash        TEXT UNIQUE NOT NULL CHECK (length(hash) = 64 AND lower(hash) = hash),
    applied_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Create trigger to enforce version compatibility
CREATE TRIGGER IF NOT EXISTS hectic_version_check
BEFORE INSERT ON hectic_version
FOR EACH ROW
WHEN NEW.name = 'migrator' 
     AND EXISTS (SELECT 1 FROM hectic_version WHERE name = 'migrator' AND version != NEW.version)
BEGIN
    SELECT RAISE(ABORT, 'Incompatible migrator versions');
END;

-- Insert version if not exists
INSERT OR IGNORE INTO hectic_version (name, version) VALUES ('migrator', 'VERSION_PLACEHOLDER');

COMMIT;
EOF
  )"

  # Replace version placeholder
  sql=$(printf '%s' "$sql" | sed "s/VERSION_PLACEHOLDER/$VERSION/g")

  printf '%s' "$sql"
}

init_sql() {
  local db_type
  db_type=$(detect_db_type)
  
  case "$db_type" in
    postgresql)
      init_sql_postgresql
      ;;
    sqlite)
      init_sql_sqlite
      ;;
  esac
}

help() {
  # shellcheck disable=SC2059
  printf "$(cat <<EOF
${BGREEN}Usage:$NC migrator [OPTIONS] COMMAND [ARGS...]

migrator - A lightweight database migration tool supporting PostgreSQL and SQLite.
           Tracks migrations in a dedicated table and supports bidirectional migrations.

${BGREEN}Commands:
    ${BCYAN}init$NC                Initialize migration tables in database
    ${BCYAN}migrate$NC             Apply or revert migrations
    ${BCYAN}create$NC              Create a new migration file
    ${BCYAN}list$NC                List available migrations
    ${BCYAN}fetch$NC               Fetch migration status from database

${BGREEN}Global Options:
    ${BCYAN}--db-url ${CYAN}URL$NC, $BCYAN-u ${CYAN}URL$NC
                        Database connection URL (required for most commands)
                        PostgreSQL: postgresql://user@host/database
                        SQLite:     sqlite:///path/to/file.db or /path/to/file.db
    
    ${BCYAN}--migration-dir ${CYAN}DIR$NC, ${BCYAN}-d ${CYAN}DIR$NC
                        Directory containing migrations (default: ./migration)
    
    ${BCYAN}--inherits ${CYAN}TABLE$NC    (PostgreSQL only) Parent table for hectic.migration
                        Can be specified multiple times

${BGREEN}Migrate Subcommands:
    ${BCYAN}up ${CYAN}[N]$NC              Apply next N migrations (default: 1)
    ${BCYAN}up all$NC              Apply all pending migrations (same as: up latest)
    ${BCYAN}down ${CYAN}[N]$NC            Revert last N migrations (default: 1)
    ${BCYAN}to ${CYAN}MIGRATION$NC        Migrate to specific migration (forward or backward)
    ${BCYAN}to latest$NC           Migrate to the latest migration (aliases: head, last)

${BGREEN}Migrate Options:
    $BCYAN--force$NC, $BCYAN-f$NC         Force migration despite tree mismatch (not implemented)
    $BCYAN--set ${CYAN}VAR$NC, $BCYAN-v ${CYAN}VAR$NC   Set psql variable (PostgreSQL only)

${BGREEN}Init Options:
    $BCYAN--dry-run$NC           Print initialization SQL without executing

${BGREEN}Create Options:
    $BCYAN--name ${CYAN}NAME$NC, $BCYAN-n ${CYAN}NAME$NC
                        Name for the migration (default: random word)

${BGREEN}List Options:
    $BCYAN--raw$NC, $BCYAN-r$NC           Output raw migration names without validation

${BGREEN}Examples:
    ${BBLACK}# Initialize migration tracking$NC
    migrator --db-url postgresql://user@localhost/mydb init

    ${BBLACK}# Create a new migration$NC
    migrator create --name add-users-table

    ${BBLACK}# Apply next migration$NC
    migrator -u postgresql://user@localhost/mydb migrate up

    ${BBLACK}# Apply next 3 migrations$NC
    migrator -u postgresql://user@localhost/mydb migrate up 3

    ${BBLACK}# Apply all pending migrations$NC
    migrator -u postgresql://user@localhost/mydb migrate up all
    ${BBLACK}# or:$NC
    migrator -u postgresql://user@localhost/mydb migrate to latest

    ${BBLACK}# Revert last migration$NC
    migrator -u postgresql://user@localhost/mydb migrate down

    ${BBLACK}# Migrate to specific version$NC
    migrator -u postgresql://user@localhost/mydb migrate to 20231201120000-add-users

    ${BBLACK}# List migrations$NC
    migrator list

    ${BBLACK}# Use SQLite$NC
    migrator --db-url sqlite:///path/to/db.sqlite migrate up

    ${BBLACK}# PostgreSQL with table inheritance$NC
    migrator --inherits audit_log --db-url $DB_URL init

${BGREEN}Migration File Structure:$NC
    migration/
    └── 20231201120000-migration-name/
        ├── up.sql      - Forward migration
        └── down.sql    - Rollback migration

${BGREEN}Migration Naming:$NC
    Migrations must follow the format: YYYYMMDDHHMMSS-description
    Example: 20231201120000-add-users-table

${BGREEN}Database Support:$NC
    PostgreSQL:
        - Full schema support (hectic.migration)
        - Domains with regex validation
        - Triggers and functions
        - Table inheritance (--inherits)
        - Custom psql variables (--set)
    
    SQLite:
        - Simple table names (hectic_migration, hectic_version)
        - CHECK constraints for validation
        - Trigger-based version control
        - File-based databases

${BGREEN}Environment Bariables:$NC
    ${BBLACK}MIGRATION_DIR$NC       Default migration directory
    ${BBLACK}DB_URL$NC              Default database URL (can be overridden with --db-url)

${BGREEN}Exit Codes:$NC
    0    Success
    1    Generic error
    2    Ambiguous arguments or unrelated migration tree
    3    Missing required argument
    4    Migration execution failed
    5    Table does not exist (for --inherits)
    9    Invalid argument or command
    13   System/database incompatibility
    127  Required tool not installed (psql or sqlite3)

${BGREEN}Version:$NC
    0.0.1

${BGREEN}More Info:$NC
    Migration files are executed within transactions.
    Failed migrations are automatically rolled back.
    Migration hashes are tracked to detect tampering.
EOF
)" | "$PAGER"
}

migrate_down() {
  DOWN_NUMBER=1
  while [ $# -gt 0 ]; do
    case $1 in
      --*|-*)
        log error "\`migrate down\` argument $WHITE$1$NC does not exists"
        exit 1
      ;;
      ''|*[!0-9]*)
        log error "down argument not a number";
        exit 1;
      ;;
      *)
        DOWN_NUMBER=$1
        shift;
      ;;
    esac
  done

  # Calculate target migration: current - DOWN_NUMBER
  if [ -z "$db_migrations" ]; then
    log error "cannot migrate down: no migrations applied"
    exit 1
  fi
  
  current_migration=$(printf '%s\n' "$db_migrations" | tail -n1)
  current_idx=$(index_of "$fs_migrations" "$current_migration")
  target_line=$((current_idx - DOWN_NUMBER))
  
  if [ "$target_line" -lt 0 ]; then
    log error "cannot migrate down $DOWN_NUMBER step(s): would go before first migration"
    exit 1
  fi
  
  # target_line of 0 means migrate down to nothing (revert all)
  if [ "$target_line" -eq 0 ]; then
    printf ''
  else
    target_migration=$(printf '%s' "$fs_migrations" | sed -n "${target_line}p")
    printf '%s' "$target_migration"
  fi
}

migrate_up() {
  UP_NUMBER=1
  local apply_all=0
  
  while [ $# -gt 0 ]; do
    case $1 in
      --*|-*)
        log error "\`migrate up\` argument $WHITE$1$NC does not exists"
        exit 1
      ;;
      all|latest|head)
        apply_all=1
        shift
      ;;
      ''|*[!0-9]*)
        log error "up argument not a number or 'all'";
        exit 1;
      ;;
      *)
        UP_NUMBER=$1
        shift;
      ;;
    esac
  done

  if [ "$apply_all" -eq 1 ]; then
    target_migration=$(printf '%s' "$fs_migrations" | tail -n1)
    if [ -z "$target_migration" ]; then
      log error "no migrations found"
      exit 1
    fi
    printf '%s' "$target_migration"
    return 0
  fi

  # Calculate target migration: current + UP_NUMBER
  if [ -z "$db_migrations" ]; then
    target_line=$UP_NUMBER
  else
    current_migration=$(printf '%s\n' "$db_migrations" | tail -n1)
    current_idx=$(index_of "$fs_migrations" "$current_migration")
    target_line=$((current_idx + UP_NUMBER))
  fi
  
  target_migration=$(printf '%s' "$fs_migrations" | sed -n "${target_line}p")
  
  if [ -z "$target_migration" ]; then
    log error "cannot migrate up $UP_NUMBER step(s): not enough migrations"
    exit 1
  fi
  
  printf '%s' "$target_migration"
}

migrate_to() {
  local migration_name
  while [ $# -gt 0 ]; do
    case $1 in
      --*|-*)
        log error  "\`migrate to\` argument $WHITE$1$NC does not exists"
        exit 1
      ;;
      *)
        #shellcheck disable=SC2016
        [ "${migration_name+x}" ] && { log error '`migrate to` too many arguments'; exit 1; }
        migration_name=$1
        shift
      ;;
    esac
  done

  [ "${migration_name+x}" ] || { log error "no migration name specified"; exit 1; }
  
  case "$migration_name" in
    latest|head|last)
      # Return the last migration from filesystem
      printf '%s' "$fs_migrations" | tail -n1
      ;;
    *)
      printf '%s' "$migration_name"
      ;;
  esac
}

migration_list() {
  find "$MIGRATION_DIR" -maxdepth 1 -type d -regextype posix-extended -regex '^.*/[0-9]{14}-.*$' -printf '%f\n' | sort
}

# index_of(array, name)
index_of() {
  local list name m i=1
  list=$1
  name=$2
  [ -z "$name" ] && return 1

  # no subshell, no pipeline
  while IFS= read -r m; do
    [ "$m" = "$name" ] && { printf '%s\n' "$i"; return 0; }
    i=$((i+1))
  done <<EOF
$list
EOF

  return 1
}

migrate() {
  local fs_migrations db_migrations db_migration fs_migration psql_args var #target_migration
  MIGRATOR_REMAINING_ARS=

  while [ $# -gt 0 ]; do
    log trace "migrate arg $WHITE$1"
    case $1 in
      up|down|to)
        [ "${MIGRATE_SUBCOMMAND+x}" ] && {
          log error "ambiguous migrate subcommand, decide ${WHITE}$MIGRATE_SUBCOMMAND ${NC}or ${WHITE}$1";
          exit 2
        }
        MIGRATE_SUBCOMMAND="$1"
        shift
      ;;
      --db-url|-u)
        DB_URL="$2"
        shift 2
      ;;
      --force|-f)
        FORCE=1
        shift
      ;;
      --set|-v)
        VARIABLE_LIST="${VARIABLE_LIST+$VARIABLE_LIST }$2"
        shift 2
      ;;
      --*|-*) MIGRATOR_REMAINING_ARS="$MIGRATOR_REMAINING_ARS $(quote "$1")"; shift ;;              # unknown global -> pass through
      *) MIGRATOR_REMAINING_ARS="$MIGRATOR_REMAINING_ARS $(quote "$1")"; shift ;;
    esac
  done

  log debug "migrate REMAINING_ARGS: $WHITE$MIGRATOR_REMAINING_ARS"

  [ "${FORCE+x}" ] && {
    log error "migrate --force not implemented"
    exit 1
  }

  init

  fs_migrations=$(migration_list)

  db_type=$(detect_db_type)
  
  case "$db_type" in
    postgresql)
      db_migrations=$(db_query "SELECT name FROM hectic.migration ORDER BY name ASC")
      ;;
    sqlite)
      db_migrations=$(db_query "SELECT name FROM hectic_migration ORDER BY name ASC")
      ;;
  esac

  log debug "db mig: $db_migrations"
  db_mig_count=$(printf '%s' "$db_migrations" | wc -l)
  log debug "mig count: $db_mig_count"

  # Log migration lists for debugging
  fs_mig_count=$(printf '%s' "$fs_migrations" | wc -l)
  log info "Filesystem migrations found: ${WHITE}$fs_mig_count"
  log info "Database migrations applied: ${WHITE}$db_mig_count"
  
  # Check if the DB migrations form a proper prefix of disk migrations
  # (meaning all DB-applied migration filenames should appear in the same order at the start).
  i=0
  for db_migration in $db_migrations; do
    fs_migration=$(printf '%s' "$fs_migrations" | sed -n "$((i+1))p")
    log debug "Checking migration $((i+1)): DB=${WHITE}$db_migration${NC} vs FS=${WHITE}$fs_migration"
    
    if [ -z "$fs_migration" ] || [ "$fs_migration" != "$db_migration" ]; then
      if ! [ "${FORCE+x}" ]; then
        log error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log error "${RED}Migration history mismatch detected!${NC}"
        log error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log error ""
        log error "Position: Migration #$((i+1))"
        log error "Database has: ${WHITE}$db_migration"
        log error "Filesystem has: ${WHITE}$fs_migration"
        log error ""
        log error "Full filesystem migrations (in order):"
        j=1
        printf '%s\n' "$fs_migrations" | while IFS= read -r m; do
          log error "  $j. ${CYAN}$m"
          j=$((j+1))
        done
        log error ""
        log error "Full database migrations (in order):"
        j=1
        printf '%s\n' "$db_migrations" | while IFS= read -r m; do
          log error "  $j. ${CYAN}$m"
          j=$((j+1))
        done
        log error ""
        log error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log error "This usually means:"
        log error "  • Migration files were removed or renamed"
        log error "  • Migrations were applied out of order"
        log error "  • Database and codebase are from different versions"
        log error ""
        log error "${YELLOW}To proceed anyway, use: ${WHITE}--force${NC}${YELLOW}!${NC}"
        log error "${YELLOW}Warning: This may cause data inconsistencies!${NC}"
        log error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        exit 2
      else
        log notice "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log notice "${YELLOW}Migration history mismatch detected but ${WHITE}--force${NC}${YELLOW} specified${NC}"
        log notice "Position: Migration #$((i+1))"
        log notice "Database has: ${WHITE}$db_migration"
        log notice "Filesystem has: ${WHITE}$fs_migration"
        log notice "${YELLOW}Proceeding with migration despite mismatch...${NC}"
        log notice "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        break
      fi
    fi
    i=$((i+1))
  done
  
  log info "Migration history validation: ${GREEN}OK${NC} (${WHITE}$i${NC} migrations match)"

  eval "set -- $MIGRATOR_REMAINING_ARS"
  target_migration="$("migrate_$MIGRATE_SUBCOMMAND" "$@")"

  if [ -z "$db_migrations" ]; then
    log info "it'll firs migration"
    current_idx=0
  else
    current_migration=$(printf '%s\n' "$db_migrations" | tail -n1)
    current_idx=$(index_of "$fs_migrations" "$current_migration")
  fi

  log debug "[$WHITE$fs_migrations$NC]"
  log debug "$target_migration"

  if [ -z "$target_migration" ]; then
    target_idx=0
  else
    target_idx=$(index_of "$fs_migrations" "$target_migration")
  fi

  log debug "indexes $WHITE$current_idx$NC $WHITE${target_idx}"

  if [ "$target_idx" -eq "$current_idx" ]; then
    if [ "$target_idx" -eq 0 ]; then
      log notice "database already at clean state (no migrations)"
    else
      log notice "database already at ${WHITE}$target_migration${NC}"
    fi
    exit 0
  fi

  # Apply migrations
  psql_args="$(form_psql_args)"
  
  if [ "$target_idx" -gt "$current_idx" ]; then
    # Migrate UP
    log info "migrating up from index $current_idx to $target_idx"
    
    i=$((current_idx + 1))
    while [ "$i" -le "$target_idx" ]; do
      fs_migration=$(printf '%s' "$fs_migrations" | sed -n "${i}p")
      
      escaped_name=$(printf '%s' "$fs_migration" | sed "s/'/''/g")
      mig_path="$MIGRATION_DIR/$fs_migration/up.sql"
      escaped_path=$(printf '%s' "$mig_path" | sed "s/'/''/g")
      
      if [ ! -f "$mig_path" ]; then
        log error "migration file not found: ${WHITE}$mig_path${NC}"
        exit 1
      fi
      
      mig_hash=$(sha256sum "$mig_path")
      log info "applying migration ${WHITE}$fs_migration${NC} (up)"
      
      case "$db_type" in
        postgresql)
          local psql_args
          psql_args="$(form_psql_args)"
          # shellcheck disable=SC2086
          if ! psql $psql_args "$DB_URL" <<SQL
BEGIN;
\i '$escaped_path'
INSERT INTO hectic.migration (name, hash) VALUES ('$escaped_name', '$mig_hash');
COMMIT;
SQL
          then
            log error "migration failed: ${WHITE}$fs_migration${NC}"
            exit 4
          fi
          ;;
        sqlite)
          local db_path
          db_path=$(get_sqlite_path)
          if ! sqlite3 -bail -batch "$db_path" <<SQL
BEGIN TRANSACTION;
.read $mig_path
INSERT INTO hectic_migration (name, hash) VALUES ('$escaped_name', '$mig_hash');
COMMIT;
SQL
          then
            log error "migration failed: ${WHITE}$fs_migration${NC}"
            exit 4
          fi
          ;;
      esac
      
      i=$((i + 1))
    done
    
    log notice "successfully migrated to ${WHITE}$target_migration${NC}"
    
  elif [ "$target_idx" -lt "$current_idx" ]; then
    # Migrate DOWN
    log info "migrating down from index $current_idx to $target_idx"
    
    i=$current_idx
    while [ "$i" -gt "$target_idx" ]; do
      fs_migration=$(printf '%s' "$fs_migrations" | sed -n "${i}p")
      
      escaped_name=$(printf '%s' "$fs_migration" | sed "s/'/''/g")
      mig_path="$MIGRATION_DIR/$fs_migration/down.sql"
      escaped_path=$(printf '%s' "$mig_path" | sed "s/'/''/g")
      
      if [ ! -f "$mig_path" ]; then
        log error "migration file not found: ${WHITE}$mig_path${NC}"
        exit 1
      fi
      
      log info "reverting migration ${WHITE}$fs_migration${NC} (down)"
      
      case "$db_type" in
        postgresql)
          local psql_args
          psql_args="$(form_psql_args)"
          # shellcheck disable=SC2086
          if ! psql $psql_args "$DB_URL" <<SQL
BEGIN;
\i '$escaped_path'
DELETE FROM hectic.migration WHERE name = '$escaped_name';
COMMIT;
SQL
          then
            log error "migration rollback failed: ${WHITE}$fs_migration${NC}"
            exit 4
          fi
          ;;
        sqlite)
          local db_path
          db_path=$(get_sqlite_path)
          if ! sqlite3 -bail -batch "$db_path" <<SQL
BEGIN TRANSACTION;
.read $mig_path
DELETE FROM hectic_migration WHERE name = '$escaped_name';
COMMIT;
SQL
          then
            log error "migration rollback failed: ${WHITE}$fs_migration${NC}"
            exit 4
          fi
          ;;
      esac
      
      i=$((i - 1))
    done
    
    if [ "$target_idx" -eq 0 ]; then
      log notice "successfully migrated down to clean state"
    else
      log notice "successfully migrated down to ${WHITE}$target_migration${NC}"
    fi
  fi
}

form_psql_args() {
  local psql_args="-v ON_ERROR_STOP=1"
  for var in ${VARIABLE_LIST:-}; do
    psql_args="$psql_args -v $var"
  done
  printf '%s' "$psql_args"
}

create() {
  local time_stamp name file_name file_path

  while [ $# -gt 0 ]; do
    case $1 in
      --name|-n)
        # shellcheck disable=SC2034
        MIGRATION_NAME=$2
        shift 2
      ;;
      --*|-*)
        log error "create argument $1 does not exists"
        exit 9
      ;;
      *)
        log error "create subcommand $1 does not exists"
        exit 9
      ;;
    esac
  done

  [ -d "$MIGRATION_DIR" ] || mkdir -p "$MIGRATION_DIR"

  time_stamp="$(date '+%Y%m%d%H%M%S')"
  name="${MIGRATION_NAME:-$(generate_word)}"
  file_name="${time_stamp}-${name}.sql"
  file_path="${MIGRATION_DIR}/${file_name}"

  printf '%s Write your migration SQL here\n' '--' > "$file_path"

  log notice "created migration: ${WHITE}${file_path}${NC}"
}

fetch() {
  while [ $# -gt 0 ]; do
    case $1 in
      --db-url|-u)
        # shellcheck disable=SC2034
        if ! [ "${DB_URL+x}" ]; then
          DB_URL=$2
        fi
        shift 2
      ;;
    esac
  done

  error_handler_no_db_url
}

list() {
  while [ $# -gt 0 ]; do
    case $1 in
      --raw|-r)
        RAW=1
        shift
      ;;
      --*|-*)
        log error "init argument $1 does not exists"
        exit 9
      ;;
      *)
        log error "init subcommand $1 does not exists"
        exit 9
      ;;
    esac
  done

  [ "${RAW+x}" ] && {
    migration_list
    exit
  }

  migration_list | while read -r name; do
    dir="./${MIGRATION_DIR}/${name}"
    up="$dir/up.sql"
    down="$dir/down.sql"
  
    if [ ! -f "$up" ] || [ ! -f "$down" ]; then
      echo "$name: missing $( [ ! -f "$up" ] && echo up.sql ) $( [ ! -f "$down" ] && echo down.sql )"
    else
      echo "$name"
    fi
  done
}

generate_word() {
  C="b c d f g h j k l m n p r s t v w z"
  V="a e i o u"
  N=${N:-5}
  
  w=
  for i in $(seq 3); do
    c=$(echo "$C" | tr ' ' '\n' | shuf -n1)
    v=$(echo "$V" | tr ' ' '\n' | shuf -n1)
    w="${w}${c}${v}"
  done
  printf '%s' "$w"
}

check_db_dependencies() {
  [ "${DB_URL+x}" ] || return 0  # Skip if no DB_URL yet
  
  db_type=$(detect_db_type)
  
  case "$db_type" in
    postgresql)
      if ! command -v psql >/dev/null; then
        log error "Required tool (psql) is not installed."
        log error "PostgreSQL client tools are required for postgresql:// URLs"
        exit 127
      fi
      ;;
    sqlite)
      if ! command -v sqlite3 >/dev/null; then
        log error "Required tool (sqlite3) is not installed."
        log error "SQLite3 client is required for sqlite:// URLs"
        exit 127
      fi
      ;;
  esac
}

if ! [ "${AS_LIBRARY+x}" ]; then
  # Show help if no arguments
  [ $# -eq 0 ] && { help; exit 0; }
  
  while [ $# -gt 0 ]; do
    log debug "arg: $1"
    case $1 in
      --version|-V)
        printf 'migrator version %s\n' "$VERSION"
        exit 0
      ;;
      help|--help|-h)
        help
        exit 0
      ;;
      migrate|create|fetch|list|init)
        [ "${SUBCOMMAND+x}" ] && { 
          log error "ambiguous subcommand, decide ${WHITE}$SUBCOMMAND ${NC}or ${WHITE}$1";
          exit 2;
        }
        SUBCOMMAND=$1
        shift
      ;;
      --migration-dir|-d)
        MIGRATION_DIR=$2
        shift 2
      ;;
      --inherits)
        INHERITS_LIST="${INHERITS_LIST+$INHERITS_LIST\"}$2"
        shift 2
      ;;
      --*|-*) REMAINING_ARS="$REMAINING_ARS $(quote "$1")"; shift ;;              # unknown global -> pass through
      *) REMAINING_ARS="$REMAINING_ARS $(quote "$1")"; shift ;;
    esac
  done
  
  [ "${INHERITS_LIST+x}" ] && INHERITS_LIST="$(printf '%s' "$INHERITS_LIST" | sed -E 's/"/,/g; s/([^,]+)/"\1"/g')"
  [ "${SUBCOMMAND+x}"    ] || { log error "no subcommand specified. Use 'migrator help' for usage information."; exit 1; }
  
  
  eval "set -- $REMAINING_ARS"
  "$SUBCOMMAND" "$@"
fi
