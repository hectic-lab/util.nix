-- Test section rendering
DO $$
DECLARE
    test_result text;
    expected text;
    total_tests integer := 0;
    passed_tests integer := 0;
BEGIN
    -- Test 1: String iteration
    total_tests := total_tests + 1;
    BEGIN
        test_result := hemar.render(
            '{"text": "Hello"}'::jsonb,
            '{{for char in text}}{{char}}{{end}}'
        );
        expected := 'Hello';
        IF test_result = expected THEN
            RAISE NOTICE 'Test %: String iteration: PASSED', total_tests;
            passed_tests := passed_tests + 1;
        ELSE
            RAISE WARNING 'Test %: String iteration: FAILED. Expected "%", got "%"', total_tests, expected, test_result;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Test %: String iteration: FAILED with error: %', total_tests, SQLERRM;
    END;

    -- Test 2: Array iteration
    total_tests := total_tests + 1;
    BEGIN
        test_result := hemar.render(
            '{"numbers": [1, 2, 3]}'::jsonb,
            '{{for num in numbers}}{{num}}{{end}}'
        );
        expected := '123';
        IF test_result = expected THEN
            RAISE NOTICE 'Test %: Array iteration: PASSED', total_tests;
            passed_tests := passed_tests + 1;
        ELSE
            RAISE WARNING 'Test %: Array iteration: FAILED. Expected "%", got "%"', total_tests, expected, test_result;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Test %: Array iteration: FAILED with error: %', total_tests, SQLERRM;
    END;

    -- Test 3: Object iteration
    total_tests := total_tests + 1;
    BEGIN
        test_result := hemar.render(
            '{"user": {"name": "John", "age": 30}}'::jsonb,
            '{{for item in user}}{{item.key}}: {{item.value}}{{end}}'
        );
        expected := 'age: 30name: John';
        IF test_result = expected THEN
            RAISE NOTICE 'Test %: Object iteration: PASSED', total_tests;
            passed_tests := passed_tests + 1;
        ELSE
            RAISE WARNING 'Test %: Object iteration: FAILED. Expected "%", got "%"', total_tests, expected, test_result;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Test %: Object iteration: FAILED with error: %', total_tests, SQLERRM;
    END;

    -- Test 4: Boolean condition (true)
    total_tests := total_tests + 1;
    BEGIN
        test_result := hemar.render(
            '{"show": true}'::jsonb,
            '{{for show in show}}Content{{end}}'
        );
        expected := 'Content';
        IF test_result = expected THEN
            RAISE NOTICE 'Test %: Boolean condition (true): PASSED', total_tests;
            passed_tests := passed_tests + 1;
        ELSE
            RAISE WARNING 'Test %: Boolean condition (true): FAILED. Expected "%", got "%"', total_tests, expected, test_result;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Test %: Boolean condition (true): FAILED with error: %', total_tests, SQLERRM;
    END;

    -- Test 5: Boolean condition (false)
    total_tests := total_tests + 1;
    BEGIN
        test_result := hemar.render(
            '{"show": false}'::jsonb,
            '{{for show in show}}Content{{end}}'
        );
        expected := '';
        IF test_result = expected THEN
            RAISE NOTICE 'Test %: Boolean condition (false): PASSED', total_tests;
            passed_tests := passed_tests + 1;
        ELSE
            RAISE WARNING 'Test %: Boolean condition (false): FAILED. Expected "%", got "%"', total_tests, expected, test_result;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Test %: Boolean condition (false): FAILED with error: %', total_tests, SQLERRM;
    END;


    -- Test 6: Nested sections
    total_tests := total_tests + 1;
    BEGIN
        test_result := hemar.render(
            '{"items": [{"name": "Item 1", "tags": ["tag1", "tag2"]}, {"name": "Item 2", "tags": ["tag3"]}]}'::jsonb,
            '{{for item in items}}{{item.name}}: {{for tag in item.tags}}{{tag}} {{end}}{{end}}'
        );
        expected := 'Item 1: tag1 tag2 Item 2: tag3 ';
        IF test_result = expected THEN
            RAISE NOTICE 'Test %: Nested sections: PASSED', total_tests;
            passed_tests := passed_tests + 1;
        ELSE
            RAISE WARNING 'Test %: Nested sections: FAILED. Expected "%", got "%"', total_tests, expected, test_result;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Test %: Nested sections: FAILED with error: %', total_tests, SQLERRM;
    END;

    -- Test 7: Section with context
    total_tests := total_tests + 1;
    BEGIN
        test_result := hemar.render(
            '{"items": ["a", "b"], "prefix": "Item: "}'::jsonb,
            '{{for item in items}}{{prefix}}{{item}}{{end}}'
        );
        expected := 'Item: aItem: b';
        IF test_result = expected THEN
            RAISE NOTICE 'Test %: Section with context: PASSED', total_tests;
            passed_tests := passed_tests + 1;
        ELSE
            RAISE WARNING 'Test %: Section with context: FAILED. Expected "%", got "%"', total_tests, expected, test_result;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Test %: Section with context: FAILED with error: %', total_tests, SQLERRM;
    END;

    -- Test 8: Empty array
    total_tests := total_tests + 1;
    BEGIN
        test_result := hemar.render(
            '{"items": []}'::jsonb,
            '{{for item in items}}{{item}}{{end}}'
        );
        expected := '';
        IF test_result = expected THEN
            RAISE NOTICE 'Test %: Empty array: PASSED', total_tests;
            passed_tests := passed_tests + 1;
        ELSE
            RAISE WARNING 'Test %: Empty array: FAILED. Expected "%", got "%"', total_tests, expected, test_result;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Test %: Empty array: FAILED with error: %', total_tests, SQLERRM;
    END;

    -- Test 9: Empty object
    total_tests := total_tests + 1;
    BEGIN
        test_result := hemar.render(
            '{"user": {}}'::jsonb,
            '{{for key in user}}{{key}}{{end}}'
        );
        expected := '';
        IF test_result = expected THEN
            RAISE NOTICE 'Test %: Empty object: PASSED', total_tests;
            passed_tests := passed_tests + 1;
        ELSE
            RAISE WARNING 'Test %: Empty object: FAILED. Expected "%", got "%"', total_tests, expected, test_result;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Test %: Empty object: FAILED with error: %', total_tests, SQLERRM;
    END;

    -- Test 10: Invalid collection type (number)
    total_tests := total_tests + 1;
    BEGIN
        test_result := hemar.render(
            '{"number": 42}'::jsonb,
            '{{for item in number}}{{item}}{{end}}'
        );
        expected := '';
        IF test_result = expected THEN
            RAISE NOTICE 'Test %: Invalid collection type: PASSED (error raised as expected)', total_tests;
            passed_tests := passed_tests + 1;
        ELSE
            RAISE WARNING 'Test %: Invalid collection type: FAILED. Expected "%", got "%"', total_tests, expected, test_result;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Test %: Invalid collection type: FAILED with error: %', total_tests, SQLERRM;
    END;

    
    -- Test 11: Section whitespaces
    total_tests := total_tests + 1;
    BEGIN
        test_result := hemar.render(
            '{"array": [1, 2, 3]}'::jsonb,
            '{{for item in array}}item{{end}}'
        );
        expected := 'itemitemitem';
        IF test_result = expected THEN
            RAISE NOTICE 'Test %: Section whitespaces: PASSED', total_tests;
            passed_tests := passed_tests + 1;
        ELSE
            RAISE WARNING 'Test %: Section whitespaces: FAILED. Expected "%", got "%"', total_tests, expected, test_result;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Test %: Section whitespaces: FAILED with error: %', total_tests, SQLERRM;
    END;

    -- Test 12: Section whitespaces 2
    total_tests := total_tests + 1;
    BEGIN
        test_result := hemar.render(
            '{"array": [1, 2, 3]}'::jsonb,
            '{{for item in array}}
    item
{{end}}'
        );
        expected := '    item
    item
    item
