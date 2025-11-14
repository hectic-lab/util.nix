#!/bin/dash

if ! command -v psql >/dev/null; then
    log error "Required tool (psql) are not installed."
    exit 127
fi

MIGRATION_DIR="${MIGRATION_DIR:-migration}"
quote() { printf "'%s'" "$(printf %s "$1" | sed "s/'/'\\\\''/g")"; }
REMAINING_ARS=

while [ $# -gt 0 ]; do
  log debug "$1"
  case $1 in
    migrate|create|fetch|list)
      [ "${SUBCOMMAND+x}" ] && { printf 'ambiguous subcommand, decide %s or %s\n' "$SUBCOMMAND" "$1"; exit 1; }
      SUBCOMMAND=$1
      shift
    ;;
    --migration-dir|-d)
      MIGRATION_DIR=$2
      shift 2
    ;;
    --inherits)
      INHERITS_LIST="${INHERITS_LIST:+$INHERITS_LIST\"}$2"
      shift 2
    ;;
    --init-dry-run)
      INIT_DRY_RUN=1
      shift
    ;;
    --*|-*) REMAINING_ARS="$REMAINING_ARS $(quote "$1")"; shift ;;              # unknown global -> pass through
    *) REMAINING_ARS="$REMAINING_ARS $(quote "$1")"; shift ;;
  esac
done

INHERITS_LIST="$(printf '%s' "$INHERITS_LIST" | sed -E 's/"/,/g; s/([^,]+)/"\1"/g')"

init() {
  log debug "inherits: ${WHITE}${INHERITS_LIST}${NC}"
  local create_table
  create_table="$(printf '%s\n' \
    'CREATE SCHEMA IF NOT EXISTS hectic;' \
    'CREATE TABLE IF NOT EXISTS hectic.migration (' \
    '    id SERIAL PRIMARY KEY,' \
    '    name TEXT UNIQUE NOT NULL,'\
    '    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()' \
    ')')"

  printf '%s INHERITS(%s)' "$create_table" "$INHERITS_LIST"
}

[ "${INIT_DRY_RUN+x}" ] && { printf '%s\n' "$(init)"; exit; }

[ "${SUBCOMMAND+x}" ] || { log error "no subcomand specified"; exit 1; }

help() {
  # inherits: List one or more tables the migration table must inherit from
  echo help
}

migrate_down() {
  DOWN_NUMBER=1
  while [ $# -gt 0 ]; do
    case $1 in
      --*|-*)
        printf 'migrate argument %s does not exists' "$1"
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
        printf 'migrate argument %s does not exists' "$1"
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
  while [ $# -gt 0 ]; do
    case $1 in
      --*|-*)
        printf 'migrate argument %s does not exists' "$1"
        exit 1
      ;;
      *)
	MIGRATION_NAME=
      ;;
    esac
  done

  [ "${MIGRATION_NAME+x}" ] || { log error "no migration name specified"; exit 1; }
}

migrate() {
  local fs_migrations db_migrations db_migration fs_migration psql_args var #target_migration
  while [ $# -gt 0 ]; do
    case $1 in
      up|down|to)
        [ -n "$MIGRATE_SUBCOMMAND" ] || (printf 'ambiguous migrate subcommand, decide %s or %s' "$MIGRATE_SUBCOMMAND" "$1"; exit 1)
	MIGRATE_SUBCOMMAND="$1"
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
	VARIABLE_LIST="${VARIABLE_LIST:+$VARIABLE_LIST }$2"
        shift 2
      ;;
      --*|-*) REMAINING_ARS="$REMAINING_ARS $(quote "$1")"; shift ;;              # unknown global -> pass through
      *) REMAINING_ARS="$REMAINING_ARS $(quote "$1")"; shift ;;
      #--*|-*)
      #  printf 'migrate argument %s does not exists' "$1"
      #  exit 1
      #;;
      #*)
      #  printf 'migrate subcommand %s does not exists' "$1"
      #  exit 1
      #;;
    esac
  done

  init

  fs_migrations=$(
    find "$MIGRATION_DIR" -maxdepth 1 -type f -name '*.sql' \
      | sort \
      | xargs -n1 basename
  )

  db_migrations=$(
    psql -Atqc "SELECT name FROM hectic.migration ORDER BY name ASC" \
      | awk NF
  )

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

  eval "set -- $REMAINING_ARS"
  #target_migration="$("migrate_$MIGRATE_SUBCOMMAND" "$@")"

  printf '%s\n' "$fs_migrations" | while IFS= read -r fs_migration; do
    # skip already applied migrations
    printf '%s' "$db_migrations" | grep -qxF "$fs_migration" && continue

    psql_args="-d $DB_URL"
    for var in $VARIABLE_LIST; do
        psql_args="$psql_args -v $var"
    done

    escaped_name=$(printf "%s" "$fs_migration" | sed "s/'/''/g")
    escaped_path=$(printf "%s/%s" "$MIGRATION_DIR" "$fs_migration" | sed "s/'/''/g")

    # shellcheck disable=SC2086
    if ! psql $psql_args <<SQL
BEGIN;
\i '$escaped_path';
INSERT INTO hectic.migration (name) VALUES ('$escaped_name');
COMMIT;
SQL
    then
      log error "Migration failed: ${WHITE}$fs_migration${NC}"
      return 3
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
        exit 1
      ;;
      *)
        log error "create subcommand $1 does not exists"
        exit 1
      ;;
    esac
  done

  mkdir -p "$MIGRATION_DIR" 2>/dev/null

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
}

list() {
  ls "$MIGRATION_DIR" -1
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

log debug "subcommand: $SUBCOMMAND"
log debug "subcommand args: $REMAINING_ARS"

eval "set -- $REMAINING_ARS"
"$SUBCOMMAND" "$@"
