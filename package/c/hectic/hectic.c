#include "hectic.h"
#include <fnmatch.h>
#include <string.h>
#include <assert.h>

// On systems without strsep, provide a custom implementation
#ifndef _GNU_SOURCE
#define _GNU_SOURCE 1
#endif

#ifndef HAVE_STRSEP
char *strsep(char **stringp, const char *delim) {
    char *start = *stringp;
    char *p;

    if (!start)
        return NULL;

    p = start;
    while (*p && !strchr(delim, *p))
        p++;

    if (*p) {
        *p++ = '\0';
        *stringp = p;
    } else {
        *stringp = NULL;
    }

    return start;
}
#endif

// Forward declarations
void free_log_rules();
const char* json_type_to_string(JsonType type);

// Global color mode variable definition
ColorMode color_mode = COLOR_MODE_AUTO;

// Global logging variables
LogLevel current_log_level = LOG_LEVEL_INFO;
LogRule *log_rules = NULL;

const char* color_mode_to_string(ColorMode mode) {
    switch (mode) {
        case COLOR_MODE_AUTO: return "AUTO";
        case COLOR_MODE_FORCE: return "FORCE";
        case COLOR_MODE_DISABLE: return "DISABLE";
        default: return "UNKNOWN";
    }
}

void set_output_color_mode(ColorMode mode) {
    // Log the color mode change
    const char* mode_name = color_mode_to_string(mode);
    
    // Using fprintf since this might be called before logging is initialized
    raise_message(LOG_LEVEL_INFO, __FILE__, __func__, __LINE__, "CONFIG: Setting output color mode to %s", mode_name);
    
    // Set the mode
    color_mode = mode;
}

#define POSITION_INFO_DECLARATION const char *file, const char *func, int line
#define POSITION_INFO file, func, line
#define CTX_DECLARATION POSITION_INFO_DECLARATION, Arena *arena
#define CTX(lifetimed_arena) POSITION_INFO, arena = (lifetimed_arena)

// ------------
// -- Logger --
// ------------

const char* log_level_to_string(LogLevel level) {
    switch (level) {
        case LOG_LEVEL_TRACE: return "TRACE";
        case LOG_LEVEL_DEBUG: return "DEBUG";
        case LOG_LEVEL_LOG:  return "LOG";
        case LOG_LEVEL_INFO:  return "INFO";
        case LOG_LEVEL_NOTICE:  return "NOTICE";
        case LOG_LEVEL_WARN:  return "WARN";
        case LOG_LEVEL_EXCEPTION: return "EXCEPTION";
        default:              return "UNKNOWN";
    }
}

const char* log_level_to_color(LogLevel level) {
    switch (level) {
        case LOG_LEVEL_TRACE: return OPTIONAL_COLOR(COLOR_GREEN);
        case LOG_LEVEL_DEBUG: return OPTIONAL_COLOR(COLOR_BLUE);
        case LOG_LEVEL_LOG:  return OPTIONAL_COLOR(COLOR_CYAN);
        case LOG_LEVEL_INFO:  return OPTIONAL_COLOR(COLOR_GREEN);
        case LOG_LEVEL_NOTICE:  return OPTIONAL_COLOR(COLOR_CYAN);
        case LOG_LEVEL_WARN:  return OPTIONAL_COLOR(COLOR_YELLOW);
        case LOG_LEVEL_EXCEPTION: return OPTIONAL_COLOR(COLOR_RED);
        default:              return OPTIONAL_COLOR(COLOR_RESET);
    }
}


LogLevel log_level_from_string(const char *level_str) {
    if (!level_str) return LOG_LEVEL_INFO;
    if (strcmp(level_str, "TRACE") == 0)
        return LOG_LEVEL_TRACE;
    else if (strcmp(level_str, "DEBUG") == 0)
        return LOG_LEVEL_DEBUG;
    else if (strcmp(level_str, "LOG") == 0)
        return LOG_LEVEL_LOG;
    else if (strcmp(level_str, "INFO") == 0)
        return LOG_LEVEL_INFO;
    else if (strcmp(level_str, "NOTICE") == 0)
        return LOG_LEVEL_NOTICE;
    else if (strcmp(level_str, "WARN") == 0)
        return LOG_LEVEL_WARN;
    else if (strcmp(level_str, "EXCEPTION") == 0)
        return LOG_LEVEL_EXCEPTION;
    else
        return LOG_LEVEL_INFO;
}

void logger_level_reset() {
    current_log_level = LOG_LEVEL_INFO;
    free_log_rules();
}

void logger_level(LogLevel level) {
    current_log_level = level;
    free_log_rules(); // Clear any complex rules
}

void init_logger(void) {
    const char* env_level = getenv("LOG_LEVEL");
    
    if (env_level) {
        // Check if it's a complex rule format (contains '=' or ',')
        if (strchr(env_level, '=') || strchr(env_level, ',')) {
            if (logger_parse_rules(env_level)) {
                fprintf(stderr, "INIT: Logger initialized with complex rules from environment\n");
            } else {
                fprintf(stderr, "INIT: Failed to parse complex log rules, using default level INFO\n");
                current_log_level = LOG_LEVEL_INFO;
            }
        } else {
            // Simple log level
            current_log_level = log_level_from_string(env_level);
            fprintf(stderr, "INIT: Logger initialized with level %s from environment\n", 
                    log_level_to_string(current_log_level));
        }
    } else {
        fprintf(stderr, "INIT: Logger initialized with default level %s\n", 
                log_level_to_string(current_log_level));
    }
}

char* raise_message(
  LogLevel level,
  const char *file,
  const char *func,
  int line,
  const char *format,
  ...) {
    // Check against the effective log level for this context
    LogLevel effective_level = logger_get_effective_level(file, func, line);
    if (level < effective_level) {
        return NULL;
    }

    time_t now = time(NULL);
    struct tm tm_info;
    localtime_r(&now, &tm_info);
    static char timeStr[20];
    strftime(timeStr, sizeof(timeStr), "%Y-%m-%d %H:%M:%S", &tm_info);

    // Print timestamp, log level with color, location info
    fprintf(stderr, "%s %s%s%s %s:%s:%s%d%s ", 
            timeStr, 
            log_level_to_color(level), 
            log_level_to_string(level), 
            OPTIONAL_COLOR(COLOR_RESET),
            file,
            func,
            OPTIONAL_COLOR(COLOR_GREEN),
            line,
            OPTIONAL_COLOR(COLOR_RESET));

    // Print the actual message with variable arguments
    va_list args;
    va_start(args, format);
    vfprintf(stderr, format, args);
    va_end(args);

    fprintf(stderr, "\n");

    return timeStr;
}

// -----------
// -- debug --
// -----------

PtrSet *ptrset_init__(POSITION_INFO_DECLARATION, Arena *arena) {
    PtrSet *set = arena_alloc__(POSITION_INFO, arena, sizeof(PtrSet));
    set->data = arena_alloc__(POSITION_INFO, arena, 4 * sizeof(void*));
    set->size = 0;
    set->capacity = 4;
    return set;
}

bool debug_ptrset_contains__(PtrSet *set, void *ptr) {
    for (size_t i = 0; i < set->size; i++) {
        if (set->data[i] == ptr)
            return true;
    }
    return false;
}

void debug_ptrset_add__(CTX_DECLARATION, PtrSet *set, void *ptr) {
    if (set->size == set->capacity) {
        set->capacity = set->capacity ? set->capacity * 2 : 4;
        set->data = arena_realloc__(CTX(arena), set->data, set->capacity, set->capacity * sizeof(void*));
    }
    set->data[set->size++] = ptr;
}

char *string_to_debug_str__(CTX_DECLARATION, const char *name, const char *string) {
    return arena_strdup_fmt__(CTX(arena), "%s = %p \"%s\"", name, string, string);
}

char *int_to_debug_str__(CTX_DECLARATION, const char *name, int number) {
    return arena_strdup_fmt__(CTX(arena), "%s = %d", name, number);
}

char *float_to_debug_str__(CTX_DECLARATION, const char *name, double number) {
    return arena_strdup_fmt__(CTX(arena), "%s = %f", name, number);
}

char *size_t_to_debug_str__(CTX_DECLARATION, const char *name, size_t number) {
    return arena_strdup_fmt__(CTX(arena), "%s = %zu", name, number);
}

char *ptr_to_debug_str__(CTX_DECLARATION, const char *name, void *ptr) {
    return arena_strdup_fmt__(CTX(arena), "%s = %p", name, ptr);
}

char *char_to_debug_str__(CTX_DECLARATION, const char *name, char c) {
    return arena_strdup_fmt__(CTX(arena), "%s = %c", name, c);
}


/* Private function */
char *debug_join_debug_strings_v(CTX_DECLARATION, int count, va_list args) {
    raise_message(LOG_LEVEL_TRACE, POSITION_INFO, "DEBUG JOIN: Joining %d strings", count);
    int total_len = 1;

    va_list args_copy;
    va_copy(args_copy, args);
    raise_message(LOG_LEVEL_TRACE, POSITION_INFO, "DEBUG JOIN: Starting first pass");
    for (int i = 0; i < count; i++) {
        raise_message(LOG_LEVEL_TRACE, POSITION_INFO, "iter1");
        char *s = va_arg(args_copy, char*);
        int len = strlen(s);
        raise_message(LOG_LEVEL_TRACE, POSITION_INFO, "DEBUG JOIN: String %d: [%s] %p len: %d", i, s, s, len);
        total_len += len;
        raise_message(LOG_LEVEL_TRACE, POSITION_INFO, "iter2");
    }
    va_end(args_copy);

    char *joined = arena_alloc__(CTX(arena), total_len);
    joined[0] = '\0';

    raise_message(LOG_LEVEL_TRACE, POSITION_INFO, "DEBUG JOIN: concatenating strings");
    va_copy(args_copy, args);
    for (int i = 0; i < count; i++) {
        char *s = va_arg(args_copy, char*);
        strcat(joined, s);
        if (i < count - 1) {
            strcat(joined, ", ");
        }
    }
    va_end(args_copy);

    return joined;
}

