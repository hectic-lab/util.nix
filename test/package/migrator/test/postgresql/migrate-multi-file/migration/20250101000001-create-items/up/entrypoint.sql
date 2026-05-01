CREATE TABLE items (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL
) INHERITS ("hectic"."created_at");
