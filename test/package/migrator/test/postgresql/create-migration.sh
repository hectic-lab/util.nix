#!/bin/dash

HECTIC_NAMESPACE=test-create-migration

log notice "test case: ${WHITE}first migration"
if ! migrator create; then
  log error "test failed: ${WHITE}error on migration creation"
  exit 1
fi 

if ! [ -d ./migration ]; then
  log error "test failed: ${WHITE}migration directory not created"
  exit 1
fi

if [ "$(find ./migration -maxdepth 1 -type f | wc -l)" -eq 0 ]; then
  log error "test failed: ${WHITE}migration not created"
  exit 1
fi

log notice "test case: ${WHITE}next migration"
if ! migrator create; then
  log error "test failed: ${WHITE}error on migration creation"
  exit 1
fi 

if [ "$(find ./migration -maxdepth 1 -type f | wc -l)" -eq 1 ]; then
  log error "test failed: ${WHITE}migration not created"
  exit 1
fi

log notice "test case: ${WHITE}migration with custom name"
if ! migrator create --name test; then
  log error "test failed: ${WHITE}error on migration creation"
  exit 1
fi 

if [ "$(find ./migration -maxdepth 1 -type f | wc -l)" -eq 2 ]; then
  log error "test failed: ${WHITE}migration not created"
  exit 1
fi

if ! find ./migration -maxdepth 1 -type f -name '*test.sql' \
    | grep -Eq '/[0-9]{14}-test\.sql$'; then
    log eror "test failed: ${WHITE}migration have unexpected name"
    exit 1
fi

log notice "test case: ${WHITE}migration with custom name that contains space"
if ! migrator create --name 'test name'; then
  log error "test failed: ${WHITE}error on migration creation"
  exit 1
fi 

if [ "$(find ./migration -maxdepth 1 -type f | wc -l)" -eq 3 ]; then
  log error "test failed: ${WHITE}migration not created"
  exit 1
fi

if ! find ./migration -maxdepth 1 -type f -name '*test name.sql' \
    | grep -Eq '/[0-9]{14}-test name\.sql$'; then
    log eror "test failed: ${WHITE}migration have unexpected name"
    exit 1
fi

log notice "test passed"
