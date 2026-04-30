-- hectic.created_at / hectic.updated_at / hectic.immutable inheritance machinery.
--
-- Provides:
--   * schema  hectic
--   * tables  hectic.created_at(created_at TIMESTAMPTZ NOT NULL DEFAULT NOW())
--             hectic.updated_at(updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW())
--             hectic.immutable()                                  -- pure marker
--   * function hectic.set_updated_at()  -- BEFORE UPDATE row trigger function
--   * function hectic.block_immutable_dml()
--         BEFORE INSERT/UPDATE/DELETE/TRUNCATE row+statement trigger function;
--         allows DML iff current_setting('hectic.migration_mode', true) = 'on'.
--   * GUC  hectic.inheritance_extra_excluded_schemas
--         (text, comma-separated list of schemas the enforcement trigger skips)
--   * GUC  hectic.migration_mode
--         (text, 'on' enables DML on tables inheriting hectic.immutable.
--          Intended use: SET LOCAL inside a migration transaction.)
--   * event trigger hectic_enforce_created_at_inheritance
--         RAISE EXCEPTION on CREATE TABLE that does not inherit hectic.created_at
--   * event trigger hectic_attach_updated_at_trigger
--         auto-attaches BEFORE UPDATE row trigger calling hectic.set_updated_at()
--         on any new table that inherits hectic.updated_at and lacks one.
--   * event trigger hectic_attach_immutable_triggers
--         auto-attaches BEFORE INSERT/UPDATE/DELETE FOR EACH ROW and BEFORE
--         TRUNCATE FOR EACH STATEMENT triggers calling hectic.block_immutable_dml()
--         on any new table that inherits hectic.immutable and lacks them.
--
-- Idempotent: safe to run on an already-bootstrapped database.

CREATE SCHEMA IF NOT EXISTS "hectic";

CREATE TABLE IF NOT EXISTS "hectic"."created_at" (
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS "hectic"."updated_at" (
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS "hectic"."immutable" ();

DO $bootstrap$
BEGIN
  PERFORM set_config('hectic.inheritance_extra_excluded_schemas',
                     current_setting('hectic.inheritance_extra_excluded_schemas', true),
                     false);
EXCEPTION WHEN undefined_object THEN
  PERFORM set_config('hectic.inheritance_extra_excluded_schemas', '', false);
END
$bootstrap$;

DO $bootstrap_mm$
BEGIN
  PERFORM set_config('hectic.migration_mode',
                     current_setting('hectic.migration_mode', true),
                     false);
EXCEPTION WHEN undefined_object THEN
  PERFORM set_config('hectic.migration_mode', '', false);
END
$bootstrap_mm$;

CREATE OR REPLACE FUNCTION "hectic"."set_updated_at"() RETURNS trigger
LANGUAGE plpgsql AS $fn$
BEGIN
  NEW."updated_at" := NOW();
  RETURN NEW;
END
$fn$;

CREATE OR REPLACE FUNCTION "hectic"."block_immutable_dml"() RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE
  mm text;
BEGIN
  BEGIN
    mm := current_setting('hectic.migration_mode', true);
  EXCEPTION WHEN OTHERS THEN
    mm := '';
  END;
  IF mm = 'on' THEN
    IF TG_LEVEL = 'STATEMENT' THEN RETURN NULL; END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
  END IF;
  RAISE EXCEPTION
    'hectic: table %.% inherits hectic.immutable; % blocked outside migration_mode',
    quote_ident(TG_TABLE_SCHEMA), quote_ident(TG_TABLE_NAME), TG_OP
    USING HINT = 'wrap the statement in a migration transaction with '
              || 'SET LOCAL hectic.migration_mode = ''on''';
END
$fn$;

CREATE OR REPLACE FUNCTION "hectic"."_is_excluded_schema"(p_schema text) RETURNS boolean
LANGUAGE plpgsql STABLE AS $fn$
DECLARE
  extra text;
  s     text;
BEGIN
  IF p_schema = 'hectic'
     OR p_schema = 'information_schema'
     OR p_schema LIKE 'pg\_%' ESCAPE '\'
  THEN
    RETURN true;
  END IF;
  BEGIN
    extra := current_setting('hectic.inheritance_extra_excluded_schemas', true);
  EXCEPTION WHEN OTHERS THEN
    extra := '';
  END;
  IF extra IS NULL OR extra = '' THEN
    RETURN false;
  END IF;
  FOREACH s IN ARRAY string_to_array(extra, ',') LOOP
    IF btrim(s) = p_schema THEN
      RETURN true;
    END IF;
  END LOOP;
  RETURN false;
END
$fn$;

CREATE OR REPLACE FUNCTION "hectic"."_table_inherits"(p_oid oid, p_parent regclass) RETURNS boolean
LANGUAGE sql STABLE AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM pg_inherits
    WHERE inhrelid = p_oid AND inhparent = p_parent
  );
$fn$;

CREATE OR REPLACE FUNCTION "hectic"."enforce_created_at_inheritance"() RETURNS event_trigger
LANGUAGE plpgsql AS $fn$
DECLARE
  obj         record;
  rel         pg_class;
  schema_name text;
  parent_oid  oid;
BEGIN
  parent_oid := 'hectic.created_at'::regclass;
  FOR obj IN SELECT * FROM pg_event_trigger_ddl_commands() WHERE command_tag = 'CREATE TABLE'
  LOOP
    SELECT * INTO rel FROM pg_class WHERE oid = obj.objid;
    IF NOT FOUND THEN CONTINUE; END IF;
    IF rel.relpersistence = 't' THEN CONTINUE; END IF;
    IF rel.relispartition THEN CONTINUE; END IF;
    SELECT nspname INTO schema_name FROM pg_namespace WHERE oid = rel.relnamespace;
    IF "hectic"."_is_excluded_schema"(schema_name) THEN CONTINUE; END IF;
    IF NOT "hectic"."_table_inherits"(rel.oid, parent_oid) THEN
      RAISE EXCEPTION
        'hectic: table %.% must INHERITS (hectic.created_at)',
        quote_ident(schema_name), quote_ident(rel.relname)
        USING HINT = 'add INHERITS ("hectic"."created_at") to the CREATE TABLE statement, '
                  || 'or add the schema to hectic.inheritance_extra_excluded_schemas';
    END IF;
  END LOOP;
END
$fn$;

CREATE OR REPLACE FUNCTION "hectic"."attach_updated_at_trigger"() RETURNS event_trigger
LANGUAGE plpgsql AS $fn$
DECLARE
  obj           record;
  rel           pg_class;
  schema_name   text;
  parent_oid    oid;
  trigger_name  text;
  has_trigger   boolean;
BEGIN
  parent_oid := 'hectic.updated_at'::regclass;
  FOR obj IN SELECT * FROM pg_event_trigger_ddl_commands() WHERE command_tag = 'CREATE TABLE'
  LOOP
    SELECT * INTO rel FROM pg_class WHERE oid = obj.objid;
    IF NOT FOUND THEN CONTINUE; END IF;
    IF rel.relpersistence = 't' THEN CONTINUE; END IF;
    IF rel.relispartition THEN CONTINUE; END IF;
    SELECT nspname INTO schema_name FROM pg_namespace WHERE oid = rel.relnamespace;
    IF schema_name = 'hectic' THEN CONTINUE; END IF;
    IF NOT "hectic"."_table_inherits"(rel.oid, parent_oid) THEN CONTINUE; END IF;
    trigger_name := 'hectic_set_updated_at';
    SELECT EXISTS (
      SELECT 1 FROM pg_trigger
      WHERE tgrelid = rel.oid AND tgname = trigger_name AND NOT tgisinternal
    ) INTO has_trigger;
    IF has_trigger THEN CONTINUE; END IF;
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE UPDATE ON %I.%I FOR EACH ROW EXECUTE FUNCTION "hectic"."set_updated_at"()',
      trigger_name, schema_name, rel.relname
    );
  END LOOP;
