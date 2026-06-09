# shellcheck shell=dash

export HECTIC_NAMESPACE=test-db-ops-missing-pgurl

dotenv_file=$(mktemp)
trap 'rm -f "$dotenv_file"' EXIT INT TERM
printf 'TEST_SECRET=hello-world\n' > "$dotenv_file"

if db-ops secrets load --dotenv-file "$dotenv_file" > /tmp/db-ops-missing-pgurl.out 2>&1; then
  log error "expected db-ops secrets load to fail without PGURL"
  exit 1
else
  exit_code=$?
fi

[ "$exit_code" -eq 3 ] || {
  log error "expected exit code 3 without PGURL, got: $exit_code"
  cat /tmp/db-ops-missing-pgurl.out >&2
  exit 1
}

if ! grep -qF 'PGURL or DB_URL is required' /tmp/db-ops-missing-pgurl.out; then
  log error "missing PGURL error message"
  cat /tmp/db-ops-missing-pgurl.out >&2
  exit 1
fi

log notice "test passed"
