#include "hmpl.h"

Json *eval_object(Arena *arena, const Json * const context, const char * const query) {
  raise_debug("eval_object(%p, %s, %s)", arena, json_to_string(DISPOSABLE_ARENA, context), query);
  if (!context || !query) return NULL;

  const Json *res = context;
  char *dot, *key = arena_strdup(arena, query);

  while ((dot = strchr(key, '.')) != NULL) {
    *dot = '\0';
    raise_debug("eval_object: key: %s", key);
    res = json_get_object_item(res, key);
    if (!res)
      return NULL;
    key = dot + 1;
  }

  raise_debug("eval_object: final key: %s", key);
  return json_get_object_item(res, key);
}

char *eval_string(Arena *arena, const Json * const context, const char * const query) {
  Json *res = eval_object(arena, context, query);
  if (!res)
    return NULL;
  return json_to_string_with_opts(arena, res, JSON_RAW);
}

// {{[prefix]key}}
void hmpl_render_interpolation_tags(Arena *arena, char **text_ptr, const Json * const context, const char * const prefix) {
  raise_debug("hmpl_render_interpolation_tags(%p, %s, %s)", arena, *text_ptr, prefix);
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
          raise_debug("no replacement for key: `%s`", key);
          offset = (end - current_text) + 2;
          continue;
      }
      
      // Calculate the replacement length from the beginning of {{[prefix] to the end }}
      int replace_length = (end - start) + 2; // +2 for "}}"
      
      char *new_text = arena_repstr(arena, current_text,
        start_index,
        replace_length,
        replacement);

      
      

      *text_ptr = new_text;
      offset = start_index;
  }
}

void hmpl_render_interpolation_tags_opts(Arena *arena, char **text_ptr, const Json *context, const HmplInterpolationTagsOptions *options) {
  hmpl_render_interpolation_tags(arena, text_ptr, context, options->prefix);
}

