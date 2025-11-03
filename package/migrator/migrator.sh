#!/bin/dash

if ! command -v psql >/dev/null; then
    log error "Required tool (psql) are not installed."
    exit 127
fi

MIGRATION_DIR="${MIGRATION_DIR:-migration}"

while [ $# -gt 0 ]; do
  case $1 in
    migrate|create|fetch)
      [ -n "$SUBCOMMAND" ] || (printf 'ambiguous subcommand, decide %s or %s' "$SUBCOMMAND" "$1"; exit 1)
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
    --*|-*) ;; # skip all unrecognized arguments
    *)
      printf 'subcommand %s does not exists' "$1"
      exit 1
    ;;
  esac
done

[ -z "$SUBCOMMAND" ] || (log error "no subcomand specified"; exit 1)

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
        printf 'argument %s does not exists' "$1"
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
        echo "Unrelated migration tree detected. Use --force to proceed." >&2
        exit 2
      else
        echo "Unrelated migration tree forced. Proceeding..." >&2
        break
      fi
    fi
    i=$((i+1))
  done
}

create() {
  while [ $# -gt 0 ]; do
    case $1 in
      --name|-n)
	# shellcheck disable=SC2034
        NAME=$2
        shift 2
      ;;
    esac
  done
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

"$SUBCOMMAND"
