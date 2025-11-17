#!/bin/dash

HECTIC_NAMESPACE=test-migration-list

log notice "test case: ${WHITE}getting list of local migrations"
if ! list="$(migrator list)"; then
  log error "test failed: ${WHITE}error during execution"
  exit 1
fi

ls
ls migration

exit 1

log notice "test passed"