char *struct_to_debug_str__(CTX_DECLARATION, const char *type, const char *name, void *ptr, int count, ...) {
    raise_message(LOG_LEVEL_TRACE, POSITION_INFO, "DEBUG STR: type: %s, name: %s, ptr: %p, count: %d", type, name, ptr, count);

    va_list args;
    va_start(args, count);
    char *joined = debug_join_debug_strings_v(CTX(arena), count, args);
    va_end(args);

    return arena_strdup_fmt__(CTX(arena), "%s %s = {%s} %p", type, name, joined, ptr);
}

// ------------
// -- arena --
// ------------

Arena arena_init__(POSITION_INFO_DECLARATION, size_t size) {
    // Function entry logging
    raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, 
        "ARENA INIT: Creating arena (size: %zu bytes)", size);
    
    Arena arena;
    arena.begin = malloc(size);
    
    // Check for allocation failure
    if (!arena.begin) {
        raise_message(LOG_LEVEL_EXCEPTION, POSITION_INFO,
            "ARENA INIT: Failed to allocate memory for arena (requested: %zu bytes)", size);
        exit(1);
    }
    
    memset(arena.begin, 0, size);
    arena.current = arena.begin;
    arena.capacity = size;
    
    // Success logging at LOG level
    raise_message(LOG_LEVEL_LOG, POSITION_INFO,
	"ARENA INIT: Arena initialized successfully (address: %p, capacity: %zu bytes)", arena.begin, size);
    return arena;
}

void* arena_alloc_or_null__(POSITION_INFO_DECLARATION, Arena *arena, size_t size, bool expand) {
    raise_message(LOG_LEVEL_TRACE, POSITION_INFO, 
        "ARENA ALLOC: Requesting memory from arena (arena: %p, size: %zu bytes)", arena, size);

    if (arena->begin == 0) {
        raise_message(LOG_LEVEL_DEBUG, POSITION_INFO,
            "ARENA ALLOC: Arena not initialized, creating new arena");
        *arena = arena_init__(POSITION_INFO, 1024);
    }

    // align size to 8
    size = (size + 7) & ~((size_t)7);

    size_t used = (size_t)arena->current - (size_t)arena->begin;
    size_t available = arena->capacity - used;

    if (available < size) {
        if (expand) {
            // FIXME(yukkop): All pointers to the arena will be invalidated
            // We need to use a virtual memory allocator to avoid this issue
            size_t new_capacity = arena->capacity * 2 + size;
            raise_message(LOG_LEVEL_WARN, POSITION_INFO,
                "ARENA ALLOC: Expanding arena (old: %zu, new: %zu)", arena->capacity, new_capacity);

            void *new_mem = malloc(new_capacity);
            if (!new_mem) {
                raise_message(LOG_LEVEL_WARN, POSITION_INFO,
                    "ARENA ALLOC: Failed to expand arena (requested: %zu bytes)", new_capacity);
                return NULL;
            }

            memcpy(new_mem, arena->begin, used);
            free(arena->begin);
            arena->begin = new_mem;
            arena->current = (char *)new_mem + used;
            arena->capacity = new_capacity;

            raise_message(LOG_LEVEL_WARN, POSITION_INFO,
                "ARENA ALLOC: Arena expanded successfully (address: %p, capacity: %zu)", new_mem, new_capacity);
        } else {
            raise_message(LOG_LEVEL_WARN, POSITION_INFO,
                "ARENA ALLOC: Insufficient memory in arena (address: %p, capacity: %zu bytes, used: %zu bytes, requested: %zu bytes)",
                arena->begin, arena->capacity, used, size);
            return NULL;
        }
    }

    void *mem = arena->current;
    arena->current = (char*)arena->current + size;

    raise_message(LOG_LEVEL_DEBUG, POSITION_INFO,
        "ARENA ALLOC: Memory allocated (address: %p, size: %zu)", mem, size);
    return mem;
}

void* arena_alloc__(POSITION_INFO_DECLARATION, Arena *arena, size_t size) {
    // Function entry logging
    raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, 
                 "ARENA ALLOC: Allocating memory (arena: %p, size: %zu bytes)", arena, size);
    
    void *mem = arena_alloc_or_null__(POSITION_INFO, arena, size, false);
    if (!mem) {
        raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, 
      "ARENA ALLOC: Allocation failed (arena: %p, requested: %zu bytes)", arena, size);
        raise_message(LOG_LEVEL_EXCEPTION, POSITION_INFO, 
	  "ARENA ALLOC: Arena out of memory (requested: %zu bytes)", size);
        exit(1);
    }
    
    // Success logging
    raise_message(LOG_LEVEL_LOG, POSITION_INFO,
                 "ARENA ALLOC: Memory allocated successfully (address: %p, size: %zu bytes)", mem, size);
    return mem;
}

/*
 * Reallocates a memory block and copies the contents of the old block to the new one.
 * NOTE(yukkop): We need to provide the old size to avoid copying more than needed.
 */
void* arena_realloc__(POSITION_INFO_DECLARATION, Arena *arena,
                           void *ptr, size_t size, size_t new_size) {
    void *new_ptr = NULL;
    if (ptr == NULL) {
        new_ptr = arena_alloc__(POSITION_INFO, arena, new_size);
    } else if (new_size <= size) {
        new_ptr = ptr;
    } else {
        // FIXME(yukkop): Must tries to expand the arena before allocating new memory
        new_ptr = arena_alloc_or_null__(POSITION_INFO, arena, new_size, false);
        if (new_ptr)
            memcpy(new_ptr, ptr, size);
    }
    return new_ptr;
}

void arena_reset__(POSITION_INFO_DECLARATION, Arena *arena) {
  // Function entry logging
  raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, 
    "ARENA RESET: Resetting arena (address: %p)", arena);
  
  // Check for NULL arena
  if (!arena) {
    raise_message(LOG_LEVEL_WARN, POSITION_INFO,
      "ARENA RESET: Attempted to reset NULL arena");
    return;
  }
  
  // Reset the arena
  arena->current = arena->begin;
  
  // Operation success logging
  raise_message(LOG_LEVEL_LOG, POSITION_INFO,
    "ARENA RESET: Arena reset successfully (address: %p, capacity: %zu bytes)", 
    arena->begin, arena->capacity);
}

void arena_free__(POSITION_INFO_DECLARATION, Arena *arena) {
  // Function entry logging
  raise_message(LOG_LEVEL_DEBUG, POSITION_INFO,
    "ARENA FREE: Releasing arena memory (address: %p)", arena);
  
  // Check for NULL arena
  if (!arena) {
    raise_message(LOG_LEVEL_WARN, POSITION_INFO,
      "ARENA FREE: Attempted to free NULL arena");
    return;
  }
  
  // Check for NULL begin pointer
  if (!arena->begin) {
    raise_message(LOG_LEVEL_WARN, POSITION_INFO,
      "ARENA FREE: Attempted to free arena with NULL memory block");
    return;
  }
  
  // Calculate used memory for logging
  size_t used = (size_t)arena->current - (size_t)arena->begin;
  
  // Free the memory
  free(arena->begin);
  
  // Success logging
  raise_message(LOG_LEVEL_LOG, POSITION_INFO,
    "ARENA FREE: Arena released successfully (address: %p, capacity: %zu bytes, used: %zu bytes)",
    arena->begin, arena->capacity, used);
    
  // Clear the pointers
  arena->begin = NULL;
  arena->current = NULL;
  arena->capacity = 0;
}

/* 
 * Duplicates a string and returns a pointer to the new string.
*/
char* arena_strdup__(POSITION_INFO_DECLARATION, Arena *arena, const char *s) {
    // Function entry logging
    raise_message(LOG_LEVEL_TRACE, POSITION_INFO,
        "ARENA STRDUP: Duplicating string (arena: %p, source: %p, preview: %.20s%s)",
        arena, s, s ? s : "", s && strlen(s) > 20 ? "..." : "");
    
    // Check for NULL string
    if (!s) {
        raise_message(LOG_LEVEL_DEBUG, POSITION_INFO,
            "ARENA STRDUP: Source string is NULL, returning NULL");
        return NULL;
    }
    
    // Calculate string length and allocate memory
    size_t len = strlen(s) + 1;
    
    // Success case
    char *result = (char*)arena_alloc__(POSITION_INFO, arena, len);
    
    // Copy the string
    memcpy(result, s, len);
    
    // Success logging
    raise_message(LOG_LEVEL_DEBUG, POSITION_INFO,
        "ARENA STRDUP: String duplicated successfully (result: %p, length: %zu bytes)", 
        result, len);
    
    return result;
}

/*
 * Duplicates a string and returns a pointer to the new string.
 * The string is formatted using the provided format string and arguments.
 */
char* arena_strdup_fmt__(POSITION_INFO_DECLARATION, Arena *arena, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    int len = vsnprintf(NULL, 0, fmt, args);
    va_end(args);

    if (len < 0) return NULL;

    char *temp = arena_alloc__(POSITION_INFO, DISPOSABLE_ARENA, len + 1);
    va_start(args, fmt);
    vsnprintf(temp, len + 1, fmt, args);
    va_end(args);

    return arena_strdup__(POSITION_INFO, arena, temp);
}

char* arena_strncpy__(POSITION_INFO_DECLARATION, Arena *arena, const char *start, size_t len) {
    // Function entry logging
    raise_message(LOG_LEVEL_TRACE, POSITION_INFO,
        "ARENA STRNCPY: Copying string (arena: %p, source: %p, length: %zu, preview: %.20s%s)",
        arena, start, len, start ? start : "", start && strlen(start) > 20 ? "..." : "");
    
    // Check for NULL string
    if (!start) {
        raise_message(LOG_LEVEL_DEBUG, POSITION_INFO,
            "ARENA STRNCPY: Source string is NULL, returning NULL");
        return NULL;
    }
    
    // Allocate memory for the string plus null terminator
    char *result = (char*)arena_alloc__(POSITION_INFO, arena, len + 1);
    if (!result) {
        raise_message(LOG_LEVEL_DEBUG, POSITION_INFO,
            "ARENA STRNCPY: Memory allocation failed");
        return NULL;
    }
    
    // Copy the string and ensure null termination
    strncpy(result, start, len);
    result[len] = '\0';
    
    // Success logging
    raise_message(LOG_LEVEL_DEBUG, POSITION_INFO,
        "ARENA STRNCPY: String copied successfully (result: %p, length: %zu bytes)", 
        result, len + 1);
    
    return result;
}

