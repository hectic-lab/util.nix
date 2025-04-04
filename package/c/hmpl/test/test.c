#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "hmpl.h"
#include "hectic.h"

#define TEST_DATA_INTERPOLATION_CONTEXT        \
  "{\n"                                        \
  "  \"persona\": {\n"                         \
  "    \"name\": \"John\",\n"                  \
  "    \"surname\": \"Doe\",\n"                \
  "    \"address\": {\n"                       \
  "      \"home\": {\n"                        \
  "        \"street\": \"123 Main St\",\n"     \
  "        \"city\": \"Springfield\",\n"       \
  "        \"zip\": \"12345\"\n"               \
  "      },\n"                                 \
  "      \"work\": {\n"                        \
  "        \"street\": \"456 Business Rd\",\n" \
  "        \"city\": \"Metropolis\",\n"        \
  "        \"zip\": \"67890\"\n"               \
  "      }\n"                                  \
  "    },\n"                                   \
  "    \"contact\": {\n"                       \
  "      \"email\": \"john@example.com\",\n"   \
  "      \"phone\": {\n"                       \
  "        \"home\": \"555-1234\",\n"          \
  "        \"mobile\": \"555-5678\"\n"         \
  "      }\n"                                  \
  "    }\n"                                    \
  "  }\n"                                      \
  "}"

#define TEST_DATA_INTERPOLATION_TEMPLATE              \
  "Hello {{persona.name}} {{persona.surname}},\n"     \
  "\n"                                                \
  "Your home address:\n"                              \
  "{{persona.address.home.street}},\n"                \
  "{{persona.address.home.city}},\n"                  \
  "{{persona.address.home.zip}}\n"                    \
  "\n"                                                \
  "Your work address:\n"                              \
  "{{persona.address.work.street}},\n"                \
  "{{persona.address.work.city}},\n"                  \
  "{{persona.address.work.zip}}\n"                    \
  "\n"                                                \
  "Contact information:\n"                            \
  "Email: {{persona.contact.email}}\n"                \
  "Home Phone: {{persona.contact.phone.home}}\n"      \
  "Mobile Phone: {{persona.contact.phone.mobile}}\n"

#define TEST_DATA_INTERPOLATION_RESULT \
      "Hello John Doe,\n"              \
      "\n"                             \
      "Your home address:\n"           \
      "123 Main St,\n"                 \
      "Springfield,\n"                 \
      "12345\n"                        \
      "\n"                             \
      "Your work address:\n"           \
      "456 Business Rd,\n"             \
      "Metropolis,\n"                  \
      "67890\n"                        \
      "\n"                             \
      "Contact information:\n"         \
      "Email: john@example.com\n"      \
      "Home Phone: 555-1234\n"         \
      "Mobile Phone: 555-5678\n"

#define TEST_DATA_INTERPOLATION_WITH_PREFIX_CONTEXT \
  TEST_DATA_INTERPOLATION_CONTEXT

#define TEST_DATA_INTERPOLATION_WITH_PREFIX_TEMPLATE  \
  "Hello {{.persona.name}} {{.persona.surname}},\n"   \
  "\n"                                                \
  "Your home address:\n"                              \
  "{{.persona.address.home.street}},\n"               \
  "{{.persona.address.home.city}},\n"                 \
  "{{.persona.address.home.zip}}\n"                   \
  "\n"                                                \
  "Your work address:\n"                              \
  "{{.persona.address.work.street}},\n"               \
  "{{.persona.address.work.city}},\n"                 \
  "{{.persona.address.work.zip}}\n"                   \
  "\n"                                                \
  "Contact information:\n"                            \
  "Email: {{.persona.contact.email}}\n"               \
  "Home Phone: {{.persona.contact.phone.home}}\n"     \
  "Mobile Phone: {{.persona.contact.phone.mobile}}\n"

#define TEST_DATA_INTERPOLATION_WITH_PREFIX_RESULT \
  TEST_DATA_INTERPOLATION_RESULT

#define TEST_DATA_SIMPLE_SECTION_ITERATION_CONTEXT   \
  "{"                                                \
  "  \"array\": ["                                   \
  "    { \"field\": { \"subfield\": \"value1\" } }," \
  "    { \"field\": { \"subfield\": \"value2\" } }," \
  "    { \"field\": { \"subfield\": \"value3\" } }"  \
  "  ]"                                              \
  "}"

#define TEST_DATA_SIMPLE_SECTION_ITERATION_TEMPLATE \
  "{{#element array}}"                              \
  "  {{element.field.subfield}}"                    \
  "{{/array}}"

#define TEST_DATA_SIMPLE_SECTION_ITERATION_RESULT \
  "value1"                                        \
  "value2"                                        \
  "value3"

#define TEST_DATA_COMPLEX_SECTION_ITERATION_CONTEXT \
  "{"                                               \
  "  \"users\": ["                                  \
  "    { \"name\": \"John\", \"age\": 30 },"       \
  "    { \"name\": \"Jane\", \"age\": 25 }"        \
  "  ]"                                             \
  "}"

#define TEST_DATA_COMPLEX_SECTION_ITERATION_TEMPLATE \
  "{{#user users}}"                                \
  "  Name: {{user.name}}, Age: {{user.age}}\n"     \
  "{{/users}}"

