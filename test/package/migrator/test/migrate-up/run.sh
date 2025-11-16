#!/bin/dash

HECTIC_NAMESPACE=test-migration-list

psql "$DATABASE_URL" 'CREATE TABLE profile (
  id       INTEGER,
  username TEXT
)'

#migrator migrate to 20251104192425-add-info-to-profile
