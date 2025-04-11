#include "hectic.h"

typedef struct TestStruct TestStruct;

struct TestStruct {
    int a;
    int b;
    char *c;
    TestStruct *next;
};

typedef struct TestStruct2 TestStruct2;

struct TestStruct2 {
    int a;
    char *c;
    float f;
    TestStruct2 *left;
    TestStruct *other;
};

#define test_struct_to_debug_str(arena, name, self) test_struct_to_debug_str__(arena, name, self, ptrset_init(arena))

char *test_struct_to_debug_str__(Arena *arena, char *name, TestStruct *self, PtrSet *visited) {
    if (name == NULL) {
        name = "$1";
    }

    DEBUG_CHECK_CYCLE(arena, TestStruct, name, self, visited);

    char *result = STRUCT_TO_DEBUG_STR(arena, TestStruct, name, self, 3, 
      NUMBER_TO_DEBUG_STR(arena, "a", self->a),
      NUMBER_TO_DEBUG_STR(arena, "b", self->b),
      test_struct_to_debug_str__(arena, "next", self->next, visited)
    );
    return result;
}

//char *test_struct_to_debug_str__(Arena *arena, char *name, char *type, TestStruct *self) {
//    char *result = arena_strdup_fmt(arena, "%s %s{", name, type);
//
//    result = arena_strdup_fmt(arena, "%s%s", result, NUMBER_TO_DEBUG_STR(arena, "a", self->a));
//    result = arena_strdup_fmt(arena, "%s%s", result, NUMBER_TO_DEBUG_STR(arena, "b", self->b));
//    result = arena_strdup_fmt(arena, "%s%s", result, test_struct_to_debug_str__(arena, "next", TestStruct, self->next));
//
//    result = arena_strdup_fmt(arena, "%s} (%p)", result, self);
//    return result;
//}

int main(void) {
    printf("%sRunning %s%s%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_CYAN), __FILE__,  OPTIONAL_COLOR(COLOR_RESET));
    init_logger();

    TestStruct test_struct = {.a = 1, .b = 2, .next = NULL};
    test_struct.next = &test_struct;
    raise_notice("%s", test_struct_to_debug_str(DISPOSABLE_ARENA, "test_struct", &test_struct));

    printf("%sAll tests passed %s%s%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_CYAN), __FILE__, OPTIONAL_COLOR(COLOR_RESET));
    return 0;
}