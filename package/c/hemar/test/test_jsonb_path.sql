-- Test file for hemar.jsonb_get_by_path function
-- Run with: psql -f test_jsonb_path.sql

-- Load extension if not already loaded
-- CREATE EXTENSION IF NOT EXISTS hemar;

-- Create sample test data
DO $$
DECLARE
    test_json jsonb;
    result jsonb;
    passed boolean;
    total_tests integer := 0;
    passed_tests integer := 0;
    current_path text;
BEGIN
    test_json := jsonb_build_object(
        'name', 'John Doe',
        'age', 30,
        'is_active', true,
        'tags', jsonb_build_array('developer', 'postgresql', 'jsonb'),
        'address', jsonb_build_object(
            'street', '123 Main St',
            'city', 'New York',
            'zip', '10001'
        ),
        'contacts', jsonb_build_array(
            jsonb_build_object(
                'type', 'email',
                'value', 'john@example.com'
            ),
            jsonb_build_object(
                'type', 'phone',
                'value', '555-1234',
                'verified', true
            )
        ),
        'skills', jsonb_build_array(
            jsonb_build_array('PostgreSQL', 5),
            jsonb_build_array('Python', 4),
            jsonb_build_array('JavaScript', 3)
        )
    );

    -- Test basic field access
    total_tests := total_tests + 1;
    current_path := 'name';
    result := hemar.jsonb_get_by_path(test_json, current_path);
    passed := result = '"John Doe"'::jsonb;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Simple field access (path="%"): % | PASSED: %', 
            total_tests, current_path, result, passed;
    ELSE
        RAISE WARNING 'Test %: Simple field access (path="%"): % | PASSED: % (expected: "John Doe")', 
            total_tests, current_path, result, passed;
    END IF;
    
    total_tests := total_tests + 1;
    current_path := 'age';
    result := hemar.jsonb_get_by_path(test_json, current_path);
    passed := result = '30'::jsonb;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Numeric field access (path="%"): % | PASSED: %', 
            total_tests, current_path, result, passed;
    ELSE
        RAISE WARNING 'Test %: Numeric field access (path="%"): % | PASSED: % (expected: 30)', 
            total_tests, current_path, result, passed;
    END IF;
    
    total_tests := total_tests + 1;
    current_path := 'is_active';
    result := hemar.jsonb_get_by_path(test_json, current_path);
    passed := result = 'true'::jsonb;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Boolean field access (path="%"): % | PASSED: %', 
            total_tests, current_path, result, passed;
    ELSE
        RAISE WARNING 'Test %: Boolean field access (path="%"): % | PASSED: % (expected: true)', 
            total_tests, current_path, result, passed;
    END IF;
    
    -- Test nested field access
    total_tests := total_tests + 1;
    current_path := 'address.city';
    result := hemar.jsonb_get_by_path(test_json, current_path);
    passed := result = '"New York"'::jsonb;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Nested object field access (path="%"): % | PASSED: %', 
            total_tests, current_path, result, passed;
    ELSE
        RAISE WARNING 'Test %: Nested object field access (path="%"): % | PASSED: % (expected: "New York")', 
            total_tests, current_path, result, passed;
    END IF;
    
    -- Test array access
    total_tests := total_tests + 1;
    current_path := 'tags[1]';
    result := hemar.jsonb_get_by_path(test_json, current_path);
    passed := result = '"postgresql"'::jsonb;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Simple array access (path="%"): % | PASSED: %', 
            total_tests, current_path, result, passed;
    ELSE
        RAISE WARNING 'Test %: Simple array access (path="%"): % | PASSED: % (expected: "postgresql")', 
            total_tests, current_path, result, passed;
    END IF;
    
    total_tests := total_tests + 1;
    current_path := 'contacts[0].type';
    result := hemar.jsonb_get_by_path(test_json, current_path);
    passed := result = '"email"'::jsonb;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Object in array access (path="%"): % | PASSED: %', 
            total_tests, current_path, result, passed;
    ELSE
        RAISE WARNING 'Test %: Object in array access (path="%"): % | PASSED: % (expected: "email")', 
            total_tests, current_path, result, passed;
    END IF;
    
    total_tests := total_tests + 1;
    current_path := 'skills[1][0]';
    result := hemar.jsonb_get_by_path(test_json, current_path);
    passed := result = '"Python"'::jsonb;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Nested array access (path="%"): % | PASSED: %', 
            total_tests, current_path, result, passed;
    ELSE
        RAISE WARNING 'Test %: Nested array access (path="%"): % | PASSED: % (expected: "Python")', 
            total_tests, current_path, result, passed;
    END IF;
    
    total_tests := total_tests + 1;
    current_path := 'contacts[1].value';
    result := hemar.jsonb_get_by_path(test_json, current_path);
    passed := result = '"555-1234"'::jsonb;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Complex path with multiple array indices (path="%"): % | PASSED: %', 
            total_tests, current_path, result, passed;
    ELSE
        RAISE WARNING 'Test %: Complex path with multiple array indices (path="%"): % | PASSED: % (expected: "555-1234")', 
            total_tests, current_path, result, passed;
    END IF;
    
    -- Test object and array returns
    total_tests := total_tests + 1;
    current_path := 'address';
    result := hemar.jsonb_get_by_path(test_json, current_path);
    passed := jsonb_typeof(result) = 'object';
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Path to object (path="%"): % | PASSED: %', 
            total_tests, current_path, result, passed;
    ELSE
        RAISE WARNING 'Test %: Path to object (path="%"): % | PASSED: % (expected type: object, got: %)', 
            total_tests, current_path, result, passed, jsonb_typeof(result);
    END IF;
    
    total_tests := total_tests + 1;
    current_path := 'contacts';
    result := hemar.jsonb_get_by_path(test_json, current_path);
    passed := jsonb_typeof(result) = 'array';
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Path to array (path="%"): % | PASSED: %', 
            total_tests, current_path, result, passed;
    ELSE
        RAISE WARNING 'Test %: Path to array (path="%"): % | PASSED: % (expected type: array, got: %)', 
            total_tests, current_path, result, passed, jsonb_typeof(result);
    END IF;
    
    -- Test error cases
    total_tests := total_tests + 1;
    current_path := 'unknown_field';
    result := hemar.jsonb_get_by_path(test_json, current_path);
    passed := result IS NULL;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Non-existent field (path="%"): % | PASSED: %', 
            total_tests, current_path, result, passed;
    ELSE
        RAISE WARNING 'Test %: Non-existent field (path="%"): % | PASSED: % (expected: NULL)', 
            total_tests, current_path, result, passed;
    END IF;
    
    total_tests := total_tests + 1;
    current_path := 'address.country';
    result := hemar.jsonb_get_by_path(test_json, current_path);
    passed := result IS NULL;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);

    IF passed THEN
        RAISE NOTICE 'Test %: Non-existent nested field (path="%"): % | PASSED: %', 
            total_tests, current_path, result, passed;
    ELSE
        RAISE WARNING 'Test %: Non-existent nested field (path="%"): % | PASSED: % (expected: NULL)', 
            total_tests, current_path, result, passed;
    END IF;
    
    total_tests := total_tests + 1;
    current_path := 'tags[10]';
    result := hemar.jsonb_get_by_path(test_json, current_path);
    passed := result IS NULL;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Array index out of bounds (path="%"): % | PASSED: %', 
            total_tests, current_path, result, passed;
    ELSE
        RAISE WARNING 'Test %: Array index out of bounds (path="%"): % | PASSED: % (expected: NULL)', 
            total_tests, current_path, result, passed;
    END IF;
        
    -- Test edge cases
    total_tests := total_tests + 1;
    current_path := '';
    result := hemar.jsonb_get_by_path(test_json, current_path);
    passed := result IS NULL;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Empty path (path="%"): % | PASSED: %', 
            total_tests, current_path, result, passed;
    ELSE
        RAISE WARNING 'Test %: Empty path (path="%"): % | PASSED: % (expected: NULL)', 
            total_tests, current_path, result, passed;
    END IF;
        
    total_tests := total_tests + 1;
    current_path := 'skills[0][1]';
    result := hemar.jsonb_get_by_path(test_json, current_path);
    passed := result = '5'::jsonb;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Multiple array indices (path="%"): % | PASSED: %', 
            total_tests, current_path, result, passed;
    ELSE
        RAISE WARNING 'Test %: Multiple array indices (path="%"): % | PASSED: % (expected: 5)', 
            total_tests, current_path, result, passed;
    END IF;
        
    -- Additional complex test cases
    
    -- Test 16: Deep nested object access
    total_tests := total_tests + 1;
    test_json := jsonb_build_object(
        'level1', jsonb_build_object(
            'level2', jsonb_build_object(
                'level3', jsonb_build_object(
                    'level4', jsonb_build_object(
                        'value', 'deep nested value'
                    )
                )
            )
        )
    );
    current_path := 'level1.level2.level3.level4.value';
    result := hemar.jsonb_get_by_path(test_json, current_path);
    passed := result = '"deep nested value"'::jsonb;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Deep nested object access (path="%"): % | PASSED: %', 
            total_tests, current_path, result, passed;
    ELSE
        RAISE WARNING 'Test %: Deep nested object access (path="%"): % | PASSED: % (expected: "deep nested value")', 
            total_tests, current_path, result, passed;
    END IF;
    
    -- Test 17: Deep nested array access
    total_tests := total_tests + 1;
    test_json := jsonb_build_array(
        jsonb_build_array(
            jsonb_build_array(
                jsonb_build_array(
                    'nested array value'
                )
            )
        )
    );
    current_path := '[0][0][0][0]';
    result := hemar.jsonb_get_by_path(test_json, current_path);
    passed := result = '"nested array value"'::jsonb;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Deep nested array access (path="%"): % | PASSED: %', 
            total_tests, current_path, result, passed;
    ELSE
        RAISE WARNING 'Test %: Deep nested array access (path="%"): % | PASSED: % (expected: "nested array value")', 
            total_tests, current_path, result, passed;
    END IF;
    
    -- Test 18: Complex mixed nesting (object -> array -> object -> array)
    total_tests := total_tests + 1;
    test_json := jsonb_build_object(
        'users', jsonb_build_array(
            jsonb_build_object(
                'name', 'Alice',
                'permissions', jsonb_build_array('read', 'write', 'admin')
            ),
            jsonb_build_object(
                'name', 'Bob',
                'permissions', jsonb_build_array('read', 'write')
            )
        )
    );
    current_path := 'users[1].permissions[0]';
    result := hemar.jsonb_get_by_path(test_json, current_path);
    passed := result = '"read"'::jsonb;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Complex mixed nesting (path="%"): % | PASSED: %', 
            total_tests, current_path, result, passed;
    ELSE
        RAISE WARNING 'Test %: Complex mixed nesting (path="%"): % | PASSED: % (expected: "read")', 
            total_tests, current_path, result, passed;
    END IF;
    
    -- Test 19: Array with mixed types
    total_tests := total_tests + 1;
    test_json := jsonb_build_array(
        'string',
        42,
        true,
        jsonb_build_object('key', 'value'),
        jsonb_build_array(1, 2, 3)
    );
    current_path := '[3].key';
    result := hemar.jsonb_get_by_path(test_json, current_path);
    passed := result = '"value"'::jsonb;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Array with mixed types (path="%"): % | PASSED: %', 
            total_tests, current_path, result, passed;
    ELSE
        RAISE WARNING 'Test %: Array with mixed types (path="%"): % | PASSED: % (expected: "value")', 
            total_tests, current_path, result, passed;
    END IF;
    
    -- Test 20: Path with array at the end
    total_tests := total_tests + 1;
    test_json := jsonb_build_object(
        'data', jsonb_build_object(
            'items', jsonb_build_array(10, 20, 30, 40)
        )
    );
    current_path := 'data.items[2]';
    result := hemar.jsonb_get_by_path(test_json, current_path);
    passed := result = '30'::jsonb;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Path with array at the end (path="%"): % | PASSED: %', 
            total_tests, current_path, result, passed;
    ELSE
        RAISE WARNING 'Test %: Path with array at the end (path="%"): % | PASSED: % (expected: 30)', 
            total_tests, current_path, result, passed;
    END IF;
    
    -- Test 21: Numeric field names
    total_tests := total_tests + 1;
    test_json := jsonb_build_object(
        '123', 'numeric key',
        '456', jsonb_build_object(
            '789', 'nested numeric key'
        )
    );
    current_path := '456.789';
    result := hemar.jsonb_get_by_path(test_json, current_path);
    passed := result = '"nested numeric key"'::jsonb;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Numeric field names (path="%"): % | PASSED: %', 
            total_tests, current_path, result, passed;
    ELSE
        RAISE WARNING 'Test %: Numeric field names (path="%"): % | PASSED: % (expected: "nested numeric key")', 
            total_tests, current_path, result, passed;
    END IF;
    
    -- Test 22: Special characters in field names
    total_tests := total_tests + 1;
    test_json := jsonb_build_object(
        'special@field', 'special value',
        'nested', jsonb_build_object(
            'field-with-hyphens', 'hyphenated value'
        )
    );
    current_path := 'nested.field-with-hyphens';
    result := hemar.jsonb_get_by_path(test_json, current_path);
    passed := result = '"hyphenated value"'::jsonb;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Special characters in field names (path="%"): % | PASSED: %', 
            total_tests, current_path, result, passed;
    ELSE
        RAISE WARNING 'Test %: Special characters in field names (path="%"): % | PASSED: % (expected: "hyphenated value")', 
            total_tests, current_path, result, passed;
    END IF;
    
    -- Test 23: Array of arrays of arrays
    total_tests := total_tests + 1;
    test_json := jsonb_build_array(
        jsonb_build_array(
            jsonb_build_array(1, 2),
            jsonb_build_array(3, 4)
        ),
        jsonb_build_array(
            jsonb_build_array(5, 6),
            jsonb_build_array(7, 8)
        )
    );
    current_path := '[1][0][1]';
    result := hemar.jsonb_get_by_path(test_json, current_path);
    passed := result = '6'::jsonb;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Array of arrays of arrays (path="%"): % | PASSED: %', 
            total_tests, current_path, result, passed;
    ELSE
        RAISE WARNING 'Test %: Array of arrays of arrays (path="%"): % | PASSED: % (expected: 6)', 
            total_tests, current_path, result, passed;
    END IF;
    
    -- Test 24: Complex path with multiple array indices and object fields
    total_tests := total_tests + 1;
    test_json := jsonb_build_object(
        'companies', jsonb_build_array(
            jsonb_build_object(
                'name', 'Company A',
                'departments', jsonb_build_array(
                    jsonb_build_object(
                        'name', 'Engineering',
                        'teams', jsonb_build_array(
                            jsonb_build_object(
                                'name', 'Backend',
                                'members', jsonb_build_array(
                                    jsonb_build_object('name', 'John', 'role', 'Developer'),
                                    jsonb_build_object('name', 'Jane', 'role', 'Lead')
                                )
                            )
                        )
                    )
                )
            )
        )
    );
    current_path := 'companies[0].departments[0].teams[0].members[1].role';
    result := hemar.jsonb_get_by_path(test_json, current_path);
    passed := result = '"Lead"'::jsonb;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Very complex path (path="%"): % | PASSED: %', 
            total_tests, current_path, result, passed;
    ELSE
        RAISE WARNING 'Test %: Very complex path (path="%"): % | PASSED: % (expected: "Lead")', 
            total_tests, current_path, result, passed;
    END IF;
    
    -- Test 25: Empty array and object edge cases
    total_tests := total_tests + 1;
    test_json := jsonb_build_object(
        'emptyArray', jsonb_build_array(),
        'emptyObject', jsonb_build_object(),
        'arrayWithEmptyObject', jsonb_build_array(jsonb_build_object()),
        'objectWithEmptyArray', jsonb_build_object('empty', jsonb_build_array())
    );
    current_path := 'objectWithEmptyArray.empty';
    result := hemar.jsonb_get_by_path(test_json, current_path);
    passed := jsonb_typeof(result) = 'array' AND jsonb_array_length(result) = 0;
    passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
    IF passed THEN
        RAISE NOTICE 'Test %: Empty array/object edge cases (path="%"): % | PASSED: %', 
            total_tests, current_path, result, passed;
    ELSE
        RAISE WARNING 'Test %: Empty array/object edge cases (path="%"): % | PASSED: % (expected: empty array)', 
            total_tests, current_path, result, passed;
    END IF;
        
    -- Print summary
    IF passed_tests = total_tests THEN
        RAISE NOTICE '------------------------------------';
        RAISE NOTICE 'SUMMARY: % of % jsonb_get_by_path tests passed (100%%)', 
            passed_tests, total_tests;
        RAISE NOTICE '------------------------------------';
    ELSE
        RAISE WARNING '------------------------------------';
        RAISE WARNING 'SUMMARY: % of % jsonb_get_by_path tests passed (%)', 
            passed_tests, 
            total_tests, 
            round((passed_tests::numeric / total_tests::numeric) * 100, 2) || '%';
        RAISE WARNING '------------------------------------';
    END IF;

    IF passed_tests != total_tests THEN
      RAISE EXCEPTION 'Tests failed: % of % jsonb_get_by_path tests did not pass', (total_tests - passed_tests), total_tests;
    END IF;
END $$; 