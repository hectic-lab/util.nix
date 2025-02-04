-- PostgreSQL database dump generated from SQLite
CREATE SCHEMA IF NOT EXISTS legacy;

SET client_encoding = 'UTF8';

CREATE TABLE legacy."authors" (
    "id" SERIAL PRIMARY KEY,
    "name" text NOT NULL,
    "email" text
) INHERITS (created_at, updated_at);

ALTER TABLE legacy."authors" OWNER TO postgres;

CREATE TABLE legacy."books" (
    "id" SERIAL PRIMARY KEY,
    "title" text NOT NULL,
    "author_id" bigint NOT NULL,
    "published_date" text,
    "price" double precision
) INHERITS (created_at, updated_at);

ALTER TABLE legacy."books" OWNER TO postgres;

CREATE INDEX idx_books_price ON legacy."books" ("price");

CREATE INDEX idx_books_title ON legacy."books" ("title");

ALTER TABLE legacy."books" ADD CONSTRAINT fk_books_0 FOREIGN KEY ("author_id") REFERENCES legacy."authors" ("id");

CREATE TABLE legacy."reviews" (
    "book_id" bigint,
    "review_id" bigint,
    "reviewer" text,
    "rating" bigint,
    "comment" text,
    PRIMARY KEY ("book_id", "review_id")
) INHERITS (created_at, updated_at);

ALTER TABLE legacy."reviews" OWNER TO postgres;

ALTER TABLE legacy."reviews" ADD CONSTRAINT fk_reviews_0 FOREIGN KEY ("book_id") REFERENCES legacy."books" ("id");

CREATE TABLE legacy."book_log" (
    "log_id" SERIAL PRIMARY KEY,
    "book_id" bigint,
    "created_at" text DEFAULT CURRENT_TIMESTAMP
) INHERITS (created_at, updated_at);

ALTER TABLE legacy."book_log" OWNER TO postgres;

CREATE SEQUENCE legacy_books_seq START WITH 3 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;

-- Data for table authors
COPY legacy."authors" (id, name, email) FROM stdin;
1	Author One	author1@example.com
2	Author Two	author2@example.com
\.

-- Data for table books
COPY legacy."books" (id, title, author_id, published_date, price) FROM stdin;
1	Book One	1	2020-01-01	9.99
2	Book Two	2	2021-05-15	19.99
\.

-- Data for table reviews
COPY legacy."reviews" (book_id, review_id, reviewer, rating, comment) FROM stdin;
1	1	Reviewer A	4	Good book
1	2	Reviewer B	5	Excellent!
2	1	Reviewer C	3	Average
\.

-- Data for table book_log
COPY legacy."book_log" (log_id, book_id, created_at) FROM stdin;
1	1	2025-02-04 00:21:48
2	2	2025-02-04 00:21:48
\.
