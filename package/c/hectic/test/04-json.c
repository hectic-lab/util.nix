#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "hectic.h"

#define ARENA_SIZE 1024 * 1024

// Test 1: Parse JSON object with a string value.
static void test_parse_json_object(Arena *arena) {
    const char *json = "{\"key\":\"value\"}";
    Json *root = json_parse(arena, &json);
    assert(root->type == JSON_OBJECT);
    Json *child = root->child;
    assert(child && strcmp(child->key, "key") == 0);
    assert(child->type == JSON_STRING);
    assert(strcmp(child->JsonValue.string, "value") == 0);
}

// Test 2: Parse JSON number.
static void test_parse_json_number(Arena *arena) {
    const char *json = "42";
    Json *root = json_parse(arena, &json);
    assert(root->type == JSON_NUMBER);
    assert(root->JsonValue.number == 42);
}

// Test 3: Parse JSON string.
static void test_parse_json_string(Arena *arena) {
    const char *json = "\"hello\"";
    Json *root = json_parse(arena, &json);
    assert(root->type == JSON_STRING);
    assert(strcmp(root->JsonValue.string, "hello") == 0);
}

// Test 4: Get object items by key.
static void test_get_object_items(Arena *arena) {
    const char *json = "{\"a\":\"1\", \"b\":2}";
    Json *root = json_parse(arena, &json);
    Json *item_a = json_get_object_item(root, "a");
    assert(item_a && item_a->type == JSON_STRING);
    assert(strcmp(item_a->JsonValue.string, "1") == 0);
    Json *item_b = json_get_object_item(root, "b");
    assert(item_b && item_b->type == JSON_NUMBER);
    assert(item_b->JsonValue.number == 2);
}

// Test 5: Print JSON object.
static void test_print_json_object(Arena *arena) {
    const char *json = "{\"key\":\"value\", \"num\":3.14}";
    Json *root = json_parse(arena, &json);
    char *printed = json_to_string(arena, root);
    assert(strstr(printed, "\"key\":") != NULL);
    assert(strstr(printed, "\"value\"") != NULL);
    assert(strstr(printed, "\"num\":") != NULL);
    assert(strstr(printed, "3.14") != NULL);
}

// Test 6: Print JSON number.
static void test_print_json_number(Arena *arena) {
    const char *json = "123.456";
    Json *root = json_parse(arena, &json);
    char *printed = json_to_string(arena, root);
    double val = atof(printed);
    assert(val == 123.456);
}

// Test 7: Print JSON string.
static void test_print_json_string(Arena *arena) {
    const char *json = "\"test string\"";
    Json *root = json_parse(arena, &json);
    char *printed = json_to_string(arena, root);
    assert(strcmp(printed, "\"test string\"") == 0);
}

// Test 8: Nested JSON object.
static void test_nested_json_object(Arena *arena) {
    const char *json = "{\"outer\":{\"inner\":100}}";
    Json *root = json_parse(arena, &json);
    assert(root != NULL);
    assert(root->type == JSON_OBJECT);

    Json *outer = json_get_object_item(root, "outer");
    assert(outer != NULL);
    assert(outer->type == JSON_OBJECT);

    Json *inner = json_get_object_item(outer, "inner");
    assert(inner != NULL);
    assert(inner->type == JSON_NUMBER);
    assert(inner->JsonValue.number == 100);

}

// Test 9: Arena reset and reuse.
static void test_arena_reset_reuse(Arena *arena) {
    const char *json1 = "{\"key\":\"value\"}";
    Json *root1 = json_parse(arena, &json1);
    char *printed1 = json_to_string(arena, root1);
    assert(strcmp(printed1, "{\"key\":\"value\"}") == 0);
    arena_reset(arena);
    const char *json2 = "\"another test\"";
    Json *root2 = json_parse(arena, &json2);
    char *printed2 = json_to_string(arena, root2);
    assert(strcmp(printed2, "\"another test\"") == 0);
}

static void test_debug_str_to_json(Arena *arena) {
    const char *debug_str = "struct SomeStruct struct_name = { name = \"value\", next = NULL, value = 123 }";
    JsonResult result = DEBUG_STR_TO_JSON(arena, &debug_str);
    if (IS_RESULT_ERROR(result)) {
        raise_exception("DEBUG_STR_TO_JSON: %s", &RESULT_ERROR_MESSAGE(result));
        return;
    }
    raise_notice("result: %s", json_to_string(arena, &RESULT_SOME_VALUE(result)));
    assert(RESULT_SOME_VALUE(result).type == JSON_OBJECT);
}

int main(void) {
    printf("%sRunning %s%s%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_CYAN), __FILE__,  OPTIONAL_COLOR(COLOR_RESET));
    logger_init();

    Arena arena = arena_init(ARENA_SIZE);

    test_parse_json_object(&arena);
    arena_reset(&arena);
    test_parse_json_number(&arena);
    arena_reset(&arena);
    test_parse_json_string(&arena);
    arena_reset(&arena);
    test_get_object_items(&arena);
    arena_reset(&arena);
    test_print_json_object(&arena);
    arena_reset(&arena);
    test_print_json_number(&arena);
    arena_reset(&arena);
    test_print_json_string(&arena);
    arena_reset(&arena);
    test_nested_json_object(&arena);
    arena_reset(&arena);
    test_arena_reset_reuse(&arena);
    arena_reset(&arena);
    test_debug_str_to_json(&arena);

    arena_free(&arena);
    logger_free();
    printf("%sall tests passed.%s%s%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_CYAN), __FILE__, OPTIONAL_COLOR(COLOR_RESET));
    return 0;
}
