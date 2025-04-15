#include "hectic.h"
#include <assert.h>

typedef struct Struct Struct;

struct Struct {
    int a;
    int b;
    char *c;
    Struct *next;
};

typedef struct Struct2 Struct2;

struct Struct2 {
    int a;
    char *c;
    float f;
    Struct2 *left;
    Struct *other;
};

typedef enum TestUnionVariant {
    TEST_UNION_VARIANT_A,
    TEST_UNION_VARIANT_B,
    TEST_UNION_VARIANT_C
} TestUnionVariant;

typedef union TestUnion {
    int a;
    char *b;
    float c;
} TestUnion;

char *struct_to_debug_str(Arena *arena, char *name, Struct *self, PtrSet *visited) {
    raise_trace("struct_to_debug_str: name: %s, self: %p, visited: %p", name, self, visited);

    char *result = arena_alloc(arena, MEM_KiB);
    STRUCT_TO_DEBUG_STR(arena, result, Struct, name, self, visited, 3, 
      INT_TO_DEBUG_STR(arena, "a", self->a),
      INT_TO_DEBUG_STR(arena, "b", self->b),
      struct_to_debug_str(arena, "next", self->next, visited)
    );
    return result;
}

char *struct2_to_debug_str(Arena *arena, char *name, Struct2 *self, PtrSet *visited) {
    raise_trace("struct2_to_debug_str: name: %s, self: %p, visited: %p", name, self, visited);

    char *result = arena_alloc(arena, MEM_KiB);
    STRUCT_TO_DEBUG_STR(arena, result, Struct2, name, self, visited, 5, 
      INT_TO_DEBUG_STR(arena, "a", self->a),
      FLOAT_TO_DEBUG_STR(arena, "f", self->f),
      STRING_TO_DEBUG_STR(arena, "c", self->c),
      struct_to_debug_str(arena, "other", self->other, visited),
      struct2_to_debug_str(arena, "left", self->left, visited)
    );

    raise_trace("returning result");
    return result;
}

char *test_union_to_debug_str(Arena *arena, char *name, TestUnion *self, PtrSet *visited, TestUnionVariant active_variant) {
    raise_trace("test_union_to_debug_str: name: %s, self: %p, visited: %p, active_variant: %zu", name, self, visited, active_variant);

    char *result = arena_alloc(arena, MEM_KiB);
    UNION_TO_DEBUG_STR(arena, result, TestUnion, name, self, visited, active_variant, 3, 
      TEST_UNION_VARIANT_A, INT_TO_DEBUG_STR(arena, "a", self->a),    
      TEST_UNION_VARIANT_B, STRING_TO_DEBUG_STR(arena, "b", self->b),
      TEST_UNION_VARIANT_C, FLOAT_TO_DEBUG_STR(arena, "c", self->c)
    );
    return result;
}

void test_struct_to_debug_str(Arena *arena) {
    // Mock a struct with a cycle
    Struct test_struct = {.a = 1, .b = 2, .next = NULL};
    test_struct.next = &test_struct;

    PtrSet *visited = ptrset_init(arena);
    char *result = struct_to_debug_str(arena, "struct", &test_struct, visited);
    raise_notice("result: %s", result);

    char *check = arena_alloc(arena, MEM_KiB);
    sprintf(check, "struct Struct struct = {a = 1, b = 2, struct Struct next = {a = 1, b = 2, struct Struct next = <cycle detected> %p} %p} %p", (void*)&test_struct, (void*)&test_struct, (void*)&test_struct);
    raise_notice("check: %s", check);
    assert(strcmp(result, check) == 0);
}

