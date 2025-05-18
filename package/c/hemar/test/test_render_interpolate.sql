-- Test the render function with interpolation tags
CREATE EXTENSION IF NOT EXISTS hemar;

DO $$
DECLARE
    total_tests INT := 0;
    passed_tests INT := 0;
    test_result TEXT;
    expected TEXT;
    passed BOOLEAN;
BEGIN
    -- Test 1: Simple string interpolation
    total_tests := total_tests + 1;
    test_result := hemar.render(
        '{"name": "John"}'::jsonb,
        'Hello {{ name }}!'
    );
    expected := 'Hello John!';
    passed := test_result = expected;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Simple string interpolation: PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Simple string interpolation: FAILED. Expected "%", got "%"', 
            total_tests, expected, test_result;
    END IF;

    -- Test 2: Numeric interpolation
    total_tests := total_tests + 1;
    test_result := hemar.render(
        '{"age": 30, "price": 19.99}'::jsonb,
        'Age: {{ age }}, Price: {{ price }}'
    );
    expected := 'Age: 30, Price: 19.99';
    passed := test_result = expected;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Numeric interpolation: PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Numeric interpolation: FAILED. Expected "%", got "%"', 
            total_tests, expected, test_result;
    END IF;

    -- Test 3: Boolean interpolation
    total_tests := total_tests + 1;
    test_result := hemar.render(
        '{"is_active": true, "is_deleted": false}'::jsonb,
        'Status: {{ is_active }}, Deleted: {{ is_deleted }}'
    );
    expected := 'Status: true, Deleted: false';
    passed := test_result = expected;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Boolean interpolation: PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Boolean interpolation: FAILED. Expected "%", got "%"', 
            total_tests, expected, test_result;
    END IF;

    -- Test 4: Null value interpolation
    total_tests := total_tests + 1;
    test_result := hemar.render(
        '{"name": null}'::jsonb,
        'Name: {{ name }}'
    );
    expected := 'Name: ';
    passed := test_result = expected;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Null value interpolation: PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Null value interpolation: FAILED. Expected "%", got "%"', 
            total_tests, expected, test_result;
    END IF;

    -- Test 5: Nested object interpolation
    total_tests := total_tests + 1;
    test_result := hemar.render(
        '{"user": {"profile": {"name": "John", "age": 30}}}'::jsonb,
        'User: {{ user.profile.name }}, Age: {{ user.profile.age }}'
    );
    expected := 'User: John, Age: 30';
    passed := test_result = expected;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Nested object interpolation: PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Nested object interpolation: FAILED. Expected "%", got "%"', 
            total_tests, expected, test_result;
    END IF;

    -- Test 6: Array interpolation
    total_tests := total_tests + 1;
    test_result := hemar.render(
        '{"numbers": [1, 2, 3], "names": ["John", "Jane"]}'::jsonb,
        'Numbers: {{ numbers }}, Names: {{ names }}'
    );
    expected := 'Numbers: [1, 2, 3], Names: ["John", "Jane"]';
    passed := test_result = expected;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Array interpolation: PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Array interpolation: FAILED. Expected "%", got "%"', 
            total_tests, expected, test_result;
    END IF;

    -- Test 7: Array index interpolation
    total_tests := total_tests + 1;
    test_result := hemar.render(
        '{"items": [{"id": 1, "name": "Item 1"}, {"id": 2, "name": "Item 2"}]}'::jsonb,
        'First item: {{ items[0].name }}, Second item: {{ items[1].name }}'
    );
    expected := 'First item: Item 1, Second item: Item 2';
    passed := test_result = expected;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Array index interpolation: PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Array index interpolation: FAILED. Expected "%", got "%"', 
            total_tests, expected, test_result;
    END IF;

    -- Test 8: Complex nested structure interpolation
    total_tests := total_tests + 1;
    test_result := hemar.render(
        '{"company": {"name": "Tech Corp", "employees": [{"name": "John", "role": "Developer"}, {"name": "Jane", "role": "Manager"}]}}'::jsonb,
        'Company: {{ company.name }}, First employee: {{ company.employees[0].name }} ({{ company.employees[0].role }})'
    );
    expected := 'Company: Tech Corp, First employee: John (Developer)';
    passed := test_result = expected;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Complex nested structure interpolation: PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Complex nested structure interpolation: FAILED. Expected "%", got "%"', 
            total_tests, expected, test_result;
    END IF;

    -- Test 9: Multiple interpolations in text
    total_tests := total_tests + 1;
    test_result := hemar.render(
        '{"greeting": "Hello", "name": "John", "punctuation": "!"}'::jsonb,
        '{{ greeting }} {{ name }}{{ punctuation }} How are you {{ name }}?'
    );
    expected := 'Hello John! How are you John?';
    passed := test_result = expected;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Multiple interpolations in text: PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Multiple interpolations in text: FAILED. Expected "%", got "%"', 
            total_tests, expected, test_result;
    END IF;

    -- Test 10: Invalid path handling
    total_tests := total_tests + 1;
    test_result := hemar.render(
        '{"name": "John"}'::jsonb,
        'Name: {{ name }}, Age: {{ age }}, Address: {{ address.street }}'
    );
    expected := 'Name: John, Age: , Address: ';
    passed := test_result = expected;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Invalid path handling: PASSED', total_tests;
    ELSE
        RAISE WARNING 'Test %: Invalid path handling: FAILED. Expected "%", got "%"', 
            total_tests, expected, test_result;
    END IF;

    -- Print summary
    IF passed_tests = total_tests THEN
        RAISE NOTICE '------------------------------------';
        RAISE NOTICE 'SUMMARY: % of % interpolation render tests passed (100%%)', 
            passed_tests, total_tests;
        RAISE NOTICE '------------------------------------';
    ELSE
        RAISE WARNING '------------------------------------';
        RAISE WARNING 'SUMMARY: % of % interpolation render tests passed (%)', 
            passed_tests, 
            total_tests, 
            round((passed_tests::numeric / total_tests::numeric) * 100, 2) || '%';
        RAISE WARNING '------------------------------------';
    END IF;

    IF passed_tests != total_tests THEN
      RAISE EXCEPTION 'Tests failed: % of % interpolation render tests did not pass', (total_tests - passed_tests), total_tests;
    END IF;
END $$; 