# shellcheck shell=dash
# shellcheck disable=SC3043

: "${REMAINING_ARGS:=}"

: "${DEFAULT_BACKUP_PATH:=${LOCAL_DIR:-$PWD}/focus/postgresql-backup/}"

: "${SCRIPT_NAME:=$(basename "$0")}"
SCRIPT_NAME=${SCRIPT_NAME%%.sh}

: "${PATCH_SQL:=${PROFILE_DIR:-${LOCAL_DIR:-$PWD}}/test-data.sql}"

if [ "${PG_LOG_PATH+x}" ]; then
  : "${PATCH_LOG:=${PG_LOG_PATH}/patch.stdout.log}"
  : "${HYDRATE_LOG:=${PG_LOG_PATH}/hydate.stdout.log}"
fi

: "${DATABASE_DIR:=${LOCAL_DIR:-$PWD}/db}"
: "${MIGRATION_DIR:=$DATABASE_DIR/migration}"
: "${DATABASE_SOURCE:=$DATABASE_DIR/src}"

: "${HYDRATE_ENTRYPOINT:=entrypoint.sql}"

HYDRATE_ENTRYPOINT="${DATABASE_SOURCE}/${HYDRATE_ENTRYPOINT}"

: "${ENVIRONMENT:=}"

pager_or_cat_init

: "${DB_URL:=${PGURL:-}}"

form_psql_args() {
  local psql_args="$PGURL -v ON_ERROR_STOP=1"
  #for var in ${VARIABLE_LIST:-}; do
  #  psql_args="$psql_args -v $var"
  #done
  printf '%s' "$psql_args"
}

psql_logged() {
  local log_file="$1"
  shift
  if [ -n "$log_file" ]; then
    psql "$@" > "$log_file"
  else
    psql "$@"
  fi
}

db_exec() {
  local sql="$1"
  # shellcheck disable=SC2046
  printf '%s' "$sql" | psql $(form_psql_args)
}

todo() {
  log panic "TODO"
  exit 1
}

log_pager() {
  # shellcheck disable=SC2068
  nvim -R \
       -u NONE \
       -c 'nnoremap q :qa!<CR>' \
       -c 'runtime! plugin/*.vim' \
       -c 'set conceallevel=3' \
       $@ \
       -
}

help_log() {
  # shellcheck disable=SC2059
  printf "$(cat <<EOF
${BGREEN}Usage:${NC} $SCRIPT_NAME log [list|<file>|<index>]

View PostgreSQL logs for current PG_WORKING_DIR.

${BGREEN}Modes:${NC}
  ${BCYAN}log$NC                Interactive pager when attached to TTY,
                     non-interactive concat when piped/redirected
  ${BCYAN}log list$NC           List available log files with numeric indexes
  ${BCYAN}log <index>$NC        Open/print one file by numeric index from list
  ${BCYAN}log <file>$NC         Open/print one file by exact name or unique substring

${BGREEN}Examples:${NC}
  $SCRIPT_NAME log
  $SCRIPT_NAME log list
  $SCRIPT_NAME log 1
  $SCRIPT_NAME log postgresql-2026-04-21

EOF
)" | "$PAGER_OR_CAT"
}

