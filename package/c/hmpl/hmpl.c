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

// {{item#array}}...{{/array}}
void hmpl_render_section_tags(Arena *arena, char **text_ptr, Json *context, const char * const prefix_start, const char * const prefix_end, const char * const separator_pattern) {
    raise_debug("hmpl_render_section_tags(%p, %s, <optimized>, %s, %s, %s)", arena, *text_ptr, prefix_start, prefix_end, separator_pattern);
    
    // Create search patterns
    char start_pattern[32];
    snprintf(start_pattern, sizeof(start_pattern), "{{%s", prefix_start);
    Slice start_slice = slice_create(char, start_pattern, strlen(start_pattern), 0, strlen(start_pattern));
    raise_trace("start_slice: %s", start_slice.data);

    // Create a mutable copy of separator_pattern
    char separator_copy[32];
    strncpy(separator_copy, separator_pattern, sizeof(separator_copy) - 1);
    separator_copy[sizeof(separator_copy) - 1] = '\0';
    Slice separator_slice = slice_create(char, separator_copy, strlen(separator_copy), 0, strlen(separator_copy));
    raise_trace("separator_slice: %s", separator_slice.data);
    if (separator_slice.len == 0) {
        raise_exception("Unexpected usage: separator pattern cannot be empty");
    }

    // Create slice for the text
    Slice text_slice = slice_create(char, *text_ptr, strlen(*text_ptr), 0, strlen(*text_ptr));
    size_t offset = 0;

    while (1) {
        // Find tag start
        char *text_data = (char*)text_slice.data;
        char *opening_tag_start = strstr(text_data + offset, (char*)start_slice.data);
        if (!opening_tag_start) break;

        // Create slice for separator search
        size_t start_index = opening_tag_start - text_data;
        Slice remaining_slice = slice_subslice(text_slice, start_index, text_slice.len - start_index);
        
        // Find separator
        char *opening_tag_separator = strstr((char*)remaining_slice.data, (char*)separator_slice.data);
        if (!opening_tag_separator) {
            raise_exception("Malformed template: missing separator for section tag or not specified name for element");
            exit(1);
        }
        
        // Extract element name (now before separator)
        size_t separator_index = opening_tag_separator - (char*)remaining_slice.data;
        size_t element_name_start = start_slice.len;
        size_t element_name_length = separator_index;
        
        char *element_name = arena_alloc(arena, element_name_length + 1);
        substr_clone((char*)remaining_slice.data, element_name, element_name_start, element_name_length);
        element_name[element_name_length] = '\0';

        // Find closing braces
        Slice after_separator = slice_subslice(remaining_slice, separator_index + separator_slice.len, 
                                             remaining_slice.len - separator_index - separator_slice.len);
        char *opening_tag_end = strstr((char*)after_separator.data, "}}");
        if (!opening_tag_end) {
            raise_exception("Malformed template: missing closing braces for section tag");
            exit(1);
        }

        // Extract key (now after separator)
        size_t key_start = 0;
        size_t key_length = opening_tag_end - (char*)after_separator.data;
        char *key = arena_alloc(arena, key_length + 1);
        substr_clone((char*)after_separator.data, key, key_start, key_length);
        key[key_length] = '\0';

        // Create pattern for closing tag
        char *close_tag_pattern = arena_alloc(arena, start_slice.len + key_length + 3); // +3 for "{{" and "}}"
        snprintf(close_tag_pattern, start_slice.len + key_length + 3, 
                "{{%s%s}}", prefix_end, key);
        raise_trace("close_tag_pattern: %s", close_tag_pattern);

        // Find closing tag
        size_t after_opening_end = (opening_tag_end - (char*)after_separator.data) + 2;
        Slice after_opening_slice = slice_subslice(after_separator, after_opening_end, 
                                                 after_separator.len - after_opening_end);
        
        // Find the exact closing tag by checking for complete tag pattern
        char *close_tag = NULL;
        char *search_start = (char*)after_opening_slice.data;
        while ((search_start = strstr(search_start, "{{")) != NULL) {
            if (strncmp(search_start, close_tag_pattern, strlen(close_tag_pattern)) == 0) {
                close_tag = search_start;
                break;
            }
            search_start += 2; // Move past the "{{" we found
        }
        
        if (!close_tag) {
            raise_exception("Malformed template: missing loop end for key %s", key);
            exit(1);
        }

        // Get array from context
        Json *arr = eval_object(arena, context, key);

        if (arr && arr->type == JSON_ARRAY) {
            // Count array elements
            size_t elem_count = 0;
            for (Json *e = arr->child; e; e = e->next) elem_count++;
            
            // Allocate memory for replacement
            char *replacement = arena_alloc(arena, MEM_KiB * elem_count);
            size_t replacement_offset = 0;

            // Extract template block
            size_t block_start = after_opening_end;
            size_t block_length = (close_tag - (char*)after_opening_slice.data);
            char *block_buff = arena_alloc(arena, block_length + 1);
            substr_clone((char*)after_opening_slice.data, block_buff, block_start, block_length);
            block_buff[block_length] = '\0';

            // Process each array element
            for (Json *elem = arr->child; elem; elem = elem->next) {
                char *block = arena_strdup(arena, block_buff);
                
                char *prefix = arena_alloc(arena, element_name_length + 2);
                snprintf(prefix, element_name_length + 2, "%s.", element_name);
                
                hmpl_render_interpolation_tags(arena, &block, context, prefix);
                raise_trace("block after: %s", block);
                
                size_t block_len = strlen(block);
                memcpy(replacement + replacement_offset, block, block_len);
                replacement_offset += block_len;
            }

            replacement[replacement_offset] = '\0';
            raise_trace("replacement: %s", replacement);

            // Calculate replacement positions
            size_t replace_start = start_index;
            size_t replace_length = (close_tag - (char*)after_opening_slice.data) + 
                                  start_slice.len + key_length + 2;

            // Perform replacement
            char *new_text = arena_repstr(arena, (char*)text_slice.data, replace_start, replace_length, replacement);
            *text_ptr = new_text;
            
            // Update text slice
            text_slice = slice_create(char, new_text, strlen(new_text), 0, strlen(new_text));
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
