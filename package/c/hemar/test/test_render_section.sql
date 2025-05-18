-- Test section rendering
DO $$
DECLARE
    test_result text;
    expected text;
BEGIN
    -- Test 1: String iteration
    test_result := hemar.render(
        '{"text": "Hello"}'::jsonb,
        '{{for char in text}}{{char}}{{end}}'
    );
    expected := 'Hello';
    ASSERT test_result = expected, format('Test 1: String iteration: FAILED. Expected "%s", got "%s"', expected, test_result);
    RAISE NOTICE 'Test 1: String iteration: PASSED';

    -- Test 2: Array iteration
    test_result := hemar.render(
        '{"numbers": [1, 2, 3]}'::jsonb,
        '{{for num in numbers}}{{num}}{{end}}'
    );
    expected := '123';
    ASSERT test_result = expected, format('Test 2: Array iteration: FAILED. Expected "%s", got "%s"', expected, test_result);
    RAISE NOTICE 'Test 2: Array iteration: PASSED';

    -- Test 3: Object iteration
    test_result := hemar.render(
        '{"user": {"name": "John", "age": 30}}'::jsonb,
        '{{for item in user}}{{item.key}}: {{item.value}}{{end}}'
    );
    expected := 'name: Johnage: 30';
    ASSERT test_result = expected, format('Test 3: Object iteration: FAILED. Expected "%s", got "%s"', expected, test_result);
    RAISE NOTICE 'Test 3: Object iteration: PASSED';

    -- Test 4: Boolean condition (true)
    test_result := hemar.render(
        '{"show": true}'::jsonb,
        '{{for show in show}}Content{{end}}'
    );
    expected := 'Content';
    ASSERT test_result = expected, format('Test 4: Boolean condition (true): FAILED. Expected "%s", got "%s"', expected, test_result);
    RAISE NOTICE 'Test 4: Boolean condition (true): PASSED';

    -- Test 5: Boolean condition (false)
    test_result := hemar.render(
        '{"show": false}'::jsonb,
        '{{for show in show}}Content{{end}}'
    );
    expected := '';
    ASSERT test_result = expected, format('Test 5: Boolean condition (false): FAILED. Expected "%s", got "%s"', expected, test_result);
    RAISE NOTICE 'Test 5: Boolean condition (false): PASSED';

    -- Test 6: Nested sections
    test_result := hemar.render(
        '{"items": [{"name": "Item 1", "tags": ["tag1", "tag2"]}, {"name": "Item 2", "tags": ["tag3"]}]}'::jsonb,
        '{{for item in items}}{{item.name}}: {{for tag in item.tags}}{{tag}} {{end}}{{end}}'
    );
    expected := 'Item 1: tag1 tag2 Item 2: tag3 ';
    ASSERT test_result = expected, format('Test 6: Nested sections: FAILED. Expected "%s", got "%s"', expected, test_result);
    RAISE NOTICE 'Test 6: Nested sections: PASSED';

    -- Test 7: Section with context
    test_result := hemar.render(
        '{"items": ["a", "b"], "prefix": "Item: "}'::jsonb,
        '{{for item in items}}{{prefix}}{{item}}{{end}}'
    );
    expected := 'Item: aItem: b';
    ASSERT test_result = expected, format('Test 7: Section with context: FAILED. Expected "%s", got "%s"', expected, test_result);
    RAISE NOTICE 'Test 7: Section with context: PASSED';

    -- Test 8: Empty array
    test_result := hemar.render(
        '{"items": []}'::jsonb,
        '{{for item in items}}{{item}}{{end}}'
    );
    expected := '';
    ASSERT test_result = expected, format('Test 8: Empty array: FAILED. Expected "%s", got "%s"', expected, test_result);
    RAISE NOTICE 'Test 8: Empty array: PASSED';

    -- Test 9: Empty object
    test_result := hemar.render(
        '{"user": {}}'::jsonb,
        '{{for key in user}}{{key}}{{end}}'
    );
    expected := '';
    ASSERT test_result = expected, format('Test 9: Empty object: FAILED. Expected "%s", got "%s"', expected, test_result);
    RAISE NOTICE 'Test 9: Empty object: PASSED';

    -- Test 10: Invalid collection type (number)
    test_result := hemar.render(
        '{"number": 42}'::jsonb,
        '{{for item in number}}{{item}}{{end}}'
    );
    expected := '';
    ASSERT test_result = expected, format('Test 10: Invalid collection type: FAILED. Expected "%s", got "%s"', expected, test_result);
    RAISE NOTICE 'Test 10: Invalid collection type: PASSED (error raised as expected)';

    RAISE NOTICE 'All section rendering tests completed successfully!';
END $$; 