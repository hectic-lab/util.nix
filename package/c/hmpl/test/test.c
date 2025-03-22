#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "hmpl.h"
#include "hectic.h"

void test_eval_single_level_key(Arena *arena) {
    char *context_text = arena_strdup(arena, "{\"name\": \"world\"}");
    Json *context = json_parse(arena, &context_text);
    if (!context) { raise_exception("Malformed json"); exit(1); }

    char *result = eval(arena, context, "name");
    raise_debug("eval result: %s", result);
    assert(result && strcmp(result, "world") == 0);
}

void test_eval_nested_key(Arena *arena) {
    char *context_text = arena_strdup(arena, "{\"person\": {\"name\": \"Alice\"}}");
    Json *context = json_parse(arena, &context_text);
    if (!context) { raise_exception("Malformed json"); exit(1); }

    char *result = eval(arena, context, "person.name");
    raise_notice("context: %s, eval result: %s", json_to_string(arena, context), result);
    assert(result && strcmp(result, "Alice") == 0);
}

void test_render_interpolation_tags(Arena *arena) {
    char *context_text = arena_strdup(arena, 
        "{\n"
        "  \"persona\": {\n"
        "    \"name\": \"John\",\n"
        "    \"surname\": \"Doe\",\n"
        "    \"address\": {\n"
        "      \"home\": {\n"
        "        \"street\": \"123 Main St\",\n"
        "        \"city\": \"Springfield\",\n"
        "        \"zip\": \"12345\"\n"
        "      },\n"
        "      \"work\": {\n"
        "        \"street\": \"456 Business Rd\",\n"
        "        \"city\": \"Metropolis\",\n"
        "        \"zip\": \"67890\"\n"
        "      }\n"
        "    },\n"
        "    \"contact\": {\n"
        "      \"email\": \"john@example.com\",\n"
        "      \"phone\": {\n"
        "        \"home\": \"555-1234\",\n"
        "        \"mobile\": \"555-5678\"\n"
        "      }\n"
        "    }\n"
        "  }\n"
        "}");
    Json *context = json_parse(arena, &context_text);
    if (!context) { raise_exception("Malformed json"); exit(1); }

    char *text = arena_strdup(arena,
      "Hello {{persona.name}} {{persona.surname}},\n"
      "\n"
      "Your home address:\n"
      "{{persona.address.home.street}},\n"
      "{{persona.address.home.city}},\n"
      "{{persona.address.home.zip}}\n"
      "\n"
      "Your work address:\n"
      "{{persona.address.work.street}},\n"
      "{{persona.address.work.city}},\n"
      "{{persona.address.work.zip}}\n"
      "\n"
      "Contact information:\n"
      "Email: {{persona.contact.email}}\n"
      "Home Phone: {{persona.contact.phone.home}}\n"
      "Mobile Phone: {{persona.contact.phone.mobile}}\n"); 

    hmpl_render_with_arena(arena, &text, context);
    assert(strcmp(text, 
      "Hello John Doe,\n"
      "\n"
      "Your home address:\n"
      "123 Main St,\n"
      "Springfield,\n"
      "12345\n"
      "\n"
      "Your work address:\n"
      "456 Business Rd,\n"
      "Metropolis,\n"
      "67890\n"
      "\n"
      "Contact information:\n"
      "Email: john@example.com\n"
      "Home Phone: 555-1234\n"
      "Mobile Phone: 555-5678\n") == 0);
}


int main(void) {
    Arena arena = arena_init(1024 * 1024);

    test_eval_single_level_key(&arena);
    test_eval_nested_key(&arena);
    test_render_interpolation_tags(&arena);

    printf("All tests passed.\n");

    arena_free(&arena);
    return 0;
}
