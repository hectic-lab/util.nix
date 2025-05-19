-- Test file for hemar template parser
-- Run with: psql -f test_template_parser.sql

-- Load extension if not already loaded
-- CREATE EXTENSION IF NOT EXISTS hemar;

-- SAFETY(yukkop): !!! If you fix identation, you will ruin the tests.

-- Create test function to validate template parsing
CREATE OR REPLACE FUNCTION test_template_parse(template_text text, expected_structure text) RETURNS boolean AS $$
DECLARE
    parsed_result text;
    passed boolean;
BEGIN
    BEGIN
        parsed_result := hemar.parse(template_text);
        
        IF parsed_result IS NULL THEN
            RAISE WARNING 'Parser returned NULL for template: %', template_text;
            RETURN false;
        END IF;
        
        passed := position(expected_structure in parsed_result) > 0;
        
        IF NOT passed THEN
            RAISE WARNING 'Template parsing test failed!';
            RAISE WARNING 'Template: %', template_text;
            -- RAISE WARNING 'Expected to find: %', pg_temp.test_regexp_replace(expected_structure);
            -- RAISE WARNING 'Actual result: %', pg_temp.test_regexp_replace(parsed_result);
            RAISE WARNING 'Expected to find: %', expected_structure;
            RAISE WARNING 'Actual result: %', parsed_result;
        END IF;
        
        RETURN passed;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Exception during parsing: % (state: %)', SQLERRM, SQLSTATE;
        RAISE WARNING 'Template: %', template_text;
        RETURN false;
    END;
END;
$$ LANGUAGE plpgsql;

-- Run the tests
DO $$
DECLARE
    total_tests integer := 0;
    passed_tests integer := 0;
    result boolean;
