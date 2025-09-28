-- Test include tag functionality
DO $$
DECLARE
    result text;
    total_tests integer := 0;
    passed_tests integer := 0;
BEGIN
    -- Test 1: Plain text inclusion
    total_tests := total_tests + 1;
    BEGIN
        result := hemar.render(
            '{
                "include": {
                    "inner_template": {
                        "content": "<p>Hello World</p>"
                    }
                }
            }'::jsonb,
            $hemar${{ include inner_template }}$hemar$
        );
    
        IF result = '<p>Hello World</p>' THEN
            RAISE NOTICE 'Test %: Plain text inclusion works correctly', total_tests;
            passed_tests := passed_tests + 1;
        ELSE
            RAISE WARNING 'Test %: failed, Expected "<p>Hello World</p>", got "%"', total_tests, result;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Test %: Plain text inclusion: FAILED with error: %', total_tests, SQLERRM;
    END;

    -- Test 2: Template with separate context
    total_tests := total_tests + 1;
    result := hemar.render(
        '{
            "include": {
                "inner_template": {
                    "template": "Hello {{ name }}!",
                    "context": {
                        "name": "John"
                    }
                }
            }
        }'::jsonb,
        $hemar${{ include inner_template }}$hemar$
    );
    
    IF result = 'Hello John!' THEN
        RAISE NOTICE 'Test %: Template with separate context works correctly', total_tests;
        passed_tests := passed_tests + 1;
    ELSE
        RAISE WARNING 'Test %: failed, Expected "Hello John!", got "%"', total_tests, result;
    END IF;

    -- Test 3: Template with shared context
    total_tests := total_tests + 1;
    result := hemar.render(
        '{
            "name": "John",
            "include": {
                "inner_template": {
                    "template": "Hello {{ name }}!"
                }
            }
        }'::jsonb,
        $hemar${{ include inner_template }}$hemar$
    );
    
    IF result = 'Hello John!' THEN
        RAISE NOTICE 'Test % passed: Template with shared context works correctly', total_tests;
        passed_tests := passed_tests + 1;
    ELSE
        RAISE WARNING 'Test % failed: Expected "Hello John!", got "%"', total_tests, result;
    END IF;

    -- Test 4: Nested includes
    total_tests := total_tests + 1;
    result := hemar.render(
        '{
            "include": {
                "outer_template": {
                    "template": "Outer: {{ include inner_template }}",
                    "context": {
                        "include": {
                            "inner_template": {
                                "template": "Inner: {{ name }}",
                                "context": {
                                    "name": "John"
                                }
                            }
                        }
                    }
                }
            }
        }'::jsonb,
        $hemar${{ include outer_template }}$hemar$
    );
    
    IF result = 'Outer: Inner: John' THEN
        RAISE NOTICE 'Test % passed: Nested includes work correctly', total_tests;
        passed_tests := passed_tests + 1;
    ELSE
        RAISE WARNING 'Test % failed: Expected "Outer: Inner: John", got "%"', total_tests, result;
    END IF;

    -- Test 5: Complex template with multiple includes
    total_tests := total_tests + 1;
    result := hemar.render(
        '{
            "include": {
                "header": {
                    "content": "<header>Welcome</header>"
                },
                "content": {
                    "template": "Hello {{ user.name }}!",
                    "context": {
                        "user": {
                            "name": "John"
                        }
                    }
                },
                "footer": {
                    "template": "Copyright {{ year }}",
                    "context": {
                        "year": "2024"
                    }
                }
            }
        }'::jsonb,
        $hemar$Header: {{ include header }}
        Content: {{ include content }}
        Footer: {{ include footer }}$hemar$
    );
    
    IF result = 'Header: <header>Welcome</header>
        Content: Hello John!
        Footer: Copyright 2024' THEN
        RAISE NOTICE 'Test % passed: Complex template with multiple includes works correctly', total_tests;
        passed_tests := passed_tests + 1;
    ELSE
        RAISE WARNING 'Test % failed: Expected , got "%"', total_tests, result;
    END IF;

    -- Test 6: Error handling - missing include data
    total_tests := total_tests + 1;
    BEGIN
        result := hemar.render(
            '{{ include missing_template }}',
            '{}'::jsonb
        );
        RAISE WARNING 'Test % failed: Should have raised an error for missing include data', total_tests;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'Test % passed: Error handling for missing include data works correctly', total_tests;
	        passed_tests := passed_tests + 1;
    END;

    -- Test 7: Error handling - invalid include data
    total_tests := total_tests + 1;
    BEGIN
        result := hemar.render(
                '{
                    "include": {
                    "invalid_template": "not an object"
                }
            }'::jsonb,
            '{{ include invalid_template }}'
        );

        IF result = '' THEN
            RAISE NOTICE 'Test % passed: Error handling for invalid include data works correctly', total_tests;
            passed_tests := passed_tests + 1;
        ELSE
            RAISE WARNING 'Test % failed: Expected "", got "%"', total_tests, result;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Test % failed: Should have raised an error for invalid include data', total_tests;
    END;

    -- Test 8: Error handling - unexisting include object
    total_tests := total_tests + 1;
    BEGIN
        result := hemar.render(
                '{}'::jsonb,
            '{{ include invalid_template }}'
        );

        IF result = '' THEN
            RAISE NOTICE 'Test % passed: Error handling for unexisting include object works correctly', total_tests;
            passed_tests := passed_tests + 1;
        ELSE
            RAISE WARNING 'Test % failed: Expected "", got "%"', total_tests, result;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Test % failed: Should have raised an error for unexisting include object', total_tests;
    END;

    -- Test 9: Error handling - unexisting include data
    total_tests := total_tests + 1;
    BEGIN
        result := hemar.render(
                '{
                    "include": { }
                }'::jsonb,
            '{{ include invalid_template }}'
        );

        IF result = '' THEN
            RAISE NOTICE 'Test % passed: Error handling for unexisting include data works correctly', total_tests;
            passed_tests := passed_tests + 1;
        ELSE
            RAISE WARNING 'Test % failed: Expected "", got "%"', total_tests, result;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Test % failed: Should have raised an error for unexisting include data', total_tests;
    END;

    IF passed_tests = total_tests THEN
        RAISE NOTICE '------------------------------------';
        RAISE NOTICE 'SUMMARY: % of % template include tests passed (100%%)', 
            passed_tests, total_tests;
        RAISE NOTICE '------------------------------------';
    ELSE
        RAISE WARNING '------------------------------------';
        RAISE WARNING 'SUMMARY: % of % template include tests passed (%)', 
            passed_tests, 
            total_tests, 
            round((passed_tests::numeric / total_tests::numeric) * 100, 2) || '%';
        RAISE WARNING '------------------------------------';
    END IF;

    IF passed_tests != total_tests THEN
      RAISE EXCEPTION 'Tests failed: % of % template include tests did not pass', (total_tests - passed_tests), total_tests;
    END IF;
END $$; 
