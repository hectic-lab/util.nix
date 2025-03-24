#include "hmpl.h"

Json *eval_object(Arena *arena, const Json * const context, const char * const query) {
  if (!context || !query) return NULL;

  const Json *res = context;
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
  return json_get_object_item(res, key);
}

char *eval_string(Arena *arena, const Json * const context, const char * const query) {
  Json *res = eval_object(arena, context, query);
  if (!res)
    return NULL;
  return json_to_string_with_opts(arena, res, JSON_RAW);
}

/* Modified: text is passed by reference so we can update it and free old allocations */
// {{[prefix]key}}
void hmpl_render_interpolation_tags(Arena *arena, char **text_ptr, const Json * const context, const char * const prefix) {
  raise_debug("hmpl_render_interpolation_tags");
  char start_pattern[256];
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
      substr_clone(current_text, key, key_start, key_length);

      char *replacement = eval_string(arena, context, key);
      if (!replacement) {
          offset = (end - current_text) + 2;
          continue;
      }
      char *new_text = arena_repstr(arena, current_text,
        start_index,
        end - start + 2,
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
//     loop_key := substr_cloneing(result from loop_start + 3 for key_end - loop_start - 3);
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
//     block := substr_cloneing(result from key_end + 2 for loop_end - key_end - 2);
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
//     result := substr_cloneing(result from 1 for loop_start - 1)
//               || rendered_block
//               || substr_cloneing(result from loop_end + char_length('{{/#' || loop_key || '}}'));
//   END LOOP;
// 
//   RETURN result;
// END $$;

// {{#array_key}}
void hmpl_render_section_tags(Arena *arena, char **text_ptr, Json *context, const char * const prefix_start, const char * const prefix_end, const char * const separator_pattern){
  raise_debug("hmpl_render_section_tags(%p, %s, <optimized>, %s, %s, %s)", arena, *text_ptr, prefix_start, prefix_end, separator_pattern);
  char start_pattern[32];
  snprintf(start_pattern, sizeof(start_pattern), "{{%s", prefix_start);
  int start_pattern_length = strlen(start_pattern);

  // TODO: rename close_tag_start_pattern
  char end_pattern[32];
  snprintf(end_pattern, sizeof(end_pattern), "{{%s", prefix_end);
  int end_pattern_length = strlen(end_pattern);

  int separator_pattern_length = strlen(separator_pattern);
  if (!separator_pattern || separator_pattern_length == 0) {
    raise_exception("Unexpected usage: separator pattern cannot be empty");
  }

  int offset = 0;

  while (1) {
    char *current_text = *text_ptr;
    char *opening_tag_start = strstr(current_text + offset, start_pattern);
    if (!opening_tag_start)
      break;
    int start_index = opening_tag_start - current_text;
    int relative_key_start = start_index + start_pattern_length;

    char *opening_tag_separator = strstr(opening_tag_start, separator_pattern);
    if (!opening_tag_start) {
      raise_exception("Malformed template: missing separator for section tag or not specifiet name for element");
      exit(1);
    }
    int separator_index = opening_tag_separator - current_text;
    int element_name_start = separator_index + separator_pattern_length;

    char *opening_tag_end = strstr(opening_tag_separator, "}}");
    if (!opening_tag_end) {
      raise_exception("Malformed template: missing closing braces for section tag");
      exit(1);
    }
    assert((size_t)opening_tag_end > (size_t)opening_tag_separator);
    assert((size_t)opening_tag_separator > (size_t)opening_tag_start);

    int key_length = (opening_tag_separator - current_text) - relative_key_start;
    assert(key_length > 0);
    
    char *key = arena_alloc(arena, key_length + 1);
    substr_clone(current_text, key, relative_key_start, key_length);

    int element_name_length = (opening_tag_end - current_text) - element_name_start;
    assert(element_name_length > 0);

    char *element_name = arena_alloc(arena, element_name_length + 1);
    substr_clone(current_text, element_name, element_name_start, element_name_length);

    int close_tag_patern_length = start_pattern_length + key_length + end_pattern_length;
    char *close_tag_patern = arena_alloc(arena, close_tag_patern_length + 1);
    snprintf(close_tag_patern, sizeof(*close_tag_patern), "%s%s%s", start_pattern, key, end_pattern);

    char *close_tag = strstr(opening_tag_end + offset + 1, close_tag_patern);
    if (!close_tag) {
       raise_exception("Malformed template: missing loop end for key %s", key);
       exit(1);
    }

    Json *arr = eval_object(arena, context, key);

    if (arr && arr->type == JSON_ARRAY) {
        size_t elem_count = 0;
        for (Json *e = arr->child; e; e = e->next) elem_count++;
    
        char *replacement = arena_alloc(arena, MEM_KiB * elem_count);
        size_t offset = 0;

        char *block_buff = arena_alloc(arena, MEM_KiB);
	size_t block_start = (size_t)opening_tag_end + 2;
	size_t block_len = (size_t)opening_tag_end - (size_t)close_tag - 2;
	raise_trace("block_len %p = %p - %p - 2", block_len, opening_tag_end, close_tag);
	assert(block_len > 0);
        substr_clone(current_text, block_buff, block_start, block_len);
    
        for (Json *elem = arr->child; elem; elem = elem->next) {
	    char *block = arena_strdup(arena, block_buff);
    
            char *prefix = arena_alloc(arena, element_name_length + 2);
            snprintf(prefix, element_name_length + 2, "%s.", element_name);
    
            hmpl_render_interpolation_tags(arena, &block, context, prefix);
	    raise_trace("block after: %s", block);
    
            size_t block_len = strlen(block);
            memcpy(replacement + offset, block, block_len);
            offset += block_len;
        }

        replacement[offset] = '\0';
	raise_trace("replacement: %s", replacement);

        char *new_text = arena_repstr(arena, current_text,
          (size_t)opening_tag_start - 1,
          close_tag + close_tag_patern_length - opening_tag_start + 2,
          replacement);

         *text_ptr = new_text;
    }
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
  Arena arena = arena_init(MEM_MiB);

  hmpl_render_with_arena(&arena, text, context);

  arena_free(&arena);
}
