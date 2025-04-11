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


typedef struct PtrSet {
    void **data;
    size_t size;
    size_t capacity;
} PtrSet;

static bool debug_ptrset_contains(PtrSet *set, void *ptr) {
    for (size_t i = 0; i < set->size; i++) {
        if (set->data[i] == ptr)
            return true;
    }
    return false;
}

static void debug_ptrset_add(PtrSet *set, void *ptr) {
    if (set->size == set->capacity) {
        set->capacity = set->capacity ? set->capacity * 2 : 4;
        set->data = realloc(set->data, set->capacity * sizeof(void*));
    }
    set->data[set->size++] = ptr;
}


#define STRING_TO_DEBUG_STR(arena, name, string) \
	arena_strdup_fmt__(__FILE__, __func__, __LINE__, arena, "%s = %p \"%s\"", name, string, string)

#define NUMBER_TO_DEBUG_STR(arena, name, number) \
	arena_strdup_fmt__(__FILE__, __func__, __LINE__, arena, "%s = %d", name, number)

#define STRUCT_TO_DEBUG_STR(arena, type, name, ptr, ...) __extension__ ({ \
  char *result; \
  if ((ptr) == NULL) { \
    result = arena_strdup_fmt__(__FILE__, __func__, __LINE__, arena, "%s %s = NULL", #type, name); \
  } else { \
    char* fields = arena_strdup_fmt__(__FILE__, __func__, __LINE__, arena, "%s, %s, %s", __VA_ARGS__); \
    result = arena_strdup_fmt__(__FILE__, __func__, __LINE__, arena, "%s %s = {%s} %p", #type, name, fields, ptr); \
  } \
  result; \
})

#define test_struct_to_debug_str(arena, name, self) test_struct_to_debug_str__(arena, name, self)

char *test_struct_to_debug_str__(Arena *arena, char *name, TestStruct *self) {
    if (name == NULL) {
        name = "$1";
    }

    char *result = STRUCT_TO_DEBUG_STR(arena, TestStruct, name, self, 
      NUMBER_TO_DEBUG_STR(arena, "a", self->a),
      NUMBER_TO_DEBUG_STR(arena, "b", self->b),
      test_struct_to_debug_str__(arena, "next", self->next)
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
    raise_notice("%s", test_struct_to_debug_str(DISPOSABLE_ARENA, "test_struct", &test_struct));

    printf("%sAll tests passed %s%s%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_CYAN), __FILE__, OPTIONAL_COLOR(COLOR_RESET));
    return 0;
}