
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
