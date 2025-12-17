-- SQLite doesn't support DROP COLUMN directly before 3.35.0
-- We need to recreate the table
CREATE TABLE users_new (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL
);

INSERT INTO users_new (id, name) SELECT id, name FROM users;
DROP TABLE users;
ALTER TABLE users_new RENAME TO users;