END
$fn$;

DROP EVENT TRIGGER IF EXISTS "hectic_enforce_created_at_inheritance";
CREATE EVENT TRIGGER "hectic_enforce_created_at_inheritance"
  ON ddl_command_end
  WHEN TAG IN ('CREATE TABLE')
  EXECUTE FUNCTION "hectic"."enforce_created_at_inheritance"();

DROP EVENT TRIGGER IF EXISTS "hectic_attach_updated_at_trigger";
CREATE EVENT TRIGGER "hectic_attach_updated_at_trigger"
  ON ddl_command_end
  WHEN TAG IN ('CREATE TABLE')
  EXECUTE FUNCTION "hectic"."attach_updated_at_trigger"();

CREATE OR REPLACE FUNCTION "hectic"."attach_immutable_triggers"() RETURNS event_trigger
LANGUAGE plpgsql AS $fn$
DECLARE
  obj         record;
  rel         pg_class;
  schema_name text;
  parent_oid  oid;
  has_row     boolean;
  has_trunc   boolean;
BEGIN
  parent_oid := 'hectic.immutable'::regclass;
  FOR obj IN SELECT * FROM pg_event_trigger_ddl_commands() WHERE command_tag = 'CREATE TABLE'
  LOOP
    SELECT * INTO rel FROM pg_class WHERE oid = obj.objid;
    IF NOT FOUND THEN CONTINUE; END IF;
    IF rel.relpersistence = 't' THEN CONTINUE; END IF;
    IF rel.relispartition THEN CONTINUE; END IF;
    SELECT nspname INTO schema_name FROM pg_namespace WHERE oid = rel.relnamespace;
    IF schema_name = 'hectic' THEN CONTINUE; END IF;
    IF NOT "hectic"."_table_inherits"(rel.oid, parent_oid) THEN CONTINUE; END IF;
    SELECT EXISTS (
      SELECT 1 FROM pg_trigger
      WHERE tgrelid = rel.oid
        AND tgname  = 'hectic_block_immutable_dml'
        AND NOT tgisinternal
    ) INTO has_row;
    SELECT EXISTS (
      SELECT 1 FROM pg_trigger
      WHERE tgrelid = rel.oid
        AND tgname  = 'hectic_block_immutable_truncate'
        AND NOT tgisinternal
    ) INTO has_trunc;
    IF NOT has_row THEN
      EXECUTE format(
        'CREATE TRIGGER %I BEFORE INSERT OR UPDATE OR DELETE ON %I.%I '
        || 'FOR EACH ROW EXECUTE FUNCTION "hectic"."block_immutable_dml"()',
        'hectic_block_immutable_dml', schema_name, rel.relname
      );
    END IF;
    IF NOT has_trunc THEN
      EXECUTE format(
        'CREATE TRIGGER %I BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON %I.%I '
        || 'FOR EACH STATEMENT EXECUTE FUNCTION "hectic"."block_immutable_dml"()',
        'hectic_block_immutable_truncate', schema_name, rel.relname
      );
    END IF;
  END LOOP;
END
$fn$;

DROP EVENT TRIGGER IF EXISTS "hectic_attach_immutable_triggers";
CREATE EVENT TRIGGER "hectic_attach_immutable_triggers"
  ON ddl_command_end
  WHEN TAG IN ('CREATE TABLE')
  EXECUTE FUNCTION "hectic"."attach_immutable_triggers"();
