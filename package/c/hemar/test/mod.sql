BEGIN;
  \ir test_jsonb_path.sql
  \ir test_template_parser.sql
  \ir test_render_exec.sql
  \ir test_render_interpolate.sql
  \ir test_render_section.sql
  \ir test_render_include.sql
  \ir test_render_all.sql
ROLLBACK;
