-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION hemar" to load this file. \quit

CREATE SCHEMA hemar;

-- Define the template rendering functions using hectic library
-- Expected usage:
--   ```sql
--    SELECT "hemar"."render"(
--      "declare" := 
--        jsonb_build_object(
--          'name', 'test',
--          'config', jsonb_build_object(
--            'debug', true,
--            'limit', 100
--          )
--        ),
--      "template" := $hemar$
--        {{ name }} {{ config.limit }}
--      $hemar$
--    ); 
--   ```
CREATE FUNCTION "hemar"."render"("declare" jsonb, "template" text)
RETURNS text
LANGUAGE C STRICT
AS 'hemar', 'pg_render';

-- Parse function returns the structure of a template for debugging
CREATE FUNCTION "hemar"."parse"("template" text)
RETURNS text
LANGUAGE C STRICT
AS 'hemar', 'pg_template_parse';
