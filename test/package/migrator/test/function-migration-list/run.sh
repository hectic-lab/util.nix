# shellcheck disable=SC2034
AS_LIBRARY= 
# shellcheck disable=SC1090
. "$(which migrator)"

log notice "test case: ${WHITE}migration list"
if ! answer=$(migration_list); then
  log error "test failed: ${WHITE}error during migration_list call"
  exit 1
fi

if [ "$answer" != "20251104192425-add-info-to-profile" ]; then
  log error "test failed: ${WHITE}unexpected \`migration list\` answer"
  exit 1
fi

log notice "test passed"
