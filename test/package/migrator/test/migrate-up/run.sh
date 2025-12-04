#!/bin/dash

HECTIC_NAMESPACE=test-migration-list



log notice "test case: ${WHITE}migration up"
psql "$DATABASE_URL" 'CREATE TABLE profile (
  id       INTEGER,
  username TEXT
)'

if ! migrator --db-url "$DATABASE_URL" migrate to 20251104192425-add-info-to-profile; then
  log error "test failed: ${WHITE}error on migration up"
  exit 1
fi 

log notice "$(columns profile)"


exit 1