/*
 * Replaces a substring in a string with a new string.
 */
char* arena_repstr__(POSITION_INFO_DECLARATION, Arena *arena,
                             const char *src, size_t start, size_t len, const char *rep) {
  // Function entry logging
  raise_message(LOG_LEVEL_TRACE, POSITION_INFO, 
    "ARENA REPSTR: Replacing substring (source: %p, start: %zu, length: %zu, replacement: %.20s%s)", 
    src, start, len, rep, strlen(rep) > 20 ? "..." : "");
  
  // Check inputs
  if (!src) {
    raise_message(LOG_LEVEL_WARN, POSITION_INFO,
      "ARENA REPSTR: Source string is NULL");
    return NULL;
  }
  
  if (!rep) {
    raise_message(LOG_LEVEL_WARN, POSITION_INFO,
      "ARENA REPSTR: Replacement string is NULL");
    return NULL;
  }
  
  // Calculate lengths
  int src_len = strlen(src);
  int rep_len = strlen(rep);
  
  // Validate start and length
  if (start > (size_t)src_len) {
    raise_message(LOG_LEVEL_WARN, POSITION_INFO,
      "ARENA REPSTR: Start position %zu exceeds source length %d", start, src_len);
    // Return a copy of the source string
    return arena_strdup__(POSITION_INFO, arena, src);
  }
  
  if (start + len > (size_t)src_len) {
    size_t old_len = len;
    len = src_len - start;
    raise_message(LOG_LEVEL_DEBUG, POSITION_INFO,
      "ARENA REPSTR: Adjusted length from %zu to %zu to fit source bounds", old_len, len);
  }
  
  // Calculate new length and allocate memory
  int new_len = src_len - (int)len + rep_len;
  char *new_str = (char*)arena_alloc__(POSITION_INFO, arena, new_len + 1);
  
  // Perform the replacement operation
  memcpy(new_str, src, start);
  memcpy(new_str + start, rep, rep_len);
  strcpy(new_str + start + rep_len, src + start + len);
  
  // Success logging
  raise_message(LOG_LEVEL_DEBUG, POSITION_INFO,
    "ARENA REPSTR: Replacement complete (result: %p, new length: %d)", new_str, new_len);
  
  return new_str;
}

// ----------
// -- misc --
// ----------

void substr_clone__(POSITION_INFO_DECLARATION, const char * const src, char *dest, size_t from, size_t len) {
    // Log function entry at TRACE level
    raise_message(LOG_LEVEL_TRACE, POSITION_INFO,
        "Function called with src=%p, dest=%p, from=%zu, len=%zu",
        src, dest, from, len);

    if (!src || !dest) {
        raise_message(LOG_LEVEL_EXCEPTION, POSITION_INFO,
            "Invalid NULL pointer: %s%s",
            (!src ? "src " : ""),
            (!dest ? "dest" : ""));
        if (dest) dest[0] = '\0';
        return;
    }

    size_t srclen = strlen(src);
    if (from >= srclen) {
        // Log warning with context when 'from' is out of range
        raise_message(LOG_LEVEL_WARN, POSITION_INFO,
            "Out of range: 'from' index (%zu) exceeds source length (%zu)",
            from, srclen);
        dest[0] = '\0';
        return;
    }

    // Adjust length if needed
    if (from + len > srclen) {
        size_t old_len = len;
        len = srclen - from;
        raise_message(LOG_LEVEL_DEBUG, POSITION_INFO,
            "Adjusted length from %zu to %zu to fit source bounds",
            old_len, len);
    }

    // Copy the substring
    strncpy(dest, src + from, len);
    dest[len] = '\0';

    // Log success at TRACE level
    raise_message(LOG_LEVEL_TRACE, POSITION_INFO,
        "Successfully copied %zu bytes: \"%.*s\"",
        len, (int)len, dest);
}

// ----------
// -- Json --
// ----------

char *json_to_pretty_str__(POSITION_INFO_DECLARATION, Arena *arena, const Json * const item, int indent_level) {
    raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, 
                  "PRETTY: Starting JSON prettification (item: %p, indent: %d)", 
                  item, indent_level);
    
    if (!item) {
        raise_message(LOG_LEVEL_EXCEPTION, POSITION_INFO, 
                     "PRETTY: Invalid JSON object (NULL) provided for prettification");
        return NULL;
    }
    
    if (!arena) {
        raise_message(LOG_LEVEL_EXCEPTION, POSITION_INFO,
                     "PRETTY: Invalid arena (NULL) provided for prettification");
        return NULL;
    }
    
    char *out = arena_alloc__(POSITION_INFO, arena, 1024);
    if (!out) {
        raise_message(LOG_LEVEL_EXCEPTION, POSITION_INFO, 
                     "PRETTY: Memory allocation failed during JSON prettification");
        return NULL;
    }
    
    char *ptr = out;
    
    if (item->type == JSON_OBJECT) {
        ptr += sprintf(ptr, "{\n");
        
        Json *child = item->child;
        int child_count = 0;
        
        raise_message(LOG_LEVEL_TRACE, POSITION_INFO, 
                      "PRETTY: Processing JSON object children");
        
        while (child) {
            for (int i = 0; i < indent_level + 1; i++) {
                ptr += sprintf(ptr, "  ");
            }
            
            ptr += sprintf(ptr, "\"%s\": ", child->key ? child->key : "");
            char *child_str = json_to_pretty_str__(POSITION_INFO, arena, child, indent_level + 1);
            if (child_str) {
                ptr += sprintf(ptr, "%s", child_str);
            } else {
                raise_message(LOG_LEVEL_WARN, POSITION_INFO, 
                              "PRETTY: Failed to prettify child element (key=%s)", 
                              child->key ? child->key : "<null>");
            }
            
            if (child->next) {
                ptr += sprintf(ptr, ",\n");
            } else {
                ptr += sprintf(ptr, "\n");
            }
            child = child->next;
            child_count++;
        }
        
        for (int i = 0; i < indent_level; i++) {
            ptr += sprintf(ptr, "  ");
        }
        sprintf(ptr, "}");
        raise_message(LOG_LEVEL_TRACE, POSITION_INFO, 
                      "PRETTY: Object prettification complete with %d child elements", child_count);
    } else if (item->type == JSON_ARRAY) {
        ptr += sprintf(ptr, "[\n");
        
        Json *child = item->child;
        int child_count = 0;
        
        raise_message(LOG_LEVEL_TRACE, POSITION_INFO, 
                      "PRETTY: Processing JSON array elements");
        
        while (child) {
            // Add indentation
            for (int i = 0; i < indent_level + 1; i++) {
                ptr += sprintf(ptr, "  ");
            }
            
            char *child_str = json_to_pretty_str__(POSITION_INFO, arena, child, indent_level + 1);
            if (child_str) {
                ptr += sprintf(ptr, "%s", child_str);
            } else {
                raise_message(LOG_LEVEL_WARN, POSITION_INFO, 
                              "PRETTY: Failed to prettify array element at index %d", child_count);
            }
            
            if (child->next) {
                ptr += sprintf(ptr, ",\n");
            } else {
                ptr += sprintf(ptr, "\n");
            }
            child = child->next;
            child_count++;
        }
        
        for (int i = 0; i < indent_level; i++) {
            ptr += sprintf(ptr, "  ");
        }
        sprintf(ptr, "]");
        raise_message(LOG_LEVEL_TRACE, POSITION_INFO, 
                      "PRETTY: Array prettification complete with %d elements", child_count);
    } else if (item->type == JSON_STRING) {
        sprintf(ptr, "\"%s\"", item->JsonValue.string ? item->JsonValue.string : "");
    } else if (item->type == JSON_NUMBER) {
        sprintf(ptr, "%g", item->JsonValue.number);
    } else if (item->type == JSON_BOOL) {
        sprintf(ptr, item->JsonValue.boolean ? "true" : "false");
    } else if (item->type == JSON_NULL) {
        sprintf(ptr, "null");
    }
    
    raise_message(LOG_LEVEL_LOG, POSITION_INFO, 
                  "PRETTY: JSON %s prettified (length=%zu)", 
                  json_type_to_string(item->type), strlen(out));
    
    return out;
}

const char* json_type_to_string(JsonType type) {
    switch (type) {
        case JSON_NULL: return "NULL";
        case JSON_BOOL: return "BOOL";
        case JSON_NUMBER: return "NUMBER";
        case JSON_STRING: return "STRING";
        case JSON_ARRAY: return "ARRAY";
        case JSON_OBJECT: return "OBJECT";
        default: return "UNKNOWN";
    }
}


/* Utility: Skip whitespace */
static const char *skip_whitespace(const char *s) {
    while (*s && isspace((unsigned char)*s))
        s++;
    return s;
}

static Json *json_parse_value__(POSITION_INFO_DECLARATION, const char **s, Arena *arena);

/* Parse a JSON string (does not handle full escaping) */
static char *json_parse_string__(POSITION_INFO_DECLARATION, const char **s_ptr, Arena *arena) {
    const char *s = *s_ptr;
    raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, "Entering json_parse_string__ at position: %p", s);
    if (*s != '"') {
        raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, "Expected '\"' at start of string, got: %c", *s);
        return NULL;
    }
    s++; // skip opening quote
    const char *start = s;
    while (*s && *s != '"') {
        if (*s == '\\') {
            s++; // skip escape char indicator
        }
        s++;
    }
    if (*s != '"') {
        raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, "Unterminated string starting at: %p", start);
        return NULL;
    }
    size_t len = s - start;
    char *str = arena_alloc__(POSITION_INFO, arena, len + 1);
    if (!str) {
        raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, "Memory allocation failed in json_parse_string__");
        return NULL;
    }
    memcpy(str, start, len);
    str[len] = '\0';
    *s_ptr = s + 1; // skip closing quote
    raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, "Parsed string: \"%s\" (length: %zu)", str, len);
    return str;
}

