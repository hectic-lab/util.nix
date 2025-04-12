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

char *test_struct_to_debug_str(Arena *arena, char *name, TestStruct *self, PtrSet *visited) {
    raise_trace("test_struct_to_debug_str: name: %s, self: %p, visited: %p", name, self, visited);

    char *result = arena_alloc(arena, MEM_KiB);
    STRUCT_TO_DEBUG_STR(arena, result, TestStruct, name, self, visited, 3, 
      NUMBER_TO_DEBUG_STR(arena, "a", self->a),
      NUMBER_TO_DEBUG_STR(arena, "b", self->b),
      test_struct_to_debug_str(arena, "next", self->next, visited)
    );
    return result;
}

char *test_struct2_to_debug_str(Arena *arena, char *name, TestStruct2 *self, PtrSet *visited) {
    raise_trace("test_struct2_to_debug_str: name: %s, self: %p, visited: %p", name, self, visited);

    char *result = arena_alloc(arena, MEM_KiB);
    STRUCT_TO_DEBUG_STR(arena, result, TestStruct, name, self, visited, 5, 
      NUMBER_TO_DEBUG_STR(arena, "a", self->a),
      NUMBER_TO_DEBUG_STR(arena, "f", self->f),
      STRING_TO_DEBUG_STR(arena, "c", self->c),
      test_struct_to_debug_str(arena, "other", self->other, visited),
      test_struct2_to_debug_str(arena, "left", self->left, visited)
    );

    raise_trace("returning result");
    return result;
}

int main(void) {
    printf("%sRunning %s%s%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_CYAN), __FILE__,  OPTIONAL_COLOR(COLOR_RESET));
    init_logger();

    TestStruct test_struct = {.a = 1, .b = 2, .next = NULL};
    test_struct.next = &test_struct;
    Arena lifetime = arena_init(MEM_MiB);
    PtrSet *visited = ptrset_init(&lifetime);
    raise_notice("%s", test_struct_to_debug_str(&lifetime, "test_struct", &test_struct, visited));

    TestStruct2 test_struct2 = {.a = 1, .c = "hello", .f = 3.14, .left = NULL, .other = &test_struct};
    visited = ptrset_init(&lifetime);
    raise_notice("%s", test_struct2_to_debug_str(&lifetime, "test_struct2", &test_struct2, visited));


    arena_free(&lifetime);
    printf("%sAll tests passed %s%s%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_CYAN), __FILE__, OPTIONAL_COLOR(COLOR_RESET));
    return 0;
}