#include "hmpl.h"

char *eval(Arena *arena, const Json * const context, const char * const query) {
  if (!context || !query) return NULL;

  Json *res = context;
  char *dot, *key = arena_strdup(arena, query);

  while ((dot = strchr(key, '.')) != NULL) {
    *dot = '\0';
    raise_debug("res: %s, key: %s, query: %s", json_to_string(arena, res), key, query);
    res = json_get_object_item(res, key);
    if (!res)
      return NULL;
    key = dot + 1;
  }

  raise_debug("res: %s, key: %s, query: %s", json_to_string(arena, res), key, query);
  res = json_get_object_item(res, key);
  if (!res)
    return NULL;

  return json_to_string_with_opts(arena, res, JSON_RAW);
}

/* Modified: text is passed by reference so we can update it and free old allocations */
// {{[prefix]key}}
void hmpl_render_interpolation_tags(Arena *arena, char **text_ptr, Json *context, const char * const prefix) {
  raise_debug("hmpl_render_interpolation_tags");
  char start_pattern[8];
  snprintf(start_pattern, sizeof(start_pattern), "{{%s", prefix);
  int start_pattern_length = strlen(start_pattern);
  int offset = 0;

  while (1) {
      char *current_text = *text_ptr;
      char *start = strstr(current_text + offset, start_pattern);
      if (!start)
          break;

      int start_index = start - current_text;
      int key_start = start_index + start_pattern_length;

      char *end = strstr(start, "}}");
      if (!end)
          raise_exception("Malformed template: missing closing braces for interpolation tag");
      int key_length = (end - current_text) - key_start;
      char *key = arena_alloc(arena, key_length + 1);
      substr(current_text, key, key_start, key_length);

      char *replacement = eval(arena, context, key);
      if (!replacement) {
          offset = (end - current_text) + 2;
          continue;
      }
      char *new_text = arena_repstr(arena, current_text,
        start_index,
        end - start + 1,
        replacement);

      *text_ptr = new_text;
      offset = start_index;
  }
}

// CREATE OR REPLACE FUNCTION common.render_template_loop_blocks(result TEXT, context JSONB)
// RETURNS TEXT LANGUAGE plpgsql AS $$
// DECLARE
//   loop_start INT;
//   key_end INT;
//   loop_end INT;
//   loop_key TEXT;
//   block TEXT;
//   rendered_block TEXT;
//   arr JSONB;
//   item JSONB;
//   item_text TEXT;
// BEGIN
//   LOOP
//     loop_start := strpos(result, '{{#');
//     EXIT WHEN loop_start = 0; -- Exit if no loop start found.
//     
//     -- Locate the end of the loop key marker.
//     key_end := strpos(result, '}}', loop_start);
//     IF key_end = 0 THEN
//       RAISE EXCEPTION 'Malformed template: missing closing braces for loop start';
//     END IF;
//     
//     -- Extract the key used for the loop.
//     loop_key := substring(result from loop_start + 3 for key_end - loop_start - 3);
// 
//     RAISE DEBUG 'loop key %', loop_key;
//     
//     -- Find the matching loop end marker for this key.
//     loop_end := strpos(result, '{{/#' || loop_key || '}}', key_end);
//     IF loop_end = 0 THEN
//       RAISE EXCEPTION 'Malformed template: missing loop end for key %', loop_key;
//     END IF;
// 
//     -- Extract the inner block of the loop.
//     block := substring(result from key_end + 2 for loop_end - key_end - 2);
// 
//     -- Retrieve the JSON array from the context for the loop key.
//     arr := eval_value(context, loop_key);
//     rendered_block := '';
//     
//     -- If an array is found, iterate over each element.
//     IF arr IS NOT NULL AND jsonb_typeof(arr) = 'array' THEN
//       FOR item IN SELECT * FROM jsonb_array_elements(arr) LOOP
//         item_text := block;  -- Begin with the raw block.
//         IF jsonb_typeof(item) != 'object' THEN
//           -- Replace interpolation for primitive values.
//           item_text := replace(item_text, '{{.}}', item::text);
//         ELSE
//           -- For object values, iterate over each key/value.
//           item_text := render_template_interpolations(item_text, item, '.'::CHAR(1));
//           item_text := render_template_conditions(item_text, item, '.');
//         END IF;
//         rendered_block := rendered_block || item_text;
//       END LOOP;
//     END IF;
//     
//     -- Replace the entire loop block in the result with the rendered content.
//     result := substring(result from 1 for loop_start - 1)
//               || rendered_block
//               || substring(result from loop_end + char_length('{{/#' || loop_key || '}}'));
//   END LOOP;
// 
//   RETURN result;
// END $$;

// {{#array_key}}
// void hmpl_render_section_tags(Arena *arena, char **text_ptr, Json *context, const char * const prefix){
//   raise_debug("hmpl_render_section_tags");
//   char start_pattern[8];
//   snprintf(start_pattern, sizeof(start_pattern), "{{%s", prefix);
//   int start_pattern_length = strlen(start_pattern);
//   int offset = 0;
// 
//   while (1) {
//     char *current_text = *text_ptr;
//     char *opening_tag_start = strstr(current_text + offset, start_pattern);
//     if (!opening_tag_start)
//       break;
// 
//     int start_index = start - current_text;
//     int key_start = start_index + start_pattern_length;
// 
//     char *end = strstr(start, "}}");
//     if (!end)
//       raise_exception("Malformed template: missing closing braces for section tag");
//     int key_length = (end - current_text) - key_start;
// 
// 
//     char *key = arena_alloc(arena, key_length + 1);
//     substr(current_text, key, key_start, key_length);
// 
//     char *arr = eval(arena, context, key);
//   }
// }

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
