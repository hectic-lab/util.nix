# shellcheck shell=dash

HECTIC_NAMESPACE=test-init-hectic-bundle

if ! migrator --db-url "$DATABASE_URL" init; then
  log error "migrator init failed"
  exit 1
fi

run_sql() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -tAc "$1"
}

run_sql_expect_fail() {
  if psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "$1" >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

log notice "case 1: hectic schema, version/secret/migration/parent tables exist"
got=$(run_sql "SELECT count(*) FROM pg_namespace WHERE nspname='hectic';") || exit 1
[ "$got" = 1 ] || { log error "hectic schema missing"; exit 1; }
got=$(run_sql "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hectic' AND c.relname IN ('version','secret','migration','created_at','updated_at','immutable');") || exit 1
[ "$got" = 6 ] || { log error "expected 6 hectic tables (version,secret,migration,created_at,updated_at,immutable), got: $got"; exit 1; }

log notice "case 2: hectic.version row populated"
got=$(run_sql "SELECT count(*) FROM hectic.version;") || exit 1
[ "$got" = 1 ] || { log error "hectic.version row missing (got: $got)"; exit 1; }

log notice "case 3: re-running migrator init is idempotent"
if ! migrator --db-url "$DATABASE_URL" init; then
  log error "second migrator init failed"
  exit 1
fi

log notice "case 4: CREATE TABLE without inheritance is rejected"
if ! run_sql_expect_fail 'CREATE TABLE public.bad_table (id int);'; then
  log error "non-inheriting CREATE TABLE was accepted"
  exit 1
fi

log notice "case 5: CREATE TABLE inheriting hectic.created_at is accepted"
run_sql 'CREATE TABLE public.good_table (id int) INHERITS ("hectic"."created_at");' || exit 1

log notice "case 6: tables inheriting hectic.updated_at get auto BEFORE UPDATE trigger"
run_sql 'CREATE TABLE public.with_updated (id int, val text) INHERITS ("hectic"."created_at", "hectic"."updated_at");' || exit 1
got=$(run_sql "SELECT count(*) FROM pg_trigger WHERE tgrelid='public.with_updated'::regclass AND tgname='hectic_set_updated_at' AND NOT tgisinternal;") || exit 1
[ "$got" = 1 ] || { log error "auto updated_at trigger missing"; exit 1; }

run_sql "INSERT INTO public.with_updated (id, val) VALUES (1, 'a');" || exit 1
sleep 1
run_sql "UPDATE public.with_updated SET val='b' WHERE id=1;" || exit 1
got=$(run_sql "SELECT (updated_at > created_at)::int FROM public.with_updated WHERE id=1;") || exit 1
[ "$got" = 1 ] || { log error "updated_at not bumped on UPDATE (got: $got)"; exit 1; }

log notice "case 7: GUC hectic.inheritance_extra_excluded_schemas exempts schemas"
run_sql 'CREATE SCHEMA legacy;' || exit 1
if ! run_sql_expect_fail 'CREATE TABLE legacy.t1 (id int);'; then
  log error "legacy.t1 should be rejected before GUC set"
  exit 1
fi
run_sql "ALTER DATABASE \"$PGDATABASE\" SET hectic.inheritance_extra_excluded_schemas = 'legacy';" || exit 1
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'CREATE TABLE legacy.t1 (id int);' || {
  log error "legacy.t1 rejected even after GUC exclusion"
  exit 1
}

log notice "case 8: declarative partitions are exempt"
run_sql "ALTER DATABASE \"$PGDATABASE\" SET hectic.inheritance_extra_excluded_schemas = 'legacy,parts';" || exit 1
run_sql 'CREATE SCHEMA parts;' || exit 1
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'CREATE TABLE parts.events (id int, region text) PARTITION BY LIST (region);' || {
  log error "partitioned parent in excluded schema rejected"
  exit 1
}
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "CREATE TABLE parts.events_us PARTITION OF parts.events FOR VALUES IN ('us');" || {
  log error "declarative partition was rejected (should be exempt via relispartition)"
  exit 1
}

log notice "case 9: hectic.immutable inheritors are blocked from DML outside migration_mode"
run_sql 'CREATE TABLE public.frozen (id int, label text) INHERITS ("hectic"."created_at", "hectic"."immutable");' || exit 1

got=$(run_sql "SELECT count(*) FROM pg_trigger WHERE tgrelid='public.frozen'::regclass AND tgname IN ('hectic_block_immutable_dml','hectic_block_immutable_truncate') AND NOT tgisinternal;") || exit 1
[ "$got" = 2 ] || { log error "immutable triggers missing on public.frozen (got: $got)"; exit 1; }

if ! run_sql_expect_fail "INSERT INTO public.frozen (id, label) VALUES (1, 'x');"; then
  log error "INSERT on immutable table accepted outside migration_mode"
  exit 1
fi
if ! run_sql_expect_fail "UPDATE public.frozen SET label='y' WHERE id=1;"; then
  log error "UPDATE on immutable table accepted outside migration_mode"
  exit 1
fi
if ! run_sql_expect_fail "DELETE FROM public.frozen WHERE id=1;"; then
  log error "DELETE on immutable table accepted outside migration_mode"
  exit 1
fi
if ! run_sql_expect_fail "TRUNCATE public.frozen;"; then
  log error "TRUNCATE on immutable table accepted outside migration_mode"
  exit 1
fi

log notice "case 10: SET LOCAL hectic.migration_mode='on' allows DML"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL' || { log error "migration_mode tx failed"; exit 1; }
BEGIN;
SET LOCAL hectic.migration_mode = 'on';
INSERT INTO public.frozen (id, label) VALUES (1, 'x');
UPDATE public.frozen SET label = 'y' WHERE id = 1;
COMMIT;
SQL
got=$(run_sql "SELECT label FROM public.frozen WHERE id=1;") || exit 1
[ "$got" = y ] || { log error "expected label=y after migration tx, got: $got"; exit 1; }

log notice "case 11: GUC does not leak past COMMIT"
if ! run_sql_expect_fail "INSERT INTO public.frozen (id, label) VALUES (2, 'z');"; then
  log error "INSERT accepted after migration_mode tx committed (GUC leaked)"
  exit 1
fi

log notice "case 12: TRUNCATE allowed under migration_mode"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL' || { log error "truncate under migration_mode failed"; exit 1; }
BEGIN;
SET LOCAL hectic.migration_mode = 'on';
TRUNCATE public.frozen;
COMMIT;
SQL
got=$(run_sql "SELECT count(*) FROM public.frozen;") || exit 1
[ "$got" = 0 ] || { log error "frozen not truncated"; exit 1; }

log notice "case 13: --inherits emits deprecation warning but still succeeds"
warn_output=$(migrator --inherits some_table --db-url "$DATABASE_URL" init 2>&1) || {
  log error "migrator init with deprecated --inherits failed"
  exit 1
}
if ! echo "$warn_output" | grep -q "deprecated"; then
  log error "--inherits did not emit deprecation warning"
  exit 1
fi

log notice "test passed"
