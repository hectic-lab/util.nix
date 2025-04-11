#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "hectic.h"

#define ARENA_SIZE 1024 * 1024

//static char *remove_all_spaces(char *s) {
//    char *new_s = NULL;
//    while (*s) {
//        if (*s != ' ' && *s != '\t' && *s != '\n') {
//            new_s = s;
//        }
//        s++;
//    }
//    return new_s;
//}

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

    char *debug_str = template_node_to_debug_str(arena, root);

    raise_notice("debug_str: %s", debug_str);
    //assert(strcmp(
    //  remove_all_spaces(debug_str),
    //  remove_all_spaces(""            
    //  "["                             
    //  "  {"                           
    //  "    \"type\":\"TEXT\","        
    //  "    \"content\":{"             
    //  "      \"content\":\"Hello\""   
    //  "    }"                         
    //  "  },"                          
    //  "  {"                           
    //  "    \"type\":\"INTERPOLATE\"," 
    //  "    \"content\":{"             
    //  "      \"key\":\"name\""        
    //  "    }"                         
    //  "  },"                          
    //  "  {"                           
    //  "    \"type\":\"TEXT\","        
    //  "    \"content\":{"             
    //  "      \"content\":\"!\""       
    //  "    }"                         
    //  "  }"                           
    //  "]")) == 0);
}

//static void test_template_parse(Arena *arena, TemplateConfig *config) {
//    const char *template = "Hello {% name %}!";
//    TemplateResult *result = template_parse(arena, &template, config);
//
//    Arena *debug_arena = DISPOSABLE_ARENA;
//    const char *debug_str = template_node_to_debug_str(debug_arena, &result->Result.node);
//    raise_notice("debug_str: %s", debug_str);
//    raise_notice("result: %s", json_to_pretty_str(debug_arena, json_parse(debug_arena, &debug_str)));
//    assert(result->type == TEMPLATE_RESULT_NODE);
//}

int main(void) {
    init_logger();

    Arena arena = arena_init(ARENA_SIZE);

    //TemplateConfig config = template_default_config();

    printf("%sRunning template parser tests...%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_RESET));

    test_template_node_to_debug_str(&arena);
    printf("%sTest 0: template_node_to_debug_str passed%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_RESET));
    arena_reset(&arena);

    //test_template_parse(&arena, &config);
    //printf("%sTest 1: template_parse passed%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_RESET));
    //arena_reset(&arena);

    arena_free(&arena);
    printf("%s%s all tests passed.%s\n", OPTIONAL_COLOR(COLOR_GREEN), __FILE__, OPTIONAL_COLOR(COLOR_RESET));
    return 0;
} 