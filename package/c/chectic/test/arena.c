#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include "chectic.h"

void test_arena_init() {
  Arena arena = arena_init(128);
  assert(arena.begin != NULL);
  assert(arena.current == arena.begin);
  assert(arena.capacity == 128);
  arena_free(&arena);
}

void test_arena_alloc() {
  Arena arena = arena_init(64);
  void *ptr1 = arena_alloc(&arena, 16);
  assert(ptr1 != NULL);
  void *ptr2 = arena_alloc(&arena, 16);
  assert(ptr2 != NULL);
  raise_debug("%d - %d = %d", (size_t)ptr2, (size_t)ptr1, (char *)ptr2 - (char *)ptr1);
  assert((char *)ptr2 - (char *)ptr1 == 16);
  arena_free(&arena);
}

void test_arena_alloc_or_null_out_of_memory() {
  Arena arena = arena_init(32);
  void *ptr = arena_alloc_or_null(&arena, 64);
  raise_debug("%d %d %d %d", arena.begin, arena.current, arena.capacity, (size_t)ptr);
  assert(ptr == NULL);
  arena_free(&arena);
}

void test_arena_reset() {
  Arena arena = arena_init(64);
  void *ptr1 = arena_alloc(&arena, 16);
  arena_reset(&arena);
  void *ptr2 = arena_alloc(&arena, 16);
  assert(ptr1 == ptr2); // same address after reset
  arena_free(&arena);
}

void test_arena_null_init() {
  Arena arena = {0};
  void *ptr = arena_alloc_or_null(&arena, 32);
  assert(ptr != NULL);
  arena_free(&arena);
}

void test_arena_strdup() {
  Arena arena = arena_init(64);
  const char *orig = "Hello, Arena!";
  char *copy = arena_strdup(&arena, orig);
  assert(copy != NULL);
  assert(strcmp(copy, orig) == 0);
  arena_free(&arena);
}

int main() {
  set_output_color_mode(COLOR_MODE_DISABLE);
  logger_level(LOG_LEVEL_DEBUG);

  test_arena_init();
  test_arena_alloc();
  test_arena_alloc_or_null_out_of_memory();
  test_arena_reset();
  test_arena_null_init();
  test_arena_strdup();
  printf("All tests passed.\n");
}
