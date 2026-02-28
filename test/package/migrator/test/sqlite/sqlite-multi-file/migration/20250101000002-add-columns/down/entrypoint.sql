CREATE TABLE items_backup (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL);
INSERT INTO items_backup SELECT id, name FROM items;
DROP TABLE items;
ALTER TABLE items_backup RENAME TO items;
