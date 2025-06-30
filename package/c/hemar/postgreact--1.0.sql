-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION postgreact" to load this file. \quit

-- Define the hello function that uses our C implementation
CREATE FUNCTION hello()
RETURNS
  TEXT
STRICT VOLATILE
LANGUAGE C
AS
  'MODULE_PATHNAME', 'hello'
;
