# shellcheck shell=dash

export HECTIC_NAMESPACE=test-db-ops-missing-dotenv

if db-ops --url 'postgresql://example.invalid/test' secrets load > /tmp/db-ops-missing-dotenv.out 2>&1; then
  log error "expected db-ops secrets load to fail without dotenv source"
  exit 1
else
  exit_code=$?
fi

[ "$exit_code" -eq 3 ] || {
  log error "expected exit code 3 without dotenv source, got: $exit_code"
  cat /tmp/db-ops-missing-dotenv.out >&2
  exit 1
}

if ! grep -qF 'dotenv source is required' /tmp/db-ops-missing-dotenv.out; then
  log error "missing dotenv source error message"
  cat /tmp/db-ops-missing-dotenv.out >&2
  exit 1
fi

log notice "test passed"
