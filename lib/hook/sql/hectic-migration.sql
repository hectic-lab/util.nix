DO $bootstrap$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'hectic' AND t.typname = 'migration_name'
    ) THEN
        CREATE DOMAIN "hectic"."migration_name" AS TEXT
            CHECK (VALUE ~ '^[0-9]{14}-.*');
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'hectic' AND t.typname = 'sha256'
    ) THEN
        CREATE DOMAIN "hectic"."sha256" AS CHAR(64)
            CHECK (VALUE ~ '^[0-9a-f]{64}$');
    END IF;
END
$bootstrap$;

CREATE OR REPLACE FUNCTION "hectic"."sha256_lower"() RETURNS trigger
LANGUAGE plpgsql AS $fn$
BEGIN
    NEW."hash" := lower(NEW."hash");
    RETURN NEW;
END
$fn$;

CREATE TABLE IF NOT EXISTS "hectic"."migration" (
    "id"          SERIAL                  PRIMARY KEY,
    "name"        "hectic"."migration_name" UNIQUE NOT NULL,
    "hash"        "hectic"."sha256"         UNIQUE NOT NULL,
    "applied_at"  TIMESTAMPTZ             NOT NULL DEFAULT NOW()
);

DO $trg$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'hectic_t_sha256_lower'
          AND tgrelid = '"hectic"."migration"'::regclass
          AND NOT tgisinternal
    ) THEN
        CREATE TRIGGER "hectic_t_sha256_lower"
            BEFORE INSERT OR UPDATE ON "hectic"."migration"
            FOR EACH ROW EXECUTE FUNCTION "hectic"."sha256_lower"();
    END IF;
END
$trg$;
