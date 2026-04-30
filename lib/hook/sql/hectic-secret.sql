CREATE TABLE IF NOT EXISTS "hectic"."secret" (
    "id"     SERIAL PRIMARY KEY,
    "key"    TEXT   UNIQUE NOT NULL,
    "value"  TEXT          NOT NULL
);

CREATE OR REPLACE FUNCTION "hectic"."load_secrets_from_env"(env_content TEXT)
RETURNS void
LANGUAGE plpgsql AS $fn$
DECLARE
    line TEXT;
    k    TEXT;
    v    TEXT;
BEGIN
    TRUNCATE TABLE "hectic"."secret";

    FOR line IN
        SELECT regexp_split_to_table(env_content, E'\n')
    LOOP
        line := btrim(line);

        IF line = '' OR line LIKE '#%' THEN
            CONTINUE;
        END IF;

        k := split_part(line, '=', 1);
        v := substring(line FROM position('=' IN line) + 1);

        k := btrim(k);
        v := btrim(v);

        IF v ~ '^".*"$' OR v ~ '^''.*''$' THEN
            v := substring(v FROM 2 FOR char_length(v) - 2);
        END IF;

        INSERT INTO "hectic"."secret" ("key", "value") VALUES (k, v);
    END LOOP;
END
$fn$;

CREATE OR REPLACE FUNCTION "hectic"."get_secret"(k TEXT)
RETURNS TEXT
LANGUAGE plpgsql AS $fn$
BEGIN
    RETURN (
        SELECT "value"
        FROM "hectic"."secret"
        WHERE "key" = k
    );
END
$fn$;