';
        IF test_result = expected THEN
            RAISE NOTICE 'Test %: Section whitespaces 2: PASSED', total_tests;
            passed_tests := passed_tests + 1;
        ELSE
            RAISE WARNING 'Test %: Section whitespaces 2: FAILED. Expected "%", got "%"', total_tests, expected, test_result;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Test %: Section whitespaces 2: FAILED with error: %', total_tests, SQLERRM;
    END;

    -- Test 13: Section whitespaces 3
    total_tests := total_tests + 1;
    BEGIN
        test_result := hemar.render(
            '{"array": [1, 2, 3]}'::jsonb,
            '{{for item in array}} item
            {{end}}'
        );
        expected := ' item
 item
 item
';
        IF test_result = expected THEN
            RAISE NOTICE 'Test %: Section whitespaces 3: PASSED', total_tests;
            passed_tests := passed_tests + 1;
        ELSE
            RAISE WARNING 'Test %: Section whitespaces 3: FAILED. Expected "%", got "%"', total_tests, expected, test_result;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Test %: Section whitespaces 3: FAILED with error: %', total_tests, SQLERRM;
    END;

    -- Test 14: Section whitespaces 4
    total_tests := total_tests + 1;
    BEGIN
        test_result := hemar.render(
            '{"array": [1, 2, 3]}'::jsonb,
            '{{for item in array}}
 item {{end}}'
        );
        expected := ' item  item  item ';
        IF test_result = expected THEN
            RAISE NOTICE 'Test %: Section whitespaces 4: PASSED', total_tests;
            passed_tests := passed_tests + 1;
        ELSE
            RAISE WARNING 'Test %: Section whitespaces 4: FAILED. Expected "%", got "%"', total_tests, expected, test_result;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Test %: Section whitespaces 4: FAILED with error: %', total_tests, SQLERRM;
    END;

    -- Test 15: Section whitespaces 5
    total_tests := total_tests + 1;
    BEGIN
        test_result := hemar.render(
            '{"array": [1, 2, 3]}'::jsonb,
            '{{for item in array}}
  item
             {{end}}
'
        );
        expected := '  item
  item
  item
