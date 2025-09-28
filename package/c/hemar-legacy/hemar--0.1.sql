-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION hemar" to load this file. \quit

CREATE SCHEMA hemar;
-- Parse function returns the structure of a template for debugging
CREATE FUNCTION "hemar"."parse"("template" text)
RETURNS text
LANGUAGE C STRICT
AS 'hemar', 'pg_template_parse';

-- JSONB path access function
CREATE FUNCTION "hemar"."jsonb_get_by_path"("json" jsonb, "path" text)
RETURNS jsonb
LANGUAGE C STRICT
AS 'hemar', 'pg_jsonb_get_by_path';

-- Template rendering function
CREATE FUNCTION "hemar"."render"("define" jsonb, "template" text)
RETURNS text
LANGUAGE C STRICT
AS 'hemar', 'pg_template_render';
