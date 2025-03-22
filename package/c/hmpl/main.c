#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "chectic.h"
#include "cjson/cJSON.h"
#include "hmpl.h"

int main(int argc, char *argv[]) {
  init_logger();
  raise_info("start");

  Arena arena = arena_init(1024 * 1024);
  Arena arena_for_jsons = arena_init(1024 * 1024);
  init_cjson_with_arenas(&arena_for_jsons);

  raise_info("read the arguments");
  char *text = NULL;

  const char *json_input = (argc > 1 ? argv[1] : "{}");
  cJSON *context = cJSON_Parse(json_input);

  if (!context) {
      fprintf(stderr, "Error parsing JSON\n");
      return 1;
  }

  if (argc > 2) {
    text = arena_strdup(&arena, argv[2]);
  } else if (!isatty(fileno(stdin))) {
    size_t size = 0;
    char *heap_text = NULL;
    ssize_t len = getdelim(&heap_text, &size, '\0', stdin);
    if (len < 0) {
      perror("read stdin");
      cJSON_Delete(context);
      return 1;
    }
    text = arena_strdup(&arena, heap_text);
    free(heap_text);  // free temporary heap allocation
  } else {
    text = arena_strdup(&arena, "");
  }

  render_template_with_arena(&arena, &text, context);
  printf("%s", text);

  arena_free(&arena);
  cJSON_Delete(context);
  return 0;
}
