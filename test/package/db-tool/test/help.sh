# shellcheck shell=dash

HECTIC_NAMESPACE=test-db-tool-help

log notice "test case: database --help exits 0"
if ! database --help > /tmp/help-out.txt 2>&1; then
  log error "test failed: database --help exited non-zero"
  exit 1
fi

for tok in deploy pull_staging cleanup check log init migrator; do
  if ! grep -qF "$tok" /tmp/help-out.txt; then
    log error "test failed: --help output missing token: $tok"
    cat /tmp/help-out.txt >&2
    exit 1
  fi
done

log notice "test passed"
