#include "hmpl.h"

char *eval(Arena *arena, const Json * const context, const char * const key) {
  if (!context || !key) return NULL;

  char *key_copy = arena_strdup(arena, key);
  Json *res = context;
  char *start = key_copy;
  char *dot;

  // Instead of using strtok_r, manually split the string using strchr.
  while ((dot = strchr(start, '.')) != NULL) {
    *dot = '\0';
    raise_debug("res: %s, token: %s, key: %s", json_to_string(arena, res), start, key);
    res = json_get_object_item(res, start);
    if (!res)
      return NULL;
    start = dot + 1;
  }

  raise_debug("res: %s, token: %s, key: %s", json_to_string(arena, res), start, key);
  res = json_get_object_item(res, start);
  if (!res)
    return NULL;

  return json_to_string_with_opts(arena, res, 1);
}

/* Modified: text is passed by reference so we can update it and free old allocations */
void hmpl_render_interpolation_tags(Arena *arena, char **text_ptr, Json *context, const char * const prefix) {
  raise_debug("hmpl_render_interpolation_tags");
  char start_pattern[256];
  snprintf(start_pattern, sizeof(start_pattern), "{{%s", prefix);
  int start_pattern_length = strlen(start_pattern);
  int offset = 0;

  while (1) {
      char *current_text = *text_ptr;
      char *placeholder_start = strstr(current_text + offset, start_pattern);
      if (!placeholder_start)
          break;
      int start_index = placeholder_start - current_text;
      int key_start = start_index + start_pattern_length;
      raise_debug("start: %d", key_start);

      char *placeholder_end = strstr(placeholder_start, "}}");
      if (!placeholder_end)
          raise_exception("Malformed template: missing closing braces for placeholder start");
      int key_length = (placeholder_end - current_text) - key_start;
      char *placeholder_key = arena_alloc(arena, key_length + 1);
      substr(current_text, placeholder_key, key_start, key_length);
      raise_debug("key: %s", placeholder_key);

      char *replacement = eval(arena, context, placeholder_key);
      raise_debug("%s = eval(context, %s)", replacement ? replacement : "NULL", placeholder_key);
      if (!replacement) {
          offset = (placeholder_end - current_text) + 2;
          continue;
      }
      char *new_text = arena_repstr(arena, current_text,
        start_index,
        placeholder_end - placeholder_start + 1,
        replacement);

      *text_ptr = new_text;
      offset = start_index;
  }
}

void hmpl_render_with_arena(Arena *arena, char **text, const Json * const context) {
  if (context->type != JSON_OBJECT) {
    raise_exception("Malformed context: context is not json");
    exit(1);
  }

  hmpl_render_interpolation_tags(arena, text, context, "");
}

void hmpl_render(char **text, const Json * const context) {
  Arena arena = arena_init(1024 * 1024);

  hmpl_render_with_arena(&arena, text, context);

  arena_free(&arena);
}
