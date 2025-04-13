#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "hectic.h"

#define ARENA_SIZE 1024 * 1024

// Test 1: Parse JSON object with a string value.
static void test_parse_json_object(void) {
    Arena arena = arena_init(ARENA_SIZE);
    const char *json = "{\"key\":\"value\"}";
    Json *root = json_parse(&arena, &json);
    assert(root->type == JSON_OBJECT);
    Json *child = root->child;
    assert(child && strcmp(child->key, "key") == 0);
    assert(child->type == JSON_STRING);
    assert(strcmp(child->JsonValue.string, "value") == 0);
    arena_free(&arena);
}

// Test 2: Parse JSON number.
static void test_parse_json_number(void) {
    Arena arena = arena_init(ARENA_SIZE);
    const char *json = "42";
    Json *root = json_parse(&arena, &json);
    assert(root->type == JSON_NUMBER);
    assert(root->JsonValue.number == 42);
    arena_free(&arena);
}

// Test 3: Parse JSON string.
static void test_parse_json_string(void) {
    Arena arena = {0};
    const char *json = "\"hello\"";
    Json *root = json_parse(&arena, &json);
    assert(root->type == JSON_STRING);
    assert(strcmp(root->JsonValue.string, "hello") == 0);
    arena_free(&arena);
}

// Test 4: Get object items by key.
static void test_get_object_items(void) {
    Arena arena = arena_init(ARENA_SIZE);
    const char *json = "{\"a\":\"1\", \"b\":2}";
    Json *root = json_parse(&arena, &json);
    Json *item_a = json_get_object_item(root, "a");
    assert(item_a && item_a->type == JSON_STRING);
    assert(strcmp(item_a->JsonValue.string, "1") == 0);
    Json *item_b = json_get_object_item(root, "b");
    assert(item_b && item_b->type == JSON_NUMBER);
    assert(item_b->JsonValue.number == 2);
    arena_free(&arena);
}

// Test 5: Print JSON object.
static void test_print_json_object(void) {
    Arena arena = arena_init(ARENA_SIZE);
    const char *json = "{\"key\":\"value\", \"num\":3.14}";
    Json *root = json_parse(&arena, &json);
    char *printed = json_to_string(&arena, root);
    assert(strstr(printed, "\"key\":") != NULL);
    assert(strstr(printed, "\"value\"") != NULL);
    assert(strstr(printed, "\"num\":") != NULL);
    assert(strstr(printed, "3.14") != NULL);
    arena_free(&arena);
}

// Test 6: Print JSON number.
static void test_print_json_number(void) {
    Arena arena = arena_init(ARENA_SIZE);
    const char *json = "123.456";
    Json *root = json_parse(&arena, &json);
    char *printed = json_to_string(&arena, root);
    double val = atof(printed);
    assert(val == 123.456);
    arena_free(&arena);
}

// Test 7: Print JSON string.
static void test_print_json_string(void) {
    Arena arena = arena_init(ARENA_SIZE);
    const char *json = "\"test string\"";
    Json *root = json_parse(&arena, &json);
    char *printed = json_to_string(&arena, root);
    assert(strcmp(printed, "\"test string\"") == 0);
    arena_free(&arena);
}

// Test 8: Nested JSON object.
static void test_nested_json_object(void) {
    Arena arena = arena_init(1024 * 1024);
    const char *json = "{\"outer\":{\"inner\":100}}";
    Json *root = json_parse(&arena, &json);
    assert(root != NULL);
    assert(root->type == JSON_OBJECT);

    Json *outer = json_get_object_item(root, "outer");
    assert(outer != NULL);
    assert(outer->type == JSON_OBJECT);

    Json *inner = json_get_object_item(outer, "inner");
    assert(inner != NULL);
    assert(inner->type == JSON_NUMBER);
    assert(inner->JsonValue.number == 100);

    arena_free(&arena);
}

// Test 9: Arena reset and reuse.
static void test_arena_reset_reuse(void) {
    Arena arena = arena_init(ARENA_SIZE);
    const char *json1 = "{\"key\":\"value\"}";
    Json *root1 = json_parse(&arena, &json1);
    char *printed1 = json_to_string(&arena, root1);
    assert(strcmp(printed1, "{\"key\":\"value\"}") == 0);
    arena_reset(&arena);
    const char *json2 = "\"another test\"";
    Json *root2 = json_parse(&arena, &json2);
    char *printed2 = json_to_string(&arena, root2);
    assert(strcmp(printed2, "\"another test\"") == 0);
    arena_free(&arena);
}

int main(void) {
    printf("%sRunning %s%s%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_CYAN), __FILE__,  OPTIONAL_COLOR(COLOR_RESET));
    logger_init();

    test_parse_json_object();
    test_parse_json_number();
    test_parse_json_string();
    test_get_object_items();
    test_print_json_object();
    test_print_json_number();
    test_print_json_string();
    test_nested_json_object();
    test_arena_reset_reuse();

    logger_free();
    printf("%sall tests passed.%s%s%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_CYAN), __FILE__, OPTIONAL_COLOR(COLOR_RESET));
    return 0;
}
