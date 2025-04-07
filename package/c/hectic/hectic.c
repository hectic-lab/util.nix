#include "hectic.h"
#include <fnmatch.h>
#include <string.h> // For strdup, strchr, etc.

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
LogRule *log_rules = NULL; // Linked list of log rules

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

#define POSITION_INFO file, func, line

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
    // Read log level or rules from environment
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
    fprintf(stderr, "%s %s%s%s [%s:%s:%d] ", 
            timeStr, 
            log_level_to_color(level), 
            log_level_to_string(level), 
            OPTIONAL_COLOR(COLOR_RESET),
            file,
            func,
            line);

    // Print the actual message with variable arguments
    va_list args;
    va_start(args, format);
    vfprintf(stderr, format, args);
    va_end(args);

    fprintf(stderr, "\n");

    return timeStr;
}

// -----------
// -- arena --
// -----------

Arena arena_init__(const char *file, const char *func, int line, size_t size) {
    // Function entry logging
    raise_message(LOG_LEVEL_DEBUG, file, func, line, 
        "INIT: Creating arena (size: %zu bytes)", size);
    
    Arena arena;
    arena.begin = malloc(size);
    
    // Check for allocation failure
    if (!arena.begin) {
        raise_message(LOG_LEVEL_EXCEPTION, file, func, line,
            "INIT: Failed to allocate memory for arena (requested: %zu bytes)", size);
        exit(1);
    }
    
    memset(arena.begin, 0, size);
    arena.current = arena.begin;
    arena.capacity = size;
    
    // Success logging at LOG level
    raise_message(LOG_LEVEL_LOG, file, func, line,
	"INIT: Arena initialized successfully (address: %p, capacity: %zu bytes)", arena.begin, size);
    return arena;
}

void* arena_alloc_or_null__(const char *file, const char *func, int line, Arena *arena, size_t size) {
    // Function entry at TRACE level
    raise_message(LOG_LEVEL_TRACE, file, func, line, 
                 "ALLOC: Requesting memory from arena (arena: %p, size: %zu bytes)", arena, size);
    
    void *mem = NULL;
    if (arena->begin == 0) {
        raise_message(LOG_LEVEL_DEBUG, file, func, line,
                     "ALLOC: Arena not initialized, creating new arena");
        *arena = arena_init__(file, func, line, 1024); // ARENA_DEFAULT_SIZE assumed as 1024
    }
    
    size_t current = (size_t)arena->current - (size_t)arena->begin;
    if (arena->capacity <= current || arena->capacity - current < size) {
        raise_message(LOG_LEVEL_WARN, file, func, line,
	    "ALLOC: Insufficient memory in arena (address: %p, capacity: %zu bytes, used: %zu bytes, requested: %zu bytes)",
                               arena->begin, arena->capacity, current, size);
	return NULL;
    } else {
        raise_message(LOG_LEVEL_DEBUG, file, func, line,
	    "ALLOC: Allocating from arena (address: %p, capacity: %zu bytes, used: %zu bytes, requested: %zu bytes)",
                               arena->begin, arena->capacity, current, size);
        mem = arena->current;
        arena->current = (char*)arena->current + size;
    }
    
    // Success logging
    raise_message(LOG_LEVEL_DEBUG, file, func, line, 
                 "ALLOC: Memory allocated successfully (address: %p, size: %zu bytes)", mem, size);
    return mem;
}

void* arena_alloc__(const char *file, const char *func, int line, Arena *arena, size_t size) {
    // Function entry logging
    raise_message(LOG_LEVEL_DEBUG, file, func, line, 
                 "ALLOC: Allocating memory (arena: %p, size: %zu bytes)", arena, size);
    
    void *mem = arena_alloc_or_null__(file, func, line, arena, size);
    if (!mem) {
        raise_message(LOG_LEVEL_DEBUG, file, func, line, 
	  "ALLOC: Allocation failed (arena: %p, requested: %zu bytes)", arena, size);
        raise_message(LOG_LEVEL_EXCEPTION, file, func, line, 
	  "ALLOC: Arena out of memory (requested: %zu bytes)", size);
        exit(1);
    }
    
    // Success logging
    raise_message(LOG_LEVEL_LOG, file, func, line,
                 "ALLOC: Memory allocated successfully (address: %p, size: %zu bytes)", mem, size);
    return mem;
}

