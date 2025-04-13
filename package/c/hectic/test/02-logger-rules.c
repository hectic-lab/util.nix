#include "hectic.h"
#include <assert.h>

void test_parse_rules(Arena *arena) {
    char *rules = arena_alloc(arena, MEM_KiB);
    strcpy(rules, "ERROR,02-logger-rules.c@5:13=INFO,hectic.c@arena_alloc__=NOTICE");

    LogRuleResult result = logger_parse_rules__(__FILE__, __func__, __LINE__, arena, rules);

    raise_notice("result.type: %s", result_type_to_string(result.type));
    assert(result.type != RESULT_ERROR);

    raise_notice("result.some: %s", LOG_RULES_TO_DEBUG_STR(arena, "result.some", &RESULT_SOME_VALUE(result)));
}

int main(void) {
    printf("%sRunning %s%s%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_CYAN), __FILE__,  OPTIONAL_COLOR(COLOR_RESET));
    debug_color_mode = COLOR_MODE_DISABLE;
    logger_init();

    Arena arena = arena_init(MEM_MiB);

    test_parse_rules(&arena);

    arena_free(&arena);
    logger_free();
    printf("%sAll tests passed %s%s%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_CYAN), __FILE__, OPTIONAL_COLOR(COLOR_RESET));
    return 0;
}