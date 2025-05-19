-- Test all template tags together
CREATE OR REPLACE FUNCTION pg_temp.diff(string1 text, string2 text) RETURNS TABLE("index" int, char1 text, char2 text) AS $$
BEGIN
    RETURN QUERY WITH 
        s1 AS (SELECT string1 AS str),
        s2 AS (SELECT string2 AS str)
    SELECT i,
        substring(s1.str FROM i FOR 1) AS char1,
        substring(s2.str FROM i FOR 1) AS char2
    FROM s1, s2,
        generate_series(1, GREATEST(length(s1.str), length(s2.str))) AS i
    WHERE substring(s1.str FROM i FOR 1) IS DISTINCT FROM substring(s2.str FROM i FOR 1);

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pg_temp.test_regexp_replace(string text) RETURNS text AS $$
BEGIN
    RETURN regexp_replace(
             regexp_replace(
               regexp_replace(
                 regexp_replace(
                   regexp_replace(string, E'\t', '[TAB]', 'g'),
                 E'\n', '[LF]', 'g'),
               E'\r', '[CR]', 'g'),
             ' ', '[SPACE]', 'g'),
           '\s', '[WHITESPACE]', 'g');
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    total_tests INT := 0;
    passed_tests INT := 0;
    test_result TEXT;
    expected TEXT;
    passed BOOLEAN;
    item INT;
    c1 TEXT;
    c2 TEXT;
BEGIN
    -- Test 1: Template with execute tag using context from section
    total_tests := total_tests + 1;
    BEGIN
        test_result := hemar.render(
            '{
                "items": [
                    {"id": 1, "value": 100},
                    {"id": 2, "value": 200},
                    {"id": 3, "value": 300}
                ]
            }'::jsonb,
            $template$Items:{{ for item in items }}
    Item {{ item.id }}: {{ exec RETURN (context->'item'->>'value')::int * 2; }}
{{ end }}$template$
        );
    
        expected:='Items:
    Item 1: 200
    Item 2: 400
    Item 3: 600
';
    
        passed := test_result = expected;
        passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
        IF passed THEN
            RAISE NOTICE 'Test %: Template with execute tag using context from section: PASSED', total_tests;
        ELSE
            RAISE WARNING 'Test %: Template with execute tag using context from section: FAILED. Expected "%", got "%"', 
                total_tests, pg_temp.test_regexp_replace(expected), pg_temp.test_regexp_replace(test_result);
            FOR item, c1, c2 IN 
                SELECT * FROM pg_temp.diff(expected, test_result)
            LOOP
                RAISE NOTICE ' % | % | %', item, c1, c2;
            END LOOP;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Test % failed: Error: %', total_tests, SQLERRM;
    END;

    -- Test 2: Complex template with all tag types
    total_tests := total_tests + 1;
    BEGIN
        test_result := hemar.render(
            '{
                "page": {
                    "title": "My Page",
                    "sections": [
                        {
                            "id": "section1",
                            "title": "Section 1",
                            "items": [
                                {
                                    "id": "item1",
                                    "status": "active",
                                    "content": "Item 1 Content",
                                    "template": "item_template"
                                },
                                {
                                    "id": "item2",
                                    "status": "inactive",
                                    "content": "Item 2 Content",
                                    "template": "item_template"
                                }
                            ]
                        }
                    ]
                },
                "include": {
                    "meta_tags": {
                        "content": "<meta name=\"description\" content=\"Test Page\">"
                    },
                    "header": {
                        "template": "Welcome to {{ page.title }}!",
                        "context": {
                            "page": {
                                "title": "My Page"
                            }
                        }
                    },
                    "item_template": {
                        "template": "Status: {{ status }}, Content: {{ content }}"
                    },
                    "footer": {
                        "content": "<footer>Copyright 2024</footer>"
                    }
                }
            }'::jsonb,
            $template$<!DOCTYPE html>
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
                        {{ include item.template }}
                        {{ exec
                            DECLARE
                                v_status TEXT;
                            BEGIN
                                v_status := context->'item'->>'status';
                                RETURN CASE 
                                    WHEN v_status = 'active' THEN ' (Active Item)'
                                    ELSE ' (Inactive Item)'
                                END;
                            END;
                        }}
                    </div>
                {{ end }}
            </section>
        {{ end }}
    </main>
    <footer>{{ include footer }}</footer>
