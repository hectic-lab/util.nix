#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include "hectic.h"

void test_slice_create() {
    int arr[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
    Slice s = slice_create(int, arr, 10, 0, 5);
    assert(s.data != NULL);
    assert(s.len == 5);
    assert(s.isize == sizeof(int));
    
    // Verify slice contents
    int *data = (int*)s.data;
    for (int i = 0; i < 5; i++) {
        assert(data[i] == i + 1);
    }
}

void test_slice_subslice() {
    int arr[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
    Slice s = slice_create(int, arr, 10, 0, 10);
    Slice sub = slice_subslice(s, 2, 4);
    
    assert(sub.data != NULL);
    assert(sub.len == 4);
    assert(sub.isize == sizeof(int));
    
    // Verify subslice contents
    int *data = (int*)sub.data;
    for (int i = 0; i < 4; i++) {
        assert(data[i] == i + 3);
    }
}

void test_slice_copy() {
    Arena arena = arena_init(128);
    int arr[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
    Slice s = slice_create(int, arr, 10, 0, 5);
    
    int *copy = arena_slice_copy(&arena, s);
    assert(copy != NULL);
    
    // Verify copy contents
    for (int i = 0; i < 5; i++) {
        assert(copy[i] == i + 1);
    }
    
    arena_free(&arena);
}

void test_slice_edge_cases() {
    int arr[] = {1, 2, 3, 4, 5};
    
    // Test empty slice
    Slice empty = slice_create(int, arr, 5, 0, 0);
    assert(empty.len == 0);
    assert(empty.data != NULL);
    
    // Test full array slice
    Slice full = slice_create(int, arr, 5, 0, 5);
    assert(full.len == 5);
    assert(full.data != NULL);
    
    // Test slice at end of array
    Slice end = slice_create(int, arr, 5, 3, 2);
    assert(end.len == 2);
    assert(end.data != NULL);
    int *end_data = (int*)end.data;
    assert(end_data[0] == 4);
    assert(end_data[1] == 5);
}

void test_slice_string() {
    const char *str = "Hello, World!";
    Slice s = slice_create(char, (void*)str, strlen(str), 0, 5);
    assert(s.len == 5);
    assert(s.isize == sizeof(char));
    
    char *data = (char*)s.data;
    assert(strncmp(data, "Hello", 5) == 0);
}

int main() {
    printf("%sRunning %s%s%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_CYAN), __FILE__,  OPTIONAL_COLOR(COLOR_RESET));
    init_logger();

    test_slice_create();
    test_slice_subslice();
    test_slice_copy();
    test_slice_edge_cases();
    test_slice_string();
    
    printf("%sall tests passed.%s%s%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_CYAN), __FILE__, OPTIONAL_COLOR(COLOR_RESET));
    return 0;
}