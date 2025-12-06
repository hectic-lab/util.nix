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
REMAINING_ARS=

quote() { printf "'%s'" "$(printf %s "$1" | sed "s/'/'\\\\''/g")"; }

# cat filename | sha256sum()
# sha256sum(filename)
sha256sum() {
  local file
  file="${1:-'-'}"
  cksum --algorithm=sha256 --untagged "$file" | awk '{printf $1}'
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

  psql_args="$(form_psql_args)"

  [ ${INHERITS_LIST+x} ] && {
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

    # shellcheck disable=SC2086
    if ! psql $psql_args -c "$check_inherits"; then
      log error "init failed: ${WHITE}one of inherits table does not exists: ${CYAN}$INHERITS_LIST"
      exit 5
    fi
  }

  # shellcheck disable=SC2086
  if ! psql $psql_args -c "$(init_sql)"; then
    log error "init failed"
    exit 13
  fi
}

# error_handler_no_db_url()
error_handler_no_db_url() {
  [ "${DB_URL+x}" ] || { log error "no ${WHITE}DB_URL${NC} or ${WHITE}--db-url${NC} specified"; exit 3; }
}

init_sql() {
  local sql

  inherits=
  [ ${INHERITS_LIST+x} ] && inherits="$(printf 'INHERITS(%s)' "$INHERITS_LIST")"

  sql="$(cat <<EOF
BEGIN;

DO \$$
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
      RAISE EXCEPTION 'Incampetible migrator versions: % and $VERSION', version; -- TODO(yukkop): show versions
    END IF;
  ELSE
    CREATE DOMAIN hectic.migration_name AS TEXT CHECK (VALUE ~ '^[0-9]{15}-.*');
    CREATE DOMAIN hectic.sha256 AS CHAR(64) CHECK (VALUE ~ '^[0-9a-f]{64}$');

    CREATE FUNCTION hectic.sha256_lower() RETURNS trigger AS \$fn$
    BEGIN
      NEW.hash = lower(NEW.hash);
      RETURN NEW;
    END;
    \$fn$ LANGUAGE plpgsql;

    CREATE TABLE hectic.version (
        name          TEXT                 PRIMARY KEY,
        version       TEXT                 NOT NULL,
        installed_at  TIMESTAMPTZ          NOT NULL DEFAULT NOW()
    );

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
\$$;

COMMIT;
EOF
  )"

  printf '%s' "$sql"
}

help() {
  # inherits: List one or more tables the migration table must inherit from
  echo help
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
        DOWN_NUMBER=$2
        shift 2;
      ;;
    esac
  done

  : "$DOWN_NUMBER"
}

migrate_up() {
  UP_NUMBER=1
  while [ $# -gt 0 ]; do
    case $1 in
      --*|-*)
        log error "\`migrate up\` argument $WHITE$1$NC does not exists"
        exit 1
      ;;
      ''|*[!0-9]*)
        log error "up argument not a number";
        exit 1;
      ;;
      *)
        UP_NUMBER=$2
        shift 2;
      ;;
    esac
  done

  : "$UP_NUMBER"
  #ls "$MIGRATION_DIR" -1 | sort
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
        # shellcheck disable=SC2016
        [ "${migration_name+x}" ] && { log error '`migrate to` too many arguments'; exit 1; }
        migration_name=$1
        shift
      ;;
    esac
  done

  [ "${migration_name+x}" ] || { log error "no migration name specified"; exit 1; }
  printf '%s' "$migration_name"
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

  db_migrations=$(
    psql "$DB_URL" --no-align --tuples-only --quiet \
      --command "SELECT name FROM hectic.migration ORDER BY name ASC" \
      | awk NF
  )

  log debug "db mig: $db_migrations"
  db_mig_count=$(printf '%s' "$db_migrations" | wc -l)
  log debug "mig count: $db_mig_count"

  # Check if the DB migrations form a proper prefix of disk migrations
  # (meaning all DB-applied migration filenames should appear in the same order at the start).
  i=0
  for db_migration in $db_migrations; do
    fs_migration=$(printf '%s' "$fs_migrations" | sed -n "$((i+1))p")
    if [ -z "$fs_migration" ] || [ "$fs_migration" != "$db_migration" ]; then
      if [ -z "$FORCE" ]; then
        log error "unrelated migration tree detected. Use --force to proceed."
        exit 2
      else
        log error "unrelated migration tree forced. Proceeding..."
        break
      fi
    fi
    i=$((i+1))
  done

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

  target_idx=$(index_of "$fs_migrations" "$target_migration")

  log debug "indexes $WHITE$current_idx$NC $WHITE${target_idx}"
}

form_psql_args() {
  psql_args="-d $DB_URL -v ON_ERROR_STOP=1"
  for var in ${VARIABLE_LIST:-}; do
    psql_args="$psql_args -v $var"
  done
}

migrate_inner() {
  printf '%s\n' "$fs_migrations" | while IFS= read -r fs_migration; do
    # skip already applied migrations
    printf '%s' "$db_migrations" | grep -qxF "$fs_migration" && continue

    psql_args="$(form_psql_args)"

    direction=1
    mig_direction=$([ "$direction" -gt 0 ] && printf 'up.sql' || printf 'down.sql')

    escaped_name=$(printf '%s' "$fs_migration" | sed "s/'/''/g")
    mig_path=$(printf '%s/%s/%s' "$MIGRATION_DIR" "$fs_migration" "$mig_direction")
    escaped_path=$(printf '%s' "$mig_path" | sed "s/'/''/g")

    log trace "mig name: $escaped_name; mig path: $escaped_path"

    # shellcheck disable=SC2086
    if ! psql $psql_args <<SQL
BEGIN;
\i '$escaped_path';
INSERT INTO hectic.migration (name, hash) VALUES ('$escaped_name', '$(sha256sum "$mig_path")');
COMMIT;
SQL
    then
      log error "migration failed: ${WHITE}$fs_migration${NC}"
      exit 4
    fi
  done
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
        DB_URL=$2
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

if ! command -v psql >/dev/null; then
    log error "Required tool (psql) are not installed."
    exit 127
fi

if ! [ "${AS_LIBRARY+x}" ]; then
  while [ $# -gt 0 ]; do
    log debug "arg: $1"
    case $1 in
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
  
  [ ${INHERITS_LIST+x} ] && INHERITS_LIST="$(printf '%s' "$INHERITS_LIST" | sed -E 's/"/,/g; s/([^,]+)/"\1"/g')"
  [ "${SUBCOMMAND+x}" ] || { log error "no subcomand specified"; exit 1; }
  
  
  log debug "subcommand: $WHITE$SUBCOMMAND"
  log debug "subcommand args: $WHITE$REMAINING_ARS"
  
  eval "set -- $REMAINING_ARS"
  "$SUBCOMMAND" "$@"
fi