// {{item#array}}...{{/array}}
void hmpl_render_section_tags(Arena *arena, char **text_ptr, Json *context, const char * const prefix_start, const char * const prefix_end, const char * const separator_pattern) {
    raise_debug("hmpl_render_section_tags(%p, %s, <optimized>, %s, %s, %s)", arena, *text_ptr, prefix_start, prefix_end, separator_pattern);

    // prefix_start and prefix_end must be different
    assert(strcmp(prefix_start, prefix_end) != 0);

    // prefix_start, prefix_end and separator_pattern must be less than 28 characters
    assert(strlen(prefix_start) < 28);
    assert(0 < strlen(separator_pattern) && strlen(prefix_end) < 28);
    assert(0 < strlen(separator_pattern) && strlen(separator_pattern) < 28);
    
    // Create search patterns
    char start_pattern[32];
    snprintf(start_pattern, sizeof(start_pattern), "{{%s", prefix_start);
    Slice start_slice = slice_create(char, start_pattern, strlen(start_pattern), 0, strlen(start_pattern));
    

    // Create a mutable copy of separator_pattern
    char separator_copy[32];
    strncpy(separator_copy, separator_pattern, sizeof(separator_copy) - 1);
    separator_copy[sizeof(separator_copy) - 1] = '\0';
    Slice separator_slice = slice_create(char, separator_copy, strlen(separator_copy), 0, strlen(separator_copy));
    
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
        size_t separator_index = opening_tag_separator - (char*)remaining_slice.data - strlen(start_slice.data);
        size_t element_name_start = start_slice.len;
        size_t element_name_length = separator_index;
        

        char *element_name = arena_alloc(arena, element_name_length + 1);
        substr_clone((char*)remaining_slice.data, element_name, element_name_start, element_name_length);
        

        // Find closing braces
        Slice after_separator = slice_subslice(remaining_slice, separator_index + separator_slice.len, 
                                             remaining_slice.len - separator_index - separator_slice.len);
        char *opening_tag_end = strstr((char*)after_separator.data, "}}");
        if (!opening_tag_end) {
            raise_exception("Malformed template: missing closing braces for section tag");
            exit(1);
        }

        // Extract key (now after separator)
        size_t key_start = strlen(start_slice.data);
        size_t key_length = opening_tag_end - (char*)after_separator.data - strlen(start_slice.data);
        char *key = arena_alloc(arena, key_length + 1);
        substr_clone((char*)after_separator.data, key, key_start, key_length);
        
        key[key_length] = '\0';

        // +2 for "{{" and "}}" + 1 for null terminator
        size_t close_tag_pattern_length = key_length + strlen(prefix_end) + 2 + 2 + 1;
        char *close_tag_pattern = arena_alloc(arena, close_tag_pattern_length);
        snprintf(
          close_tag_pattern,
          close_tag_pattern_length,
          "{{%s%s}}",
          prefix_end,
          key
        );
        

        size_t after_opening_end = (opening_tag_end - (char*)after_separator.data) + 2;
        Slice after_opening_slice = slice_subslice(
          after_separator,
          after_opening_end, 
          after_separator.len - after_opening_end
        );
        
        
        // Find the exact closing tag by directly searching for the closing tag pattern
        char *close_tag = strstr(after_opening_slice.data, close_tag_pattern);
        
        
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
            size_t block_length = (close_tag - (char*)after_opening_slice.data);
            char *block_buff = arena_alloc(arena, block_length + 1);
            substr_clone((char*)after_opening_slice.data, block_buff, 0, block_length);
            block_buff[block_length] = '\0';
            

            // Process each array element
            for (Json *elem = arr->child; elem; elem = elem->next) {
                char *block = arena_strdup(arena, block_buff);
                
                char *prefix = arena_alloc(arena, element_name_length + 2);
                snprintf(prefix, element_name_length + 2, "%s.", element_name);
                
                raise_debug("Processing element with prefix: %s", prefix);
                raise_debug("Block before processing: %s", block);

                hmpl_render_interpolation_tags(arena, &block, elem, prefix);
                raise_debug("Block after interpolation: %s", block);
                
                // Recursively process nested sections
                hmpl_render_section_tags(arena, &block, elem, prefix_start, prefix_end, separator_pattern);
                raise_debug("Block after section processing: %s", block);
                
                size_t block_len = strlen(block);
                memcpy(replacement + replacement_offset, block, block_len);
                replacement_offset += block_len;
            }

            replacement[replacement_offset] = '\0';
            

            // Calculate replacement positions
            size_t replace_start = start_index;
            size_t replace_length = (close_tag - opening_tag_start) + strlen(close_tag_pattern);
            
            
            

            // Perform replacement
            char *new_text = arena_repstr(arena, (char*)text_slice.data, replace_start, replace_length, replacement);
            
            *text_ptr = new_text;
            
            // Update text slice
            text_slice = slice_create(char, new_text, strlen(new_text), 0, strlen(new_text));
        }
        
        offset = start_index;
    }
}

void hmpl_render_section_tags_opts(Arena *arena, char **text_ptr, const Json *context, const HmplSectionTagsOptions *options) {
  // Create a copy of the context without const qualifier for compatibility with hmpl_render_section_tags
  hmpl_render_section_tags(arena, text_ptr, (Json*)context, options->prefix_start, options->prefix_end, options->separator_pattern);
}

void hmpl_render_with_arena(Arena *arena, char **text, const Json * const context, const HmplOptions * const options) {
  if (context->type != JSON_OBJECT) {
    raise_exception("Malformed context: context is not json");
    exit(1);
  }

  hmpl_render_interpolation_tags_opts(arena, text, context, &options->interpolation_tags_options);
  hmpl_render_section_tags_opts(arena, text, context, &options->section_tags_options);
}

void hmpl_render(char **text, const Json * const context, const HmplOptions * const options) {
  Arena arena = arena_init(MEM_MiB);

  hmpl_render_with_arena(&arena, text, context, options);

  arena_free(&arena);
}
