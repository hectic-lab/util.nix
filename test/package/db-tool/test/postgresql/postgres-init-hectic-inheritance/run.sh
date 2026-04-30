# shellcheck shell=dash

HECTIC_NAMESPACE=test-db-tool-hectic-inheritance

PG_WORKING_DIR=$(mktemp -d)
export PG_WORKING_DIR PG_DATABASE=testdb PG_PORT=5432 PG_SHARED_PRELOAD_LIBRARIES=''
export PG_HECTIC_INHERITANCE=1

cleanup() {
  postgres-cleanup >/dev/null 2>&1 || :
  rm -rf "$PG_WORKING_DIR"
}
trap 'cleanup' EXIT INT TERM

if ! postgres-init; then
  log error "postgres-init with PG_HECTIC_INHERITANCE=1 failed"
  exit 1
fi

sockdir="$PG_WORKING_DIR/sock"
user=$(id -un)
pgurl="postgresql://${user}@/testdb?host=${sockdir}&port=5432"

run_sql() {
  psql "$pgurl" -v ON_ERROR_STOP=1 -tAc "$1"
}

run_sql_expect_fail() {
  if psql "$pgurl" -v ON_ERROR_STOP=1 -c "$1" >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

log notice "case 1: hectic schema and parent tables exist"
got=$(run_sql "SELECT count(*) FROM pg_namespace WHERE nspname='hectic';") || exit 1
[ "$got" = 1 ] || { log error "hectic schema missing"; exit 1; }
got=$(run_sql "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hectic' AND c.relname IN ('created_at','updated_at');") || exit 1
[ "$got" = 2 ] || { log error "parent tables missing"; exit 1; }

log notice "case 2: CREATE TABLE without inheritance is rejected"
if ! run_sql_expect_fail 'CREATE TABLE public.bad_table (id int);'; then
  log error "non-inheriting CREATE TABLE was accepted"
  exit 1
fi

log notice "case 3: CREATE TABLE inheriting hectic.created_at is accepted"
run_sql 'CREATE TABLE public.good_table (id int) INHERITS ("hectic"."created_at");' || exit 1

log notice "case 4: tables inheriting hectic.updated_at get auto BEFORE UPDATE trigger"
run_sql 'CREATE TABLE public.with_updated (id int, val text) INHERITS ("hectic"."created_at", "hectic"."updated_at");' || exit 1
got=$(run_sql "SELECT count(*) FROM pg_trigger WHERE tgrelid='public.with_updated'::regclass AND tgname='hectic_set_updated_at' AND NOT tgisinternal;") || exit 1
[ "$got" = 1 ] || { log error "auto updated_at trigger missing"; exit 1; }

run_sql "INSERT INTO public.with_updated (id, val) VALUES (1, 'a');" || exit 1
sleep 1
run_sql "UPDATE public.with_updated SET val='b' WHERE id=1;" || exit 1
got=$(run_sql "SELECT (updated_at > created_at)::int FROM public.with_updated WHERE id=1;") || exit 1
[ "$got" = 1 ] || { log error "updated_at not bumped on UPDATE (got: $got)"; exit 1; }

log notice "case 5: GUC hectic.inheritance_extra_excluded_schemas exempts schemas"
run_sql 'CREATE SCHEMA legacy;' || exit 1
if ! run_sql_expect_fail 'CREATE TABLE legacy.t1 (id int);'; then
  log error "legacy.t1 should be rejected before GUC set"
  exit 1
fi
run_sql "ALTER DATABASE testdb SET hectic.inheritance_extra_excluded_schemas = 'legacy';" || exit 1
psql "$pgurl" -v ON_ERROR_STOP=1 -c 'CREATE TABLE legacy.t1 (id int);' || {
  log error "legacy.t1 rejected even after GUC exclusion"
  exit 1
}

log notice "case 6: declarative partitions are exempt"
run_sql 'CREATE TABLE public.parted (id int, region text) PARTITION BY LIST (region) INHERITS ("hectic"."created_at");' && {
  log error "PARTITION BY combined with INHERITS unexpectedly succeeded"
  exit 1
} || :
run_sql 'CREATE TABLE public.events (id int, region text, created_at timestamptz NOT NULL DEFAULT NOW()) PARTITION BY LIST (region);' && {
  log error "partitioned parent without inheritance unexpectedly succeeded"
  exit 1
} || :
run_sql "ALTER DATABASE testdb SET hectic.inheritance_extra_excluded_schemas = 'legacy,parts';" || exit 1
run_sql 'CREATE SCHEMA parts;' || exit 1
psql "$pgurl" -v ON_ERROR_STOP=1 -c 'CREATE TABLE parts.events (id int, region text) PARTITION BY LIST (region);' || {
  log error "partitioned parent in excluded schema rejected"
  exit 1
}
psql "$pgurl" -v ON_ERROR_STOP=1 -c "CREATE TABLE parts.events_us PARTITION OF parts.events FOR VALUES IN ('us');" || {
  log error "declarative partition was rejected (should be exempt via relispartition)"
  exit 1
}

log notice "test passed"