';
        IF test_result = expected THEN
            RAISE NOTICE 'Test %: Section whitespaces 5: PASSED', total_tests;
            passed_tests := passed_tests + 1;
        ELSE
            RAISE WARNING 'Test %: Section whitespaces 5: FAILED. Expected "%", got "%"', total_tests, pg_temp.test_regexp_replace(expected), pg_temp.test_regexp_replace(test_result);
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Test %: Section whitespaces 5: FAILED with error: %', total_tests, SQLERRM;
    END;

    -- Test 16: Tabs
    total_tests := total_tests + 1;
    BEGIN
        test_result := hemar.render(
            '{"array": [1, 2, 3]}'::jsonb,
            '
identation1
{{for item in array}}
    identation2
{{end}}
identation1
'
        );
        expected := '
identation1
    identation2
    identation2
    identation2
identation1
';

        IF test_result = expected THEN
            RAISE NOTICE 'Test %: Tabs: PASSED', total_tests;
            passed_tests := passed_tests + 1;
        ELSE
            RAISE WARNING 'Test %: Tabs: FAILED. Expected "%", got "%"', total_tests, pg_temp.test_regexp_replace(expected), pg_temp.test_regexp_replace(test_result);
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Test %: Tabs: FAILED with error: %', total_tests, SQLERRM;
    END;

    -- Test 17: Tabs 2
    total_tests := total_tests + 1;
    BEGIN
        test_result := hemar.render(
            '{"array": [1, 2, 3]}'::jsonb,
            '
        identation1
        {{for item in array}}
            identation2
        {{end}}
        identation1
'
        );
        expected := '
        identation1
            identation2
            identation2
            identation2
        identation1
';

        IF test_result = expected THEN
            RAISE NOTICE 'Test %: Tabs: PASSED', total_tests;
            passed_tests := passed_tests + 1;
        ELSE
            RAISE WARNING 'Test %: Tabs: FAILED. Expected "%", got "%"', total_tests, pg_temp.test_regexp_replace(expected), pg_temp.test_regexp_replace(test_result);
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Test %: Tabs: FAILED with error: %', total_tests, SQLERRM;
    END;

    -- Test 18: Context
    total_tests := total_tests + 1;
    BEGIN
        test_result := hemar.render(
            '{"value": 12, "array": [1, 2, 3]}'::jsonb,
            '
        {{for item in array}}
            {{exec RETURN context::TEXT}}
        {{end}}
'
        );
        expected := '
';

        IF test_result = expected THEN
            RAISE NOTICE 'Test %: Context: PASSED', total_tests;
            passed_tests := passed_tests + 1;
        ELSE
            RAISE WARNING 'Test %: Context: FAILED. Expected "%", got "%"', total_tests, expected, test_result;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Test %: Context: FAILED with error: %', total_tests, SQLERRM;
    END;

    -- Print summary
    IF passed_tests = total_tests THEN
        RAISE NOTICE '------------------------------------';
        RAISE NOTICE 'SUMMARY: % of % template section tests passed (100%%)', 
            passed_tests, total_tests;
        RAISE NOTICE '------------------------------------';
    ELSE
        RAISE WARNING '------------------------------------';
        RAISE WARNING 'SUMMARY: % of % template section tests passed (%)', 
            passed_tests, 
            total_tests, 
            round((passed_tests::numeric / total_tests::numeric) * 100, 2) || '%';
        RAISE WARNING '------------------------------------';
    END IF;

    IF passed_tests != total_tests THEN
      RAISE EXCEPTION 'Tests failed: % of % template section tests did not pass', (total_tests - passed_tests), total_tests;
    END IF;
END $$;