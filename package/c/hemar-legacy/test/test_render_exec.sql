-- Test the render function with execute tags
CREATE EXTENSION IF NOT EXISTS hemar;

DO $$
DECLARE
    total_tests INT := 0;
    passed_tests INT := 0;
    test_result TEXT;
    expected TEXT;
    passed BOOLEAN;
BEGIN
    -- Test 1: Simple execute tag that sets a variable
    total_tests := total_tests + 1;
    test_result := hemar.render(
        '{"name": "John", "age": 30}'::jsonb,
        'Hello {{ exec PERFORM 1; }}'
    );
    expected := 'Hello ';
    passed := test_result = expected;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Simple execute tag: PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Simple execute tag: FAILED. Expected "%", got "%"', 
            total_tests, expected, test_result;
    END IF;
    
    -- Test 2: Execute tag with context access
    total_tests := total_tests + 1;
    DROP TABLE IF EXISTS test_output;
    CREATE TEMP TABLE test_output (value TEXT);
    
    test_result := hemar.render(
        '{"name": "John", "age": 30}'::jsonb,
        $expected$Hello {{ exec INSERT INTO test_output VALUES (context->'name'); }}$expected$
    );
    
    SELECT value INTO expected FROM test_output;
    passed := expected = '"John"';
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Execute tag with context access: PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Execute tag with context access: FAILED. Expected "John", got "%"', 
            total_tests, expected;
    END IF;
    
    -- Test 3: Execute tag with quotes and complex SQL
    total_tests := total_tests + 1;
    DROP TABLE IF EXISTS test_output;
    CREATE TEMP TABLE test_output (value TEXT);
    
    test_result := hemar.render(
        '{"items": [{"id": 1, "name": "Item 1"}, {"id": 2, "name": "Item 2"}]}'::jsonb,
        $expected$Items: {{ exec 
            INSERT INTO test_output 
            SELECT jsonb_array_elements(context->'items')->>'name';
        }}$expected$
    );
    
    SELECT string_agg(value, ', ' ORDER BY value) INTO expected FROM test_output;
    passed := expected = 'Item 1, Item 2';
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Execute tag with complex SQL: PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Execute tag with complex SQL: FAILED. Expected "Item 1, Item 2", got "%"', 
            total_tests, expected;
    END IF;
    
    -- Test 4: Execute tag with output capture
    total_tests := total_tests + 1;
    test_result := hemar.render(
        '{"name": "John", "age": 30}'::jsonb,
        $expected$Hello {{ exec RETURN context->>'name'; }}$expected$
    );
    expected := 'Hello John';
    passed := test_result = expected;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Execute tag with output capture: PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Execute tag with output capture: FAILED. Expected "%", got "%"', 
            total_tests, expected, test_result;
    END IF;
    
    -- Test 5: Execute tag with complex output
    total_tests := total_tests + 1;
    test_result := hemar.render(
        '{"items": [{"id": 1, "name": "Item 1"}, {"id": 2, "name": "Item 2"}]}'::jsonb,
        $expected$Items: {{ exec 
            RETURN (SELECT string_agg(value, ', ')
            FROM (
                SELECT jsonb_array_elements(context->'items')->>'name' as value
            ) t);
        }}$expected$
    );
    expected := 'Items: Item 1, Item 2';
    passed := test_result = expected;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Execute tag with complex output: PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Execute tag with complex output: FAILED. Expected "%", got "%"', 
            total_tests, expected, test_result;
    END IF;
    
    -- Test 6: Execute tag with multiple statements
    total_tests := total_tests + 1;
    test_result := hemar.render(
        '{"name": "John", "age": 30}'::jsonb,
        $expected$Hello {{ exec 
            DECLARE
                v_name TEXT;
            BEGIN
                v_name := context->>'name';
                RETURN v_name;
            END;
        }}$expected$
    );
    expected := 'Hello John';
    passed := test_result = expected;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Execute tag with multiple statements: PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Execute tag with multiple statements: FAILED. Expected "%", got "%"', 
            total_tests, expected, test_result;
    END IF;

    -- Test 7: Execute tag with array operations
    total_tests := total_tests + 1;
    test_result := hemar.render(
        '{"numbers": [1, 2, 3, 4, 5]}'::jsonb,
        $expected$Sum: {{ exec 
            RETURN (SELECT sum(value::int) 
                   FROM jsonb_array_elements_text(context->'numbers') as value);
        }}$expected$
    );
    expected := 'Sum: 15';
    passed := test_result = expected;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Execute tag with array operations: PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Execute tag with array operations: FAILED. Expected "%", got "%"', 
            total_tests, expected, test_result;
    END IF;

    -- Test 8: Execute tag with nested JSON operations
    total_tests := total_tests + 1;
    test_result := hemar.render(
        '{"user": {"profile": {"settings": {"theme": "dark", "notifications": true}}}}'::jsonb,
        $expected$Settings: {{ exec 
            RETURN context->'user'->'profile'->'settings'->>'theme';
        }}$expected$
    );
    expected := 'Settings: dark';
    passed := test_result = expected;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Execute tag with nested JSON operations: PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Execute tag with nested JSON operations: FAILED. Expected "%", got "%"', 
            total_tests, expected, test_result;
    END IF;

    -- Test 9: Execute tag with conditional logic
    total_tests := total_tests + 1;
    test_result := hemar.render(
        '{"age": 25, "country": "US"}'::jsonb,
        $expected$Status: {{ exec 
            DECLARE
                v_status TEXT;
            BEGIN
                IF (context->>'age')::int >= 21 AND context->>'country' = 'US' THEN
                    v_status := 'Adult in US';
                ELSE
                    v_status := 'Other';
                END IF;
                RETURN v_status;
            END;
        }}$expected$
    );
    expected := 'Status: Adult in US';
    passed := test_result = expected;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Execute tag with conditional logic: PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Execute tag with conditional logic: FAILED. Expected "%", got "%"', 
            total_tests, expected, test_result;
    END IF;

    -- Test 10: Execute tag with string manipulation
    total_tests := total_tests + 1;
    test_result := hemar.render(
        '{"text": "hello world"}'::jsonb,
        $expected$Text: {{ exec 
            RETURN upper(context->>'text');
        }}$expected$
    );
    expected := 'Text: HELLO WORLD';
    passed := test_result = expected;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Execute tag with string manipulation: PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Execute tag with string manipulation: FAILED. Expected "%", got "%"', 
            total_tests, expected, test_result;
    END IF;

    -- Test 11: Execute tag with date operations
    total_tests := total_tests + 1;
    test_result := hemar.render(
        '{"date": "2024-03-15"}'::jsonb,
        $expected$Date: {{ exec 
            RETURN to_char((context->>'date')::date, 'Month DD, YYYY');
        }}$expected$
    );
    expected := 'Date: March     15, 2024';
    passed := test_result = expected;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Execute tag with date operations: PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Execute tag with date operations: FAILED. Expected "%", got "%"', 
            total_tests, expected, test_result;
    END IF;

    -- Test 12: Execute tag with aggregation
    total_tests := total_tests + 1;
    test_result := hemar.render(
        '{"scores": [85, 92, 78, 95, 88]}'::jsonb,
        $expected$Stats: {{ exec 
            RETURN (SELECT format('Avg: %s, Max: %s', 
                                round(avg(value::float)::numeric, 1), 
                                max(value::int))
                   FROM jsonb_array_elements_text(context->'scores') as value);
        }}$expected$
    );
    expected := 'Stats: Avg: 87.6, Max: 95';
    passed := test_result = expected;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Execute tag with aggregation: PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Execute tag with aggregation: FAILED. Expected "%", got "%"', 
            total_tests, expected, test_result;
    END IF;

    -- Test 13: Execute tag with error handling
    total_tests := total_tests + 1;
    test_result := hemar.render(
        '{"value": "not_a_number"}'::jsonb,
        $expected$Result: {{ exec 
            BEGIN
                RETURN (context->>'value')::int::text;
            EXCEPTION WHEN OTHERS THEN
                RETURN 'Error: Invalid number';
            END;
        }}$expected$
    );
    expected := 'Result: Error: Invalid number';
    passed := test_result = expected;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Execute tag with error handling: PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Execute tag with error handling: FAILED. Expected "%", got "%"', 
            total_tests, expected, test_result;
    END IF;

    -- Test 14: Execute tag with complex JSON transformation
    total_tests := total_tests + 1;
    test_result := hemar.render(
        '{"users": [{"name": "Alice", "roles": ["admin", "user"]}, {"name": "Bob", "roles": ["user"]}]}'::jsonb,
        $expected$Users: {{ exec 
            RETURN (SELECT string_agg(
                format('%s (%s)', 
                    user_data->>'name',
                    (SELECT string_agg(role, ', ') 
                     FROM jsonb_array_elements_text(user_data->'roles') as role)
                ),
                '; '
            )
            FROM jsonb_array_elements(context->'users') as user_data);
        }}$expected$
    );
    expected := 'Users: Alice (admin, user); Bob (user)';
    passed := test_result = expected;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Execute tag with complex JSON transformation: PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Execute tag with complex JSON transformation: FAILED. Expected "%", got "%"', 
            total_tests, expected, test_result;
    END IF;

    -- Test 15: Execute tag with empty/null handling
    total_tests := total_tests + 1;
    test_result := hemar.render(
        '{"name": null, "items": []}'::jsonb,
        $expected$Result: {{ exec 
            DECLARE
                v_name TEXT;
                v_count INT;
            BEGIN
                v_name := COALESCE(context->>'name', 'Unknown');
                v_count := jsonb_array_length(context->'items');
                RETURN format('Name: %s, Items: %s', v_name, v_count);
            END;
        }}$expected$
    );
    expected := 'Result: Name: Unknown, Items: 0';
    passed := test_result = expected;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Execute tag with empty/null handling: PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Execute tag with empty/null handling: FAILED. Expected "%", got "%"', 
            total_tests, expected, test_result;
    END IF;

    -- Print summary
    IF passed_tests = total_tests THEN
        RAISE NOTICE '------------------------------------';
        RAISE NOTICE 'SUMMARY: % of % render exec tests passed (100%%)', 
            passed_tests, total_tests;
        RAISE NOTICE '------------------------------------';
    ELSE
        RAISE WARNING '------------------------------------';
        RAISE WARNING 'SUMMARY: % of % render exec tests passed (%)', 
            passed_tests, 
            total_tests, 
            round((passed_tests::numeric / total_tests::numeric) * 100, 2) || '%';
        RAISE WARNING '------------------------------------';
    END IF;

    IF passed_tests != total_tests THEN
      RAISE EXCEPTION 'Tests failed: % of % render exec tests did not pass', (total_tests - passed_tests), total_tests;
    END IF;
END $$; 