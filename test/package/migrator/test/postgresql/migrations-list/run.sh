#!/bin/dash

HECTIC_NAMESPACE=test-migration-list

log notice "test case: ${WHITE}getting list of local migrations"
if ! result="$(migrator list --raw)"; then
  log error "test failed: ${WHITE}error during execution"
  exit 1
fi

printf '%s' "$result" > result

printf '20251004192425-some-changes
20251004292448-some-changes
20251104172425-third-migration
20251104192427-an-other-one
20251104292469-almoust-last
20251204152446-very-last' > expected

#printf 'result\n[\n%s\n]\n' "$(cat result)"
#printf 'expected\n[\n%s\n]\n' "$(cat expected)"

diff -q result expected || {
  log error "test failed: ${WHITE}unexpected result"
  exit 1
}

log notice "test case: ${WHITE}getting list of local migrations with info"
if ! result="$(migrator list)"; then
  log error "test failed: ${WHITE}error during execution"
  exit 1
fi

printf '%s' "$result" > result

printf '20251004192425-some-changes: missing up.sql down.sql
20251004292448-some-changes
20251104172425-third-migration: missing  down.sql
20251104192427-an-other-one: missing  down.sql
20251104292469-almoust-last
20251204152446-very-last' > expected

#printf 'result\n[\n%s\n]\n' "$(cat result)"
#printf 'expected\n[\n%s\n]\n' "$(cat expected)"

diff -q result expected || {
  log error "test failed: ${WHITE}unexpected result"
  exit 1
}

log notice "test passed"
