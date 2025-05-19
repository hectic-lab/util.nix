BEGIN;
  CREATE OR REPLACE FUNCTION pg_temp.diff(string1 text, string2 text) RETURNS TABLE("index" int, char1 text, char2 text) AS $$
  BEGIN
      RETURN QUERY WITH 
          s1 AS (SELECT string1 AS str),
          s2 AS (SELECT string2 AS str)
      SELECT i,
          substring(s1.str FROM i FOR 1) AS char1,
          substring(s2.str FROM i FOR 1) AS char2
      FROM s1, s2,
          generate_series(1, GREATEST(length(s1.str), length(s2.str))) AS i
      WHERE substring(s1.str FROM i FOR 1) IS DISTINCT FROM substring(s2.str FROM i FOR 1);
  
  END;
  $$ LANGUAGE plpgsql;
  
  CREATE OR REPLACE FUNCTION pg_temp.test_regexp_replace(string text) RETURNS text AS $$
  BEGIN
      RETURN regexp_replace(
               regexp_replace(
                 regexp_replace(
                   regexp_replace(
                     regexp_replace(string, E'\t', '\\t', 'g'),
                   E'\n', '\\n', 'g'),
                 E'\r', '\\r', 'g'),
               ' ', '[S]', 'g'),
             '\s', '\\s', 'g');
  END;
  $$ LANGUAGE plpgsql;

  \ir test_jsonb_path.sql
  -- \ir test_template_parser.sql
  \ir test_render_exec.sql
  \ir test_render_interpolate.sql
  \ir test_render_section.sql
  \ir test_render_include.sql
  \ir test_render_all.sql
ROLLBACK;
