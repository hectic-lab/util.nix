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
    migrate|create|fetch)
      [ "${SUBCOMMAND+x}" ] && { printf 'ambiguous subcommand, decide %s or %s\n' "$SUBCOMMAND" "$1"; exit 1; }
      SUBCOMMAND=$1
      shift
    ;;
    --migration-dir|-d)
      MIGRATION_DIR=$2
      shift 2
    ;;
    --inherits)
      INHERITS_LIST="${INHERITS_LIST:+$INHERITS_LIST }$2"
      shift 2
    ;;
    --*|-*) REMAINING_ARS="$REMAINING_ARS $(quote "$1")"; shift ;;              # unknown global -> pass through
    *) REMAINING_ARS="$REMAINING_ARS $(quote "$1")"; shift ;;
  esac
done

[ "${SUBCOMMAND+x}" ] || { log error "no subcomand specified"; exit 1; }

help() {
  # inherits: List one or more tables the migration table must inherit from
  echo help
}

migrate() {
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
      --*|-*)
        printf 'migrate argument %s does not exists' "$1"
        exit 1
      ;;
      *)
        printf 'migrate subcommand %s does not exists' "$1"
        exit 1
      ;;
    esac
  done

  # Get the list of new migrations from disk
  fs_migrations=$(
    find "$MIGRATION_DIR" -maxdepth 1 -type f -name '*.sql' \
      | sort \
      | xargs -n1 basename
  )

  # Get the list of already applied migrations from DB
  db_migrations=$(
    psql -Atqc "SELECT name FROM hectic.migration ORDER BY name ASC" \
      | awk NF
  )

  # Check if the DB migrations form a proper prefix of disk migrations
  # (meaning all DB-applied migration filenames should appear in the same order at the start).
  i=0
  for db_migration in $db_migrations; do
    fs_migration=$(echo "$fs_migrations" | sed -n "$((i+1))p")
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