db_log_list_files() {
  log_dir="$1"
  for log_file in "$log_dir"/*; do
    [ -f "$log_file" ] || continue
    printf '%s\n' "$log_file"
  done
}

db_log_print_list() {
  log_dir="$1"
  idx=1
  found=0
  for log_file in "$log_dir"/*; do
    [ -f "$log_file" ] || continue
    found=1
    printf '%2s  %s\n' "$idx" "$(basename "$log_file")"
    idx=$((idx + 1))
  done
  if [ "$found" -eq 0 ]; then
    log warn "no log files in $log_dir"
  fi
}

db_log_resolve_one() {
  log_dir="$1"
  selector="$2"

  if [ -f "$log_dir/$selector" ]; then
    printf '%s\n' "$log_dir/$selector"
    return 0
  fi

  if [ -n "$selector" ] && [ "$selector" -eq "$selector" ] 2>/dev/null; then
    idx=1
    for log_file in "$log_dir"/*; do
      [ -f "$log_file" ] || continue
      if [ "$idx" -eq "$selector" ]; then
        printf '%s\n' "$log_file"
        return 0
      fi
      idx=$((idx + 1))
    done
    return 1
  fi

  matches=
  match_count=0
  for log_file in "$log_dir"/*; do
    [ -f "$log_file" ] || continue
    case "$(basename "$log_file")" in
      *"$selector"*)
        match_count=$((match_count + 1))
        matches="$matches$(printf '%s\n' "$log_file")"
      ;;
    esac
  done

  if [ "$match_count" -eq 1 ]; then
    printf '%s' "$matches"
    return 0
  fi

  return 1
}

help() {
  # shellcheck disable=SC2059
  printf "$(cat <<EOF
${BRED}TLDR; For the most lazy$NC
${BCYAN}$SCRIPT_NAME deploy$NC            ${BRED}Сделать заебись$NC: deploy local db + hydrate sources + patch test data

${BRED}Further useless infomation:$NC
${BGREEN}Usage:${NC} $SCRIPT_NAME [OPTIONS] <SUBCOMMAND> [OPTIONS]

PostgreSQL development database management

${BGREEN}Global Options:${NC}
  $BCYAN-h$NC, $BCYAN--help$NC               Show this help message
  $BCYAN-i$NC, $BCYAN--inherits$NC           Parent table for hectic.migration
                                             Can be specified multiple times
  $BCYAN-u$NC, $BCYAN--url$NC                PostgreSQL connection string (overrides PGURL)

${BGREEN}Database Subcommands:${NC}
  ${BCYAN}deploy ${CYAN}[OPTIONS]$NC         Initialize and deploy PostgreSQL database
                           Default action with full setup including hydrate and patch
                           Options:
                             $BCYAN--no-patch$NC    Skip applying test-data.sql
                             $BCYAN--no-hydrate$NC  Skip building from source files

  ${BCYAN}init${NC} ${CYAN}[OPTIONS]$NC           Initialize PostgreSQL cluster without hydrate or patch

  ${BCYAN}restore${NC} ${CYAN}[PATH]$NC           Restore database from backup

  ${BCYAN}backup${NC}                   Create database backup
                           Creates compressed backup at $BBLACK$DEFAULT_BACKUP_PATH$NC

  ${BCYAN}patch${NC} ${CYAN}[OPTIONS]$NC          Patch file: $BBLACK$PATCH_SQL$NC
                           Apply patch to current database
                           Uses patch file if exists
                           Creates empty patch file if not found
                           Options:
                             $BCYAN--edit$NC, $BCYAN-e$NC   Edit test-data.sql in \$EDITOR before applying

  ${BCYAN}hydrate${NC} ${CYAN}[OPTIONS]$NC        Build database from source files
                           Runs $BBLACK$HYDRATE_ENTRYPOINT$NC

  ${BCYAN}migrator${NC} ${CYAN}[OPTIONS]$NC       Run database migrations
                           Uses for production or pre production

  ${BCYAN}log${NC} ${CYAN}[ARG]$NC                Show PostgreSQL logs
                            ARG: ${BBLACK}list$NC, numeric index, or filename/substring
                            No ARG: interactive on TTY, concat output when piped

  ${BCYAN}replay${NC} ${CYAN}[OPTIONS]$NC         Restore database from point to point using SQL
                           Useful for development after minor schema changes
                           ${BRED}WIP$NC

  ${BCYAN}pull_staging${NC}               Pull data from staging DB into test-data.sql
                           Uses STAGING_* environment variables for connection and dump selection

  ${BCYAN}format${NC}                   Format database source files
                           ${BRED}WIP$NC

  ${BCYAN}test${NC}                     Run SQL test suite (BEGIN/ROLLBACK, no side effects)
                           Executes ${BBLACK}${DATABASE_DIR}/test/test.sql$NC

  ${BCYAN}diff${NC} ${CYAN}[OPTIONS] [PATH]$NC    Compare backup+migrations vs current sources
                           Shows schema differences between production and dev
                           Creates isolated instances for safe comparison
                           Subcommands:
                             ${BCYAN}log$NC            Show diff operation logs

  ${BCYAN}check${NC} ${CYAN}[OPTIONS]$NC          Full deploy + cleanup in an isolated temporary cluster
                           Does not affect your running development database
                           Options:
                             $BCYAN--no-patch$NC    Skip applying test-data.sql
                             $BCYAN--no-hydrate$NC  Skip building from source files
                             $BCYAN-m$NC            Mock external API calls

  ${BCYAN}cleanup${NC}                  Stop the running PostgreSQL cluster and remove its working directory

${BGREEN}Environment Variables:${NC}
  ${BBLACK}PGURL$NC                    PostgreSQL connection string (auto-detected)
  ${BBLACK}PROFILE_DIR$NC              Profile directory (auto-detected)
  ${BBLACK}DATABASE_SOURCE$NC          Database source files directory (default $BBLACK$DATABASE_SOURCE$NC)

${BGREEN}Examples:${NC}
  ${BBLACK}# Basic operations$NC
  $SCRIPT_NAME deploy                     Deploy database with full setup
  $SCRIPT_NAME deploy --no-patch          Deploy without test data
  $SCRIPT_NAME init                       Initialize PostgreSQL only
  $SCRIPT_NAME restore                    Restore from default backup
  $SCRIPT_NAME restore /path/to/backup    Restore from specific path
  $SCRIPT_NAME backup                     Create backup
  $SCRIPT_NAME log                        Show database logs
  $SCRIPT_NAME log list                   List available log files
  $SCRIPT_NAME log 1                      Show one log file by index
  $SCRIPT_NAME log postgresql-2026-04-21 Show one log file by name pattern
  $SCRIPT_NAME patch                      Apply test data
  $SCRIPT_NAME patch --edit               Edit test data and apply

  ${BBLACK}# Schema comparison$NC
  $SCRIPT_NAME diff                       Compare backup vs sources
  $SCRIPT_NAME diff -o diff.txt           Save comparison to file
  $SCRIPT_NAME diff --with-data           Include data in comparison

  ${BBLACK}# Isolated validation$NC
  $SCRIPT_NAME check                      Full deploy + cleanup in temp cluster
  $SCRIPT_NAME check -P                   Check without test data
  $SCRIPT_NAME check -H                   Check without hydrating schema

EOF
)" | "$PAGER_OR_CAT"
}

help_patch() {
  # shellcheck disable=SC2059
  printf "$(cat <<EOF
${BGREEN}Usage:${NC} $SCRIPT_NAME patch [OPTIONS]

Apply test-data.sql to database

${BGREEN}Options:
  $BCYAN-e$NC, $BCYAN--edit$NC    Edit test-data.sql in $BBLACK\$EDITOR$NC before applying

EOF
)" | "$PAGER_OR_CAT"
}

help_hydrate() {
  # shellcheck disable=SC2059
  printf "$(cat <<EOF
${BGREEN}Usage:${NC} $SCRIPT_NAME hydrate [OPTIONS]

Build database from source files

This command builds the database schema from source files by executing
the hydrate entrypoint SQL file. Run hectic secrets hook before
hydration for environment-specific configuration.

${BGREEN}Options:${NC}
  $BCYAN-H$NC, $BCYAN--no-hook$NC         Skip hectic secrets hook
                        Useful when secrets are not needed or already applied
  $BCYAN-m$NC, $BCYAN--mock$NC            Enable mock mode for external API calls
                        Replaces HTTP-calling functions with stubs/test data
                        Cron functions get hardcoded test data instead
  $BCYAN-h$NC, $BCYAN--help$NC            Show this help message

${BGREEN}Process:${NC}
  1. Run hectic secrets hook (unless $BBLACK\`--no-hook\`$NC specified)
     Executes $BBLACK${LOCAL_DIR}/lib/hook/postgres-secrets.sh$NC
  2. Execute hydrate entrypoint SQL file
     Runs $BBLACK$HYDRATE_ENTRYPOINT$NC

${BGREEN}Source Files:${NC}
  DATABASE_SOURCE: $BBLACK${DATABASE_SOURCE}$NC
  HYDRATE_ENTRYPOINT: $BBLACK${HYDRATE_ENTRYPOINT}$NC

${BGREEN}Environment Variables:${NC}
  ${BBLACK}PGURL$NC                  PostgreSQL connection string (required)
  ${BBLACK}DATABASE_SOURCE$NC        Path to database source files directory
  ${BBLACK}HYDRATE_ENTRYPOINT$NC     Path to entrypoint SQL file
  ${BBLACK}ENVIRONMENT$NC            Environment name for secrets hook
  ${BBLACK}PG_LOG_PATH$NC            Log directory for hydrate output

${BGREEN}Examples:${NC}
  $SCRIPT_NAME hydrate              Build database with secrets hook
  $SCRIPT_NAME hydrate --no-hook    Build without running secrets hook
  $SCRIPT_NAME hydrate --mock       Build with external APIs mocked

${BGREEN}Notes:${NC}
  - Database must be running and accessible via ${BBLACK}PGURL$NC
  - Hydration logs are written to $BBLACK${HYDRATE_LOG:-stdout}$NC
  - This command is typically called by $BBLACK\`deploy\`$NC subcommand

EOF
)" | "$PAGER_OR_CAT"
}

help_backup() {
  # shellcheck disable=SC2059
  printf "$(cat <<EOF
${BGREEN}Usage:${NC} $SCRIPT_NAME backup [OPTIONS]

Create a compressed backup of the PostgreSQL server

This command creates a full physical backup of the PostgreSQL server
using $BBLACK\`pg_basebackup\`$NC. The backup is stored in a compressed
tar format at $BBLACK$DEFAULT_BACKUP_PATH$NC.

${BGREEN}Process:${NC}
  1. Removes any existing backup at $BBLACK$DEFAULT_BACKUP_PATH$NC
  2. Creates fresh backup directory
  3. Runs $BBLACK\`pg_basebackup\`$NC with compression
  4. Stores $BBLACK\`base.tar.gz\`$NC and $BBLACK\`pg_wal.tar.gz\`$NC files

${BGREEN}Connection Requirements:${NC}
  Uses PostgreSQL connection from ${BBLACK}PGURL$NC or $BBLACK--url$NC environment variable

${BGREEN}Files Created:${NC}
  - ${BBLACK}\`base.tar.gz\`$NC:      Database cluster backup
  - ${BBLACK}\`pg_wal.tar.gz\`$NC:    Write-Ahead Log files (if present)

${BGREEN}Examples:${NC}
  $SCRIPT_NAME backup       Create backup at default location

${BGREEN}Notes:${NC}
  - This is a physical backup, not logical dump
  - Database must be running and accessible
  - Backup can be restored with $BBLACK\`restore\`$NC subcommand

EOF
)" | "$PAGER_OR_CAT"
}

help_restore() {
  # shellcheck disable=SC2059
  printf "$(cat <<EOF
${BGREEN}Usage:${NC} $SCRIPT_NAME restore [OPTIONS] [path]

Restore PostgreSQL database from a physical backup

This command restores a PostgreSQL database from a backup created by
the $BBLACK\`backup\`$NC subcommand. It performs a complete restore including
data directory, WAL files, and configuration.

${BGREEN}Arguments:
  ${BCYAN}path$NC                  Backup directory path (optional)
                        If not specified defaults to $BBLACK$DEFAULT_BACKUP_PATH$NC
                        Should contain base.tar.gz and optionally pg_wal.tar.gz

${BGREEN}Options:${NC}
  $BCYAN--archive$NC             Extract from archive file first
                        Treat PATH as a compressed archive file to extract
  $BCYAN-h$NC, $BCYAN--help$NC            Show this help message

${BGREEN}Process:${NC}
  1. If $BBLACK\`--archive\`$NC used: extract archive to temporary directory
  2. Run $BBLACK\`postgres-cleanup\`$NC
     to stop and clean existing database
  3. Clear PG_WORKING_DIR directory completely
  4. Extract $BBLACK\`base.tar.gz\`$NC to $BBLACK$PG_WORKING_DIR$NC directory
  5. Extract $BBLACK\`pg_wal.tar.gz\`$NC to ${BBLACK}$PG_WORKING_DIR/pg_wal$NC if present
  6. Remove recovery signals to ensure clean startup
  7. Start PostgreSQL with existing configuration

${BGREEN}Backup Directory Requirements:${NC}
  - $BBLACK\`base.tar.gz\`$NC:      Main database cluster backup (required)
  - $BBLACK\`pg_wal.tar.gz\`$NC:    Write-Ahead Log files (optional)

${BGREEN}Environment Variables:${NC}
  ${BBLACK}PG_WORKING_DIR$NC                PostgreSQL data directory (auto-detected)

${BGREEN}Examples:${NC}
  $SCRIPT_NAME restore                           Restore from default backup
  $SCRIPT_NAME restore /path/to/backup           Restore from specific path
  $SCRIPT_NAME restore --archive backup.tar.gz   Extract and restore from archive

${BGREEN}Warnings:${NC}
  - This will completely overwrite the existing database
  - Database will be stopped during restore process
  - All current data will be lost
  - ${BRED}Only development usage for now$NC

EOF
)" | "$PAGER_OR_CAT"
}

help_diff() {
  # shellcheck disable=SC2059
  printf "$(cat <<EOF
${BGREEN}Usage:${NC} $SCRIPT_NAME diff [OPTIONS] [BACKUP_PATH]
       $SCRIPT_NAME diff log

Compare two full PostgreSQL deployments and show the diff

This command helps identify schema differences between a production backup
and the current source code. It provisions two isolated PostgreSQL instances,
restores one from backup with migrations applied, hydrates the other from
current sources, then compares their schemas.

${BGREEN}Arguments:
  ${BCYAN}BACKUP_PATH${NC}         Path to backup directory (optional)
                      If not specified defaults to $BBLACK$DEFAULT_BACKUP_PATH$NC

${BGREEN}Options:${NC}
  $BCYAN--tables${NC} ${CYAN}<list>${NC}     Comma-separated list of tables to diff
                      Example: --tables users,orders,products
  $BCYAN-m${NC}, $BCYAN--mock${NC}          Mock external API calls when hydrating DB2
                      Replaces HTTP-calling functions with stubs/test data
  $BCYAN-h${NC}, $BCYAN--help${NC}          Show this help message

${BGREEN}Subcommands:${NC}
  ${BCYAN}log${NC}                 Show PostgreSQL logs from diff operation
                      Displays logs from both DB1 and DB2 instances

${BGREEN}Process:${NC}
  1. Create two isolated PostgreSQL instances (DB1 and DB2)
  2. Restore DB1 from backup and apply all migrations
  3. Hydrate DB2 from current source files
  4. Dump both databases to SQL files
  5. Compare dumps and present diff
  6. Clean up temporary instances

${BGREEN}Environment Variables:${NC}
  ${BBLACK}DATABASE_SOURCE$NC       Path to database source files

${BGREEN}Examples:${NC}
  $SCRIPT_NAME diff                              Compare using default backup
  $SCRIPT_NAME diff /path/to/backup              Compare using specific backup
  $SCRIPT_NAME diff --tables users,orders        Compare specific tables
  $SCRIPT_NAME diff -m                           Compare with external APIs mocked
  $SCRIPT_NAME diff log                          Show logs from diff operation

${BGREEN}Notes:${NC}
  - Does not affect your development database
  - Requires backup created with $BBLACK\`backup\`$NC subcommand

EOF
)" | "$PAGER_OR_CAT"
}

help_init() {
  # shellcheck disable=SC2059
  printf "$(cat <<EOF
${BGREEN}Usage:${NC} $SCRIPT_NAME init [OPTIONS]

Initialize PostgreSQL cluster without running hydrate or patch.

${BGREEN}Options:${NC}
  ${BCYAN}--reuse${NC}                Do not wipe database if it already exists
  ${BCYAN}-h${NC}, ${BCYAN}--help${NC}           Show this help message

${BGREEN}Examples:${NC}
  $SCRIPT_NAME init
  $SCRIPT_NAME init --reuse

EOF
)" | "$PAGER_OR_CAT"
}

help_deploy() {
  # shellcheck disable=SC2059
  printf "$(cat <<EOF
${BGREEN}Usage:${NC} $SCRIPT_NAME deploy [OPTIONS]

Initialize and deploy a complete PostgreSQL database for development

This is the primary command for setting up a fresh database. It initializes
PostgreSQL, builds the database from source files, and applies test data.

${BGREEN}Deployment Process:${NC}
  1. Initialize PostgreSQL server via $BBLACK\`postgres-init\`$NC
  2. Run $BBLACK\`hydrate\`$NC to build database from source files (skips with $BBLACK\`--no-hydrate\`$NC)
     - Includes hectic secrets hook by default
  3. Run $BBLACK\`patch\`$NC to apply test-data.sql (skips with $BBLACK\`--no-patch\`$NC)

${BGREEN}Options:${NC}
  $BCYAN--resue$NC                  Do not wipe databse if it exists
  $BCYAN-P$NC, $BCYAN--no-patch$NC           Skip applying test-data.sql
  $BCYAN-H$NC, $BCYAN--no-hydrate$NC         Skip building from source files
  $BCYAN-m$NC, $BCYAN--mock$NC               Mock external API calls (stubs + test data)
  $BCYAN-h$NC, $BCYAN--help$NC               Show this help message

${BGREEN}Source Files:${NC}
  DATABASE_SOURCE: $BBLACK${DATABASE_SOURCE}$NC
  - $BBLACK\`entrypoint.sql\`$NC: Main database schema definition

${BGREEN}Test Data:${NC}
  $BBLACK$PROFILE_DIR/test-data.sql$NC:
  Test data and sample records
  - Created automatically if doesn't exist
  - You can contain here development/sample data for testing

${BGREEN}Environment Variables:${NC}
  ${BBLACK}DATABASE_SOURCE$NC          Path to database source files directory
  ${BBLACK}PROFILE_DIR$NC              Profile directory containing test-data.sql
  ${BBLACK}PGDATA$NC                   PostgreSQL data directory (auto-detected)
  ${BBLACK}PG_LOG_PATH$NC                PostgreSQL log directory

${BGREEN}Examples:${NC}
  $SCRIPT_NAME deploy          Full deployment with all steps
  $SCRIPT_NAME deploy -P       Deploy without test data
  $SCRIPT_NAME deploy -H       Deploy without rebuilding schema
  $SCRIPT_NAME deploy -m       Deploy with external APIs mocked
  $SCRIPT_NAME deploy -P -H    Just (re)setup PostgreSQL
  $SCRIPT_NAME deploy --reuse  Just (re)start postgreSQL,
                           Does not remove state
                           Includes $BBLACK\`--no-hydrate\`$NC & $BBLACK\`--no-patch\`$NC


${BGREEN}Notes:${NC}
  - This will completely overwrite PostgreSQL sever (unless $BBLACK\`--reuse\`$NC )
  - PostgreSQL server will be (re)started
  - Database connection required via ${BBLACK}PGURL$NC

EOF
)" | "$PAGER_OR_CAT"
}

# shellcheck disable=SC2120
subcommand_pull_staging() {
  change_namespace 'db pull_staging'

  if [ -z "${STAGING_SSH_HOST-}" ]; then
    printf 'STAGING_SSH_HOST is not set\n' >&2
    exit 3
  fi
  if [ -z "${STAGING_DB_URL-}" ]; then
    printf 'STAGING_DB_URL is not set\n' >&2
    exit 3
  fi
  if [ -z "${STAGING_DUMP_TABLES-}" ]; then
    printf 'STAGING_DUMP_TABLES is not set\n' >&2
    exit 3
  fi
  if [ -z "${STAGING_DUMP_FLAGS-}" ]; then
    printf 'STAGING_DUMP_FLAGS is not set\n' >&2
    exit 3
  fi

  while [ $# -gt 0 ]; do
    case $1 in
      -h|--help)
        help_pull_staging
        exit 0
      ;;
      --*|-*)
        log error "pull_staging argument $1 does not exist"
        exit 9
      ;;
      *)
        log error "pull_staging: unexpected argument $1"
        exit 9
      ;;
    esac
  done

  PG_DUMP_TABLE_ARGS=''
  for tbl in $STAGING_DUMP_TABLES; do
    PG_DUMP_TABLE_ARGS="$PG_DUMP_TABLE_ARGS -t $(quote "$tbl")"
  done

  log notice "pulling data from ${WHITE}${STAGING_SSH_HOST}${NC}"

  remote_dump_command="pg_dump $(quote "$STAGING_DB_URL") $STAGING_DUMP_FLAGS$PG_DUMP_TABLE_ARGS 2>/dev/null"
  # shellcheck disable=SC2029
  STAGING_DUMP=$(ssh "$STAGING_SSH_HOST" "$remote_dump_command") || {
    log error "failed to dump staging database via SSH"
    exit 1
  }

  if [ -z "$STAGING_DUMP" ]; then
    log error "staging dump returned empty output"
    exit 1
  fi

  SEQ_RESETS=''
  for tbl in $STAGING_DUMP_TABLES; do
    escaped_tbl=$(printf '%s' "$tbl" | sed "s/'/''/g")
    SEQ_RESETS="$SEQ_RESETS
SELECT setval(seq_name, COALESCE((SELECT MAX(\"id\") FROM $tbl), 1))
FROM (SELECT pg_get_serial_sequence('$escaped_tbl', 'id') AS seq_name) AS seq
WHERE seq_name IS NOT NULL;"
  done

  mkdir -p "$(dirname "$PATCH_SQL")"
  touch "$PATCH_SQL"
  cat > "$PATCH_SQL" <<EOSQL
-- Test data for local development
-- Pulled from staging ($STAGING_SSH_HOST) on $(date -u '+%Y-%m-%d %H:%M UTC')
-- Auto-generated by: $SCRIPT_NAME pull_staging

$STAGING_DUMP

-- Reset sequences to match imported data
$SEQ_RESETS
EOSQL

  log notice "written to ${WHITE}${PATCH_SQL}${NC}"
  log notice "tables dumped: ${WHITE}${STAGING_DUMP_TABLES}${NC}"

  restore_namespace
}

help_pull_staging() {
  # shellcheck disable=SC2059
  printf "$(cat <<EOF
${BGREEN}Usage:${NC} $SCRIPT_NAME pull_staging

Pull data from staging database into test-data.sql (data only, no schema).

Reads the staging connection and dump configuration from environment variables,
SSHs to the staging server, runs pg_dump, and writes the result to
\$PATCH_SQL (${BBLACK}${PATCH_SQL}${NC}).

${BGREEN}Required environment variables:${NC}
  ${BBLACK}STAGING_SSH_HOST${NC}       SSH host alias or hostname
  ${BBLACK}STAGING_DB_URL${NC}         PostgreSQL connection string used by pg_dump
  ${BBLACK}STAGING_DUMP_TABLES${NC}    Space-separated tables passed as -t selectors
  ${BBLACK}STAGING_DUMP_FLAGS${NC}     Extra pg_dump flags

${BGREEN}Examples:${NC}
  STAGING_SSH_HOST=staging \
  STAGING_DB_URL=postgresql://postgres@localhost/app \
  STAGING_DUMP_TABLES='public.users public.orders' \
  STAGING_DUMP_FLAGS='--data-only --column-inserts --on-conflict-do-nothing --no-owner --no-privileges --no-comments' \
  $SCRIPT_NAME pull_staging

EOF
)" | "$PAGER_OR_CAT"
}

help_test() {
  # shellcheck disable=SC2059
  printf "$(cat <<EOF
${BGREEN}Usage:${NC} $SCRIPT_NAME test

Run SQL test suite against the current database

Executes ${BBLACK}${DATABASE_DIR}/test/test.sql${NC} wrapped in
BEGIN/ROLLBACK transactions (no side effects).

${BGREEN}Requirements:${NC}
  Database must be deployed and hydrated before running tests.

${BGREEN}Examples:${NC}
  $SCRIPT_NAME test              Run all tests

EOF
)" | "$PAGER_OR_CAT"
}

subcommand_test() {
  change_namespace 'db test'

  while [ $# -gt 0 ]; do
    case $1 in
      -h|--help)
        help_test
        exit 0
      ;;
      --*|-*)
        log error "test argument $1 does not exists"
        exit 9
      ;;
      *)
        log error "test subcommand $1 does not exists"
        exit 9
      ;;
    esac
  done

  TEST_SQL="${DATABASE_DIR}/test/test.sql"

  if [ ! -f "$TEST_SQL" ]; then
    log error "test file not found: $TEST_SQL"
    exit 1
  fi

  log notice "running tests from $WHITE$TEST_SQL$NC"

  # shellcheck disable=SC2046
  if psql $(form_psql_args) -f "$TEST_SQL"; then
    log notice "all tests ${GREEN}passed"
  else
    log error "tests ${RED}failed"
    exit 1
  fi

  restore_namespace
}

subcommand_format() {
  todo
}

subcommand_backup() {
  change_namespace 'db backup'
  while [ $# -gt 0 ]; do
    case $1 in
      -h|--help)
        help_backup
        exit 0
      ;;
      --*|-*)
        log error "restore argument $1 does not exists"
        exit 9
      ;;
      *)
        log error "restore subcommand $1 does not exists"
        exit 9
      ;;
    esac
  done

  rm -rf "${DEFAULT_BACKUP_PATH:?}"
  mkdir "$DEFAULT_BACKUP_PATH"

  env PGPASSWORD="${URI_PASSWORD}" pg_basebackup \
    -h "${URI_HOST}" -p "${URI_PORT:?}" -U "${URI_USER:?}" \
    -D "${DEFAULT_BACKUP_PATH:?}" -Ft -X stream -z -P
  restore_namespace
}

# shellcheck disable=SC2120
subcommand_restore() {
  change_namespace 'db restore'

  : "${PG_WORKING_DIR:="$LOCAL_DIR/focus/postgresql"}"
  # - to set postgresql server
  #   data & sock directory

  while [ $# -gt 0 ]; do
    case $1 in
      -h|--help)
        help_restore
        exit 0
      ;;
      --archive)
        RESTORE_NEED_UNPACK=1
        shift
      ;;
      --*|-*)
        log error "restore argument $1 does not exists"
        exit 9
      ;;
      *)
        # NOTE: Only first argument unrecognized argument can be path
        if [ ${RESTORE_BACKUP_PATH+x} ]; then
          log error "restore subcommand $1 does not exists"
          exit 9
        else
          RESTORE_BACKUP_PATH=$1
          shift
        fi
      ;;
    esac
  done

  if [ ${RESTORE_NEED_UNPACK+x} ]; then
    local backup_dir
    backup_dir=$(mktemp -d)
    mkdir "$backup_dir"
    tar -xzf "${RESTORE_BACKUP_PATH+x}" -C "${backup_dir}"
    RESTORE_BACKUP_PATH="$backup_dir"
    trap 'rm -rf "$RESTORE_BACKUP_PATH"' EXIT INT HUP
  fi
  if ! [ ${RESTORE_BACKUP_PATH+x} ]; then
    RESTORE_BACKUP_PATH="$DEFAULT_BACKUP_PATH"
  fi

  postgres-cleanup

  local data="${PG_WORKING_DIR:?}/data"

  rm -rf "${data:?}"/
  mkdir -m 700 "${data}"

  tar -xzf "${RESTORE_BACKUP_PATH:?}/base.tar.gz" -C "${data}"
  if [ -f "${RESTORE_BACKUP_PATH:?}/pg_wal.tar.gz" ]; then
    tar -xzf "${RESTORE_BACKUP_PATH:?}/pg_wal.tar.gz" -C "${data}/pg_wal"
  fi

  env PG_REUSE= postgres-init

  rm -f "${data}/standby.signal" "${data}/recovery.signal"
  restore_namespace
}

subcommand_log() {
  change_namespace 'db log'
  : "${PG_WORKING_DIR:="$LOCAL_DIR/focus/postgresql"}"
  LOG_DIR="${PG_WORKING_DIR}/data/log"

  if [ ! -d "$LOG_DIR" ]; then
    log error "log directory not found: $LOG_DIR"
    exit 1
  fi

  while [ $# -gt 0 ]; do
    case $1 in
      -h|--help)
        help_log
        exit 0
      ;;
      --*|-*)
        log error "log argument $1 does not exist"
        exit 9
      ;;
      *)
        if [ "$1" = 'list' ]; then
          db_log_print_list "$LOG_DIR"
          restore_namespace
          return 0
        fi

        resolved_file="$(db_log_resolve_one "$LOG_DIR" "$1" || true)"
        if [ -z "$resolved_file" ]; then
          log error "log file not found or ambiguous: $1"
          log info "use '$SCRIPT_NAME log list' to inspect available files"
          exit 1
        fi

        if [ -t 1 ]; then
          log_pager "$resolved_file"
        else
          cat "$resolved_file"
        fi
        restore_namespace
        return 0
      ;;
    esac
  done

  if [ -t 1 ]; then
    LOG_HELP="${LOCAL_DIR}/focus/database-log-help"
    # shellcheck disable=SC2059
    printf "$(cat <<'EOF'
    press `q` - exit from logs
    use `gt` `gT` to navigate through different log files
EOF
)" > "$LOG_HELP"

    # shellcheck disable=SC2046
    set -- $(db_log_list_files "$LOG_DIR")
    if [ "$#" -eq 0 ]; then
      log warn "no log files in $LOG_DIR"
      restore_namespace
      return 0
    fi

    if [ "$#" -gt 1 ]; then
      log_pager -p "$LOG_HELP" "$@"
    else
      log_pager "$1"
    fi
  else
    found=0
    for log_file in "$LOG_DIR"/*; do
      [ -f "$log_file" ] || continue
      found=1
      cat "$log_file"
    done
    if [ "$found" -eq 0 ]; then
      log warn "no log files in $LOG_DIR"
    fi
  fi

  restore_namespace
}

subcommand_replay() {
  change_namespace 'db replay'
  todo
}



# shellcheck disable=SC2120
subcommand_hydrate() {
  change_namespace 'db hydrate'

  while [ $# -gt 0 ]; do
    case $1 in
      -h|--help)
        help_hydrate
        exit 0
      ;;
      -H|--no-hook)
        HYDRATE_NO_HOOK=1
        shift
      ;;
      -m|--mock)
        HYDRATE_USE_MOCK=1
        shift
      ;;
      --*|-*)
        log error "hydrate argument $1 does not exist"
        exit 9
      ;;
      *)
        log error "hydrate subcommand $1 does not exist"
        exit 9
      ;;
    esac
  done

  if [ ! "${HYDRATE_NO_HOOK+x}" ]; then
    log info "hectic secrets hook"
    # shellcheck disable=SC2059
    printf "${BBLACK}"
    sh "${LOCAL_DIR}/lib/hook/postgres-secrets.sh" "$PGURL" "$ENVIRONMENT"

    # shellcheck disable=SC2059
    printf "${NC}"
  else
    log info "skipping hectic secrets hook"
  fi

  local mock_arg=""
  if [ "${HYDRATE_USE_MOCK+x}" ]; then
    log info "mock mode enabled — external API calls will be stubbed"
    mock_arg="-v USE_MOCK=1"
  fi

  log notice "hydrate database sources"
  # shellcheck disable=SC2059
  printf "${BBLACK}"

  # shellcheck disable=SC2046
  # shellcheck disable=SC2086
  if psql_logged "${HYDRATE_LOG:-}" $(form_psql_args) $mock_arg \
    -f "$HYDRATE_ENTRYPOINT"; then
    log notice "hydrating succes"
  else
    log error "hydrate error, check $WHITE${HYDRATE_LOG:-stdout}$NC for more"
    exit 1
  fi

  restore_namespace
}

subcommand_migrator() {
  change_namespace 'db migrator'
  db_url="${DB_URL:-$PGURL}"
  env MIGRATION_DIR="$MIGRATION_DIR" DB_URL="$db_url" migrator "$@"
  migrator_exit_code="$?"
  restore_namespace

  return "$migrator_exit_code"
}

# ___parse_deploy_flags -- shared option parser for deploy/check
# Sets: DEPLOY_NO_PATCH, DEPLOY_NO_HYDRATE, HYDRATE_USE_MOCK, DEPLOY_REUSE
# Returns remaining unparsed args via REMAINING_ARGS (caller resets first)
# Caller must supply a CALLER name for error messages (first positional arg).
___parse_deploy_flags() {
  _caller="${1:?___parse_deploy_flags: caller name required}"; shift
  while [ $# -gt 0 ]; do
    case $1 in
      -P|--no-patch)
        DEPLOY_NO_PATCH=1
        shift
      ;;
      -H|--no-hydrate)
        DEPLOY_NO_HYDRATE=1
        shift
      ;;
      -m|--mock)
        HYDRATE_USE_MOCK=1
        shift
      ;;
      --reuse)
        DEPLOY_NO_PATCH=1
        DEPLOY_NO_HYDRATE=1
        DEPLOY_REUSE=1
        shift
      ;;
      *)
        log error "$_caller: unknown argument $1"
        exit 9
      ;;
    esac
  done
}

# ___run_deploy_flow -- shared hydrate+patch execution for deploy/check
___run_deploy_flow() {
  if [ ! "${DEPLOY_NO_HYDRATE+x}" ]; then
    subcommand_hydrate
  fi
  if [ ! "${DEPLOY_NO_PATCH+x}" ]; then
    subcommand_patch
  fi
}

subcommand_init() {
  : "${PG_WORKING_DIR:=${LOCAL_DIR}/focus/postgresql}"
  # - to set postgresql server
  #   data & sock directory

  change_namespace 'db init'
  unset DEPLOY_REUSE

  while [ $# -gt 0 ]; do
    case $1 in
      -h|--help)
        help_init
        exit 0
      ;;
      --reuse)
        DEPLOY_REUSE=1
        shift
      ;;
      --*|-*)
        log error "init argument $1 does not exist"
        exit 9
      ;;
      *)
        log error "init: unexpected argument $1"
        exit 9
      ;;
    esac
  done

  {
    [ "${DEPLOY_REUSE+x}" ] && export PG_REUSE
    postgres-init
  }

  restore_namespace
}

subcommand_deploy() {

  : "${PG_WORKING_DIR:="$LOCAL_DIR/focus/postgresql"}"
  # - to set postgresql server
  #   data & sock directory

  change_namespace 'db deploy'

  unset DEPLOY_NO_PATCH DEPLOY_NO_HYDRATE DEPLOY_REUSE DEPLOY_CLEANUP
  _deploy_extra=

  while [ $# -gt 0 ]; do
    case $1 in
      -h|--help)
        help_deploy
        exit 0
      ;;
      -c|--cleanup)
        DEPLOY_CLEANUP=1
        shift
      ;;
      *)
        _deploy_extra="$_deploy_extra $(quote "$1")"
        shift
      ;;
    esac
  done

  [ "$_deploy_extra" = '' ] || eval "___parse_deploy_flags 'deploy' $_deploy_extra"

  {
    [ "${DEPLOY_REUSE+x}" ] && export PG_REUSE
    postgres-init
  }

  ___run_deploy_flow

  if [ "${DEPLOY_CLEANUP+x}" ]; then
    log info "cleanup: stopping postgresql"
    postgres-cleanup
  fi

  restore_namespace
}

# shellcheck disable=SC2120
subcommand_patch() {
  change_namespace 'db patch'

  while [ $# -gt 0 ]; do
    case $1 in
      -e|--edit)
        PATCH_EDIT=1
        shift
      ;;
      -h|--help)
        help_patch
        exit 0
      ;;
      --*|-*)
        log error "patch argument $1 does not exists"
        exit 9
      ;;
      *)
        log error "patch subcommand $1 does not exists"
        exit 9
      ;;
    esac
  done

  mkdir -p "$(dirname "$PATCH_SQL")"
  touch "$PATCH_SQL"

  if [ "${PATCH_EDIT+x}" ]; then
    log notice "opening $WHITE$PATCH_SQL$NC in \$EDITOR"
    "${EDITOR:-vi}" "$PATCH_SQL"
    exit 0
  fi

  log notice "retoring $WHITE$PATCH_SQL$NC in database"

  # shellcheck disable=SC2059
  printf "${BBLACK}"

  # shellcheck disable=SC2046
  if psql_logged "${PATCH_LOG:-}" $(form_psql_args) -f "$PATCH_SQL"; then
    log notice "restoring succes"
  else
    log error "error, check $WHITE${PATCH_LOG:-stdout}$NC for more"
    exit 1
  fi

  restore_namespace
}

___diff_dump_schema() {
  local socket_dir="$1"
  local port="$2"
  local output_file="$3"
  local tables="${4:-}"

  log info "dumping schema to $WHITE$output_file$NC"

  if [ -n "$tables" ]; then
    # Dump specific tables with data
    local table_args=""
    old_IFS="$IFS"
    IFS=','
    for table in $tables; do
      table_args="$table_args -t $table"
    done
    IFS="$old_IFS"

    # shellcheck disable=SC2086
    pg_dump -h "$socket_dir" -p "$port" testdb \
      --schema-only --no-owner --no-privileges \
      $table_args > "$output_file" 2>/dev/null

    # shellcheck disable=SC2086
    pg_dump -h "$socket_dir" -p "$port" testdb \
      --data-only --no-owner --no-privileges \
      $table_args >> "$output_file" 2>/dev/null
  else
    # Schema only
    pg_dump -h "$socket_dir" -p "$port" testdb \
      --schema-only --no-owner --no-privileges \
      > "$output_file" 2>/dev/null
  fi
}

___diff_immutable_tables() {
  local socket_dir="$1"
  local port="$2"
  psql -h "$socket_dir" -p "$port" -d testdb -tAv ON_ERROR_STOP=1 -c "$(cat <<'SQL'
SELECT n.nspname || '.' || c.relname
FROM pg_inherits i
JOIN pg_class    c ON c.oid = i.inhrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE i.inhparent = 'hectic.immutable'::regclass
  AND c.relkind = 'r'
ORDER BY 1
SQL
)" 2>/dev/null
}

___diff_immutable_data() {
  local sock1="$1"
  local port1="$2"
  local sock2="$3"
  local port2="$4"
  local out_file="$5"

  if ! psql -h "$sock1" -p "$port1" -d testdb -tAc \
    "SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hectic' AND c.relname='immutable';" \
    >/dev/null 2>&1
  then
    return 0
  fi

  local tables1 tables2 tables
  tables1=$(___diff_immutable_tables "$sock1" "$port1" || true)
  tables2=$(___diff_immutable_tables "$sock2" "$port2" || true)
  tables=$(printf '%s\n%s\n' "$tables1" "$tables2" | sort -u | sed '/^$/d')

  if [ -z "$tables" ]; then
    return 0
  fi

  log notice "diffing data of tables inheriting hectic.immutable"

  printf '\n--- IMMUTABLE TABLE DATA ---\n' >> "$out_file"

  local data1 data2 differs=0
  data1=$(mktemp)
  data2=$(mktemp)
  trap 'rm -f "$data1" "$data2"' EXIT INT HUP

  for tbl in $tables; do
    log info "  $tbl"
    : > "$data1"
    : > "$data2"
    pg_dump -h "$sock1" -p "$port1" testdb \
      --data-only --no-owner --no-privileges --column-inserts -t "$tbl" \
      > "$data1" 2>/dev/null || :
    pg_dump -h "$sock2" -p "$port2" testdb \
      --data-only --no-owner --no-privileges --column-inserts -t "$tbl" \
      > "$data2" 2>/dev/null || :
    {
      printf '\n=== %s ===\n' "$tbl"
      if diff --color=always -u "$data1" "$data2"; then
        printf '(no differences)\n'
      else
        differs=1
      fi
    } >> "$out_file"
  done

  rm -f "$data1" "$data2"
  trap - EXIT INT HUP
  return $differs
}

help_check() {
  # shellcheck disable=SC2059
  printf "$(cat <<EOF
${BGREEN}Usage:${NC} $SCRIPT_NAME check [OPTIONS]

Run a full deploy in an isolated temporary PostgreSQL cluster, then clean up.
Does not affect your running development database.

${BGREEN}Process:${NC}
  1. Create a temporary working directory under $BBLACK\$LOCAL_DIR/focus/postgresql-check-tmp$NC
  2. Run postgres-init against that temporary cluster
  3. Run hydrate (unless $BBLACK\`--no-hydrate\`$NC)
  4. Run patch (unless $BBLACK\`--no-patch\`$NC)
  5. Stop the temporary cluster via postgres-cleanup
  6. Remove the temporary working directory

${BGREEN}Options:${NC}
  $BCYAN-P$NC, $BCYAN--no-patch$NC     Skip applying test-data.sql
  $BCYAN-H$NC, $BCYAN--no-hydrate$NC   Skip building from source files
  $BCYAN-m$NC, $BCYAN--mock$NC         Mock external API calls
  $BCYAN-h$NC, $BCYAN--help$NC         Show this help message

${BGREEN}Examples:${NC}
  $SCRIPT_NAME check            Full deploy + cleanup
  $SCRIPT_NAME check -P         Skip test data
  $SCRIPT_NAME check -H         Skip schema hydration
  $SCRIPT_NAME check -m         Mock external APIs

EOF
)" | "$PAGER_OR_CAT"
}

# ___stop_and_remove_working_dir -- stop PG cluster and remove its directory
# Expects: $1 = working dir path
___stop_and_remove_working_dir() {
  _wd="${1:?___stop_and_remove_working_dir: working dir required}"
  log info "stopping cluster at $WHITE$_wd$NC"
  PG_WORKING_DIR="$_wd" \
    postgres-cleanup
  log info "removing $WHITE$_wd$NC"
  rm -rf "$_wd"
}

subcommand_check() {
  change_namespace 'db check'

  unset DEPLOY_NO_PATCH DEPLOY_NO_HYDRATE HYDRATE_USE_MOCK DEPLOY_REUSE
  _check_extra=

  while [ $# -gt 0 ]; do
    case $1 in
      -h|--help)
        help_check
        exit 0
      ;;
      *)
        _check_extra="$_check_extra $(quote "$1")"
        shift
      ;;
    esac
  done

  [ "$_check_extra" = '' ] || eval "___parse_deploy_flags 'check' $_check_extra"

  CHECK_WORKING_DIR="${LOCAL_DIR}/focus/postgresql-check-tmp"
  log info "isolated cluster: $WHITE$CHECK_WORKING_DIR$NC"

  rm -rf "$CHECK_WORKING_DIR"
  mkdir -p "$CHECK_WORKING_DIR"

  trap '___stop_and_remove_working_dir "$CHECK_WORKING_DIR"' EXIT INT HUP

  log notice "check: initializing temporary PostgreSQL cluster"
  PG_WORKING_DIR="$CHECK_WORKING_DIR" \
  PG_DATABASE="${PG_DATABASE:-testdb}" \
  PG_DISABLE_LOGGING=1 \
    postgres-init

  PGURL="postgresql://$(id -un)/${PG_DATABASE:-testdb}?host=${CHECK_WORKING_DIR}/sock&port=${PG_PORT:-5432}"
  export PGURL
  log info "check PGURL: $WHITE$PGURL$NC"

  ___run_deploy_flow

  log notice "check: ${GREEN}success${NC} — deploy completed cleanly"
  restore_namespace
}

subcommand_cleanup() {
  change_namespace 'db cleanup'

  : "${PG_WORKING_DIR:="$LOCAL_DIR/focus/postgresql"}"

  while [ $# -gt 0 ]; do
    case $1 in
      -h|--help)
        # shellcheck disable=SC2059
        printf "$(cat <<EOF
${BGREEN}Usage:${NC} $SCRIPT_NAME cleanup

Stop the running PostgreSQL cluster and remove its working directory.
Defaults to $BBLACK$LOCAL_DIR/focus/postgresql$NC unless ${BBLACK}PG_WORKING_DIR$NC is set.

EOF
)" | "$PAGER_OR_CAT"
        exit 0
      ;;
      --*|-*)
        log error "cleanup argument $1 does not exist"
        exit 9
      ;;
      *)
        log error "cleanup: unexpected argument $1"
        exit 9
      ;;
    esac
  done

  ___stop_and_remove_working_dir "$PG_WORKING_DIR"
  restore_namespace
}

subcommand_diff() {
  change_namespace 'db diff'

  DIFF_TABLES="" # TODO: add cron table
  DIFF_NO_CRON=0 # TODO: useless option
  DIFF_BACKUP_PATH=""

  while [ $# -gt 0 ]; do
    case $1 in
      -h|--help)
        help_diff
        exit 0
      ;;
      --tables)
        DIFF_TABLES="$2"
        shift 2
      ;;
      --no-cron)
        DIFF_NO_CRON=1
        shift
      ;;
      -m|--mock)
        HYDRATE_USE_MOCK=1
        shift
      ;;
      log)
        DIFF_LOG=1
        shift
      ;;
      --*|-*)
        log error "diff argument $1 does not exist"
        exit 9
      ;;
      *)
        # NOTE: yes, RESTORE, not DIFF prefix
        if [ -z "$RESTORE_BACKUP_PATH" ]; then
          RESTORE_BACKUP_PATH="$1"
          shift
        else
          log error "diff: unexpected argument $1"
          exit 9
        fi
      ;;
    esac
  done

  DIFF_TMPDIR="${LOCAL_DIR}/focus/database-diff-operation"
  DIFF_PGDATA1="$DIFF_TMPDIR/pgdata1"
  DIFF_PGDATA2="$DIFF_TMPDIR/pgdata2"
  # TODO: suka, logi drugie
  DIFF_PGLOGFILE1="$DIFF_PGDATA1/logfile"
  DIFF_PGLOGFILE2="$DIFF_PGDATA2/logfile"
  DIFF_PGURL1="postgresql://localhost:5432/testdb?host=$DIFF_PGDATA1/sock"
  DIFF_PGURL2="postgresql://localhost:5432/testdb?host=$DIFF_PGDATA2/sock"

  if [ "${DIFF_LOG+x}" ]; then
    log_pager -O "$DIFF_PGLOGFILE1" "$DIFF_PGLOGFILE2"
    exit 0
  fi

  log info "create temporary directory for isolated instances"

  mkdir -p "$DIFF_TMPDIR"
  trap 'pg_ctl -D "$DIFF_TMPDIR/pgdata1/data" stop -m fast >/dev/null 2>&1 || true; pg_ctl -D "$DIFF_TMPDIR/pgdata2/data" stop -m fast >/dev/null 2>&1 || true;' EXIT INT HUP

  mkdir -p "$DIFF_PGDATA1" "$DIFF_PGDATA2"
  log info "DB1: $WHITE$DIFF_PGDATA1$NC"
  log info "DB2: $WHITE$DIFF_PGDATA2$NC"

  log notice "comparing backup vs sources"
  log info "backup: $WHITE$DIFF_BACKUP_PATH$NC"
  log info "sources: $WHITE$DATABASE_SOURCE$NC"

  log notice "provisioning ${WHITE}DB1$NC (backup + migrations)"

  PG_WORKING_DIR="$DIFF_PGDATA1" PG_LOG_PATH="$DIFF_PGDATA1" subcommand_restore

  log info "applying migrations to ${WHITE}DB1$NC"
  subcommand_migrator migrate up all \
    --db-url \
      "$DIFF_PGURL1" \
    || {
      log warn "migrations failed or none to apply"
    }

  log notice "provisioning ${WHITE}DB2$NC (current sources)"

  log info "initializing ${WHITE}DB2$NC with postgres-init"
  PG_WORKING_DIR="$DIFF_PGDATA2" \
  PG_DATABASE="testdb" \
  PG_DISABLE_LOGGING=1 \
    postgres-init || {
    log error "failed to initialize ${WHITE}DB2$NC"
    exit 1
  }

  log info "hydrating ${WHITE}DB2$NC from sources"
  PGURL="$DIFF_PGURL2" \
  subcommand_hydrate || {
    log error "hydration failed"
    exit 1
  }

  subcommand_migrator init \
    --db-url \
      "$DIFF_PGURL2" \
  || {
    log error "init migration failed"
    exit 1
  }

  log notice "dumping schemas"
  DIFF_DUMP1="$DIFF_TMPDIR/target.sql"
  DIFF_DUMP2="$DIFF_TMPDIR/source.sql"

  ___diff_dump_schema "$DIFF_PGDATA1/sock" "5432" "$DIFF_DUMP1" "$DIFF_TABLES"
  ___diff_dump_schema "$DIFF_PGDATA2/sock" "5432" "$DIFF_DUMP2" "$DIFF_TABLES"

  # Optional: filter out cron tables
  if [ "$DIFF_NO_CRON" = "1" ]; then
    log info "filtering cron tables"
    grep -v "cron\." "$DIFF_DUMP1" > "$DIFF_DUMP1.filtered" 2>/dev/null || true
    grep -v "cron\." "$DIFF_DUMP2" > "$DIFF_DUMP2.filtered" 2>/dev/null || true
    mv "$DIFF_DUMP1.filtered" "$DIFF_DUMP1"
    mv "$DIFF_DUMP2.filtered" "$DIFF_DUMP2"
  fi

  log notice "generating diff"

  if diff --color=always -u "$DIFF_DUMP1" "$DIFF_DUMP2" \
    > "$DIFF_TMPDIR/diff"
  then
    log notice "no schema differences found"
    schema_differs=0
  else
    log notice "schema differences found"
    schema_differs=1
  fi

  ___diff_immutable_data \
    "$DIFF_PGDATA1/sock" "5432" \
    "$DIFF_PGDATA2/sock" "5432" \
    "$DIFF_TMPDIR/diff"
  data_status=$?

  if [ "$schema_differs" = 0 ] && [ "$data_status" = 0 ]; then
    log notice "no differences found"
  else
    "$PAGER_OR_CAT" "$DIFF_TMPDIR/diff"
  fi

  restore_namespace
}

# ALLOWED_ACTIONS='backup,log'

if ! [ "${AS_LIBRARY+x}" ]; then
  if [ $# -eq 0 ]; then
    help
    exit 1
  fi

  if [ "$1" = '-h' ] || [ "$1" = '--help' ] || [ "$1" = '-?' ] || [ "$1" = 'help' ] || [ "$1" = '?' ]; then
    help
    exit 0
  fi

  while [ $# -gt 0 ]; do
    case $1 in
      -u|--url)
        PGURL=$2
        DB_URL=$2
        shift 2
      ;;
      deploy|replay|restore|patch|hydrate|backup|log|migrator|diff|pull_staging|test|check|cleanup|init)
        if [ "${SUBCOMMAND+x}" ]; then
          REMAINING_ARGS="$REMAINING_ARGS $(quote "$1")"
        else
          SUBCOMMAND="$1"
        fi
        shift
      ;;
      -i|--inherits)
        INHERITS_LIST="${INHERITS_LIST+$INHERITS_LIST\"}$2"
        shift 2
      ;;
      *) REMAINING_ARGS="$REMAINING_ARGS $(quote "$1")"; shift ;;
    esac
  done

  [ "${SUBCOMMAND+x}" ] || ( log error "no subcommand specified. Use '--help' for usage information."; exit 1; )

  # SAFETY: do not allow use on remote database
  #if ! printf '%s\n' "$ALLOWED_ACTIONS" | grep "$SUBCOMMAND"; then
  #  IS_REMOTE="$(psql "$PGURL" -tAc "SELECT (inet_client_addr() IS NOT NULL)::int;")"
  #  [ "$IS_REMOTE" = 1 ] && (log error "THIS IS NOT LOCAL DATABSE, BASTARD"; exit 1)
  #fi

  [ "${INHERITS_LIST+x}" ] && {

    INHERITS_LIST="$(printf '%s' "$INHERITS_LIST" | sed -E 's/"/,/g; s/([^,]+)/"\1"/g')"

    old_IFS="$IFS"
    IFS=','
    check_inherits=
    for table in $INHERITS_LIST; do
      check_inherits="$(printf '%s\nSELECT 1 FROM %s LIMIT 1;' "$check_inherits" "$table")"
    done
    IFS="$old_IFS"

    check_inherits=$(printf '%s\n' \
      'BEGIN;' \
      "$check_inherits" \
      'COMMIT;')

    if ! db_exec "$check_inherits"; then
      log error "init failed: ${WHITE}one of inherits table does not exists: ${CYAN}$INHERITS_LIST"
      exit 5
    fi
  }

  parsed_uri=$(mktemp)
  trap 'rm -rf "$parsed_uri"' EXIT INT HUP
  parse-uri "${PGURL:-}" > "$parsed_uri"
  # shellcheck disable=SC1090
  . "$parsed_uri"


  [ "$REMAINING_ARGS" = '' ] || eval "set -- $REMAINING_ARGS"; REMAINING_ARGS=
  "subcommand_$SUBCOMMAND" "$@"
fi
