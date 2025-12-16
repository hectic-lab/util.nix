#!/bin/dash

HECTIC_NAMESPACE=test-migrate-existing-database

log notice "test case: ${WHITE}add migrator to existing database with data"

# Simulate existing database with tables and data
log info "creating existing database schema and data"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL
-- Existing tables from before migrator
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  username TEXT NOT NULL,
  email TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE posts (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),
  title TEXT NOT NULL,
  content TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert existing data
INSERT INTO users (username, email) VALUES 
  ('alice', 'alice@example.com'),
  ('bob', 'bob@example.com'),
  ('charlie', 'charlie@example.com');

INSERT INTO posts (user_id, title, content) VALUES
  (1, 'First Post', 'Hello World'),
  (1, 'Second Post', 'More content'),
  (2, 'Bob Post', 'Bob content');
SQL

# Verify existing data
user_count=$(psql -Atc "SELECT COUNT(*) FROM users" "$DATABASE_URL")
post_count=$(psql -Atc "SELECT COUNT(*) FROM posts" "$DATABASE_URL")

if [ "$user_count" != "3" ] || [ "$post_count" != "3" ]; then
  log error "test failed: ${WHITE}existing data not created properly"
  exit 1
fi

log info "existing database has $user_count users and $post_count posts"

# NOW initialize migrator on existing database
log info "initializing migrator on existing database"
if ! migrator --db-url "$DATABASE_URL" init; then
  log error "test failed: ${WHITE}init failed on existing database"
  exit 1
fi

# Verify migrator schema was created
if ! psql -Atc "SELECT COUNT(*) FROM hectic.migration" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}hectic.migration table not created"
  exit 1
fi

# Verify existing data is still intact
user_count_after=$(psql -Atc "SELECT COUNT(*) FROM users" "$DATABASE_URL")
post_count_after=$(psql -Atc "SELECT COUNT(*) FROM posts" "$DATABASE_URL")

if [ "$user_count_after" != "$user_count" ] || [ "$post_count_after" != "$post_count" ]; then
  log error "test failed: ${WHITE}existing data was affected by migrator init"
  exit 1
fi

log info "existing data preserved: $user_count_after users, $post_count_after posts"

# Apply a migration that modifies existing table
log info "applying migration to existing table"
if ! migrator --db-url "$DATABASE_URL" migrate up; then
  log error "test failed: ${WHITE}migration on existing table failed"
  exit 1
fi

# Verify migration was applied
if ! psql -Atc "SELECT bio FROM users LIMIT 0" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}bio column not added to existing table"
  exit 1
fi

# Verify existing data still intact with NULL in new column
alice_bio=$(psql -Atc "SELECT bio FROM users WHERE username = 'alice'" "$DATABASE_URL")
if [ "$alice_bio" != "" ]; then
  log error "test failed: ${WHITE}new column should be NULL for existing rows, got: $alice_bio"
  exit 1
fi

# Verify we can still query existing data
alice_email=$(psql -Atc "SELECT email FROM users WHERE username = 'alice'" "$DATABASE_URL")
if [ "$alice_email" != "alice@example.com" ]; then
  log error "test failed: ${WHITE}existing data corrupted"
  exit 1
fi

log info "migration applied successfully to existing table"

# Apply second migration that adds a new table
if ! migrator --db-url "$DATABASE_URL" migrate up; then
  log error "test failed: ${WHITE}second migration failed"
  exit 1
fi

# Verify new table exists
if ! psql -Atc "SELECT COUNT(*) FROM comments" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}comments table not created"
  exit 1
fi

# Verify we can add data that references existing data
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL
INSERT INTO comments (post_id, user_id, content) 
VALUES (1, 2, 'Nice post!');
SQL

comment_count=$(psql -Atc "SELECT COUNT(*) FROM comments" "$DATABASE_URL")
if [ "$comment_count" != "1" ]; then
  log error "test failed: ${WHITE}could not insert into new table with foreign keys to existing data"
  exit 1
fi

log info "new table works with existing data relationships"

# Test migration rollback with existing database
log info "testing rollback on database with pre-existing tables"
if ! migrator --db-url "$DATABASE_URL" migrate down; then
  log error "test failed: ${WHITE}migration down failed"
  exit 1
fi

# Verify comments table was removed
if psql -Atc "SELECT COUNT(*) FROM comments" "$DATABASE_URL" >/dev/null 2>&1; then
  log error "test failed: ${WHITE}comments table should be removed"
  exit 1
fi

# Verify existing tables still intact
final_user_count=$(psql -Atc "SELECT COUNT(*) FROM users" "$DATABASE_URL")
final_post_count=$(psql -Atc "SELECT COUNT(*) FROM posts" "$DATABASE_URL")

if [ "$final_user_count" != "$user_count" ] || [ "$final_post_count" != "$post_count" ]; then
  log error "test failed: ${WHITE}existing data affected by rollback"
  exit 1
fi

log notice "test passed: migrator works correctly with existing database"