</body>
</html>$template$
        );
    
        expected := '<!DOCTYPE html>
<html>
<head>
    <title>My Page</title>
    <meta name="description" content="Test Page">
</head>
<body>
    <header>Welcome to My Page!</header>
    <main>
        <section id="section1">
            <h2>Section 1</h2>
            <div class="item active">
                Status: active, Content: Item 1 Content (Active Item)
            </div>
            <div class="item inactive">
                Status: inactive, Content: Item 2 Content (Inactive Item)
            </div>
        </section>
    </main>
    <footer><footer>Copyright 2024</footer></footer>
</body>
</html>';
        
        passed := test_result = expected;
        passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
        IF passed THEN
            RAISE NOTICE 'Test %: Complex template with all tag types: PASSED', total_tests;
        ELSE
            RAISE WARNING 'Test %: Complex template with all tag types: FAILED. Expected "%", got "%"', 
                total_tests, expected, test_result;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Test % failed: Error: %', total_tests, SQLERRM;
    END;
        
    -- Test 3: Template with nested includes and shared context
    total_tests := total_tests + 1;
    BEGIN
        test_result := hemar.render(
            '{
                "user": {
                    "name": "John",
                    "role": "admin"
                },
                "include": {
                    "user_info": {
                        "template": "User: {{ user.name }} ({{ user.role }})"
                    },
                    "permissions": {
                        "template": "{{ include user_info }} - Permissions: {{ for perm in user.permissions }}{{ perm }} {{ end }}",
                        "context": {
                            "user": {
                                "name": "John",
                                "role": "admin",
                                "permissions": ["read", "write", "delete"]
                            }
                        }
                    }
                }
            }'::jsonb,
            $template${{ include permissions }}$template$
        );
    
        expected := 'User: John (admin) - Permissions: read write delete ';
    
        passed := test_result = expected;
        passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
        IF passed THEN
            RAISE NOTICE 'Test %: Template with nested includes and shared context: PASSED', total_tests;
        ELSE
            RAISE WARNING 'Test %: Template with nested includes and shared context: FAILED. Expected "%", got "%"', 
                total_tests, expected, test_result;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Test % failed: Error: %', total_tests, SQLERRM;
    END;

    -- Test 4: Template with execute tag using context from section
    total_tests := total_tests + 1;
    BEGIN
        test_result := hemar.render(
            '{
                "items": [
                    {"id": 1, "value": 100},
                    {"id": 2, "value": 200},
                    {"id": 3, "value": 300}
                ]
            }'::jsonb,
            $template$Items:
{{ for item in items }}
    Item {{ item.id }}: {{ exec
        DECLARE
            v_value INT;
        BEGIN
            v_value := (context->>'value')::int;
            RETURN v_value * 2;
        END;
    }}
{{ end }}$template$
        );
    
        expected := 'Items:
    Item 1: 200
    Item 2: 400
    Item 3: 600
';
    
        passed := test_result = expected;
        passed_tests := passed_tests + (CASE WHEN passed THEN 1 ELSE 0 END);
        IF passed THEN
            RAISE NOTICE 'Test %: Template with execute tag using context from section: PASSED', total_tests;
        ELSE
            RAISE WARNING 'Test %: Template with execute tag using context from section: FAILED. Expected "%", got "%"', 
                total_tests, expected, test_result;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Test % failed: Error: %', total_tests, SQLERRM;
    END;

    -- Print summary
    IF passed_tests = total_tests THEN
        RAISE NOTICE '------------------------------------';
        RAISE NOTICE 'SUMMARY: % of % combined template tests passed (100%%)', 
            passed_tests, total_tests;
        RAISE NOTICE '------------------------------------';
    ELSE
        RAISE WARNING '------------------------------------';
        RAISE WARNING 'SUMMARY: % of % combined template tests passed (%)', 
            passed_tests, 
            total_tests, 
            round((passed_tests::numeric / total_tests::numeric) * 100, 2) || '%';
        RAISE WARNING '------------------------------------';
    END IF;

    IF passed_tests != total_tests THEN
      RAISE EXCEPTION 'Tests failed: % of % combined template tests did not pass', (total_tests - passed_tests), total_tests;
    END IF;
END $$; 