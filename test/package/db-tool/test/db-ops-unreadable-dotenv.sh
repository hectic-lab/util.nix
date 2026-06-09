# shellcheck shell=dash

export HECTIC_NAMESPACE=test-db-ops-unreadable-dotenv

dotenv_dir=$(mktemp -d)
dotenv_file="$dotenv_dir/missing.env"
trap 'rm -rf "$dotenv_dir"' EXIT INT TERM

if db-ops --url 'postgresql://example.invalid/test' secrets load --dotenv-file "$dotenv_file" > /tmp/db-ops-unreadable-dotenv.out 2>&1; then
  log error "expected db-ops secrets load to fail for unreadable explicit dotenv path"
  exit 1
else
  exit_code=$?
fi

[ "$exit_code" -eq 3 ] || {
  log error "expected exit code 3 for unreadable explicit dotenv path, got: $exit_code"
  cat /tmp/db-ops-unreadable-dotenv.out >&2
  exit 1
}

if ! grep -qF 'dotenv file is not readable' /tmp/db-ops-unreadable-dotenv.out; then
  log error "missing unreadable dotenv file error message"
  cat /tmp/db-ops-unreadable-dotenv.out >&2
  exit 1
fi

log notice "test passed"
