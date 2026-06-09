# shellcheck shell=dash

export HECTIC_NAMESPACE=test-db-ops-help

log notice "test case: db-ops --help exits 0"
if ! db-ops --help > /tmp/db-ops-help-out.txt 2>&1; then
  log error "test failed: db-ops --help exited non-zero"
  exit 1
fi

for tok in secrets load HECTIC_DOTENV_FILE PGURL DB_URL; do
  if ! grep -qF "$tok" /tmp/db-ops-help-out.txt; then
    log error "test failed: db-ops --help output missing token: $tok"
    cat /tmp/db-ops-help-out.txt >&2
    exit 1
  fi
done

log notice "test passed"