void arena_reset__(const char *file, const char *func, int line, Arena *arena) {
  // Function entry logging
  raise_message(LOG_LEVEL_DEBUG, file, func, line, 
    "ALLOC: Resetting arena (address: %p)", arena);
  
  // Check for NULL arena
  if (!arena) {
    raise_message(LOG_LEVEL_WARN, file, func, line,
      "ALLOC: Attempted to reset NULL arena");
    return;
  }
  
  // Reset the arena
  arena->current = arena->begin;
  
  // Operation success logging
  raise_message(LOG_LEVEL_LOG, file, func, line, 
    "ALLOC: Arena reset successfully (address: %p, capacity: %zu bytes)", 
    arena->begin, arena->capacity);
}

void arena_free__(const char *file, const char *func, int line, Arena *arena) {
  // Function entry logging
  raise_message(LOG_LEVEL_DEBUG, file, func, line,
    "FREE: Releasing arena memory (address: %p)", arena);
  
  // Check for NULL arena
  if (!arena) {
    raise_message(LOG_LEVEL_WARN, file, func, line,
      "FREE: Attempted to free NULL arena");
    return;
  }
  
  // Check for NULL begin pointer
  if (!arena->begin) {
    raise_message(LOG_LEVEL_WARN, file, func, line,
      "FREE: Attempted to free arena with NULL memory block");
    return;
  }
  
  // Calculate used memory for logging
  size_t used = (size_t)arena->current - (size_t)arena->begin;
  
  // Free the memory
  free(arena->begin);
  
  // Success logging
  raise_message(LOG_LEVEL_LOG, file, func, line,
    "FREE: Arena released successfully (address: %p, capacity: %zu bytes, used: %zu bytes)",
    arena->begin, arena->capacity, used);
    
  // Clear the pointers
  arena->begin = NULL;
  arena->current = NULL;
  arena->capacity = 0;
}

char* arena_strdup__(const char *file, const char *func, int line, Arena *arena, const char *s) {
    // Function entry logging
    raise_message(LOG_LEVEL_TRACE, file, func, line,
        "ALLOC: Duplicating string (arena: %p, source: %p, preview: %.20s%s)",
        arena, s, s ? s : "", s && strlen(s) > 20 ? "..." : "");
    
    // Check for NULL string
    if (!s) {
        raise_message(LOG_LEVEL_DEBUG, file, func, line,
            "ALLOC: Source string is NULL, returning NULL");
        return NULL;
    }
    
    // Calculate string length and allocate memory
    size_t len = strlen(s) + 1;
    
    // Success case
    char *result = (char*)arena_alloc__(file, func, line, arena, len);
    
    // Copy the string
    memcpy(result, s, len);
    
    // Success logging
    raise_message(LOG_LEVEL_DEBUG, file, func, line,
        "ALLOC: String duplicated successfully (result: %p, length: %zu bytes)", 
        result, len);
    
    return result;
}

char* arena_repstr__(const char *file, const char *func, int line, Arena *arena,
                             const char *src, size_t start, size_t len, const char *rep) {
  // Function entry logging
  raise_message(LOG_LEVEL_TRACE, file, func, line, 
    "STRING: Replacing substring (source: %p, start: %zu, length: %zu, replacement: %.20s%s)", 
    src, start, len, rep, strlen(rep) > 20 ? "..." : "");
  
  // Check inputs
  if (!src) {
    raise_message(LOG_LEVEL_WARN, file, func, line,
      "STRING: Source string is NULL");
    return NULL;
  }
  
  if (!rep) {
    raise_message(LOG_LEVEL_WARN, file, func, line,
      "STRING: Replacement string is NULL");
    return NULL;
  }
  
  // Calculate lengths
  int src_len = strlen(src);
  int rep_len = strlen(rep);
  
  // Validate start and length
  if (start > (size_t)src_len) {
    raise_message(LOG_LEVEL_WARN, file, func, line,
      "STRING: Start position %zu exceeds source length %d", start, src_len);
    // Return a copy of the source string
    return arena_strdup__(file, func, line, arena, src);
  }
  
  if (start + len > (size_t)src_len) {
    size_t old_len = len;
    len = src_len - start;
    raise_message(LOG_LEVEL_DEBUG, file, func, line,
      "STRING: Adjusted length from %zu to %zu to fit source bounds", old_len, len);
  }
  
  // Calculate new length and allocate memory
  int new_len = src_len - (int)len + rep_len;
  char *new_str = (char*)arena_alloc__(file, func, line, arena, new_len + 1);
  
  // Perform the replacement operation
  memcpy(new_str, src, start);
  memcpy(new_str + start, rep, rep_len);
  strcpy(new_str + start + rep_len, src + start + len);
  
  // Success logging
  raise_message(LOG_LEVEL_DEBUG, file, func, line,
    "STRING: Replacement complete (result: %p, new length: %d)", new_str, new_len);
  
  return new_str;
}

