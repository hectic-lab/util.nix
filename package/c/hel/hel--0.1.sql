-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION hel" to load this file. \quit

CREATE SCHEMA hel;

-- Define the parse_text_with_hectic function that uses hectic library
-- Expected usage:
--   ```sql
--    SELECT "hel"."render"(
--      "declare" := 
--        jsonb_build_object(
--          'name', 'test',
--          'config', jsonb_build_object(
--            'debug', true,
--            'limit', 100
--          )
--        ),
--      "template" := $hel$
--        {{ name }} {{ config.limit }}
--      $hel$
--    ); 
--   ```
CREATE FUNCTION "hel"."render"("declare" json, "template" text)
RETURNS text
AS 'hel', 'render'
LANGUAGE C STRICT;