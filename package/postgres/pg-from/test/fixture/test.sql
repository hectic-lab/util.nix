-- Enable foreign key constraints
PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

-- Table: authors
CREATE TABLE authors (
    id INTEGER PRIMARY KEY,              -- Primary key using INTEGER PRIMARY KEY
    name TEXT NOT NULL,                  -- Required field
    email TEXT UNIQUE                    -- Unique email constraint
);

-- Table: books
CREATE TABLE books (
    id INTEGER PRIMARY KEY AUTOINCREMENT,  -- Auto-incrementing primary key
    title TEXT NOT NULL,
    author_id INTEGER NOT NULL,
    published_date DATE,                   -- Date stored as TEXT (or ISO8601 format)
    price REAL,
    CONSTRAINT fk_author FOREIGN KEY(author_id) REFERENCES authors(id)
);

-- Table: reviews with composite primary key and a CHECK constraint
CREATE TABLE reviews (
    book_id INTEGER,
    review_id INTEGER,
    reviewer TEXT,
    rating INTEGER CHECK (rating BETWEEN 1 AND 5),  -- Check constraint to restrict rating values
    comment TEXT,
    PRIMARY KEY (book_id, review_id),
    FOREIGN KEY(book_id) REFERENCES books(id)
);

-- Create a standard index on books (non-unique)
CREATE INDEX idx_books_title ON books(title);

-- Create a partial index (only rows where price > 10)
CREATE INDEX idx_books_price ON books(price) WHERE price > 10;

-- Table: book_log for logging inserted books
CREATE TABLE book_log (
    log_id INTEGER PRIMARY KEY,
    book_id INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Trigger: After inserting a book, log its id into book_log
CREATE TRIGGER trg_book_insert
AFTER INSERT ON books
BEGIN
    INSERT INTO book_log (book_id) VALUES (new.id);
END;

-- Create a view joining authors and books
CREATE VIEW vw_author_books AS
SELECT a.name AS author,
       b.title,
       b.published_date,
       b.price
FROM authors a
JOIN books b ON a.id = b.author_id;

-- Insert sample data into authors
INSERT INTO authors (id, name, email) VALUES (1, 'Author One', 'author1@example.com');
INSERT INTO authors (name, email) VALUES ('Author Two', 'author2@example.com');

-- Insert sample data into books
INSERT INTO books (title, author_id, published_date, price) VALUES ('Book One', 1, '2020-01-01', 9.99);
INSERT INTO books (title, author_id, published_date, price) VALUES ('Book Two', 2, '2021-05-15', 19.99);

-- Insert sample data into reviews
INSERT INTO reviews (book_id, review_id, reviewer, rating, comment)
VALUES (1, 1, 'Reviewer A', 4, 'Good book');
INSERT INTO reviews (book_id, review_id, reviewer, rating, comment)
VALUES (1, 2, 'Reviewer B', 5, 'Excellent!');
INSERT INTO reviews (book_id, review_id, reviewer, rating, comment)
VALUES (2, 1, 'Reviewer C', 3, 'Average');

COMMIT;