/* Parse a number using strtod */
static double json_parse_number__(POSITION_INFO_DECLARATION, const char **s_ptr) {
    raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, "Parsing number at position: %p", *s_ptr);
    char *end;
    double num = strtod(*s_ptr, &end);
    if (*s_ptr == end)
        raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, "No valid number found at: %p", *s_ptr);
    *s_ptr = end;
    raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, "Parsed number: %g", num);
    return num;
}

/* Parse a JSON array: [ value, value, ... ] */
static Json *json_parse_array__(POSITION_INFO_DECLARATION, const char **s, Arena *arena) {
    raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, "Entering json_parse_array__ at position: %p", *s);
    if (**s != '[') return NULL;
    (*s)++; // skip '['
    *s = skip_whitespace(*s);
    Json *array = arena_alloc__(POSITION_INFO, arena, sizeof(Json));
    if (!array) {
        raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, "Memory allocation failed in json_parse_array__");
        return NULL;
    }
    memset(array, 0, sizeof(Json));
    array->type = JSON_ARRAY;
    Json *last = NULL;
    if (**s == ']') { // empty array
        (*s)++;
        raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, "Parsed empty array");
        return array;
    }
    while (**s) {
        Json *element = json_parse_value__(POSITION_INFO, s, arena);
        if (!element) {
            raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, "Failed to parse array element");
            return NULL;
        }
        if (!array->child)
            array->child = element;
        else
            last->next = element;
        last = element;
        *s = skip_whitespace(*s);
        if (**s == ',') {
            (*s)++;
            *s = skip_whitespace(*s);
        } else if (**s == ']') {
            (*s)++;
            raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, "Completed parsing array");
            break;
        } else {
            raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, "Unexpected character '%c' in array", **s);
            return NULL;
        }
    }
    raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, "Completed parsing array");
    return array;
}

/* Parse a JSON object: { "key": value, ... } */
static Json *json_parse_object__(POSITION_INFO_DECLARATION, const char **s, Arena *arena) {
    raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, "Entering json_parse_object__ at position: %p", *s);
    if (**s != '{') return NULL;
    (*s)++; // skip '{'
    *s = skip_whitespace(*s);
    Json *object = arena_alloc__(POSITION_INFO, arena, sizeof(Json));
    if (!object) {
        raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, "Memory allocation failed in json_parse_object__");
        return NULL;
    }
    memset(object, 0, sizeof(Json));
    object->type = JSON_OBJECT;
    Json *last = NULL;
    if (**s == '}') {
        (*s)++;
        raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, "Parsed empty object");
        return object;
    }
    while (**s) {
        char *key = json_parse_string__(POSITION_INFO, s, arena);
        if (!key) {
            raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, "Failed to parse key in object");
            return NULL;
        }
        *s = skip_whitespace(*s);
        if (**s != ':') {
            raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, "Expected ':' after key \"%s\", got: %c", key, **s);
            return NULL;
        }
        (*s)++; // skip ':'
        *s = skip_whitespace(*s);
        Json *value = json_parse_value__(POSITION_INFO, s, arena);
        if (!value) {
            raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, "Failed to parse value for key \"%s\"", key);
            return NULL;
        }
        value->key = key; // assign key to the value
        if (!object->child)
            object->child = value;
        else
            last->next = value;
        last = value;
        *s = skip_whitespace(*s);
        if (**s == ',') {
            (*s)++;
            *s = skip_whitespace(*s);
        } else if (**s == '}') {
            (*s)++;
            break;
        } else {
            raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, "Unexpected character '%c' in object", **s);
            return NULL;
        }
    }
    raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, "Completed parsing object");
    return object;
}

/* Full JSON value parser */
static Json *json_parse_value__(POSITION_INFO_DECLARATION, const char **s, Arena *arena) {
    *s = skip_whitespace(*s);
    raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, "Parsing JSON value at position: %p", *s);
    if (**s == '"') {
        Json *item = arena_alloc__(POSITION_INFO, arena, sizeof(Json));
        if (!item) {
            raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, "Memory allocation failed in json_parse_value for string");
            return NULL;
        }
        memset(item, 0, sizeof(Json));
        item->type = JSON_STRING;
        item->JsonValue.string = json_parse_string__(POSITION_INFO, s, arena);
        return item;
    } else if (strncmp(*s, "null", 4) == 0) {
        Json *item = arena_alloc__(POSITION_INFO, arena, sizeof(Json));
        if (!item) return NULL;
        memset(item, 0, sizeof(Json));
        item->type = JSON_NULL;
        *s += 4;
        return item;
    } else if (strncmp(*s, "true", 4) == 0) {
        Json *item = arena_alloc__(POSITION_INFO, arena, sizeof(Json));
        if (!item) return NULL;
        memset(item, 0, sizeof(Json));
        item->type = JSON_BOOL;
        item->JsonValue.boolean = 1;
        *s += 4;
        return item;
    } else if (strncmp(*s, "false", 5) == 0) {
        Json *item = arena_alloc__(POSITION_INFO, arena, sizeof(Json));
        if (!item) return NULL;
        memset(item, 0, sizeof(Json));
        item->type = JSON_BOOL;
        item->JsonValue.boolean = 0;
        *s += 5;
        return item;
    } else if ((**s == '-') || isdigit((unsigned char)**s)) {
        Json *item = arena_alloc__(POSITION_INFO, arena, sizeof(Json));
        if (!item) {
            raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, "Memory allocation failed in json_parse_value for number");
            return NULL;
        }
        memset(item, 0, sizeof(Json));
        item->type = JSON_NUMBER;
        item->JsonValue.number = json_parse_number__(POSITION_INFO, s);
        return item;
    } else if (**s == '[') {
        return json_parse_array__(POSITION_INFO, s, arena);
    } else if (**s == '{') {
        return json_parse_object__(POSITION_INFO, s, arena);
    }
    raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, "Unrecognized JSON value at position: %p", *s);
    return NULL;
}

Json *json_parse__(POSITION_INFO_DECLARATION, Arena *arena, const char **s) {
    // Function entry logging with DEBUG level
    raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, 
        "PARSE: Starting JSON parsing (input: %p)", *s);
    
    // Check input parameters
    if (!s || !*s) {
        raise_message(LOG_LEVEL_EXCEPTION, POSITION_INFO,
            "PARSE: Invalid input parameters (NULL pointer provided for JSON parsing)");
        return NULL;
    }
    
    if (!arena) {
        raise_message(LOG_LEVEL_EXCEPTION, POSITION_INFO,
            "PARSE: Invalid arena (NULL) provided for JSON parsing");
        return NULL;
    }
    
    // Show input preview for debugging with TRACE level
    raise_message(LOG_LEVEL_TRACE, POSITION_INFO,
        "PARSE: Input preview: '%.20s%s'", *s, strlen(*s) > 20 ? "..." : "");
    
    // Process JSON value
    Json *result = json_parse_value__(POSITION_INFO, s, arena);
    
    // Log parsing result
    if (!result) {
        raise_message(LOG_LEVEL_WARN, POSITION_INFO, 
            "PARSE: Failed to parse JSON at position %p (context: '%.10s')", 
            *s, *s && strlen(*s) > 0 ? *s : "<empty>");
    } else {
        raise_message(LOG_LEVEL_LOG, POSITION_INFO, 
            "PARSE: JSON parsing completed successfully (type: %s)", json_type_to_string(result->type));
    }
    
    return result;
}

char *json_to_string__(POSITION_INFO_DECLARATION, Arena *arena, const Json * const item) {
    return json_to_string_with_opts__(POSITION_INFO, arena, item, JSON_NORAW);
}

/* Minimal JSON printer with raw output option.
   When raw is non-zero and the item is a JSON_STRING, it is printed without quotes.
*/
char *json_to_string_with_opts__(POSITION_INFO_DECLARATION, Arena *arena, const Json * const item, JsonRawOpt raw) {
    // Function entry with DEBUG level
    raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, 
                  "FORMAT: Starting JSON conversion to string (item: %p, raw_mode: %s)", 
                  item, raw == JSON_RAW ? "enabled" : "disabled");
    
    // Check input parameters
    if (!item) {
        raise_message(LOG_LEVEL_EXCEPTION, POSITION_INFO, 
                     "FORMAT: Invalid JSON object (NULL) provided for string conversion");
        return NULL;
    }
    
    if (!arena) {
        raise_message(LOG_LEVEL_EXCEPTION, POSITION_INFO,
                     "FORMAT: Invalid arena (NULL) provided for string conversion");
        return NULL;
    }
    
    // Allocate memory for the string
    char *out = arena_alloc__(POSITION_INFO, arena, 1024);
    if (!out) {
        raise_message(LOG_LEVEL_EXCEPTION, POSITION_INFO, 
                     "FORMAT: Memory allocation failed during JSON string conversion");
        return NULL;
    }
    
    char *ptr = out;
    const char* type_name = "unknown";
    
    // Formatting based on type
    if (item->type == JSON_OBJECT) {
        ptr += sprintf(ptr, "{");
        type_name = "object";
        
        Json *child = item->child;
        int child_count = 0;
        
        raise_message(LOG_LEVEL_TRACE, POSITION_INFO, 
                      "FORMAT: Processing JSON object children");
        
        while (child) {
            ptr += sprintf(ptr, "\"%s\":", child->key ? child->key : "");
            char *child_str = json_to_string_with_opts__(POSITION_INFO, arena, child, raw);
            if (child_str) {
                ptr += sprintf(ptr, "%s", child_str);
            } else {
                raise_message(LOG_LEVEL_WARN, POSITION_INFO, 
                              "FORMAT: Failed to stringify child element (key=%s)", 
                              child->key ? child->key : "<null>");
            }
            
            if (child->next) {
                ptr += sprintf(ptr, ",");
            }
            child = child->next;
            child_count++;
        }
        
        sprintf(ptr, "}");
        raise_message(LOG_LEVEL_TRACE, POSITION_INFO, 
                      "FORMAT: Object conversion complete with %d child elements", child_count);
    } else if (item->type == JSON_ARRAY) {
        ptr += sprintf(ptr, "[");
        type_name = "array";
        
        Json *child = item->child;
        int child_count = 0;
        
        raise_message(LOG_LEVEL_TRACE, POSITION_INFO, 
                      "FORMAT: Processing JSON array elements");
        
        while (child) {
            char *child_str = json_to_string_with_opts__(file, func, line, arena, child, raw);
            if (child_str) {
                ptr += sprintf(ptr, "%s", child_str);
            } else {
                raise_message(LOG_LEVEL_WARN, POSITION_INFO, 
                              "FORMAT: Failed to stringify array element at index %d", child_count);
            }
            
            if (child->next) {
                ptr += sprintf(ptr, ",");
            }
            child = child->next;
            child_count++;
        }
        
        sprintf(ptr, "]");
        raise_message(LOG_LEVEL_TRACE, POSITION_INFO, 
                      "FORMAT: Array conversion complete with %d elements", child_count);
    } else if (item->type == JSON_STRING) {
        type_name = "string";
        if ((int)raw) {
            sprintf(ptr, "%s", item->JsonValue.string ? item->JsonValue.string : "");
        } else {
            sprintf(ptr, "\"%s\"", item->JsonValue.string ? item->JsonValue.string : "");
        }
    } else if (item->type == JSON_NUMBER) {
        type_name = "number";
        sprintf(ptr, "%g", item->JsonValue.number);
    } else if (item->type == JSON_BOOL) {
        type_name = "boolean";
        sprintf(ptr, item->JsonValue.boolean ? "true" : "false");
    } else if (item->type == JSON_NULL) {
        type_name = "null";
        sprintf(ptr, "null");
    }
    
    raise_message(LOG_LEVEL_LOG, POSITION_INFO, 
                  "FORMAT: JSON %s converted to string (length=%zu)", 
                  type_name, strlen(out));
    
    return out;
}

