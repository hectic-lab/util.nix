# shellcheck shell=dash
# Shared PostgreSQL harness for db-tool tests.

pg_harness__start_busy_socket() {
  pg_harness_socket_dir="$1"
  PG_HARNESS_BUSY_SOCKET_PATH="$pg_harness_socket_dir/.s.PGSQL.5432"
  export PG_HARNESS_BUSY_SOCKET_PATH

  rm -f "$PG_HARNESS_BUSY_SOCKET_PATH"
  nc -l -U "$PG_HARNESS_BUSY_SOCKET_PATH" >/dev/null 2>&1 &
  PG_HARNESS_BUSY_SOCKET_PID=$!
  export PG_HARNESS_BUSY_SOCKET_PID
}

pg_harness_start() {
  pg_harness_tmp_root="${TMPDIR:-/tmp}"

  if [ "${PG_HARNESS_PGDATA_OVERRIDE+x}" ]; then
    pgdata_dir="$PG_HARNESS_PGDATA_OVERRIDE"
  else
    pgdata_dir=$(mktemp -d "$pg_harness_tmp_root/pgdata_XXXXXX")
  fi

  PGDATA="$pgdata_dir"
  export PGDATA

  trap 'pg_harness_stop' EXIT INT TERM

  if ! initdb -D "$pgdata_dir" --no-locale --encoding=UTF8 -U postgres >/dev/null 2>&1; then
    pg_harness_stop
    return 1
  fi

  if [ "${PG_HARNESS_INJECT_BUSY_SOCKET+x}" ] && ! [ "${PG_HARNESS_BUSY_SOCKET_PID+x}" ]; then
    pg_harness__start_busy_socket "$pgdata_dir"
  fi

  if ! pg_ctl start -D "$pgdata_dir" -o "-k $pgdata_dir -h ''" >/dev/null 2>&1; then
    pg_harness_stop
    return 1
  fi

  PGHOST="$pgdata_dir"
  PGPORT=""
  PGUSER="postgres"
  PGDATABASE="postgres"
  export PGHOST PGPORT PGUSER PGDATABASE

  POSTGRESQL_HOST="$PGHOST"
  POSTGRESQL_PORT="$PGPORT"
  POSTGRESQL_USER="$PGUSER"
  POSTGRESQL_DATABASE="$PGDATABASE"
  PGURL="postgresql://postgres@localhost/postgres?host=$pgdata_dir"
  export POSTGRESQL_HOST POSTGRESQL_PORT POSTGRESQL_USER POSTGRESQL_DATABASE PGURL

  pg_harness_ready=
  pg_harness_attempt=0
  while [ "$pg_harness_attempt" -lt 10 ]; do
    if pg_isready -h "$pgdata_dir" >/dev/null 2>&1; then
      pg_harness_ready=1
      break
    fi

    sleep 0.5
    pg_harness_attempt=$((pg_harness_attempt + 1))
  done

  if ! [ "$pg_harness_ready" = 1 ]; then
    pg_harness_stop
    return 1
  fi
}

pg_harness_stop() {
  trap - EXIT INT TERM

  if [ "${PG_HARNESS_BUSY_SOCKET_PID+x}" ]; then
    kill "$PG_HARNESS_BUSY_SOCKET_PID" >/dev/null 2>&1 || true
    wait "$PG_HARNESS_BUSY_SOCKET_PID" >/dev/null 2>&1 || true
    unset PG_HARNESS_BUSY_SOCKET_PID
  fi

  if [ "${PG_HARNESS_BUSY_SOCKET_PATH+x}" ] && [ -n "$PG_HARNESS_BUSY_SOCKET_PATH" ]; then
    rm -f "$PG_HARNESS_BUSY_SOCKET_PATH"
  fi

  if [ "${PGDATA+x}" ] && [ -n "$PGDATA" ]; then
    pg_ctl stop -D "$PGDATA" -m fast >/dev/null 2>&1 || true
    rm -rf "$PGDATA"
  fi

  if [ "${PG_HARNESS_PGDATA_OVERRIDE+x}" ] && [ -n "$PG_HARNESS_PGDATA_OVERRIDE" ]; then
    if ! [ "${PGDATA+x}" ] || [ "$PG_HARNESS_PGDATA_OVERRIDE" != "$PGDATA" ]; then
      rm -rf "$PG_HARNESS_PGDATA_OVERRIDE"
    fi
  fi

  if [ "${PG_HARNESS_CORRUPT_PATH+x}" ] && [ -n "$PG_HARNESS_CORRUPT_PATH" ]; then
    rm -f "$PG_HARNESS_CORRUPT_PATH"
  fi

  unset PG_HARNESS_BUSY_SOCKET_PATH
  unset PG_HARNESS_CORRUPT_PATH
  unset PG_HARNESS_INJECT_BUSY_SOCKET
  unset PG_HARNESS_PGDATA_OVERRIDE
  unset PGHOST PGPORT PGUSER PGDATABASE PGDATA
  unset POSTGRESQL_HOST POSTGRESQL_PORT POSTGRESQL_USER POSTGRESQL_DATABASE PGURL
}

pg_harness_start_corrupt_dir() {
  pg_harness_tmp_root="${TMPDIR:-/tmp}"
  PG_HARNESS_PGDATA_OVERRIDE=$(mktemp "$pg_harness_tmp_root/pgdata_corrupt_XXXXXX")
  : > "$PG_HARNESS_PGDATA_OVERRIDE"
  PG_HARNESS_CORRUPT_PATH="$PG_HARNESS_PGDATA_OVERRIDE"
  export PG_HARNESS_PGDATA_OVERRIDE PG_HARNESS_CORRUPT_PATH
}

pg_harness_busy_socket() {
  pg_harness_tmp_root="${TMPDIR:-/tmp}"
  PG_HARNESS_INJECT_BUSY_SOCKET=1
  export PG_HARNESS_INJECT_BUSY_SOCKET

  if [ "${PGDATA+x}" ] && [ -d "$PGDATA" ]; then
    pg_harness_socket_dir="$PGDATA"
  else
    if [ "${PG_HARNESS_PGDATA_OVERRIDE+x}" ]; then
      pg_harness_socket_dir="$PG_HARNESS_PGDATA_OVERRIDE"
    else
      pg_harness_socket_dir=$(mktemp -d "$pg_harness_tmp_root/pgdata_busy_XXXXXX")
      PG_HARNESS_PGDATA_OVERRIDE="$pg_harness_socket_dir"
      export PG_HARNESS_PGDATA_OVERRIDE
    fi
  fi

  if [ "${PGDATA+x}" ] && [ -d "$PGDATA" ] && ! [ "${PG_HARNESS_BUSY_SOCKET_PID+x}" ]; then
    pg_harness__start_busy_socket "$pg_harness_socket_dir"
  fi
}

pg_harness_kill_postmaster() {
  if ! [ "${PGDATA+x}" ] || ! [ -f "$PGDATA/postmaster.pid" ]; then
    return 1
  fi

  IFS= read -r pg_harness_postmaster_pid < "$PGDATA/postmaster.pid" || return 1
  kill -KILL "$pg_harness_postmaster_pid"
}