void* arena_realloc_copy__(const char *file, const char *func, int line, Arena *arena,
                           void *old_ptr, size_t old_size, size_t new_size) {
    void *new_ptr = NULL;
    if (old_ptr == NULL) {
        new_ptr = arena_alloc__(file, func, line, arena, new_size);
    } else if (new_size <= old_size) {
        new_ptr = old_ptr;
    } else {
        new_ptr = arena_alloc_or_null__(file, func, line, arena, new_size);
        if (new_ptr)
            memcpy(new_ptr, old_ptr, old_size);
    }
    return new_ptr;
}

// ----------
// -- misc --
// ----------

void substr_clone__(const char *file, const char *func, int line, const char * const src, char *dest, size_t from, size_t len) {
    // Log function entry at TRACE level
    raise_message(LOG_LEVEL_TRACE, file, func, line,
        "Function called with src=%p, dest=%p, from=%zu, len=%zu",
        src, dest, from, len);

    if (!src || !dest) {
        raise_message(LOG_LEVEL_EXCEPTION, file, func, line,
            "Invalid NULL pointer: %s%s",
            (!src ? "src " : ""),
            (!dest ? "dest" : ""));
        if (dest) dest[0] = '\0';
        return;
    }

    size_t srclen = strlen(src);
    if (from >= srclen) {
        // Log warning with context when 'from' is out of range
        raise_message(LOG_LEVEL_WARN, file, func, line,
            "Out of range: 'from' index (%zu) exceeds source length (%zu)",
            from, srclen);
        dest[0] = '\0';
        return;
    }

    // Adjust length if needed
    if (from + len > srclen) {
        size_t old_len = len;
        len = srclen - from;
        raise_message(LOG_LEVEL_DEBUG, file, func, line,
            "Adjusted length from %zu to %zu to fit source bounds",
            old_len, len);
    }

    // Copy the substring
    strncpy(dest, src + from, len);
    dest[len] = '\0';

    // Log success at TRACE level
    raise_message(LOG_LEVEL_TRACE, file, func, line,
        "Successfully copied %zu bytes: \"%.*s\"",
        len, (int)len, dest);
}

// ----------
// -- Json --
// ----------

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

static Json *json_parse_value__(const char *file, const char *func, int line, const char **s, Arena *arena);

/* Parse a JSON string (does not handle full escaping) */
static char *json_parse_string__(const char *file, const char *func, int line, const char **s_ptr, Arena *arena) {
    const char *s = *s_ptr;
    raise_message(LOG_LEVEL_DEBUG, file, func, line, "Entering json_parse_string__ at position: %p", s);
    if (*s != '"') {
        raise_message(LOG_LEVEL_DEBUG, file, func, line, "Expected '\"' at start of string, got: %c", *s);
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
        raise_message(LOG_LEVEL_DEBUG, file, func, line, "Unterminated string starting at: %p", start);
        return NULL;
    }
    size_t len = s - start;
    char *str = arena_alloc__(file, func, line, arena, len + 1);
    if (!str) {
        raise_message(LOG_LEVEL_DEBUG, file, func, line, "Memory allocation failed in json_parse_string__");
        return NULL;
    }
    memcpy(str, start, len);
    str[len] = '\0';
    *s_ptr = s + 1; // skip closing quote
    raise_message(LOG_LEVEL_DEBUG, file, func, line, "Parsed string: \"%s\" (length: %zu)", str, len);
    return str;
}