/* Retrieve an object item by key (case-sensitive) */
Json *json_get_object_item__(POSITION_INFO_DECLARATION, const Json * const object, const char * const key) {
    raise_message(LOG_LEVEL_TRACE, POSITION_INFO, 
                 "ACCESS: Searching for key \"%s\" in JSON object %p", 
                 key ? key : "<null>", object);
    
    // Check input parameters
    if (!object) {
        raise_message(LOG_LEVEL_WARN, POSITION_INFO, 
                     "ACCESS: Invalid object (NULL) passed to json_get_object_item");
        return NULL;
    }
    
    if (!key) {
        raise_message(LOG_LEVEL_WARN, POSITION_INFO, 
                     "ACCESS: Invalid key (NULL) passed to json_get_object_item");
        return NULL;
    }
    
    if (object->type != JSON_OBJECT) {
        raise_message(LOG_LEVEL_WARN, POSITION_INFO, 
                     "ACCESS: JSON value is not an object (actual type: %d)", object->type);
        return NULL;
    }
    
    // Count the total number of keys for debugging
    int total_keys = 0;
    Json *debug_scan = object->child;
    while (debug_scan) {
        total_keys++;
        debug_scan = debug_scan->next;
    }
    
    raise_message(LOG_LEVEL_TRACE, POSITION_INFO, 
                 "ACCESS: Object has %d key-value pairs", total_keys);
    
    // Perform key search
    Json *child = object->child;
    int position = 0;
    
    while (child) {
        if (child->key) {
            raise_message(LOG_LEVEL_TRACE, POSITION_INFO, 
                         "ACCESS: Comparing key \"%s\" with \"%s\" at position %d", 
                         child->key, key, position);
            
            if (strcmp(child->key, key) == 0) {
                raise_message(LOG_LEVEL_LOG, POSITION_INFO, 
                             "ACCESS: Found value for key \"%s\" (type: %s)", 
                             key, json_type_to_string(child->type));
                return child;
            }
        } else {
            raise_message(LOG_LEVEL_TRACE, POSITION_INFO, 
                         "ACCESS: Skipping element at position %d with NULL key", position);
        }
        
        child = child->next;
        position++;
    }
    
    raise_message(LOG_LEVEL_DEBUG, POSITION_INFO, 
                 "ACCESS: Key \"%s\" not found in object (checked %d items)", 
                 key, position);
    return NULL;
}

char* json_to_debug_str__(POSITION_INFO_DECLARATION, Arena *arena, Json json) {
  raise_message(LOG_LEVEL_TRACE, POSITION_INFO, "json_to_debug_str(<optimized>, <optimized>)");

  char meta_buffer[256];
  
  snprintf(meta_buffer, sizeof(meta_buffer), "Json{addr=%p, type=%s, key=%s, child=%p, next=%p, value=",
           (void*)&json, json_type_to_string(json.type), json.key ? json.key : "NULL", (void*)json.child, (void*)json.next);
  
  size_t meta_len = strlen(meta_buffer);
  char value_buffer[256] = {0};
  
  switch (json.type) {
    case JSON_NULL:
      strcpy(value_buffer, "null");
      break;
    
    case JSON_BOOL:
      strcpy(value_buffer, json.JsonValue.boolean ? "true" : "false");
      break;
    
    case JSON_NUMBER:
      snprintf(value_buffer, sizeof(value_buffer), "%g", json.JsonValue.number);
      break;
    
    case JSON_STRING: {
      if (!json.JsonValue.string) {
        strcpy(value_buffer, "null");
      } else {
        snprintf(value_buffer, sizeof(value_buffer), "\"%s\"", json.JsonValue.string);
      }
      break;
    }
    
    case JSON_ARRAY: {
      // For arrays, simply note the number of elements
      size_t count = 0;
      Json *item = json.child;
      while (item) {
        count++;
        item = item->next;
      }
      snprintf(value_buffer, sizeof(value_buffer), "[array with %zu elements]", count);
      break;
    }
    
    case JSON_OBJECT: {
      // For objects, note the number of key-value pairs
      size_t count = 0;
      Json *item = json.child;
      while (item) {
        count++;
        item = item->next;
      }
      snprintf(value_buffer, sizeof(value_buffer), "{object with %zu key-value pairs}", count);
      break;
    }
    
    default:
      strcpy(value_buffer, "<UNKNOWN JSON TYPE>");
  }
  
  // Create final string
  size_t result_len = meta_len + strlen(value_buffer) + 2; // +2 for closing brace and null character
  char* result = arena_alloc(arena, result_len);
  
  strcpy(result, meta_buffer);
  strcat(result, value_buffer);
  strcat(result, "}");
  
  return result;
}

// -----------
// -- slice --
// -----------

// Create a slice from an array with boundary check.
Slice slice_create__(POSITION_INFO_DECLARATION, size_t isize, void *array, size_t array_len, size_t start, size_t len) {
    // Function entry logging
    raise_message(LOG_LEVEL_TRACE, POSITION_INFO, 
        "SLICE: Creating slice (source: %p, array_length: %zu, start: %zu, length: %zu, item_size: %zu)", 
        array, array_len, start, len, isize);
    
    // Boundary check
    if (start + len > array_len) {
        raise_message(LOG_LEVEL_WARN, POSITION_INFO,
            "SLICE: Slice boundaries exceed array length (start: %zu, length: %zu, array_length: %zu)",
            start, len, array_len);
        return (Slice){NULL, 0, isize};
    }
    
    // Create valid slice
    Slice result = (Slice){ (char *)array + start * isize, len, isize };
    
    // Success logging
    raise_message(LOG_LEVEL_TRACE, POSITION_INFO,
        "SLICE: Slice created successfully (data: %p, length: %zu, item_size: %zu)",
        result.data, result.len, result.isize);
    
    return result;
}

// Return a subslice from an existing slice.
Slice slice_subslice__(POSITION_INFO_DECLARATION, Slice s, size_t start, size_t len) {
    // Function entry logging
    raise_message(LOG_LEVEL_TRACE, POSITION_INFO, 
        "SLICE: Creating subslice (source: %p, source_length: %zu, start: %zu, length: %zu)", 
        s.data, s.len, start, len);
    
    // Boundary check
    if (start + len > s.len) {
        raise_message(LOG_LEVEL_WARN, POSITION_INFO,
            "SLICE: Subslice boundaries exceed source slice length (start: %zu, length: %zu, source_length: %zu)",
            start, len, s.len);
        return (Slice){NULL, 0, s.isize};
    }
    
    // Create valid subslice
    Slice result = (Slice){(char*)s.data + start * s.isize, len, s.isize};
    
    // Success logging
    raise_message(LOG_LEVEL_TRACE, POSITION_INFO,
        "SLICE: Subslice created successfully (data: %p, length: %zu, item_size: %zu)",
        result.data, result.len, result.isize);
    
    return result;
}

int* arena_slice_copy__(POSITION_INFO_DECLARATION, Arena *arena, Slice s) {
    raise_message(LOG_LEVEL_TRACE, POSITION_INFO, "arena_slice_copy(<optimized>, <optimized>)");
    int *copy = (void*) arena_alloc__(POSITION_INFO, arena, s.len * sizeof(int));
    if (copy)
        memcpy(copy, s.data, s.len * s.isize);
    return copy;
}

