#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "hectic.h"
#include "templater.h"

#define ARENA_SIZE 1024 * 1024

// Test 1: Basic interpolation
static void test_basic_interpolation(void) {
    Arena arena = arena_init(ARENA_SIZE);
    
    // Initialize template config
    TemplateConfig *config = template_config_init(&arena);
    assert(config != NULL);
    
    // Create test data
    const char *json_str = "{\"name\":\"John\",\"age\":30}";
    Json *data = json_parse(&arena, &json_str);
    assert(data != NULL);
    
    // Create template context
    TemplateContext *ctx = template_context_init(&arena, data, config);
    assert(ctx != NULL);
    
    // Parse template
    const char *template = "Hello {% name %}, you are {% age %} years old.";
    TemplateNode *root = template_parse(&arena, template, config);
    assert(root != NULL);
    
    // Render template
    char *result = template_render(&arena, root, ctx);
    assert(result != NULL);
    assert(strcmp(result, "Hello John, you are 30 years old.") == 0);
    
    arena_free(&arena);
}

// Test 2: Section (loop) with join
static void test_section_with_join(void) {
    Arena arena = arena_init(ARENA_SIZE);
    
    // Initialize template config
    TemplateConfig *config = template_config_init(&arena);
    assert(config != NULL);
    
    // Create test data
    const char *json_str = "{\"items\":[\"apple\",\"banana\",\"orange\"]}";
    Json *data = json_parse(&arena, &json_str);
    assert(data != NULL);
    
    // Create template context
    TemplateContext *ctx = template_context_init(&arena, data, config);
    assert(ctx != NULL);
    
    // Parse template
    const char *template = "{% for item in items join ', ' do %}{% item %}{% %}";
    TemplateNode *root = template_parse(&arena, template, config);
    assert(root != NULL);
    
    // Render template
    char *result = template_render(&arena, root, ctx);
    assert(result != NULL);
    assert(strcmp(result, "apple, banana, orange") == 0);
    
    arena_free(&arena);
}

// Test 3: Nested sections
static void test_nested_sections(void) {
    Arena arena = arena_init(ARENA_SIZE);
    
    // Initialize template config
    TemplateConfig *config = template_config_init(&arena);
    assert(config != NULL);
    
    // Create test data
    const char *json_str = "{\"users\":[{\"name\":\"John\",\"roles\":[\"admin\",\"user\"]},{\"name\":\"Jane\",\"roles\":[\"user\"]}]}";
    Json *data = json_parse(&arena, &json_str);
    assert(data != NULL);
    
    // Create template context
    TemplateContext *ctx = template_context_init(&arena, data, config);
    assert(ctx != NULL);
    
    // Parse template
    const char *template = "{% for user in users do %}{% user.name %}: {% for role in user.roles join ', ' do %}{% role %}{% %}\n{% %}";
    TemplateNode *root = template_parse(&arena, template, config);
    assert(root != NULL);
    
    // Render template
    char *result = template_render(&arena, root, ctx);
    assert(result != NULL);
    assert(strcmp(result, "John: admin, user\nJane: user\n") == 0);
    
    arena_free(&arena);
}

// Test 4: Null handling
static void test_null_handling(void) {
    Arena arena = arena_init(ARENA_SIZE);
    
    // Initialize template config
    TemplateConfig *config = template_config_init(&arena);
    assert(config != NULL);
    
    // Create test data
    const char *json_str = "{\"name\":\"John\",\"age\":null}";
    Json *data = json_parse(&arena, &json_str);
    assert(data != NULL);
    
    // Create template context
    TemplateContext *ctx = template_context_init(&arena, data, config);
    assert(ctx != NULL);
    
    // Parse template
    const char *template = "Name: {% name %}\nAge: {% age %%}unknown{% %}";
    TemplateNode *root = template_parse(&arena, template, config);
    assert(root != NULL);
    
    // Render template
    char *result = template_render(&arena, root, ctx);
    assert(result != NULL);
    assert(strcmp(result, "Name: John\nAge: unknown") == 0);
    
    arena_free(&arena);
}

// Test 5: Complex template with mixed content
static void test_complex_template(void) {
    Arena arena = arena_init(ARENA_SIZE);
    
    // Initialize template config
    TemplateConfig *config = template_config_init(&arena);
    assert(config != NULL);
    
    // Create test data
    const char *json_str = "{\"title\":\"Shopping List\",\"items\":[{\"name\":\"Milk\",\"quantity\":2},{\"name\":\"Bread\",\"quantity\":1}],\"notes\":\"Don't forget the eggs!\"}";
    Json *data = json_parse(&arena, &json_str);
    assert(data != NULL);
    
    // Create template context
    TemplateContext *ctx = template_context_init(&arena, data, config);
    assert(ctx != NULL);
    
    // Parse template
    const char *template = "Title: {% title %}\n\nItems:\n{% for item in items do %}- {% item.name %} ({% item.quantity %})\n{% %}\n\nNotes: {% notes %}";
    TemplateNode *root = template_parse(&arena, template, config);
    assert(root != NULL);
    
    // Render template
    char *result = template_render(&arena, root, ctx);
    assert(result != NULL);
    assert(strcmp(result, "Title: Shopping List\n\nItems:\n- Milk (2)\n- Bread (1)\n\nNotes: Don't forget the eggs!") == 0);
    
    arena_free(&arena);
}

int main(void) {
    printf("Running template parser tests...\n");
    
    test_basic_interpolation();
    printf("Test 1: Basic interpolation passed\n");
    
    test_section_with_join();
    printf("Test 2: Section with join passed\n");
    
    test_nested_sections();
    printf("Test 3: Nested sections passed\n");
    
    test_null_handling();
    printf("Test 4: Null handling passed\n");
    
    test_complex_template();
    printf("Test 5: Complex template passed\n");
    
    printf("All tests passed!\n");
    return 0;
} 