#!/bin/dash

postgres_cleanup_main() {
  if [ -z "${PG_WORKING_DIR:-}" ] && [ -z "${LOCAL_DIR:-}" ]; then return 0; fi
  : "${PG_WORKING_DIR:=$LOCAL_DIR/focus/postgresql}"
  if [ -f "${PG_WORKING_DIR}/data/postmaster.pid" ]; then
    pg_ctl -D "${PG_WORKING_DIR}/data" -m fast -w stop || :
  fi
  return 0
}

if [ "$(basename "$0")" = 'postgres-cleanup' ]; then
  postgres_cleanup_main "$@"
fi
