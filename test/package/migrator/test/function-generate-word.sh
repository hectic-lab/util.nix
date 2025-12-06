# shellcheck disable=SC2034
AS_LIBRARY= 
# shellcheck disable=SC1090
. "$(which migrator)"

log notice "test case: ${WHITE}generate word"
if ! answer=$(generate_word); then
  log error "test failed: ${WHITE}error during generate_word call"
  exit 1
fi

if [ "$(printf '%s' "$answer" | wc -c)" -ne 6 ]; then
  log error "test failed: ${WHITE}word length must be 6 chars"
  exit 1
fi

log notice "test passed"
