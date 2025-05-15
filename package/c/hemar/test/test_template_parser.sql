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
        
        IF parsed_result IS NULL THEN
            RAISE WARNING 'Parser returned NULL for template: %', template_text;
            RETURN false;
        END IF;
        
        passed := position(expected_structure in parsed_result) > 0;
        
        IF NOT passed THEN
            RAISE WARNING 'Template parsing test failed!';
            RAISE WARNING 'Template: %', template_text;
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
        $template9${{ exec 
          IF condition THEN 
            RETURN 'value1'; 
          ELSE 
            RETURN 'value2'; 
          END IF; 
        }}$template9$,
        $expected9$EXECUTE: "IF condition THEN
            RETURN 'value1';
          ELSE
            RETURN 'value2';
          END IF;"$expected9$
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
        $expected12$SECTION: iterator="item", collection="items"
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
        "$expected12$
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
  // FIXME: IT NEED A SPECE PIZDEZZZZ
  {{ exec
    context + '{"name3": "zalupa"}';

    IF context->condition THEN
      RAISE INFO 'some log';

      RETURN 'some text';
    END
    RETURN 'some other text';
  }}

  <div id="footer">...</div>$template15$,
        $expected15$TEXT: "<div>text before<div>

  "
INCLUDE: "inner_template"
TEXT: "

  "
INTERPOLATE: "name"
TEXT: "

  "
SECTION: iterator="item", collection="array"
  TEXT: "
    some text: "
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

  <div id=\"footer\">...</div>"$expected15$
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