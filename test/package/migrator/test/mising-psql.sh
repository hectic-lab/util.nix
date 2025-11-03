# remove psql from $PATH
dir=$(dirname -- "$(command -v psql)")
PATH=$(printf '%s' "$PATH" | awk -v RS=: -v ORS=: -v d="$dir" '$0!=d{print}')
PATH=${PATH%:}
# clear lookup cache
hash -r 2>/dev/null || true

# temporary disable break on errors, coz in this test we check error-handling scenario
set +e
# try to run migrator without installed psql
migrator 2>/dev/null
migrator_error_code=$?
set -e

log debug "migrator error code: $migrator_error_code"

if [ "$migrator_error_code" -eq 127 ]; then
  log notice "test passed"
else
  log error "test failed"
fi