/* Parse a number using strtod */
static double json_parse_number__(const char *file, const char *func, int line, const char **s_ptr) {
    raise_message(LOG_LEVEL_DEBUG, file, func, line, "Parsing number at position: %p", *s_ptr);
    char *end;
    double num = strtod(*s_ptr, &end);
    if (*s_ptr == end)
        raise_message(LOG_LEVEL_DEBUG, file, func, line, "No valid number found at: %p", *s_ptr);
    *s_ptr = end;
    raise_message(LOG_LEVEL_DEBUG, file, func, line, "Parsed number: %g", num);
    return num;
}

/* Parse a JSON array: [ value, value, ... ] */
static Json *json_parse_array__(const char *file, const char *func, int line, const char **s, Arena *arena) {
    raise_message(LOG_LEVEL_DEBUG, file, func, line, "Entering json_parse_array__ at position: %p", *s);
    if (**s != '[') return NULL;
    (*s)++; // skip '['
    *s = skip_whitespace(*s);
    Json *array = arena_alloc__(file, func, line, arena, sizeof(Json));
    if (!array) {
        raise_message(LOG_LEVEL_DEBUG, file, func, line, "Memory allocation failed in json_parse_array__");
        return NULL;
    }
    memset(array, 0, sizeof(Json));
    array->type = JSON_ARRAY;
    Json *last = NULL;
    if (**s == ']') { // empty array
        (*s)++;
        raise_message(LOG_LEVEL_DEBUG, file, func, line, "Parsed empty array");
        return array;
    }
    while (**s) {
        Json *element = json_parse_value__(file, func, line, s, arena);
        if (!element) {
            raise_message(LOG_LEVEL_DEBUG, file, func, line, "Failed to parse array element");
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
            raise_message(LOG_LEVEL_DEBUG, file, func, line, "Completed parsing array");
            break;
        } else {
            raise_message(LOG_LEVEL_DEBUG, file, func, line, "Unexpected character '%c' in array", **s);
            return NULL;
        }
    }
    raise_message(LOG_LEVEL_DEBUG, file, func, line, "Completed parsing array");
    return array;
}

/* Parse a JSON object: { "key": value, ... } */
static Json *json_parse_object__(const char *file, const char *func, int line, const char **s, Arena *arena) {
    raise_message(LOG_LEVEL_DEBUG, file, func, line, "Entering json_parse_object__ at position: %p", *s);
    if (**s != '{') return NULL;
    (*s)++; // skip '{'
    *s = skip_whitespace(*s);
    Json *object = arena_alloc__(file, func, line, arena, sizeof(Json));
    if (!object) {
        raise_message(LOG_LEVEL_DEBUG, file, func, line, "Memory allocation failed in json_parse_object__");
        return NULL;
    }
    memset(object, 0, sizeof(Json));
    object->type = JSON_OBJECT;
    Json *last = NULL;
    if (**s == '}') {
        (*s)++;
        raise_message(LOG_LEVEL_DEBUG, file, func, line, "Parsed empty object");
        return object;
    }
    while (**s) {
        char *key = json_parse_string__(file, func, line, s, arena);
        if (!key) {
            raise_message(LOG_LEVEL_DEBUG, file, func, line, "Failed to parse key in object");
            return NULL;
        }
        *s = skip_whitespace(*s);
        if (**s != ':') {
            raise_message(LOG_LEVEL_DEBUG, file, func, line, "Expected ':' after key \"%s\", got: %c", key, **s);
            return NULL;
        }
        (*s)++; // skip ':'
        *s = skip_whitespace(*s);
        Json *value = json_parse_value__(file, func, line, s, arena);
        if (!value) {
            raise_message(LOG_LEVEL_DEBUG, file, func, line, "Failed to parse value for key \"%s\"", key);
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
            raise_message(LOG_LEVEL_DEBUG, file, func, line, "Unexpected character '%c' in object", **s);
            return NULL;
        }
    }
    raise_message(LOG_LEVEL_DEBUG, file, func, line, "Completed parsing object");
    return object;
}