#define TEST_DATA_COMPLEX_SECTION_ITERATION_RESULT \
  "  Name: John, Age: 30\n"                       \
  "  Name: Jane, Age: 25\n"

void test_eval_single_level_key(Arena *arena) {
    raise_notice("Testing single level key evaluation");
    const char *context_text = arena_strdup(arena, "{\"name\": \"world\"}");
    Json *context = json_parse(arena, &context_text);
    if (!context) { raise_exception("Malformed json"); exit(1); }

    char *result = eval_string(arena, context, "name");
    raise_notice("Context: %s", json_to_string(arena, context));
    raise_notice("Query: name");
    raise_notice("Result: %s", result);
    assert(result && strcmp(result, "world") == 0);
}

void test_eval_nested_key(Arena *arena) {
    raise_notice("Testing nested key evaluation");
    const char *context_text = arena_strdup(arena, "{\"person\": {\"name\": \"Alice\"}}");
    Json *context = json_parse(arena, &context_text);
    if (!context) { raise_exception("Malformed json"); exit(1); }

    char *result = eval_string(arena, context, "person.name");
    raise_notice("Context: %s", json_to_string(arena, context));
    raise_notice("Query: person.name");
    raise_notice("Result: %s", result);
    assert(result && strcmp(result, "Alice") == 0);
}

void test_render_interpolation_tags(Arena *arena) {
    raise_notice("Testing interpolation tags without prefix");
    const char *context_text = arena_strdup(arena, TEST_DATA_INTERPOLATION_CONTEXT);
    Json *context = json_parse(arena, &context_text);
    if (!context) { raise_exception("Malformed json"); exit(1); }

    char *text = arena_strdup(arena, TEST_DATA_INTERPOLATION_TEMPLATE); 
    raise_notice("Template:\n%s", text);
    raise_notice("Context: %s", json_to_string(arena, context));

    hmpl_render_interpolation_tags(arena, &text, context, "");
    raise_notice("Result:\n%s", text);
    assert(strcmp(text, TEST_DATA_INTERPOLATION_RESULT) == 0);
}

void test_render_interpolation_tags_with_prefix(Arena *arena) {
    raise_notice("Testing interpolation tags with prefix");
    const char *context_text = arena_strdup(arena, TEST_DATA_INTERPOLATION_WITH_PREFIX_CONTEXT);
    Json *context = json_parse(arena, &context_text);
    if (!context) { raise_exception("Malformed json"); exit(1); }

    char *text = arena_strdup(arena, TEST_DATA_INTERPOLATION_WITH_PREFIX_TEMPLATE); 
    raise_notice("Template:\n%s", text);
    raise_notice("Context: %s", json_to_string(arena, context));

    hmpl_render_interpolation_tags(arena, &text, context, ".");
    raise_notice("Result:\n%s", text);
    assert(strcmp(text, TEST_DATA_INTERPOLATION_WITH_PREFIX_RESULT) == 0);
}

void test_render_section_tags(Arena *arena) {
    raise_notice("Testing simple section tags");
    const char *context_text = arena_strdup(arena, TEST_DATA_SIMPLE_SECTION_ITERATION_CONTEXT);
    Json *context = json_parse(arena, &context_text);
    if (!context) { raise_exception("Malformed json"); exit(1); }

    char *text = arena_strdup(arena, TEST_DATA_SIMPLE_SECTION_ITERATION_TEMPLATE); 
    raise_notice("Template:\n%s", text);
    raise_notice("Context: %s", json_to_string(arena, context));

    hmpl_render_section_tags(arena, &text, context, "#", "/", " ");
    raise_notice("Result:\n%s", text);
    assert(strcmp(text, TEST_DATA_SIMPLE_SECTION_ITERATION_RESULT) == 0);
}

void test_render_complex_section_tags(Arena *arena) {
    raise_notice("Testing complex section tags");
    const char *context_text = arena_strdup(arena, TEST_DATA_COMPLEX_SECTION_ITERATION_CONTEXT);
    Json *context = json_parse(arena, &context_text);
    if (!context) { raise_exception("Malformed json"); exit(1); }

    char *text = arena_strdup(arena, TEST_DATA_COMPLEX_SECTION_ITERATION_TEMPLATE); 
    raise_notice("Template:\n%s", text);
    raise_notice("Context: %s", json_to_string(arena, context));

    hmpl_render_section_tags(arena, &text, context, "#", "/", " ");
    raise_notice("Result:\n%s", text);
    assert(strcmp(text, TEST_DATA_COMPLEX_SECTION_ITERATION_RESULT) == 0);
}

int main(void) {
    init_logger();
    raise_notice("Starting HMPL tests");
    Arena arena = arena_init(MEM_MiB * 3);

    // evaluation
    raise_notice("=== Testing key evaluation ===");
    test_eval_single_level_key(&arena);
    test_eval_nested_key(&arena);

    // interpolation tags
    raise_notice("=== Testing interpolation tags ===");
    test_render_interpolation_tags(&arena);
    test_render_interpolation_tags_with_prefix(&arena);

    // section tags
    raise_notice("=== Testing section tags ===");
    test_render_section_tags(&arena);
    test_render_complex_section_tags(&arena);

    raise_notice("All tests passed successfully");
    arena_free(&arena);
    return 0;
}