BEGIN
    PERFORM pg_sleep(2);
    RAISE NOTICE 'Starting template parser tests...';
    
    -- Test 1: Simple interpolation
    total_tests := total_tests + 1;
    result := test_template_parse(
        $hemar1${{ simple_var }}$hemar1$,
        $expected1$INTERPOLATE: "simple_var"$expected1$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Simple interpolation - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Simple interpolation - FAILED', total_tests;
    END IF;
    
    -- Test 2: Interpolation with surrounding text
    total_tests := total_tests + 1;
    result := test_template_parse(
        $hemar2$Hello, {{ name }}!$hemar2$,
        $expected2$TEXT: "Hello, "
INTERPOLATE: "name"
TEXT: "!"$expected2$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Interpolation with surrounding text - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Interpolation with surrounding text - FAILED', total_tests;
    END IF;
    
    -- Test 3: Simple section (for loop)
    total_tests := total_tests + 1;
    result := test_template_parse(
        $hemar3${{ for item in items }}{{ item }}{{ end }}$hemar3$,
        $expected3$SECTION: iterator="item", collection="items"$expected3$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Simple section (for loop) - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Simple section (for loop) - FAILED', total_tests;
    END IF;
    
    -- Test 4: Section with nested interpolation
    total_tests := total_tests + 1;
    result := test_template_parse(
        $hemar4${{ for item in items }}Name: {{ item.name }}{{ end }}$hemar4$,
        $expected4$SECTION: iterator="item", collection="items"
  TEXT: "Name: "
  INTERPOLATE: "item.name"$expected4$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Section with nested interpolation - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Section with nested interpolation - FAILED', total_tests;
    END IF;
    
    -- Test 5: Nested sections
    total_tests := total_tests + 1;
    result := test_template_parse(
        $hemar5${{ for item in items }}{{ for subitem in item.subitems }}{{ subitem }}{{ end }}{{ end }}$hemar5$,
        $expected5$SECTION: iterator="item", collection="items"
  SECTION: iterator="subitem", collection="item.subitems"
    INTERPOLATE: "subitem"$expected5$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Nested sections - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Nested sections - FAILED', total_tests;
    END IF;
    
    -- Test 6: Include tag
    total_tests := total_tests + 1;
    result := test_template_parse(
        $hemar6${{ include template_name }}$hemar6$,
        $expected6$INCLUDE: "template_name"$expected6$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Include tag - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Include tag - FAILED', total_tests;
    END IF;
    
    -- Test 7: Execute tag
    total_tests := total_tests + 1;
    result := test_template_parse(
        $hemar7${{ exec RETURN my_function(arg1, arg2) }}$hemar7$,
        $expected7$EXECUTE: "RETURN my_function(arg1, arg2)"$expected7$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Execute tag - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Execute tag - FAILED', total_tests;
    END IF;
    
    -- Test 8: Complex mixed template
    total_tests := total_tests + 1;
    result := test_template_parse(
        $hemar8$<div>{{ for item in items }}<p>{{ item.name }}</p>{{ include item.template }}{{ end }}</div>$hemar8$,
        $expected8$TEXT: "<div>"
SECTION: iterator="item", collection="items"
  TEXT: "<p>"
  INTERPOLATE: "item.name"
  TEXT: "</p>"
  INCLUDE: "item.template"
TEXT: "</div>"$expected8$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Complex mixed template - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Complex mixed template - FAILED', total_tests;
    END IF;
    
    -- Test 9: Execute tag with complex SQL
    total_tests := total_tests + 1;
    result := test_template_parse(
        '{{ exec SELECT 123 AS number; }}',
        'EXECUTE: "SELECT 123 AS number;"'
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Execute tag with complex SQL - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Execute tag with complex SQL - FAILED', total_tests;
    END IF;
    
    -- Test 10: Whitespace handling
    total_tests := total_tests + 1;
    result := test_template_parse(
        $hemar10${{   spaced_var   }}$hemar10$,
        $expected10$INTERPOLATE: "spaced_var"$expected10$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Whitespace handling - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Whitespace handling - FAILED', total_tests;
    END IF;
    
    -- Test 11: Multiple consecutive tags
    total_tests := total_tests + 1;
    result := test_template_parse(
        $hemar11${{ var1 }}{{ var2 }}{{ var3 }}$hemar11$,
        $expected11$INTERPOLATE: "var1"
INTERPOLATE: "var2"
INTERPOLATE: "var3"$expected11$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Multiple consecutive tags - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Multiple consecutive tags - FAILED', total_tests;
    END IF;
    
    -- Test 12: Section with multiple nested elements
    total_tests := total_tests + 1;
    result := test_template_parse(
        $hemar12${{ for item in items }}
          <h2>{{ item.title }}</h2>
          <p>{{ item.description }}</p>
          {{ include item.footer }}
        {{ end }}$hemar12$,
        $expected12$Template parsed successfully. Structure:
SECTION: iterator="item", collection="items"
  TEXT: "          <h2>"
  INTERPOLATE: "item.title"
  TEXT: "</h2>
          <p>"
  INTERPOLATE: "item.description"
  TEXT: "</p>
          "
  INCLUDE: "item.footer"
  TEXT: "
"
$expected12$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Section with multiple nested elements - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Section with multiple nested elements - FAILED', total_tests;
    END IF;
    
    -- Test 13: Empty template
    total_tests := total_tests + 1;
    result := test_template_parse(
        '',
        'TEXT: ""'
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Empty template - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Empty template - FAILED', total_tests;
    END IF;
    
    -- Test 14: Just text, no tags
    total_tests := total_tests + 1;
    result := test_template_parse(
        $hemar14$Just plain text, no tags here.$hemar14$,
        $expected14$TEXT: "Just plain text, no tags here."$expected14$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Just text, no tags - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Just text, no tags - FAILED', total_tests;
    END IF;
    
    -- Test 15: Complex example from documentation
    total_tests := total_tests + 1;
    result := test_template_parse(
        $template15$<div>text before<div>

  {{ include inner_template }}

  {{ name }}

  {{ for item in array }}
    some text: {{ name2 }}
    {{ item.name }}
  {{ end }}

  <div>code insertion:</div>
  {{ exec
    context + '{"name3": "zalupa"}';

    IF context->condition THEN
      RAISE INFO 'some log';

      RETURN 'some text';
    END
    RETURN 'some other text';
  }}

  <div id="footer">...</div>$template15$,
        $expected15$Template parsed successfully. Structure:
TEXT: "<div>text before<div>

  "
INCLUDE: "inner_template"
TEXT: "

  "
INTERPOLATE: "name"
TEXT: "

  "
SECTION: iterator="item", collection="array"
  TEXT: "    some text: "
  INTERPOLATE: "name2"
  TEXT: "
    "
  INTERPOLATE: "item.name"
  TEXT: "
"
TEXT: "

  <div>code insertion:</div>
  "
EXECUTE: "context + '{"name3": "zalupa"}';

    IF context->condition THEN
      RAISE INFO 'some log';

      RETURN 'some text';
    END
    RETURN 'some other text';"
TEXT: "

  <div id="footer">...</div>"$expected15$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Complex example from documentation - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Complex example from documentation - FAILED', total_tests;
    END IF;
    
    -- Test 16: Multiple nested sections
    total_tests := total_tests + 1;
    result := test_template_parse(
        '{{ for a in items }}
          {{ for b in a.items }}
            {{ for c in b.items }}
              {{ c.name }}
            {{ end }}
          {{ end }}
        {{ end }}',
        'Template parsed successfully. Structure:
SECTION: iterator="a", collection="items"
  TEXT: "          "
  SECTION: iterator="b", collection="a.items"
    TEXT: "            "
    SECTION: iterator="c", collection="b.items"
      TEXT: "              "
      INTERPOLATE: "c.name"
      TEXT: "
"
    TEXT: "
"
  TEXT: "
"
'
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Multiple nested sections - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Multiple nested sections - FAILED', total_tests;
    END IF;
    
    -- Test 17: Interpolation with special characters
    total_tests := total_tests + 1;
    result := test_template_parse(
        '{{ special@field }}',
        'INTERPOLATE: "special@field"'
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Interpolation with special characters - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Interpolation with special characters - FAILED', total_tests;
    END IF;
    
    -- Test 18: Section with complex iterator and collection names
    total_tests := total_tests + 1;
    result := test_template_parse(
        '{{ for complex_item.with.dots in complex_collection[0].items }}{{ end }}',
        'SECTION: iterator="complex_item.with.dots", collection="complex_collection[0].items"'
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Section with complex iterator and collection names - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Section with complex iterator and collection names - FAILED', total_tests;
    END IF;
    
    -- Test 19: Include with complex path
    total_tests := total_tests + 1;
    result := test_template_parse(
        '{{ include templates[0].nested.path }}',
        'INCLUDE: "templates[0].nested.path"'
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Include with complex path - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Include with complex path - FAILED', total_tests;
    END IF;
    
    -- Test 20: Execute with complex SQL and quotes
    total_tests := total_tests + 1;
    result := test_template_parse(
        $template20$
        {{ exec SELECT 'text with "double" quotes' AS result; }}
        $template20$,
        $expected20$EXECUTE: "SELECT 'text with "double" quotes' AS result;"$expected20$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Execute with complex SQL and quotes - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Execute with complex SQL and quotes - FAILED', total_tests;
    END IF;
    
    -- Test 21: Execute tag with braces inside SQL code
    total_tests := total_tests + 1;
    result := test_template_parse(
        $template21${{ exec 
          -- SQL with curly braces in string literals and comments
          /* Comment with {{ braces }} inside */
          SELECT 
            '{{ This is inside a string literal }}' AS braced_text,
            $str$String with {{ and }} inside$str$ AS dollar_quoted,
            regexp_replace('test', 'e(.)t', 'a$1z') AS regex_with_curly;
        }}$template21$,
        $expected21$EXECUTE: "-- SQL with curly braces in string literals and comments
          /* Comment with {{ braces }} inside */
          SELECT 
            '{{ This is inside a string literal }}' AS braced_text,
            $str$String with {{ and }} inside$str$ AS dollar_quoted,
            regexp_replace('test', 'e(.)t', 'a$1z') AS regex_with_curly;"$expected21$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Execute tag with braces inside SQL code - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Execute tag with braces inside SQL code - FAILED', total_tests;
    END IF;
    
    -- Test 22: Deeply nested sections with mixed content
    total_tests := total_tests + 1;
    result := test_template_parse(
        $template22${{ for x in outer }}
  Level 1: {{ x.name }}
  {{ for y in x.items }}
    Level 2: {{ y.title }}
    {{ for z in y.subitems }}
      Level 3: {{ z.label }} - {{ z.value }}
      {{ for detail in z.details }}
        Details: {{ detail }}
      {{ end }}
    {{ end }}
  {{ end }}
{{ end }}$template22$,
        $expected22$Template parsed successfully. Structure:
SECTION: iterator="x", collection="outer"
  TEXT: "  Level 1: "
  INTERPOLATE: "x.name"
  TEXT: "
  "
  SECTION: iterator="y", collection="x.items"
    TEXT: "    Level 2: "
    INTERPOLATE: "y.title"
    TEXT: "
    "
    SECTION: iterator="z", collection="y.subitems"
      TEXT: "      Level 3: "
      INTERPOLATE: "z.label"
      TEXT: " - "
      INTERPOLATE: "z.value"
      TEXT: "
      "
      SECTION: iterator="detail", collection="z.details"
        TEXT: "        Details: "
        INTERPOLATE: "detail"
        TEXT: "
"
      TEXT: "
"
    TEXT: "
"
  TEXT: "
"
$expected22$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Deeply nested sections with mixed content - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Deeply nested sections with mixed content - FAILED', total_tests;
    END IF;
    
    -- Test 23: Multiple tag types mixed with HTML
    total_tests := total_tests + 1;
    result := test_template_parse(
        $template23$<div class="container">
  <header>{{ page_title }}</header>
  <nav>
    {{ for item in menu_items }}
      <a href="{{ item.url }}">{{ item.label }}</a>
    {{ end }}
  </nav>
  <main>
    {{ include content_template }}
    {{ exec SELECT get_footer_text() AS footer_text; }}
  </main>
</div>$template23$,
        $expected23$Template parsed successfully. Structure:
TEXT: "<div class="container">
  <header>"
INTERPOLATE: "page_title"
TEXT: "</header>
  <nav>
    "
SECTION: iterator="item", collection="menu_items"
  TEXT: "      <a href=""
  INTERPOLATE: "item.url"
  TEXT: "">"
  INTERPOLATE: "item.label"
  TEXT: "</a>
"
TEXT: "
  </nav>
  <main>
    "
INCLUDE: "content_template"
TEXT: "
    "
EXECUTE: "SELECT get_footer_text() AS footer_text;"
TEXT: "
  </main>
</div>"
$expected23$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Multiple tag types mixed with HTML - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Multiple tag types mixed with HTML - FAILED', total_tests;
    END IF;
    
    -- Test 24: Section with complex iterator paths
    total_tests := total_tests + 1;
    result := test_template_parse(
        $template24${{ for item.nested[0].value in collection[5].items[2].values }}
  {{ item.nested[0].value }}
{{ end }}$template24$,
        $expected24$SECTION: iterator="item.nested[0].value", collection="collection[5].items[2].values"$expected24$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Section with complex iterator paths - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Section with complex iterator paths - FAILED', total_tests;
    END IF;
    
    -- Test 25: Interpolation with Unicode characters
    total_tests := total_tests + 1;
    result := test_template_parse(
        $template25${{ unicode_var_ẞαж한글💻🌍 }}$template25$,
        $expected25$INTERPOLATE: "unicode_var_ẞαж한글💻🌍"$expected25$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Interpolation with Unicode characters - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Interpolation with Unicode characters - FAILED', total_tests;
    END IF;
    
    -- Test 26: Multiple consecutive sections
    total_tests := total_tests + 1;
    result := test_template_parse(
        $template26${{ for a in list_a }}{{ a }}{{ end }}{{ for b in list_b }}{{ b }}{{ end }}{{ for c in list_c }}{{ c }}{{ end }}$template26$,
        $expected26$SECTION: iterator="a", collection="list_a"
  INTERPOLATE: "a"
SECTION: iterator="b", collection="list_b"
  INTERPOLATE: "b"
SECTION: iterator="c", collection="list_c"
  INTERPOLATE: "c"$expected26$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Multiple consecutive sections - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Multiple consecutive sections - FAILED', total_tests;
    END IF;
    
    -- Test 27: Includes with variable paths
    total_tests := total_tests + 1;
    result := test_template_parse(
        $template27${{ include user.preferences.theme_template }}
{{ include system.templates[user.template_index] }}$template27$,
        $expected27$INCLUDE: "user.preferences.theme_template"
TEXT: "
"
INCLUDE: "system.templates[user.template_index]"$expected27$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Includes with variable paths - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Includes with variable paths - FAILED', total_tests;
    END IF;
    
    -- Test 28: Extremely long interpolation key
    total_tests := total_tests + 1;
    result := test_template_parse(
        $template28${{ very_long_variable_name_with_many_parts.that_continues_for_a_while.with_multiple_segments.and_keeps_going.for_quite_some_time.until_it_becomes_quite_verbose }}$template28$,
        $expected28$INTERPOLATE: "very_long_variable_name_with_many_parts.that_continues_for_a_while.with_multiple_segments.and_keeps_going.for_quite_some_time.until_it_becomes_quite_verbose"$expected28$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Extremely long interpolation key - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Extremely long interpolation key - FAILED', total_tests;
    END IF;
    
    -- Test 29: Tags with extra whitespace
    total_tests := total_tests + 1;
    result := test_template_parse(
        $template29${{   for   item   in   items   }}
  {{   item.name   }}
{{   end   }}$template29$,
        $expected29$Template parsed successfully. Structure:
SECTION: iterator="item", collection="items"
  TEXT: "  "
  INTERPOLATE: "item.name"
  TEXT: "
"
$expected29$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Tags with extra whitespace - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Tags with extra whitespace - FAILED', total_tests;
    END IF;
    
    -- Test 30: Execute with PL/pgSQL code blocks
    total_tests := total_tests + 1;
    result := test_template_parse(
        $template30${{ exec
DECLARE
  temp_var text;
  counter int := 0;
BEGIN
  FOR i IN 1..10 LOOP
    counter := counter + i;
  END LOOP;
  
  IF counter > 50 THEN
    temp_var := 'High';
  ELSE
    temp_var := 'Low';
  END IF;
  
  RETURN json_build_object('result', temp_var, 'count', counter);
END;
}}$template30$,
        $expected30$EXECUTE: "DECLARE
  temp_var text;
  counter int := 0;
BEGIN
  FOR i IN 1..10 LOOP
    counter := counter + i;
  END LOOP;
  
  IF counter > 50 THEN
    temp_var := 'High';
  ELSE
    temp_var := 'Low';
  END IF;
  
  RETURN json_build_object('result', temp_var, 'count', counter);
END;"$expected30$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Execute with PL/pgSQL code blocks - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Execute with PL/pgSQL code blocks - FAILED', total_tests;
    END IF;
    
    -- Test 31: Template with mixed indentation and newlines
    total_tests := total_tests + 1;
    result := test_template_parse(
        $template31$<div>
    {{ for item in items }}
        <span>{{ item.name }}</span>
    {{ end }}
</div>$template31$,
        $expected31$Template parsed successfully. Structure:
TEXT: "<div>
    "
SECTION: iterator="item", collection="items"
  TEXT: "        <span>"
  INTERPOLATE: "item.name"
  TEXT: "</span>
"
TEXT: "
</div>"$expected31$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Template with mixed indentation and newlines - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Template with mixed indentation and newlines - FAILED', total_tests;
    END IF;

    -- Test 32: Execute with window functions and complex SQL
    total_tests := total_tests + 1;
    result := test_template_parse(
        $template32${{ exec
WITH recursive cte AS (
  SELECT id, parent_id, name, 1 AS level
  FROM categories
  WHERE parent_id IS NULL
  UNION ALL
  SELECT c.id, c.parent_id, c.name, cte.level + 1
  FROM categories c
  JOIN cte ON c.parent_id = cte.id
)
SELECT 
  id, 
  repeat('  ', level - 1) || name AS indented_name,
  row_number() OVER (PARTITION BY level ORDER BY name) AS row_num
FROM cte
ORDER BY level, name;
}}$template32$,
        $expected32$EXECUTE: "WITH recursive cte AS (
  SELECT id, parent_id, name, 1 AS level
  FROM categories
  WHERE parent_id IS NULL
  UNION ALL
  SELECT c.id, c.parent_id, c.name, cte.level + 1
  FROM categories c
  JOIN cte ON c.parent_id = cte.id
)
SELECT 
  id, 
  repeat('  ', level - 1) || name AS indented_name,
  row_number() OVER (PARTITION BY level ORDER BY name) AS row_num
FROM cte
ORDER BY level, name;"$expected32$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Execute with window functions and complex SQL - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Execute with window functions and complex SQL - FAILED', total_tests;
    END IF;
    
    -- Test 33: Recursive template includes
    total_tests := total_tests + 1;
    result := test_template_parse(
        $template33${{ include base_template }}
{{ include dynamic_templates[index] }}
{{ for template_name in available_templates }}
  {{ include template_name }}
{{ end }}$template33$,
        $expected33$Template parsed successfully. Structure:
INCLUDE: "base_template"
TEXT: "
"
INCLUDE: "dynamic_templates[index]"
TEXT: "
"
SECTION: iterator="template_name", collection="available_templates"
  TEXT: "  "
  INCLUDE: "template_name"
  TEXT: "
"
$expected33$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Recursive template includes - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Recursive template includes - FAILED', total_tests;
    END IF;
    
    -- Test 34: Complex JSON manipulation in execute
    total_tests := total_tests + 1;
    result := test_template_parse(
        $template34${{ exec
WITH input_data AS (
  SELECT '{"users": [
    {"id": 1, "name": "Alice", "roles": ["admin", "editor"]},
    {"id": 2, "name": "Bob", "roles": ["viewer"]},
    {"id": 3, "name": "Charlie", "roles": ["editor", "contributor"]}
  ]}'::jsonb AS data
)
SELECT 
  jsonb_agg(
    jsonb_build_object(
      'name', user_data->>'name',
      'roles', user_data->'roles',
      'is_admin', user_data->'roles' ? 'admin'
    )
  ) AS result
FROM input_data,
jsonb_array_elements(data->'users') AS user_data;
}}$template34$,
        $expected34$EXECUTE: "WITH input_data AS (
  SELECT '{"users": [
    {"id": 1, "name": "Alice", "roles": ["admin", "editor"]},
    {"id": 2, "name": "Bob", "roles": ["viewer"]},
    {"id": 3, "name": "Charlie", "roles": ["editor", "contributor"]}
  ]}'::jsonb AS data
)
SELECT 
  jsonb_agg(
    jsonb_build_object(
      'name', user_data->>'name',
      'roles', user_data->'roles',
      'is_admin', user_data->'roles' ? 'admin'
    )
  ) AS result
FROM input_data,
jsonb_array_elements(data->'users') AS user_data;"$expected34$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Complex JSON manipulation in execute - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Complex JSON manipulation in execute - FAILED', total_tests;
    END IF;
    
    -- Test 35: Tags at start/end without whitespace
    total_tests := total_tests + 1;
    result := test_template_parse(
        $template35${{ var1 }}Text{{ var2 }}$template35$,
        $expected35$INTERPOLATE: "var1"
TEXT: "Text"
INTERPOLATE: "var2"$expected35$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Tags at start/end without whitespace - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Tags at start/end without whitespace - FAILED', total_tests;
    END IF;
    
    -- Test 36: Template with special characters in text
    total_tests := total_tests + 1;
    result := test_template_parse(
        $template36$Special chars: <>!@#$%^&*()_+`-=[]{}|;':",./<>?\nAnd {{ variable }} insertion$template36$,
        $expected36$TEXT: "Special chars: <>!@#$%^&*()_+`-=[]{}|;':",./<>?\nAnd "
INTERPOLATE: "variable"
TEXT: " insertion"$expected36$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Template with special characters in text - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Template with special characters in text - FAILED', total_tests;
    END IF;
    
    -- Test 37: Complex execute with error handling
    total_tests := total_tests + 1;
    result := test_template_parse(
        $template37${{ exec
BEGIN
  RETURN process_data(input_json);
EXCEPTION
  WHEN no_data_found THEN
    RETURN jsonb_build_object('error', 'No data found', 'code', 404);
  WHEN unique_violation THEN
    RETURN jsonb_build_object('error', 'Duplicate entry', 'code', 409);
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'error', SQLERRM,
      'code', SQLSTATE,
      'severity', 'CRITICAL'
    );
END;
}}$template37$,
        $expected37$EXECUTE: "BEGIN
  RETURN process_data(input_json);
EXCEPTION
  WHEN no_data_found THEN
    RETURN jsonb_build_object('error', 'No data found', 'code', 404);
  WHEN unique_violation THEN
    RETURN jsonb_build_object('error', 'Duplicate entry', 'code', 409);
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'error', SQLERRM,
      'code', SQLSTATE,
      'severity', 'CRITICAL'
    );
END;"$expected37$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Complex execute with error handling - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Complex execute with error handling - FAILED', total_tests;
    END IF;
    
    -- Test 38: Mixed nested sections and interpolations
    total_tests := total_tests + 1;
    result := test_template_parse(
        $template38${{ for user in users }}
  {{ user.name }}'s permissions:
  {{ for permission in user.permissions }}
    - {{ permission.name }}: {{ permission.status }}
    {{ for scope in permission.scopes }}
      * {{ scope.area }}: {{ scope.level }}
    {{ end }}
  {{ end }}
{{ end }}$template38$,
        $expected38$Template parsed successfully. Structure:
SECTION: iterator="user", collection="users"
  TEXT: "  "
  INTERPOLATE: "user.name"
  TEXT: "'s permissions:
  "
  SECTION: iterator="permission", collection="user.permissions"
    TEXT: "    - "
    INTERPOLATE: "permission.name"
    TEXT: ": "
    INTERPOLATE: "permission.status"
    TEXT: "
    "
    SECTION: iterator="scope", collection="permission.scopes"
      TEXT: "      * "
      INTERPOLATE: "scope.area"
      TEXT: ": "
      INTERPOLATE: "scope.level"
      TEXT: "
"
    TEXT: "
"
  TEXT: "
"
$expected38$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Mixed nested sections and interpolations - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Mixed nested sections and interpolations - FAILED', total_tests;
    END IF;
    
    -- Test 39: Execute with dynamic SQL generation
    total_tests := total_tests + 1;
    result := test_template_parse(
        $template39${{ exec
DECLARE
  column_names text[] := ARRAY['id', 'name', 'created_at'];
  table_name text := 'users';
  conditions text[] := ARRAY['is_active = true', 'created_at > now() - interval ''1 month'''];
  order_clause text := 'last_login DESC';
  query text;
BEGIN
  query := 'SELECT ' || array_to_string(column_names, ', ') || 
           ' FROM ' || table_name;
           
  IF array_length(conditions, 1) > 0 THEN
    query := query || ' WHERE ' || array_to_string(conditions, ' AND ');
  END IF;
  
  IF order_clause IS NOT NULL THEN
    query := query || ' ORDER BY ' || order_clause;
  END IF;
  
  EXECUTE query;
  RETURN query;
END;
}}$template39$,
        $expected39$EXECUTE: "DECLARE
  column_names text[] := ARRAY['id', 'name', 'created_at'];
  table_name text := 'users';
  conditions text[] := ARRAY['is_active = true', 'created_at > now() - interval ''1 month'''];
  order_clause text := 'last_login DESC';
  query text;
BEGIN
  query := 'SELECT ' || array_to_string(column_names, ', ') || 
           ' FROM ' || table_name;
           
  IF array_length(conditions, 1) > 0 THEN
    query := query || ' WHERE ' || array_to_string(conditions, ' AND ');
  END IF;
  
  IF order_clause IS NOT NULL THEN
    query := query || ' ORDER BY ' || order_clause;
  END IF;
  
  EXECUTE query;
  RETURN query;
END;"$expected39$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Execute with dynamic SQL generation - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Execute with dynamic SQL generation - FAILED', total_tests;
    END IF;
    
    -- Test 40: Complex nested structure with all tag types
    total_tests := total_tests + 1;
    result := test_template_parse(
        $template40$<!DOCTYPE html>
<html>
<head>
  <title>{{ page.title }}</title>
  {{ include meta_tags }}
</head>
<body>
  <header>{{ include header }}</header>
  <main>
    {{ for section in page.sections }}
      <section id="{{ section.id }}">
        <h2>{{ section.title }}</h2>
        {{ for item in section.items }}
          <div class="item {{ item.status }}">
            {{ item.content }}
            {{ include item.template }}
            {{ exec
              -- Get dynamic content for this item
              SELECT get_dynamic_content(
                '{{ item.id }}', 
                '{{ section.id }}',
                (SELECT context->'user'->'preferences')
              );
            }}
          </div>
        {{ end }}
      </section>
    {{ end }}
  </main>
  <footer>{{ include footer }}</footer>
</body>
</html>$template40$,
        $expected40$TEXT: "<!DOCTYPE html>
<html>
<head>
  <title>"
INTERPOLATE: "page.title"
TEXT: "</title>
  "
INCLUDE: "meta_tags"
TEXT: "
</head>
<body>
  <header>"
INCLUDE: "header"
TEXT: "</header>
  <main>
    "
SECTION: iterator="section", collection="page.sections"$expected40$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Complex nested structure with all tag types - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Complex nested structure with all tag types - FAILED', total_tests;
    END IF;

    -- Test 41: Subsequent object interpolation
    total_tests := total_tests + 1;
    result := test_template_parse(
        $hemar$User: {{ user.profile.name }}, Age: {{ user.profile.age }}$hemar$,
        $zalupa$Template parsed successfully. Structure:
TEXT: "User: "
INTERPOLATE: "user.profile.name"
TEXT: ", Age: "
INTERPOLATE: "user.profile.age"$zalupa$
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Subsequent object interpolation - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Subsequent object interpolation - FAILED', total_tests;
    END IF;
    
    -- Print summary
    IF passed_tests = total_tests THEN
        RAISE NOTICE '------------------------------------';
        RAISE NOTICE 'SUMMARY: % of % template parser tests passed (100%%)', 
            passed_tests, total_tests;
        RAISE NOTICE '------------------------------------';
    ELSE
        RAISE WARNING '------------------------------------';
        RAISE WARNING 'SUMMARY: % of % template parser tests passed (%)', 
            passed_tests, 
            total_tests, 
            round((passed_tests::numeric / total_tests::numeric) * 100, 2) || '%';
        RAISE WARNING '------------------------------------';
    END IF;

    IF passed_tests != total_tests THEN
      RAISE EXCEPTION 'Tests failed: % of % template parser tests did not pass', (total_tests - passed_tests), total_tests;
    END IF;
END $$; 