/* Full JSON value parser */
static Json *json_parse_value__(const char *file, const char *func, int line, const char **s, Arena *arena) {
    *s = skip_whitespace(*s);
    raise_message(LOG_LEVEL_DEBUG, file, func, line, "Parsing JSON value at position: %p", *s);
    if (**s == '"') {
        Json *item = arena_alloc__(file, func, line, arena, sizeof(Json));
        if (!item) {
            raise_message(LOG_LEVEL_DEBUG, file, func, line, "Memory allocation failed in json_parse_value for string");
            return NULL;
        }
        memset(item, 0, sizeof(Json));
        item->type = JSON_STRING;
        item->JsonValue.string = json_parse_string__(file, func, line, s, arena);
        return item;
    } else if (strncmp(*s, "null", 4) == 0) {
        Json *item = arena_alloc__(file, func, line, arena, sizeof(Json));
        if (!item) return NULL;
        memset(item, 0, sizeof(Json));
        item->type = JSON_NULL;
        *s += 4;
        return item;
    } else if (strncmp(*s, "true", 4) == 0) {
        Json *item = arena_alloc__(file, func, line, arena, sizeof(Json));
        if (!item) return NULL;
        memset(item, 0, sizeof(Json));
        item->type = JSON_BOOL;
        item->JsonValue.boolean = 1;
        *s += 4;
        return item;
    } else if (strncmp(*s, "false", 5) == 0) {
        Json *item = arena_alloc__(file, func, line, arena, sizeof(Json));
        if (!item) return NULL;
        memset(item, 0, sizeof(Json));
        item->type = JSON_BOOL;
        item->JsonValue.boolean = 0;
        *s += 5;
        return item;
    } else if ((**s == '-') || isdigit((unsigned char)**s)) {
        Json *item = arena_alloc__(file, func, line, arena, sizeof(Json));
        if (!item) {
            raise_message(LOG_LEVEL_DEBUG, file, func, line, "Memory allocation failed in json_parse_value for number");
            return NULL;
        }
        memset(item, 0, sizeof(Json));
        item->type = JSON_NUMBER;
        item->JsonValue.number = json_parse_number__(file, func, line, s);
        return item;
    } else if (**s == '[') {
        return json_parse_array__(file, func, line, s, arena);
    } else if (**s == '{') {
        return json_parse_object__(file, func, line, s, arena);
    }
    raise_message(LOG_LEVEL_DEBUG, file, func, line, "Unrecognized JSON value at position: %p", *s);
    return NULL;
}

Json *json_parse__(const char* file, const char* func, int line, Arena *arena, const char **s) {
    // Function entry logging with DEBUG level
    raise_message(LOG_LEVEL_DEBUG, file, func, line, 
        "PARSE: Starting JSON parsing (input: %p)", *s);
    
    // Check input parameters
    if (!s || !*s) {
        raise_message(LOG_LEVEL_EXCEPTION, file, func, line,
            "PARSE: Invalid input parameters (NULL pointer provided for JSON parsing)");
        return NULL;
    }
    
    if (!arena) {
        raise_message(LOG_LEVEL_EXCEPTION, file, func, line,
            "PARSE: Invalid arena (NULL) provided for JSON parsing");
        return NULL;
    }
    
    // Show input preview for debugging with TRACE level
    raise_message(LOG_LEVEL_TRACE, file, func, line,
        "PARSE: Input preview: '%.20s%s'", *s, strlen(*s) > 20 ? "..." : "");
    
    // Process JSON value
    Json *result = json_parse_value__(file, func, line, s, arena);
    
    // Log parsing result
    if (!result) {
        raise_message(LOG_LEVEL_WARN, file, func, line, 
            "PARSE: Failed to parse JSON at position %p (context: '%.10s')", 
            *s, *s && strlen(*s) > 0 ? *s : "<empty>");
    } else {
        raise_message(LOG_LEVEL_LOG, file, func, line, 
            "PARSE: JSON parsing completed successfully (type: %s)", json_type_to_string(result->type));
    }
    
    return result;
}

char *json_to_string__(const char* file, const char* func, int line, Arena *arena, const Json * const item) {
    return json_to_string_with_opts__(file, func, line, arena, item, JSON_NORAW);
}

