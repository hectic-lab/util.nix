# shellcheck shell=dash

export HECTIC_NAMESPACE=test-db-tool-normalize-backup

tmp_root=$(mktemp -d)
restore_root=
trap 'PG_WORKING_DIR=$restore_root postgres-cleanup >/dev/null 2>&1 || true; pg_harness_stop; rm -rf "$tmp_root"' EXIT INT TERM

export LOCAL_DIR="$tmp_root/local"
export PG_DATABASE=postgres
mkdir -p "$LOCAL_DIR"

log notice "test case: normalize-backup rejects output inside input backup"
pg_harness_start

current_user=$(id -un)
psql -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$current_user') THEN
    CREATE ROLE "$current_user" LOGIN SUPERUSER;
  END IF;
END
\$\$;
CREATE TABLE public.normalize_backup_probe (id integer PRIMARY KEY, label text NOT NULL);
INSERT INTO public.normalize_backup_probe VALUES (1, 'normalized artifact restored');
SQL

input_backup="$tmp_root/input-backup"
invalid_output="$input_backup/nested-output"
output_backup="$tmp_root/output-backup"
restore_root="$tmp_root/restore-pg"

mkdir -p "$input_backup"
pg_ctl stop -D "$PGDATA" -m fast -w >/dev/null
tar -czf "$input_backup/base.tar.gz" -C "$PGDATA" .
unset PGDATA PGHOST PGPORT PGUSER PGDATABASE

set +e
database normalize-backup --output "$invalid_output" --role "$current_user" --database postgres --admin-role postgres "$input_backup" >/tmp/normalize-invalid-out.txt 2>/tmp/normalize-invalid-err.txt
code=$?
set -e

if [ "$code" = 0 ]; then
  log error "test failed: normalize-backup allowed output inside input"
  cat /tmp/normalize-invalid-out.txt >&2
  cat /tmp/normalize-invalid-err.txt >&2
  exit 1
fi

log notice "test case: normalize-backup produces restorable local artifact"
database normalize-backup --output "$output_backup" --role "$current_user" --database postgres --admin-role postgres "$input_backup"

if ! [ -f "$output_backup/base.tar.gz" ]; then
  log error "test failed: normalized backup missing base.tar.gz"
  exit 1
fi

tar -tzf "$output_backup/base.tar.gz" > "$tmp_root/normalized-files.txt"
if ! grep -Eq '^(\./)?postgresql\.conf$' "$tmp_root/normalized-files.txt"; then
  log error "test failed: normalized base archive missing postgresql.conf"
  exit 1
fi

pg_harness_stop

mkdir -p "$restore_root"
PG_WORKING_DIR="$restore_root" database restore "$output_backup"

if ! psql -h "$restore_root/sock" -p 5432 -U "$current_user" -d postgres -tAc "SELECT label FROM public.normalize_backup_probe WHERE id = 1" | grep -q '^normalized artifact restored$'; then
  log error "test failed: normalized backup did not restore usable local data"
  exit 1
fi

PG_WORKING_DIR="$restore_root" postgres-cleanup
restore_root=

log notice "test passed"
