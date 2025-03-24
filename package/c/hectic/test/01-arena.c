#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include "hectic.h"

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

void test_arena_repstr() {
  Arena arena = arena_init(128);
  const char *original = "Hello, World!";
  // Replace substr_cloneing starting at index 5, length 3 (", W") with " -"
  // That results in: "Hello" + " -" + "orld!" = "Hello -orld!"
  char *result = arena_repstr(&arena, original, 5, 3, " -");
  raise_debug("%s", result);
  assert(strcmp(result, "Hello -orld!") == 0);
  arena_free(&arena);
}

void test_arena_overwrite_detection() {
  Arena arena = arena_init(128);

  char *s1 = arena_alloc(&arena, 6);
  strcpy(s1, "hello");

  char *s2 = arena_alloc(&arena, 6);
  strcpy(s2, "world");

  assert(strcmp(s1, "hello") == 0);
  assert(strcmp(s2, "world") == 0);

  // Force allocation near capacity
  void *large = arena_alloc_or_null(&arena, 100);
  assert(large != NULL || (size_t)arena.current == (size_t)arena.begin + arena.capacity); // If NULL, out of memory

  // Check strings again
  assert(strcmp(s1, "hello") == 0);
  assert(strcmp(s2, "world") == 0);

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
  test_arena_repstr();
  test_arena_overwrite_detection();
  printf("%s all tests passed.\n", __FILE__);
}