/* Minimal JSON printer with raw output option.
   When raw is non-zero and the item is a JSON_STRING, it is printed without quotes.
*/
char *json_to_string_with_opts__(const char* file, const char* func, int line, Arena *arena, const Json * const item, JsonRawOpt raw) {
    // Function entry with DEBUG level
    raise_message(LOG_LEVEL_DEBUG, file, func, line, 
                  "FORMAT: Starting JSON conversion to string (item: %p, raw_mode: %s)", 
                  item, raw == JSON_RAW ? "enabled" : "disabled");
    
    // Check input parameters
    if (!item) {
        raise_message(LOG_LEVEL_EXCEPTION, file, func, line, 
                     "FORMAT: Invalid JSON object (NULL) provided for string conversion");
        return NULL;
    }
    
    if (!arena) {
        raise_message(LOG_LEVEL_EXCEPTION, file, func, line,
                     "FORMAT: Invalid arena (NULL) provided for string conversion");
        return NULL;
    }
    
    // Allocate memory for the string
    char *out = arena_alloc__(file, func, line, arena, 1024);
    if (!out) {
        raise_message(LOG_LEVEL_EXCEPTION, file, func, line, 
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
        
        raise_message(LOG_LEVEL_TRACE, file, func, line, 
                      "FORMAT: Processing JSON object children");
        
        while (child) {
            ptr += sprintf(ptr, "\"%s\":", child->key ? child->key : "");
            char *child_str = json_to_string_with_opts__(file, func, line, arena, child, raw);
            if (child_str) {
                ptr += sprintf(ptr, "%s", child_str);
            } else {
                raise_message(LOG_LEVEL_WARN, file, func, line, 
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
        raise_message(LOG_LEVEL_TRACE, file, func, line, 
                      "FORMAT: Object conversion complete with %d child elements", child_count);
    } else if (item->type == JSON_ARRAY) {
        ptr += sprintf(ptr, "[");
        type_name = "array";
        
        Json *child = item->child;
        int child_count = 0;
        
        raise_message(LOG_LEVEL_TRACE, file, func, line, 
                      "FORMAT: Processing JSON array elements");
        
        while (child) {
            char *child_str = json_to_string_with_opts__(file, func, line, arena, child, raw);
            if (child_str) {
                ptr += sprintf(ptr, "%s", child_str);
            } else {
                raise_message(LOG_LEVEL_WARN, file, func, line, 
                              "FORMAT: Failed to stringify array element at index %d", child_count);
            }
            
            if (child->next) {
                ptr += sprintf(ptr, ",");
            }
            child = child->next;
            child_count++;
        }
        
        sprintf(ptr, "]");
        raise_message(LOG_LEVEL_TRACE, file, func, line, 
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
    
    raise_message(LOG_LEVEL_LOG, file, func, line, 
                  "FORMAT: JSON %s converted to string (length=%zu)", 
                  type_name, strlen(out));
    
    return out;
}

/* Retrieve an object item by key (case-sensitive) */
Json *json_get_object_item__(const char* file, const char* func, int line, const Json * const object, const char * const key) {
    raise_message(LOG_LEVEL_TRACE, file, func, line, 
                 "ACCESS: Searching for key \"%s\" in JSON object %p", 
                 key ? key : "<null>", object);
    
    // Check input parameters
    if (!object) {
        raise_message(LOG_LEVEL_WARN, file, func, line, 
                     "ACCESS: Invalid object (NULL) passed to json_get_object_item");
        return NULL;
    }
    
    if (!key) {
        raise_message(LOG_LEVEL_WARN, file, func, line, 
                     "ACCESS: Invalid key (NULL) passed to json_get_object_item");
        return NULL;
    }
    
    if (object->type != JSON_OBJECT) {
        raise_message(LOG_LEVEL_WARN, file, func, line, 
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
    
    raise_message(LOG_LEVEL_TRACE, file, func, line, 
                 "ACCESS: Object has %d key-value pairs", total_keys);
    
    // Perform key search
    Json *child = object->child;
    int position = 0;
    
    while (child) {
        if (child->key) {
            raise_message(LOG_LEVEL_TRACE, file, func, line, 
                         "ACCESS: Comparing key \"%s\" with \"%s\" at position %d", 
                         child->key, key, position);
            
            if (strcmp(child->key, key) == 0) {
                raise_message(LOG_LEVEL_LOG, file, func, line, 
                             "ACCESS: Found value for key \"%s\" (type: %s)", 
                             key, json_type_to_string(child->type));
                return child;
            }
        } else {
            raise_message(LOG_LEVEL_TRACE, file, func, line, 
                         "ACCESS: Skipping element at position %d with NULL key", position);
        }
        
        child = child->next;
        position++;
    }
    
    raise_message(LOG_LEVEL_DEBUG, file, func, line, 
                 "ACCESS: Key \"%s\" not found in object (checked %d items)", 
                 key, position);
    return NULL;
}

// -----------
// -- slice --
// -----------

// Create a slice from an array with boundary check.
Slice slice_create__(const char *file, const char *func, int line, size_t isize, void *array, size_t array_len, size_t start, size_t len) {
    // Function entry logging
    raise_message(LOG_LEVEL_TRACE, file, func, line, 
        "SLICE: Creating slice (source: %p, array_length: %zu, start: %zu, length: %zu, item_size: %zu)", 
        array, array_len, start, len, isize);
    
    // Boundary check
    if (start + len > array_len) {
        raise_message(LOG_LEVEL_WARN, file, func, line,
            "SLICE: Slice boundaries exceed array length (start: %zu, length: %zu, array_length: %zu)",
            start, len, array_len);
        return (Slice){NULL, 0, isize};
    }
    
    // Create valid slice
    Slice result = (Slice){ (char *)array + start * isize, len, isize };
    
    // Success logging
    raise_message(LOG_LEVEL_TRACE, file, func, line,
        "SLICE: Slice created successfully (data: %p, length: %zu, item_size: %zu)",
        result.data, result.len, result.isize);
    
    return result;
}

// Return a subslice from an existing slice.
Slice slice_subslice__(const char *file, const char *func, int line, Slice s, size_t start, size_t len) {
    // Function entry logging
    raise_message(LOG_LEVEL_TRACE, file, func, line, 
        "SLICE: Creating subslice (source: %p, source_length: %zu, start: %zu, length: %zu)", 
        s.data, s.len, start, len);
    
    // Boundary check
    if (start + len > s.len) {
        raise_message(LOG_LEVEL_WARN, file, func, line,
            "SLICE: Subslice boundaries exceed source slice length (start: %zu, length: %zu, source_length: %zu)",
            start, len, s.len);
        return (Slice){NULL, 0, s.isize};
    }
    
    // Create valid subslice
    Slice result = (Slice){(char*)s.data + start * s.isize, len, s.isize};
    
    // Success logging
    raise_message(LOG_LEVEL_TRACE, file, func, line,
        "SLICE: Subslice created successfully (data: %p, length: %zu, item_size: %zu)",
        result.data, result.len, result.isize);
    
    return result;
}

int* arena_slice_copy__(const char *file, const char *func, int line, Arena *arena, Slice s) {
    raise_message(LOG_LEVEL_TRACE, file, func, line, "arena_slice_copy(<optimized>, <optimized>)");
    int *copy = (void*) arena_alloc__(file, func, line, arena, s.len * sizeof(int));
    if (copy)
        memcpy(copy, s.data, s.len * s.isize);
    return copy;
}

// ------------
// -- debug --
// ------------

char* slice_to_debug_str(Arena *arena, Slice slice) {
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

  raise_trace("slice_to_debug_str: %s", buffer);
  
  return buffer;
}

char* json_to_debug_str(Arena *arena, Json json) {
  // Add information about the JSON structure itself
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

// ---------------
// -- Templater --
// ---------------

// Look at package\c\hectic\docs\templater.md

TemplateConfig *template_default_config__(const char *file, const char *func, int line, Arena *arena) {
  TemplateConfig *config = arena_alloc__(file, func, line, arena, sizeof(TemplateConfig));
  if (!config) return NULL;
  
  config->open_brace = "{%";
  config->close_brace = "%}";
  config->null_handler = "%%";
  config->section_prefix = "for ";
  config->section_suffix = " in ";
  config->section_optional_suffix = " join ";
  config->section_post_suffix = " do ";
  config->interpolation_prefix = "";
  config->include_prefix = "include ";
  config->function_prefix = "call ";
  
  return config;
}

static TemplateNode *template_node_create__(const char *file, const char *func, int line, Arena *arena, TemplateNodeType type, TemplateValue *value) {
  TemplateNode *node = arena_alloc__(file, func, line, arena, sizeof(TemplateNode));
  if (!node) {
    raise_message(LOG_LEVEL_EXCEPTION, file, func, line, "Failed to allocate node");
  }

  node->type = type;
  node->value = *value;
  node->children = NULL;
  node->next = NULL;

  return node;
}

#define CHECK_CONFIG_STR(field, name)                                      \
do {                                                                       \
  if (!(config->field)) {                                                  \
    raise_message(LOG_LEVEL_EXCEPTION, file, func, line, "CONFIG: " name " is NULL");     \
    return false;                                                          \
  }                                                                        \
  if (strlen(config->field) > TEMPLATE_MAX_PREFIX_LEN) {                   \
    raise_message(LOG_LEVEL_EXCEPTION, file, func, line, "CONFIG: " name " is too long"); \
    return false;                                                          \
  }                                                                        \
} while (0)

bool template_validate_config__(const char *file, const char *func, int line, TemplateConfig *config) {
  if (!config) {
    raise_message(LOG_LEVEL_EXCEPTION, file, func, line, "Config is NULL");
    return false;
  }

  CHECK_CONFIG_STR(open_brace, "Open brace");
  CHECK_CONFIG_STR(close_brace, "Close brace");
  CHECK_CONFIG_STR(null_handler, "Null handler");
  CHECK_CONFIG_STR(section_prefix, "Section prefix");
  CHECK_CONFIG_STR(section_suffix, "Section suffix");
  CHECK_CONFIG_STR(section_optional_suffix, "Section optional suffix");
  CHECK_CONFIG_STR(section_post_suffix, "Section post suffix");
  CHECK_CONFIG_STR(interpolation_prefix, "Interpolation prefix");
  CHECK_CONFIG_STR(include_prefix, "Include prefix");
  CHECK_CONFIG_STR(function_prefix, "Function prefix");

  return true;
}

TemplateNode *template_parse__(const char *file, const char *func, int line, Arena *arena, const char *template, TemplateConfig *config) {
  if (!arena) {
    raise_message(LOG_LEVEL_EXCEPTION, file, func, line, "Arena is NULL");
  }
  
  if (!config) {
    raise_message(LOG_LEVEL_EXCEPTION, file, func, line, "Config is NULL");
  }
  
  if (!template) {
    raise_message(LOG_LEVEL_EXCEPTION, file, func, line, "Template is NULL");
  }

  // Find the first open brace
  const char *open_brace = strstr(template, config->open_brace);
  if (!open_brace) {
    raise_message(LOG_LEVEL_LOG, file, func, line, "No open brace found");
    TemplateValue val = {.text = {.content = (char *)template}};
    return template_node_create__(file, func, line, arena,
      TEMPLATE_NODE_TEXT, &val);
  }

  // Deside tag type by prefix
  const char *tag_prefix = open_brace + strlen(config->open_brace);
  if (strncmp(tag_prefix, config->section_prefix, strlen(config->section_prefix)) == 0) {
    // Section tag
  } else if (strncmp(tag_prefix, config->interpolation_prefix, strlen(config->interpolation_prefix)) == 0) {
    // Interpolation tag
  } else if (strncmp(tag_prefix, config->include_prefix, strlen(config->include_prefix)) == 0) {
    // Include tag
  } else if (strncmp(tag_prefix, config->function_prefix, strlen(config->function_prefix)) == 0) {
    // Function tag
  } else {
    raise_message(LOG_LEVEL_EXCEPTION, file, func, line, "Unknown tag prefix: %s", slice_create__(file, func, line, 1, (char *)tag_prefix, strlen(tag_prefix), 0, TEMPLATE_MAX_PREFIX_LEN));
    return NULL;
  }

  return NULL;
}