char* slice_to_debug_str__(POSITION_INFO_DECLARATION, Arena *arena, Slice slice) {
  // Create complete information about the Slice structure
  char buffer_meta[128];
  snprintf(buffer_meta, sizeof(buffer_meta), "Slice{addr=%p, data=%p, len=%zu, isize=%zu, content=",
           (void*)&slice, slice.data, slice.len, slice.isize);
  
  size_t meta_len = strlen(buffer_meta);
  
  // For NULL data, output a simple message
  if (!slice.data) {
    char* result = arena_alloc(arena, meta_len + 6);
    strcpy(result, buffer_meta);
    strcat(result, "NULL}");
    return result;
  }
  
  // Allocate buffer with space for quotes, metadata and null terminator
  size_t buffer_size = meta_len + slice.len * 4 + 20; // Extra space for escaping and closing brace
  char* buffer = arena_alloc(arena, buffer_size);
  
  // Copy metadata
  strcpy(buffer, buffer_meta);
  char* pos = buffer + meta_len;
  
  *pos++ = '"';
  
  // Copy slice data with escaping
  for (size_t i = 0; i < slice.len; i++) {
    char c = ((char*)slice.data)[i];
    if (c == '\0') {
      *pos++ = '\\';
      *pos++ = '0';
    } else if (c == '\n') {
      *pos++ = '\\';
      *pos++ = 'n';
    } else if (c == '\r') {
      *pos++ = '\\';
      *pos++ = 'r';
    } else if (c == '\t') {
      *pos++ = '\\';
      *pos++ = 't';
    } else if (c == '"') {
      *pos++ = '\\';
      *pos++ = '"';
    } else if (c == '\\') {
      *pos++ = '\\';
      *pos++ = '\\';
    } else if (c < 32 || c > 126) {
      // Non-printable characters as hex
      pos += sprintf(pos, "\\x%02x", (unsigned char)c);
    } else {
      *pos++ = c;
    }
  }
  
  *pos++ = '"';
  *pos++ = '}'; // Closing brace for the structure
  *pos = '\0';

  raise_message(LOG_LEVEL_TRACE, POSITION_INFO, "slice_to_debug_str: %s", buffer);
  
  return buffer;
}


// ------------------
// -- logger rules --
// ------------------

// Clean up existing log rules
void free_log_rules() {
    LogRule *rule = log_rules;
    while (rule) {
        LogRule *next = rule->next;
        if (rule->file_pattern) free(rule->file_pattern);
        if (rule->function_pattern) free(rule->function_pattern);
        free(rule);
        rule = next;
    }
    log_rules = NULL;
}

// Add a new log rule to the rule chain
LogRule* add_log_rule(LogLevel level, const char *file_pattern, const char *function_pattern, 
                      int line_start, int line_end) {
    LogRule *rule = (LogRule*)malloc(sizeof(LogRule));
    if (!rule) return NULL;
    
    rule->level = level;
    rule->file_pattern = file_pattern ? strdup(file_pattern) : NULL;
    rule->function_pattern = function_pattern ? strdup(function_pattern) : NULL;
    rule->line_start = line_start;
    rule->line_end = line_end;
    rule->next = NULL;
    
    // Add to the end of the list
    if (!log_rules) {
        log_rules = rule;
    } else {
        LogRule *last = log_rules;
        while (last->next) {
            last = last->next;
        }
        last->next = rule;
    }
    
    return rule;
}

// Parse a line range specification (start:end)
void parse_line_range(const char *range_str, int *start, int *end) {
    if (!range_str) {
        *start = -1;
        *end = -1;
        return;
    }
    
    char *endptr;
    *start = strtol(range_str, &endptr, 10);
    
    if (*endptr == ':') {
        *end = strtol(endptr + 1, NULL, 10);
    } else {
        *end = *start;
    }
    
    if (*start <= 0) *start = -1;
    if (*end <= 0) *end = -1;
}

// Parse a complex rule string and set up log rules
int logger_parse_rules(const char *rules_str) {
    if (!rules_str || !*rules_str) return 0;
    
    // Clean up existing rules
    free_log_rules();
    
    // Make a copy of the rules string since we'll be modifying it
    char *rules_copy = strdup(rules_str);
    if (!rules_copy) return 0;
    
    // First rule sets the default level
    char *next_rule = rules_copy;
    char *token = strsep(&next_rule, ",");
    current_log_level = log_level_from_string(token);
    
    // Process the remaining rules
    while (next_rule && *next_rule) {
        // Extract rule definition: pattern=level
        char *rule_def = strsep(&next_rule, ",");
        char *level_str = strchr(rule_def, '=');
        
        if (!level_str) continue; // Invalid rule
        
        *level_str = '\0'; // Split pattern and level
        level_str++;
        
        // Parse the rule pattern
        char *pattern = rule_def;
        char *file_pattern = NULL;
        char *function_pattern = NULL;
        char *line_range = NULL;
        
        // Check for line range in file pattern
        char *at_sign = strchr(pattern, '@');
        if (at_sign) {
            *at_sign = '\0';
            file_pattern = pattern;
            pattern = at_sign + 1;
            
            // Check for line range or another @ for function
            char *colon = strchr(pattern, ':');
            char *second_at = strchr(pattern, '@');
            
            if (second_at && (!colon || second_at < colon)) {
                // Format: file@function@line_range
                *second_at = '\0';
                function_pattern = pattern;
                line_range = second_at + 1;
            } else if (colon) {
                // Format: file@line_range
                line_range = pattern;
            } else {
                // Format: file@function
                function_pattern = pattern;
            }
        } else {
            // Just file pattern
            file_pattern = pattern;
        }
        
        // If file pattern is empty, set to NULL
        if (file_pattern && !*file_pattern) file_pattern = NULL;
        
        // If function pattern is empty, set to NULL
        if (function_pattern && !*function_pattern) function_pattern = NULL;
        
        // Parse line range
        int line_start = -1, line_end = -1;
        parse_line_range(line_range, &line_start, &line_end);
        
        // Create a new rule
        LogLevel level = log_level_from_string(level_str);
        add_log_rule(level, file_pattern, function_pattern, line_start, line_end);
    }
    
    free(rules_copy);
    return 1;
}

// Check if a file matches a pattern
static int match_file_pattern(const char *file, const char *pattern) {
    if (!pattern) return 1; // NULL pattern matches any file
    
    // Extract the filename part without the path
    const char *filename = strrchr(file, '/');
    if (!filename) filename = file;
    else filename++; // Skip the '/'
    
    return fnmatch(pattern, filename, 0) == 0 || fnmatch(pattern, file, 0) == 0;
}

// Check if a function matches a pattern
static int match_function_pattern(const char *func, const char *pattern) {
    if (!pattern) return 1; // NULL pattern matches any function
    return fnmatch(pattern, func, 0) == 0;
}

// Get the effective log level for a specific context
LogLevel logger_get_effective_level(const char *file, const char *func, int line) {
    // If no rules are defined, use the global level
    if (!log_rules) return current_log_level;
    
    // Default to the global log level
    LogLevel effective_level = current_log_level;
    
    // Check each rule in order
    for (LogRule *rule = log_rules; rule; rule = rule->next) {
        int file_match = match_file_pattern(file, rule->file_pattern);
        int function_match = match_function_pattern(func, rule->function_pattern);
        int line_match = (rule->line_start == -1 || (line >= rule->line_start && 
                         (rule->line_end == -1 || line <= rule->line_end)));
        
        // If all conditions match, use this rule's level
        if (file_match && function_match && line_match) {
            effective_level = rule->level;
            // Don't break here - later rules can override earlier ones
        }
    }
    
    return effective_level;
}

// Add a new log rule programmatically
int logger_add_rule(LogLevel level, const char *file_pattern, const char *function_pattern, 
                    int line_start, int line_end) {
    return add_log_rule(level, file_pattern, function_pattern, line_start, line_end) != NULL;
}

// Print all current logging rules to stderr
void logger_print_rules() {
    fprintf(stderr, "Current logging rules:\n");
    fprintf(stderr, "  Default level: %s\n", log_level_to_string(current_log_level));
    
    int rule_count = 0;
    for (LogRule *rule = log_rules; rule; rule = rule->next) {
        fprintf(stderr, "  Rule %d: Level=%s, File=%s, Function=%s, Lines=%d:%d\n",
                ++rule_count,
                log_level_to_string(rule->level),
                rule->file_pattern ? rule->file_pattern : "<any>",
                rule->function_pattern ? rule->function_pattern : "<any>",
                rule->line_start, rule->line_end);
    }
    
    if (rule_count == 0) {
        fprintf(stderr, "  No specific rules defined\n");
    }
}

// Helper to format a rule as a string
static void format_rule_to_buffer(char *buffer, size_t size, LogRule *rule) {
    char line_range[32] = "";
    
    // Format line range if specified
    if (rule->line_start > 0) {
        if (rule->line_end > 0 && rule->line_end != rule->line_start) {
            snprintf(line_range, sizeof(line_range), "%d:%d", rule->line_start, rule->line_end);
        } else {
            snprintf(line_range, sizeof(line_range), "%d", rule->line_start);
        }
    }
    
    // Format the complete rule
    if (rule->file_pattern && rule->function_pattern && line_range[0]) {
        // File + function + line range
        snprintf(buffer, size, "%s@%s@%s=%s",
                 rule->file_pattern, rule->function_pattern, line_range,
                 log_level_to_string(rule->level));
    } else if (rule->file_pattern && rule->function_pattern) {
        // File + function
        snprintf(buffer, size, "%s@%s=%s",
                 rule->file_pattern, rule->function_pattern,
                 log_level_to_string(rule->level));
    } else if (rule->file_pattern && line_range[0]) {
        // File + line range
        snprintf(buffer, size, "%s@%s=%s",
                 rule->file_pattern, line_range,
                 log_level_to_string(rule->level));
    } else if (rule->file_pattern) {
        // Just file
        snprintf(buffer, size, "%s=%s",
                 rule->file_pattern,
                 log_level_to_string(rule->level));
    } else {
        // Empty rule (shouldn't happen)
        snprintf(buffer, size, "EMPTY=%s", log_level_to_string(rule->level));
    }
}

// Format all rules into a string
char* logger_rules_to_string(Arena *arena) {
    if (!arena) return NULL;
    
    // Allocate a buffer in the arena (estimate size needed)
    size_t estimated_size = 1024; // Start with 1KB
    char *buffer = arena_alloc(arena, estimated_size);
    if (!buffer) return NULL;
    
    // Initialize with default level
    int pos = snprintf(buffer, estimated_size, "%s", log_level_to_string(current_log_level));
    
    // Add each rule
    for (LogRule *rule = log_rules; rule; rule = rule->next) {
        // Format the rule
        char rule_str[256];
        format_rule_to_buffer(rule_str, sizeof(rule_str), rule);
        
        // Check buffer space and add to result
        if (pos + strlen(rule_str) + 2 < estimated_size) {
            buffer[pos++] = ',';
            strcpy(buffer + pos, rule_str);
            pos += strlen(rule_str);
        } else {
            // Buffer too small, just stop
            strcat(buffer, ",...");
            break;
        }
    }
    
    return buffer;
}

