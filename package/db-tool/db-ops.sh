# shellcheck shell=dash

: "${SCRIPT_NAME:=$(basename "$0")}"

help() {
  # shellcheck disable=SC2059
  printf "$(cat <<EOF
${BGREEN}Usage:${NC} $SCRIPT_NAME [OPTIONS] <SUBCOMMAND> [OPTIONS]

PostgreSQL operations utility.

${BGREEN}Global Options:${NC}
  ${BCYAN}-h${NC}, ${BCYAN}--help${NC}               Show this help message
  ${BCYAN}-u${NC}, ${BCYAN}--url${NC} <url>         PostgreSQL connection string

${BGREEN}Subcommands:${NC}
  ${BCYAN}secrets load${NC} [OPTIONS]  Apply hectic bundle and load secrets

${BGREEN}Environment:${NC}
  ${BBLACK}PGURL${NC}                  PostgreSQL connection string fallback
  ${BBLACK}DB_URL${NC}                 PostgreSQL connection string fallback
  ${BBLACK}HECTIC_DOTENV_CONTENT${NC}  Raw dotenv content to load
  ${BBLACK}HECTIC_DOTENV_FILE${NC}     Dotenv file to read when readable
  ${BBLACK}LOCAL_DIR${NC}              Used with ENVIRONMENT for .env fallback
  ${BBLACK}ENVIRONMENT${NC}            Falls back to ${BBLACK}\$LOCAL_DIR/.env.\$ENVIRONMENT${NC}

EOF
)"
}

help_secrets_load() {
  # shellcheck disable=SC2059
  printf "$(cat <<EOF
${BGREEN}Usage:${NC} $SCRIPT_NAME ${BCYAN}secrets load${NC} [OPTIONS]

Apply the hectic SQL bundle and load dotenv-backed secrets into
${BBLACK}hectic.secret${NC}.

${BGREEN}Options:${NC}
  ${BCYAN}-h${NC}, ${BCYAN}--help${NC}               Show this help message
  ${BCYAN}-u${NC}, ${BCYAN}--url${NC} <url>         PostgreSQL connection string
  ${BCYAN}-f${NC}, ${BCYAN}--dotenv-file${NC} <path> Dotenv file path

${BGREEN}Resolution order:${NC}
  1. ${BBLACK}HECTIC_DOTENV_CONTENT${NC}
  2. ${BBLACK}--dotenv-file${NC} / ${BBLACK}HECTIC_DOTENV_FILE${NC}
  3. ${BBLACK}\$LOCAL_DIR/.env.\$ENVIRONMENT${NC}

Fails with exit code ${BBLACK}3${NC} when neither a PostgreSQL URL nor a dotenv
source can be resolved.

EOF
)"
}

resolve_pgurl() {
  if [ -n "${PGURL:-}" ]; then
    printf '%s' "$PGURL"
  elif [ -n "${DB_URL:-}" ]; then
    printf '%s' "$DB_URL"
  else
    return 1
  fi
}

resolve_dotenv_content() {
  dotenv_file="${1:-}"

  if [ -n "${HECTIC_DOTENV_CONTENT:-}" ]; then
    printf '%s' "$HECTIC_DOTENV_CONTENT"
  elif [ -n "$dotenv_file" ]; then
    if [ ! -f "$dotenv_file" ] || [ ! -r "$dotenv_file" ]; then
      return 2
    fi
    cat "$dotenv_file"
  elif [ -n "${ENVIRONMENT:-}" ] && [ -n "${LOCAL_DIR:-}" ] && [ -r "${LOCAL_DIR}/.env.${ENVIRONMENT}" ]; then
    cat "${LOCAL_DIR}/.env.${ENVIRONMENT}"
  else
    return 1
  fi
}

subcommand_secrets_load() {
  change_namespace 'db ops secrets load'

  dotenv_file="${HECTIC_DOTENV_FILE:-}"

  while [ $# -gt 0 ]; do
    case $1 in
      -h|--help)
        help_secrets_load
        restore_namespace
        exit 0
      ;;
      -u|--url)
        if [ $# -lt 2 ]; then
          log error "missing value for $1"
          restore_namespace
          exit 3
        fi
        PGURL=$2
        DB_URL=$2
        shift 2
      ;;
      -f|--dotenv-file)
        if [ $# -lt 2 ]; then
          log error "missing value for $1"
          restore_namespace
          exit 3
        fi
        dotenv_file=$2
        shift 2
      ;;
      --*|-*)
        log error "secrets load argument $1 does not exist"
        restore_namespace
        exit 9
      ;;
      *)
        log error "secrets load subcommand $1 does not exist"
        restore_namespace
        exit 9
      ;;
    esac
  done

  if ! pgurl="$(resolve_pgurl)"; then
    log error "PGURL or DB_URL is required"
    restore_namespace
    exit 3
  fi

  if dotenv_content="$(resolve_dotenv_content "$dotenv_file")"; then
    :
  else
    dotenv_content_exit_code=$?
    if [ "$dotenv_content_exit_code" -eq 2 ]; then
      log error "dotenv file is not readable: $dotenv_file"
    else
      log error "dotenv source is required (HECTIC_DOTENV_CONTENT, readable dotenv file, or \$LOCAL_DIR/.env.\$ENVIRONMENT)"
    fi
    restore_namespace
    exit 3
  fi

  log notice "apply hectic bundle and load secrets"
  apply_hectic_bundle "$pgurl" "$dotenv_content"
  restore_namespace
}

subcommand_secrets() {
  change_namespace 'db ops secrets'

  if [ $# -eq 0 ]; then
    help_secrets_load
    restore_namespace
    exit 0
  fi

  subcommand=$1
  shift

  case $subcommand in
    load)
      subcommand_secrets_load "$@"
    ;;
    -h|--help)
      help_secrets_load
      restore_namespace
      exit 0
    ;;
    *)
      log error "secrets subcommand $subcommand does not exist"
      restore_namespace
      exit 9
    ;;
  esac
}

while [ $# -gt 0 ]; do
  case $1 in
    -h|--help)
      help
      exit 0
    ;;
    -u|--url)
      if [ $# -lt 2 ]; then
        log error "missing value for $1"
        exit 3
      fi
      PGURL=$2
      DB_URL=$2
      shift 2
    ;;
    --*|-*)
      log error "argument $1 does not exist"
      exit 9
    ;;
    *)
      break
    ;;
  esac
done

subcommand="${1:-}"

if [ -z "$subcommand" ]; then
  help
  exit 0
fi

shift

case $subcommand in
  secrets)
    subcommand_secrets "$@"
  ;;
  *)
    log error "subcommand $subcommand does not exist"
    exit 9
  ;;
esac