void test_struct2_to_debug_str(Arena *arena) {
    // Mock a struct with some structs inside, null and cycle
    Struct test_struct = {.a = 1, .b = 2, .next = NULL};
    test_struct.next = &test_struct;

    Struct2 test_struct2 = {.a = 1, .c = "hello", .f = 3.14, .left = NULL, .other = &test_struct};

    PtrSet *visited = ptrset_init(arena);
    char *result = struct2_to_debug_str(arena, "struct2", &test_struct2, visited);
    raise_notice("result: %s", result);
    char *check = arena_alloc(arena, MEM_KiB);
    sprintf(check, "struct Struct2 struct2 = {a = 1, f = 3.140000, c = %p \"hello\", struct Struct other = {a = 1, b = 2, struct Struct next = {a = 1, b = 2, struct Struct next = <cycle detected> %p} %p} %p, struct Struct2 left = NULL} %p", (void*)test_struct2.c,(void*)&test_struct, (void*)&test_struct, (void*)&test_struct, (void*)&test_struct2);
    raise_notice("check: %s", check);
    assert(strcmp(result, check) == 0);
}

void test_test_union_to_debug_str(Arena *arena) {
    TestUnion test_union = {.a = 1};
    PtrSet *visited = ptrset_init(arena);
    char *result = test_union_to_debug_str(arena, "test_union", &test_union, visited, TEST_UNION_VARIANT_A);
    raise_notice("result: %s", result);
    char *check = arena_alloc(arena, MEM_KiB);
    sprintf(check, "union TestUnion test_union = {a = 1} %p", (void*)&test_union);
    raise_notice("check: %s", check);
    assert(strcmp(result, check) == 0);
}

#define INDENTED_RESULT \
    "struct Struct2 struct2 = {\n" \
    "  a = 1,\n" \
    "  f = 3.140000,\n" \
    "  c = %p \"hello\",\n" \
    "  struct Struct other = {\n" \
    "    a = 1,\n" \
    "    b = 2,\n" \
    "    struct Struct next = {\n" \
    "      a = 1,\n" \
    "      b = 2,\n" \
    "      struct Struct next = <cycle detected> %p\n" \
    "    } %p\n" \
    "  } %p,\n" \
    "  struct Struct2 left = NULL\n" \
    "} %p\n"

void test_debug_to_indented_str(Arena *arena) {
    Struct test_struct = {.a = 1, .b = 2, .next = NULL};
    test_struct.next = &test_struct;

    Struct2 test_struct2 = {.a = 1, .c = "hello", .f = 3.14, .left = NULL, .other = &test_struct};

    PtrSet *visited = ptrset_init(arena);
    char *result = struct2_to_debug_str(arena, "struct2", &test_struct2, visited);
    raise_notice("result: %s", result);

    char *indented = debug_to_pretty_str(arena, result);
    raise_notice("indented: \n%s", indented);

    char *expected = arena_alloc(arena, MEM_KiB);
    sprintf(expected, INDENTED_RESULT, (void*)test_struct2.c, (void*)&test_struct, (void*)&test_struct, (void*)&test_struct, (void*)&test_struct2);
    raise_notice("expected: \n%s", expected);
    assert(strcmp(indented, expected) == 0);
}

int main(void) {
    printf("%sRunning %s%s%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_CYAN), __FILE__,  OPTIONAL_COLOR(COLOR_RESET));
    debug_color_mode = COLOR_MODE_DISABLE;
    logger_init();

    Arena arena = arena_init(MEM_MiB);

    printf("%sTesting struct_to_debug_str%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_RESET));
    test_struct_to_debug_str(&arena);

    printf("%sTesting struct_to_debug_str2%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_RESET));
    test_struct2_to_debug_str(&arena);

    printf("%sTesting test_union_to_debug_str%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_RESET));
    test_test_union_to_debug_str(&arena);

    printf("%sTesting debug_to_indented_str%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_RESET));
    test_debug_to_indented_str(&arena);

    arena_free(&arena);
    logger_free();
    printf("%sAll tests passed %s%s%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_CYAN), __FILE__, OPTIONAL_COLOR(COLOR_RESET));
    return 0;
}