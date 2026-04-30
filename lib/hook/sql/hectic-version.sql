CREATE SCHEMA IF NOT EXISTS "hectic";

CREATE TABLE IF NOT EXISTS "hectic"."version" (
    "name"          TEXT                 PRIMARY KEY,
    "version"       TEXT                 NOT NULL,
    "installed_at"  TIMESTAMPTZ          NOT NULL DEFAULT NOW()
);

DO $check$
DECLARE
    existing TEXT;
BEGIN
    SELECT "version" INTO existing
    FROM "hectic"."version"
    WHERE "name" = 'hectic';

    IF existing IS NULL THEN
        INSERT INTO "hectic"."version" ("name", "version")
        VALUES ('hectic', '@HECTIC_VERSION@');
    ELSIF existing <> '@HECTIC_VERSION@' THEN
        RAISE EXCEPTION
            'hectic schema version mismatch: database has %, code expects %',
            existing, '@HECTIC_VERSION@';
    END IF;
END
$check$;
