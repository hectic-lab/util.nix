#!/bin/dash

postgres_cleanup_main() {
  if [ -z "${PG_WORKING_DIR:-}" ] && [ -z "${LOCAL_DIR:-}" ]; then return 0; fi
  : "${PG_WORKING_DIR:=$LOCAL_DIR/focus/postgresql}"
  if [ -f "${PG_WORKING_DIR}/data/postmaster.pid" ]; then
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