char *log_rules_to_debug_str__(CTX_DECLARATION, char *name, LogRule *self, PtrSet *visited) {
    char *result = arena_alloc(arena, MEM_KiB);
    STRUCT_TO_DEBUG_STR(arena, result, LogRule, name, self, visited, 6,
      string_to_debug_str__(POSITION_INFO, arena, "level", log_level_to_string(self->level)),
      string_to_debug_str__(POSITION_INFO, arena, "file_pattern", self->file_pattern),
      string_to_debug_str__(POSITION_INFO, arena, "function_pattern", self->function_pattern),
      int_to_debug_str__(POSITION_INFO, arena, "line_start", self->line_start),
      int_to_debug_str__(POSITION_INFO, arena, "line_end", self->line_end),
      log_rules_to_debug_str__(POSITION_INFO, arena, "next", self->next, visited)
    );
    return result;
}

// ---------------
// -- Templater --
// ---------------

// Look at package\c\hectic\docs\templater.md

TemplateConfig template_default_config__(POSITION_INFO_DECLARATION) {
  raise_message(LOG_LEVEL_TRACE, POSITION_INFO, "TEMPLATE: Default config");
  TemplateConfig config;

  config.Syntax.Braces.open = "{%";
  config.Syntax.Braces.close = "%}";
  config.Syntax.Section.control = "for ";
  config.Syntax.Section.source = " in ";
  config.Syntax.Section.begin = " do ";
  config.Syntax.Interpolate.invoke = "";
  config.Syntax.Include.invoke = "include ";
  config.Syntax.Execute.invoke = "exec ";
  config.Syntax.nesting = "->";

  return config;
}

#define CHECK_CONFIG_STR(field, name)                                      \
do {                                                                       \
  if (config->Syntax.field == NULL) {                                                  \
    raise_message(LOG_LEVEL_EXCEPTION, POSITION_INFO, "VALIDATE: " name " is NULL");     \
    return false;                                                          \
  }                                                                        \
  if (strlen(config->Syntax.field) > TEMPLATE_MAX_PREFIX_LEN) {                   \
    raise_message(LOG_LEVEL_EXCEPTION, POSITION_INFO, "VALIDATE: " name " is too long"); \
    return false;                                                          \
  }                                                                        \
} while (0)

bool template_validate_config__(POSITION_INFO_DECLARATION, const TemplateConfig *config) {
  raise_trace("VALIDATE: config %p", config);
  if (!config) {
    raise_message(LOG_LEVEL_EXCEPTION, POSITION_INFO, "VALIDATE: Config is NULL");
    return false;
  }

  CHECK_CONFIG_STR(Braces.open, "Open brace");
  CHECK_CONFIG_STR(Braces.close, "Close brace");
  CHECK_CONFIG_STR(Section.control, "Section control");
  CHECK_CONFIG_STR(Section.source, "Section source");
  CHECK_CONFIG_STR(Section.begin, "Section begin");
  CHECK_CONFIG_STR(Interpolate.invoke, "Interpolation invoke");
  CHECK_CONFIG_STR(Include.invoke, "Include invoke");
  CHECK_CONFIG_STR(Execute.invoke, "Execute invoke");
  CHECK_CONFIG_STR(nesting, "Nesting");

  return true;
}

#undef CHECK_CONFIG_STR

#define TEMPLATE_ASSERT_SYNTAX(pattern, message_arg, code_arg) \
  if (strncmp(*s, pattern, strlen(pattern))) { \
    raise_message(LOG_LEVEL_EXCEPTION, POSITION_INFO, "PARSE: " message_arg); \
    result->type = RESULT_ERROR; \
    result->Result.error.code = code_arg; \
    result->Result.error.message = message_arg; \
    return result; \
  }

TemplateResult *template_parse__(POSITION_INFO_DECLARATION, Arena *arena, const char **s, const TemplateConfig *config);

TemplateResult *template_parse_interpolation__(POSITION_INFO_DECLARATION, Arena *arena, const char **s_ptr, const TemplateConfig *config) {
  raise_message(LOG_LEVEL_TRACE, POSITION_INFO, "PARSE: Interpolation");

  TemplateResult *result = arena_alloc__(POSITION_INFO, arena, sizeof(TemplateResult));

  const char **s = s_ptr;

  // Skip to the content of the interpolation
  *s += strlen(config->Syntax.Braces.open);
  *s = skip_whitespace(*s);
  *s += strlen(config->Syntax.Interpolate.invoke);

  *s = skip_whitespace(*s);
  const char *key_start = *s;

  while (isalnum(**s)) {
    if (**s == ' ' || strncmp(*s, config->Syntax.Braces.close, strlen(config->Syntax.Braces.close))) break;
    TEMPLATE_ASSERT_SYNTAX(config->Syntax.Braces.open, "Nested tag in interpolation", TEMPLATE_ERROR_NESTED_INTERPOLATION);

    (*s)++;
  }

  size_t key_len = *s - key_start;
  result->Result.some.value.interpolate.key = arena_strncpy__(POSITION_INFO, arena, key_start, key_len);

  result->type = RESULT_SOME;
  result->Result.some.type = TEMPLATE_NODE_INTERPOLATE;

  *s_ptr = *s + strlen(config->Syntax.Braces.close);

  return result;
}

TemplateResult *template_parse_section__(POSITION_INFO_DECLARATION, Arena *arena, const char **s_ptr, const TemplateConfig *config) {
  raise_message(LOG_LEVEL_TRACE, POSITION_INFO, "PARSE: Section");

  TemplateResult *result = arena_alloc__(POSITION_INFO, arena, sizeof(TemplateResult));
  result->type = RESULT_SOME;
  result->Result.some.type = TEMPLATE_NODE_SECTION;

  const char **s = s_ptr;

  // Skip to the content of the section
  *s += strlen(config->Syntax.Braces.open);
  *s = skip_whitespace(*s);
  *s += strlen(config->Syntax.Section.control);

  // Find the iterator name
  *s = skip_whitespace(*s);
  const char *iterator_start = *s;

  while (isalnum(**s)) {
    if (**s == ' ' || **s == '\n' || **s == '\t' || strncmp(*s, config->Syntax.Section.source, strlen(config->Syntax.Section.source))) break;
    TEMPLATE_ASSERT_SYNTAX(config->Syntax.Braces.close, "Unexpected section end", TEMPLATE_ERROR_UNEXPECTED_SECTION_END);
    TEMPLATE_ASSERT_SYNTAX(config->Syntax.Braces.open, "Nested tag in section element name", TEMPLATE_ERROR_NESTED_SECTION_ITERATOR);

    (*s)++;
  }

  size_t iterator_len = *s - iterator_start;
  result->Result.some.value.section.iterator = arena_strncpy__(POSITION_INFO, arena, iterator_start, iterator_len);

  // Find the collection name
  *s = skip_whitespace(*s);
  const char *collection_start = *s;
  
  while (isalnum(**s)) {
    if (**s == ' ' || **s == '\n' || **s == '\t' || strncmp(*s, config->Syntax.Section.begin, strlen(config->Syntax.Section.begin))) break;
    TEMPLATE_ASSERT_SYNTAX(config->Syntax.Braces.close, "Unexpected section end", TEMPLATE_ERROR_UNEXPECTED_SECTION_END);
    TEMPLATE_ASSERT_SYNTAX(config->Syntax.Braces.open, "Nested tag in section iterator", TEMPLATE_ERROR_NESTED_SECTION_ITERATOR);

    (*s)++;
  }

  size_t collection_len = *s - collection_start;
  result->Result.some.value.section.collection = arena_strncpy__(POSITION_INFO, arena, collection_start, collection_len);

  // Parse the body
  TemplateResult *body_result = template_parse__(POSITION_INFO, arena, s, config);
  if (body_result->type == RESULT_ERROR) {
    return body_result;
  }

  result->Result.some.value.section.body = &body_result->Result.some;

  *s_ptr = *s + strlen(config->Syntax.Braces.close);

  return result;
}

TemplateResult *template_parse_include__(POSITION_INFO_DECLARATION, Arena *arena, const char **s_ptr, const TemplateConfig *config) {
  raise_message(LOG_LEVEL_TRACE, POSITION_INFO, "PARSE: Include");
  TemplateResult *result = arena_alloc__(POSITION_INFO, arena, sizeof(TemplateResult));
  result->type = RESULT_SOME;
  result->Result.some.type = TEMPLATE_NODE_INCLUDE;

  const char **s = s_ptr;

  // Skip to the content of the include
  *s += strlen(config->Syntax.Braces.open);
  *s = skip_whitespace(*s);
  *s += strlen(config->Syntax.Include.invoke);

  *s = skip_whitespace(*s);
  const char *include_start = *s;

  while (isalnum(**s)) {
    if (**s == ' ' || **s == '\n' || **s == '\t' || strncmp(*s, config->Syntax.Braces.close, strlen(config->Syntax.Braces.close))) break;
    TEMPLATE_ASSERT_SYNTAX(config->Syntax.Braces.open, "Nested tag in include", TEMPLATE_ERROR_NESTED_INCLUDE);

    (*s)++;
  }

  size_t include_len = *s - include_start;
  result->Result.some.value.include.key = arena_strncpy__(POSITION_INFO, arena, include_start, include_len);

  *s_ptr = *s + strlen(config->Syntax.Braces.close);

  return result;
}

