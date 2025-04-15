#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "hectic.h"

#define ARENA_SIZE MEM_MiB

#define TEST_TEMPLATE_NODE_TO_DEBUG_STR \
  "struct TemplateNode root = {\n" \
  "  enum type = TEXT 0 ,\n" \
  "  union TemplateValue value = {\n" \
  "    struct TemplateTextValue text = {\n" \
  "      content = %p \"Hello\"\n" \
  "    } %p\n" \
  "  } %p,\n" \
  "  struct TemplateNode children = NULL,\n" \
  "  struct TemplateNode next = {\n" \
  "    enum type = INTERPOLATE 1 ,\n" \
  "    union TemplateValue value = {\n" \
  "      struct TemplateInterpolateValue interpolate = {\n" \
  "        key = %p \"name\"\n" \
  "      } %p\n" \
  "    } %p,\n" \
  "    struct TemplateNode children = NULL,\n" \
  "    struct TemplateNode next = {\n" \
  "      enum type = TEXT 0 ,\n" \
  "      union TemplateValue value = {\n" \
  "        struct TemplateTextValue text = {\n" \
  "          content = %p \"!\"\n" \
  "        } %p\n" \
  "      } %p,\n" \
  "      struct TemplateNode children = NULL,\n" \
  "      struct TemplateNode next = NULL\n" \
  "    } %p\n" \
  "  } %p\n" \
  "} %p\n"

#define TEST_TEMPLATE_SECTION_NODE_TO_DEBUG_STR \
  "struct TemplateNode root = {\n" \
  "  enum type = SECTION 2 ,\n" \
  "  union TemplateValue value = {\n" \
  "    struct TemplateSectionValue section = {\n" \
  "      iterator = %p \"item\",\n" \
  "      collection = %p \"items\",\n" \
  "      body = {\n" \
  "        enum type = TEXT 0 ,\n" \
  "        union TemplateValue value = {\n" \
  "          struct TemplateTextValue text = {\n" \
  "            content = %p \"Loop content\"\n" \
  "          } %p\n" \
  "        } %p,\n" \
  "        struct TemplateNode children = NULL,\n" \
  "        struct TemplateNode next = NULL\n" \
  "      } %p\n" \
  "    } %p\n" \
  "  } %p,\n" \
  "  struct TemplateNode children = NULL,\n" \
  "  struct TemplateNode next = NULL\n" \
  "} %p\n"


static void test_template_node_to_debug_str(Arena *arena) {
    TemplateNode *root = arena_alloc(arena, sizeof(TemplateNode));
    root->type = TEMPLATE_NODE_TEXT;
    root->value.text.content = arena_strncpy(arena, "Hello", 5);

    root->next = arena_alloc(arena, sizeof(TemplateNode));
    root->next->type = TEMPLATE_NODE_INTERPOLATE;
    root->next->value.interpolate.key = arena_strncpy(arena, "name", 4);

    root->next->next = arena_alloc(arena, sizeof(TemplateNode));
    root->next->next->type = TEMPLATE_NODE_TEXT;
    root->next->next->value.text.content = arena_strncpy(arena, "!", 1);

    char *debug_str = debug_to_pretty_str(arena, TEMPLATE_NODE_TO_DEBUG_STR(arena, "root", root));
    raise_log("debug_str: \n%s", debug_str);

    { // some debug output
      Arena *debug_arena = DISPOSABLE_ARENA;
      const char *json_str = TEMPLATE_NODE_TO_JSON_STR(debug_arena, root);
      Json *json = json_parse(debug_arena, &json_str);
      raise_notice("json_str: \n%s", JSON_TO_PRETTY_STR(debug_arena, json));
    }

    char *expected_debug_str = arena_alloc(arena, MEM_KiB);
    sprintf(expected_debug_str, TEST_TEMPLATE_NODE_TO_DEBUG_STR,
        (void*)root->value.text.content,
        (void*)&root->value.text,
        (void*)&root->value,
        (void*)root->next->value.interpolate.key,
        (void*)&root->next->value.interpolate,
        (void*)&root->next->value,
        (void*)root->next->next->value.text.content,
        (void*)&root->next->next->value.text,
        (void*)&root->next->next->value,
        (void*)root->next->next,
        (void*)root->next,
        (void*)root
    );

    raise_log("expected_debug_str: \n%s", expected_debug_str);

    assert(strcmp(debug_str, expected_debug_str) == 0);
}

static void test_template_section_node_to_debug_str(Arena *arena) {
    // Create a section node with a child text node
    TemplateNode *root = arena_alloc(arena, sizeof(TemplateNode));
    root->type = TEMPLATE_NODE_SECTION;
    root->value.section.iterator = arena_strncpy(arena, "item", 4);
    root->value.section.collection = arena_strncpy(arena, "items", 5);
    
    // Create a body node (child of section)
    root->value.section.body = arena_alloc(arena, sizeof(TemplateNode));
    root->value.section.body->type = TEMPLATE_NODE_TEXT;
    root->value.section.body->value.text.content = arena_strncpy(arena, "Loop content", 12);

    // SAFETY(yukkop): if any of these are not NULL, the node will be corrupted
    root->value.section.body->next = NULL;
    root->value.section.body->children = NULL;
    root->next = NULL;
    root->children = NULL;
    
    char *debug_str = debug_to_pretty_str(arena, TEMPLATE_NODE_TO_DEBUG_STR(arena, "root", root));
    raise_log("debug_str: \n%s", debug_str);

    { // some debug output
      Arena *debug_arena = DISPOSABLE_ARENA;
      const char *json_str = TEMPLATE_NODE_TO_JSON_STR(debug_arena, root);
      Json *json = json_parse(debug_arena, &json_str);
      raise_notice("json_str: \n%s", JSON_TO_PRETTY_STR(debug_arena, json));
    }

    char *expected_debug_str = arena_alloc(arena, MEM_KiB);
    sprintf(expected_debug_str, TEST_TEMPLATE_SECTION_NODE_TO_DEBUG_STR,
        (void*)root->value.section.iterator,
        (void*)root->value.section.collection,
        (void*)root->value.section.body->value.text.content,
        (void*)&root->value.section.body->value.text,
        (void*)&root->value.section.body->value,
        (void*)root->value.section.body,
        (void*)&root->value.section,
        (void*)&root->value,
        (void*)root
    );

    raise_log("expected_debug_str: \n%s", expected_debug_str);

    assert(strcmp(debug_str, expected_debug_str) == 0);
}

int main(void) {
    printf("%sRunning %s%s%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_CYAN), __FILE__,  OPTIONAL_COLOR(COLOR_RESET));
    debug_color_mode = COLOR_MODE_DISABLE;
    logger_init();

    Arena arena = arena_init(ARENA_SIZE);

    //TemplateConfig config = template_default_config();

    printf("%sRunning template parser tests...%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_RESET));

    test_template_node_to_debug_str(&arena);
    printf("%sTest 0: template_node_to_debug_str passed%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_RESET));
    arena_reset(&arena);

    test_template_section_node_to_debug_str(&arena);
    printf("%sTest 1: template_section_node_to_debug_str passed%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_RESET));
    arena_reset(&arena);

    //test_template_parse(&arena, &config);
    //printf("%sTest 1: template_parse passed%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_RESET));
    //arena_reset(&arena);

    logger_free();
    arena_free(&arena);
    printf("%sall tests passed %s%s%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_CYAN), __FILE__, OPTIONAL_COLOR(COLOR_RESET));
    return 0;
} 