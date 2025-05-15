-- Test file for hemar template parser
-- Run with: psql -f test_template_parser.sql

-- Load extension if not already loaded
-- CREATE EXTENSION IF NOT EXISTS hemar;

-- Create test function to validate template parsing
CREATE OR REPLACE FUNCTION test_template_parse(template_text text, expected_structure text) RETURNS boolean AS $$
DECLARE
    parsed_result text;
    passed boolean;
BEGIN
    BEGIN
        parsed_result := hemar.parse(template_text);
        passed := position(expected_structure in parsed_result) > 0;
    EXCEPTION
        WHEN OTHERS THEN
            passed := false;
    END;
    
    IF NOT passed THEN
        RAISE WARNING 'Template parsing test failed!';
        RAISE WARNING 'Template: %', template_text;
        RAISE WARNING 'Expected to find: %', expected_structure;
        RAISE WARNING 'Actual result: %', parsed_result;
    END IF;
    
    RETURN passed;
END;
$$ LANGUAGE plpgsql;

-- Run the tests
DO $$
DECLARE
    total_tests integer := 0;
    passed_tests integer := 0;
    result boolean;
BEGIN
    RAISE NOTICE 'Starting template parser tests...';
    
    -- Test 1: Simple interpolation
    total_tests := total_tests + 1;
    result := test_template_parse(
        '{{ simple_var }}',
        'INTERPOLATE: "simple_var"'
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
        'Hello, {{ name }}!',
        'TEXT: "Hello, "
INTERPOLATE: "name"
TEXT: "!"'
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
        '{{ for item in items do }}{{ item }}{{ end }}',
        'SECTION: iterator="item", collection="items"'
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
        '{{ for item in items do }}Name: {{ item.name }}{{ end }}',
        'SECTION: iterator="item", collection="items"
  TEXT: "Name: "
  INTERPOLATE: "item.name"'
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
        '{{ for item in items do }}{{ for subitem in item.subitems do }}{{ subitem }}{{ end }}{{ end }}',
        'SECTION: iterator="item", collection="items"
  SECTION: iterator="subitem", collection="item.subitems"
    INTERPOLATE: "subitem"'
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
        '{{ include template_name }}',
        'INCLUDE: "template_name"'
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
        '{{ exec RETURN my_function(arg1, arg2) }}',
        'EXECUTE: "RETURN my_function(arg1, arg2)"'
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
        '<div>{{ for item in items do }}<p>{{ item.name }}</p>{{ include item.template }}{{ end }}</div>',
        'TEXT: "<div>"
SECTION: iterator="item", collection="items"
  TEXT: "<p>"
  INTERPOLATE: "item.name"
  TEXT: "</p>"
  INCLUDE: "item.template"
TEXT: "</div>"'
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
        '{{ exec 
          IF condition THEN 
            RETURN ''value1''; 
          ELSE 
            RETURN ''value2''; 
          END IF; 
        }}',
        'EXECUTE: "IF condition THEN'
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
        '{{   spaced_var   }}',
        'INTERPOLATE: "spaced_var"'
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
        '{{ var1 }}{{ var2 }}{{ var3 }}',
        'INTERPOLATE: "var1"
INTERPOLATE: "var2"
INTERPOLATE: "var3"'
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
        '{{ for item in items do }}
          <h2>{{ item.title }}</h2>
          <p>{{ item.description }}</p>
          {{ include item.footer }}
        {{ end }}',
        'SECTION: iterator="item", collection="items"
  TEXT: "
          <h2>"
  INTERPOLATE: "item.title"
  TEXT: "</h2>
          <p>"
  INTERPOLATE: "item.description"
  TEXT: "</p>
          "
  INCLUDE: "item.footer"
  TEXT: "
        "'
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
        'Just plain text, no tags here.',
        'TEXT: "Just plain text, no tags here."'
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
        '<div>text before<div>

  {{ include inner_template }}

  {{ name }}

  {{ for item in array do }}
    some text: {{ name2 }}
    {{ item.name }}
  {{ end }}

  <div>code insertion:</div>
  {{ exec
    context + ''{"name3": "zalupa"}'';

    IF context->condition THEN
      RAISE INFO ''some log'';

      RETURN ''some text'';
    END
    RETURN ''some other text'';
  }}

  <div id="footer">...</div>',
        'TEXT: "<div>text before<div>

  "
INCLUDE: "inner_template"
TEXT: "

  "
INTERPOLATE: "name"
TEXT: "

  "
SECTION: iterator="item", collection="array"'
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
        '{{ for a in items do }}
          {{ for b in a.items do }}
            {{ for c in b.items do }}
              {{ c.name }}
            {{ end }}
          {{ end }}
        {{ end }}',
        'SECTION: iterator="a", collection="items"
  TEXT: "
          "
  SECTION: iterator="b", collection="a.items"
    TEXT: "
            "
    SECTION: iterator="c", collection="b.items"
      TEXT: "
              "
      INTERPOLATE: "c.name"
      TEXT: "
            "'
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
        '{{ for complex_item.with.dots in complex_collection[0].items do }}{{ end }}',
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
        '{{ exec SELECT ''text with "double" quotes'' AS result; }}',
        'EXECUTE: "SELECT ''text with "double" quotes'' AS result;"'
    );
    IF result THEN
        passed_tests := passed_tests + 1;
        RAISE NOTICE 'Test %: Execute with complex SQL and quotes - PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Execute with complex SQL and quotes - FAILED', total_tests;
    END IF;
    
    -- Print summary
    IF passed_tests = total_tests THEN
        RAISE NOTICE '------------------------------------';
        RAISE NOTICE 'SUMMARY: % of % tests passed (100%%)', 
            passed_tests, total_tests;
        RAISE NOTICE '------------------------------------';
    ELSE
        RAISE WARNING '------------------------------------';
        RAISE WARNING 'SUMMARY: % of % tests passed (%)', 
            passed_tests, 
            total_tests, 
            round((passed_tests::numeric / total_tests::numeric) * 100, 2) || '%';
        RAISE WARNING '------------------------------------';
    END IF;

    IF passed_tests != total_tests THEN
      RAISE EXCEPTION 'Tests failed: % of % tests did not pass', (total_tests - passed_tests), total_tests;
    END IF;
END $$; 