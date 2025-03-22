#include "hmpl.h"

Arena *cJSON_global_arena;
size_t last_size = 0;  // tracked externally, unsafe but works for simple use

void *arena_malloc(size_t size) {
  void *ptr = arena_alloc(cJSON_global_arena, size);
  last_size = size;
  return ptr;
}

void arena_free_stub(void *ptr) {
  raise_debug("WARN: cJSON tried to free %p — ignored", ptr);
}
		       
void init_cjson_with_arenas(Arena *arena) {
  cJSON_global_arena = arena;
  cJSON_InitHooks(&(cJSON_Hooks){
    .malloc_fn = arena_malloc,
    .free_fn = arena_free_stub,
  });
}

char *eval(Arena *arena, const cJSON * const context, const char * const key) {
  if (!context || !key) return NULL;
  char *key_copy = arena_strdup(arena, key);
  char *token, *rest = key_copy;
  cJSON *res = context;
  while ((token = strtok_r(rest, ".", &rest))) {
      raise_debug("context: %s; token: %s", cJSON_Print(res), key);
      res = cJSON_GetObjectItemCaseSensitive(res, token);
      if (!res)
          return NULL;
  }
  if (cJSON_IsString(res) && res->valuestring)
      return arena_strdup(arena, res->valuestring);
  else if (cJSON_IsNumber(res)) {
      char buf[64];
      snprintf(buf, sizeof(buf), "%g", res->valuedouble);
      return arena_strdup(arena, buf);
  }
  char *temp = cJSON_PrintUnformatted(res);
  char *result = arena_strdup(arena, temp);
  free(temp);
  return result;
}

/* Modified: text is passed by reference so we can update it and free old allocations */
void render_template_placeholders(Arena *arena, char **text_ptr, cJSON *context, const char * const prefix) {
  raise_debug("render_template_placeholders");
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

void render_template_with_arena(Arena *arena, char **text, const cJSON * const context) {
  if (!cJSON_IsObject(context)) {
    raise_exception("Malformed context: context is not json");
    exit(1);
  }

  render_template_placeholders(arena, text, context, "");
}

void render_template(char **text, const cJSON * const context) {
  Arena arena = arena_init(1024 * 1024);

  render_template_with_arena(&arena, text, context);

  arena_free(&arena);
}