TemplateResult *template_parse_execute__(POSITION_INFO_DECLARATION, Arena *arena, const char **s_ptr, const TemplateConfig *config) {
  raise_message(LOG_LEVEL_TRACE, POSITION_INFO, "PARSE: Execute");

  TemplateResult *result = arena_alloc__(POSITION_INFO, arena, sizeof(TemplateResult));
  result->type = RESULT_SOME;
  result->Result.some.type = TEMPLATE_NODE_EXECUTE;

  const char **s = s_ptr;

  *s += strlen(config->Syntax.Braces.open);
  *s = skip_whitespace(*s);
  *s += strlen(config->Syntax.Execute.invoke);

  *s = skip_whitespace(*s);
  const char *code_start = *s;

  while (strncmp(*s, config->Syntax.Braces.close, strlen(config->Syntax.Braces.close))) {
    TEMPLATE_ASSERT_SYNTAX(config->Syntax.Braces.open, "Nested tag in execute", TEMPLATE_ERROR_NESTED_EXECUTE);
    (*s)++;
  }

  size_t code_len = *s - code_start;
  result->Result.some.value.execute.code = arena_strncpy__(POSITION_INFO, arena, code_start, code_len);

  *s_ptr = *s + strlen(config->Syntax.Braces.close);

  return result;
}

TemplateResult *template_parse__(POSITION_INFO_DECLARATION, Arena *arena, const char **s, const TemplateConfig *config) {
  raise_message(LOG_LEVEL_TRACE, POSITION_INFO, "PARSE: Iteration start");

  if (!template_validate_config__(POSITION_INFO, config)) {
    raise_message(LOG_LEVEL_EXCEPTION, POSITION_INFO, "PARSE: Invalid config");
    return NULL;
  }

  if (!arena) {
    raise_message(LOG_LEVEL_EXCEPTION, POSITION_INFO, "PARSE: Arena is NULL");
    return NULL;
  }

  const char *start = *s;

  TemplateNode *root = arena_alloc__(POSITION_INFO, arena, sizeof(TemplateNode));
  TemplateNode *current = root;

  int open_brace_len = strlen(config->Syntax.Braces.open);

  while (*s) {
    // Find the first open brace
    if (strncmp(*s, config->Syntax.Braces.open, open_brace_len) == 0) {
      // Add text node if there is any text before the tag
      if (start != *s) {
        raise_message(LOG_LEVEL_TRACE, POSITION_INFO, "PARSE: Text node: %s", arena_strncpy__(POSITION_INFO, DISPOSABLE_ARENA, start, *s - start));
        current->type = TEMPLATE_NODE_TEXT;
        current->value.text.content = arena_strncpy__(POSITION_INFO, arena, start, *s - start);
      }

      // Deside tag type by prefix
      TemplateResult *current_result = arena_alloc__(POSITION_INFO, arena, sizeof(TemplateResult));
      {
        raise_message(LOG_LEVEL_TRACE, POSITION_INFO, "PARSE: Found tag");

        const char *tag_prefix = *s + open_brace_len;
        tag_prefix = skip_whitespace(tag_prefix);
	    raise_trace("tag_prefix: %p", tag_prefix);

        if (strncmp(tag_prefix, config->Syntax.Section.control, strlen(config->Syntax.Section.control)) == 0) {
          raise_message(LOG_LEVEL_TRACE, POSITION_INFO, "PARSE: Section tag");
          current_result = template_parse_section__(POSITION_INFO, arena, s, config);
        } else if (strncmp(tag_prefix, config->Syntax.Interpolate.invoke, strlen(config->Syntax.Interpolate.invoke)) == 0) {
          raise_message(LOG_LEVEL_TRACE, POSITION_INFO, "PARSE: Interpolation tag");
          current_result = template_parse_interpolation__(POSITION_INFO, arena, s, config);
        } else if (strncmp(tag_prefix, config->Syntax.Include.invoke, strlen(config->Syntax.Include.invoke)) == 0) {
          raise_message(LOG_LEVEL_TRACE, POSITION_INFO, "PARSE: Include tag");
          current_result = template_parse_include__(POSITION_INFO, arena, s, config);
        } else if (strncmp(tag_prefix, config->Syntax.Execute.invoke, strlen(config->Syntax.Execute.invoke)) == 0) {
          raise_message(LOG_LEVEL_TRACE, POSITION_INFO, "PARSE: Execute tag");
          current_result = template_parse_execute__(POSITION_INFO, arena, s, config);
        } else {
          raise_message(LOG_LEVEL_EXCEPTION, POSITION_INFO, "PARSE: Unknown tag prefix: %s", slice_create__(POSITION_INFO, 1, (char *)tag_prefix, strlen(tag_prefix), 0, TEMPLATE_MAX_PREFIX_LEN));
          
          TemplateResult *error_result = arena_alloc__(POSITION_INFO, arena, sizeof(TemplateResult));

          error_result->type = RESULT_ERROR;
          error_result->Result.error.code = TEMPLATE_ERROR_UNKNOWN_TAG;
          error_result->Result.error.message = "Unknown tag prefix";

          return error_result;
        }
      }

      if (current_result->type == RESULT_ERROR) {
        return current_result;
      }

      *current = current_result->Result.some;
      current->next = arena_alloc__(POSITION_INFO, arena, sizeof(TemplateNode));
      current = current->next;
    }

    (*s)++;
  }

  // Add text node if there is any text after the last tag
  if (start != *s) {
    current->type = TEMPLATE_NODE_TEXT;
    current->value.text.content = arena_strncpy__(POSITION_INFO, arena, start, *s - start);
  }

  TemplateResult *result = arena_alloc__(POSITION_INFO, arena, sizeof(TemplateResult));
  result->type = RESULT_SOME;
  result->Result.some = *root;

  return result;
}

#undef TEMPLATE_ASSERT_SYNTAX

#define TEMPLATE_NODE_MAX_DEBUG_DEPTH 20

static const char *template_error_code_to_string(TemplateErrorCode code) {
  switch (code) {
    case TEMPLATE_ERROR_NONE: return "NONE";
    case TEMPLATE_ERROR_UNKNOWN_TAG: return "UNKNOWN_TAG";
    case TEMPLATE_ERROR_NESTED_INTERPOLATION: return "NESTED_INTERPOLATION";
    case TEMPLATE_ERROR_UNEXPECTED_SECTION_END: return "UNEXPECTED_SECTION_END";
    case TEMPLATE_ERROR_NESTED_SECTION_ITERATOR: return "NESTED_SECTION_ITERATOR";
    case TEMPLATE_ERROR_NESTED_INCLUDE: return "NESTED_INCLUDE";
    case TEMPLATE_ERROR_NESTED_EXECUTE: return "NESTED_EXECUTE";
    default: { 
        raise_exception("HECTICLIB ERROR: Unknown template error code: %d", code);
        return "UNKNOWN";
    };
  }
}

static char *template_node_type_to_string(TemplateNodeType type) {
  switch (type) {
    case TEMPLATE_NODE_SECTION: return "SECTION";
    case TEMPLATE_NODE_INTERPOLATE: return "INTERPOLATE";
    case TEMPLATE_NODE_EXECUTE: return "EXECUTE";
    case TEMPLATE_NODE_INCLUDE: return "INCLUDE";
    case TEMPLATE_NODE_TEXT: return "TEXT";
    default: { 
        raise_exception("HECTICLIB ERROR: Unknown template node type: %d", type);
        return "UNKNOWN";
    };
  }
}

char *template_node_to_debug_str__(POSITION_INFO_DECLARATION, Arena *arena, const TemplateNode *node, int depth) {
    if (!node) return arena_strncpy__(POSITION_INFO, arena, "", 0);

    if (depth > TEMPLATE_NODE_MAX_DEBUG_DEPTH) {
      return arena_strncpy__(POSITION_INFO, arena, "...", 3);
    }

    // Use a temporary buffer on the stack for building the string
    char temp_buf[MEM_MiB];
    size_t len = 0;
    
    #define APPEND(...) do { \
        int written = snprintf(temp_buf + len, sizeof(temp_buf) - len, ##__VA_ARGS__); \
        if (written < 0) return NULL; \
        len += written; \
    } while (0)

    if (depth == 0) {
      APPEND("[");
    }

    APPEND("{\"type\":\"%s\",", template_node_type_to_string(node->type));

    switch (node->type) {
        case TEMPLATE_NODE_SECTION:
            APPEND("\"content\":{\"iterator\":\"%s\",\"collection\"=\"%s\"}",
                node->value.section.iterator,
                node->value.section.collection);
            char *body_str = template_node_to_debug_str__(POSITION_INFO, arena, node->value.section.body, depth + 1);
            if (body_str) {
                APPEND(",\"body\":%s", body_str);
            }
            break;
        case TEMPLATE_NODE_INTERPOLATE:
            APPEND("\"content\":{\"key\":\"%s\"}", node->value.interpolate.key);
            break;
        case TEMPLATE_NODE_EXECUTE:
            APPEND("\"content\":{\"code\":\"%s\"}", node->value.execute.code);
            break;
        case TEMPLATE_NODE_INCLUDE:
            APPEND("\"content\":{\"key\":\"%s\"}", node->value.include.key);
            break;
        case TEMPLATE_NODE_TEXT:
            APPEND("\"content\":{\"content\":\"%s\"}", node->value.text.content);
            break;
        default:
            break;
    }

    if (node->error.code != TEMPLATE_ERROR_NONE) {
        APPEND(",\"error\":{\"code\":\"%s\",\"message\":\"%s\"}", template_error_code_to_string(node->error.code), node->error.message);
    }

    if (node->children) {
        APPEND(",\"children\":[");
        char *child_str = template_node_to_debug_str__(POSITION_INFO, arena, node->children, depth + 1);
        if (child_str) {
            APPEND(",%s", child_str);
        }
        APPEND("]");
    }

    APPEND("}");

    if (node->next) {
        char *next_str = template_node_to_debug_str__(POSITION_INFO, arena, node->next, depth + 1);
        if (next_str) {
            APPEND(",%s", next_str);
        }
    }

    if (depth == 0) {
      APPEND("]");
    }

    // Copy the final string to arena-allocated memory
    char *result = arena_strncpy__(POSITION_INFO, arena, temp_buf, len);
    return result;
}

// ---------
// -- End --
// ---------

#undef POSITION_INFO_DECLARATION
#undef POSITION_INFO