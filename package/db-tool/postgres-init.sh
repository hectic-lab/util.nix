#!/bin/dash

postgres_init_main() {
  if [ -z "${PG_WORKING_DIR:-}" ] && [ -z "${LOCAL_DIR:-}" ]; then
    printf '%s\n' 'postgres-init: PG_WORKING_DIR or LOCAL_DIR is required' >&2
    return 1
  fi

  : "${PG_WORKING_DIR:=$LOCAL_DIR/focus/postgresql}"
  : "${PG_PORT:=5432}"
  : "${PG_DATABASE:=testdb}"
  : "${PG_DISABLE_LOGGING:=0}"
  [ "${PG_SHARED_PRELOAD_LIBRARIES+x}" ] || PG_SHARED_PRELOAD_LIBRARIES='pg_cron'
  : "${PG_URL_VAR:=PGURL}"

  mkdir -p "$PG_WORKING_DIR" || return 1
  wd="$PG_WORKING_DIR"; data="$wd/data"; sockdir="$wd/sock"; db="$PG_DATABASE"

  pg_ctl -D "$data" -m fast -w stop >/dev/null 2>&1 || :
  mkdir -p "$sockdir" || return 1

  if [ "${PG_REUSE+x}" ] && [ -f "$data/PG_VERSION" ]; then PG_REUSE=1; else PG_REUSE=0; fi
  if [ "$PG_REUSE" -eq 0 ]; then
    rm -rf "$data" "$sockdir" || return 1
    mkdir -p "$sockdir" || return 1
    initdb -D "$data" --no-locale -E UTF8 || return 1
    if [ -n "${PG_CONF_FILE:-}" ]; then
      [ -r "$PG_CONF_FILE" ] || { printf '%s\n' "postgres-init: PG_CONF_FILE not readable: $PG_CONF_FILE" >&2; return 1; }
      cp -f -- "$PG_CONF_FILE" "$data/postgresql.conf" || return 1
    else
      { printf '%s\n' "listen_addresses = ''"; [ "$PG_DISABLE_LOGGING" -eq 0 ] && { printf '%s\n' 'logging_collector = on'; printf '%s\n' "log_directory = 'log'"; }; [ -n "$PG_SHARED_PRELOAD_LIBRARIES" ] && { printf '%s\n' "shared_preload_libraries = '$PG_SHARED_PRELOAD_LIBRARIES'"; printf '%s\n' "cron.database_name = '$db'"; printf '%s\n' "cron.host = '$sockdir'"; }; :; } >> "$data/postgresql.conf" || return 1
    fi
    sed -i "1ilocal all all trust" "$data/pg_hba.conf" || return 1
  fi

  sed -i '/^[[:space:]]*port[[:space:]]*=/d' "$data/postgresql.conf" || return 1
  sed -i '/^[[:space:]]*unix_socket_directories[[:space:]]*=/d' "$data/postgresql.conf" || return 1
  { printf '%s\n' "port = $PG_PORT"; printf '%s\n' "unix_socket_directories = '$sockdir'"; } >> "$data/postgresql.conf" || return 1
  pg_ctl -D "$data" -o "-F" -w start || return 2

  user="$(id -un)" || return 1
  if [ "$PG_REUSE" -eq 0 ]; then
    createdb -h "$sockdir" -U "$user" "$db" || return 1
  else
    if ! psql -h "$sockdir" -p "$PG_PORT" -U "$user" -d postgres -tAc "select 1 from pg_database where datname = '$db'" 2>/dev/null | grep -q '^1$'; then
      createdb -h "$sockdir" -U "$user" "$db" || return 1
    fi
  fi
  psql -h "$sockdir" -p "$PG_PORT" -d "$db" -v ON_ERROR_STOP=1 -c 'select 1;' || return 1

  export POSTGRESQL_HOST="$sockdir" POSTGRESQL_PORT="$PG_PORT" POSTGRESQL_USER="$user" POSTGRESQL_DATABASE="$db"
  _pg_url="postgresql://${POSTGRESQL_USER}@/${POSTGRESQL_DATABASE}?host=${POSTGRESQL_HOST}&port=${POSTGRESQL_PORT}"
  case $PG_URL_VAR in ''|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_]* ) printf '%s\n' 'postgres-init: invalid PG_URL_VAR' >&2; return 1 ;; esac
  export "${PG_URL_VAR}=${_pg_url}" || return 1
  return 0
}

postgres_init_main "$@"
