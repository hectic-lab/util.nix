#!/bin/dash

# Stop a local PostgreSQL cluster started by postgres-init.
#
# Public contract:
# - Accepts PG_WORKING_DIR directly, or derives it from LOCAL_DIR.
# - If no cluster root can be resolved, exits successfully without doing
#   anything. This keeps cleanup safe in traps and partial-init flows.
# - If no postmaster.pid exists, treats the cluster as already stopped.
# - NO_TTY=1 redirects pg_ctl output into a temp log file instead of writing to
#   the current terminal.

postgres_cleanup_help() {
  cat <<'EOF'
Usage: postgres-cleanup

Stop a local PostgreSQL cluster if it is running.

Environment:
  PG_WORKING_DIR  Cluster root directory
  LOCAL_DIR       Fallback root used to derive PG_WORKING_DIR
  NO_TTY          Redirect pg_ctl output to a temp file

Behavior:
  - Returns success if the cluster directory cannot be resolved.
  - Returns success if postmaster.pid is already absent.
  - Ignores pg_ctl stop errors so cleanup remains trap-safe.
EOF
}

postgres_cleanup_main() {
  case "${1:-}" in
    -h|--help)
      postgres_cleanup_help
      return 0
    ;;
  esac

  if [ -z "${PG_WORKING_DIR:-}" ] && [ -z "${LOCAL_DIR:-}" ]; then return 0; fi
  : "${PG_WORKING_DIR:=$LOCAL_DIR/focus/postgresql}"
  if [ -f "${PG_WORKING_DIR}/data/postmaster.pid" ]; then
    # Cleanup is intentionally forgiving so it can be used in traps after
    # partial startup failures without masking the real error.
    if [ "${NO_TTY:-0}" = "1" ]; then
      _pg_log="$(mktemp /tmp/postgres-cleanup.XXXXXX.log)"
      pg_ctl -D "${PG_WORKING_DIR}/data" -m fast -w stop > "$_pg_log" 2>&1 || :
      printf '%s\n' "postgres-cleanup: pg_ctl stop output redirected to $_pg_log" >&2
    else
      pg_ctl -D "${PG_WORKING_DIR}/data" -m fast -w stop || :
    fi
  fi
  return 0
}

if [ "$(basename "$0")" = 'postgres-cleanup' ]; then
  postgres_cleanup_main "$@"
fi
