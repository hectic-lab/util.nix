#include "hectic.h"

void set_output_color_mode(ColorMode mode) {
    color_mode = mode;
}

// ------------
// -- Logger --
// ------------

const char* log_level_to_string(LogLevel level) {
    switch (level) {
        case LOG_LEVEL_TRACE: return "TRACE";
        case LOG_LEVEL_ZALUPA: return "ZALUPA";
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
        case LOG_LEVEL_ZALUPA: return OPTIONAL_COLOR(COLOR_MAGENTA);
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
    else if (strcmp(level_str, "ZALUPA") == 0)
        return LOG_LEVEL_ZALUPA;
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

LogLevel current_log_level = LOG_LEVEL_INFO;

void logger_level_reset() {
    current_log_level = LOG_LEVEL_INFO;
}

void logger_level(LogLevel level) {
    current_log_level = level;
}

void init_logger(void) {
    current_log_level = log_level_from_string(getenv("LOG_LEVEL"));
}

char* raise_message(
  LogLevel level,
  const char *file,
  const char *func,
  int line,
  const char *format,
  ...) {
    (void)func;
    if (level < current_log_level) {
        return NULL;
    }

    time_t now = time(NULL);
    struct tm tm_info;
    localtime_r(&now, &tm_info);
    static char timeStr[20];
    strftime(timeStr, sizeof(timeStr), "%Y-%m-%d %H:%M:%S", &tm_info);

    fprintf(stderr, "%s %s%s%s %s:%d ", timeStr, log_level_to_color(level), log_level_to_string(level), OPTIONAL_COLOR(COLOR_RESET), file, line);

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
    Arena arena;
    arena.begin = malloc(size);
    memset(arena.begin, 0, size);
    arena.current = arena.begin;
    arena.capacity = size;
    raise_message(LOG_LEVEL_DEBUG, file, func, line,
	"Initialized arena at %p with capacity %zu", arena.begin, size);
    return arena;
}

void* arena_alloc_or_null__(const char *file, const char *func, int line, Arena *arena, size_t size) {
    raise_message(LOG_LEVEL_TRACE, file, func, line, "arena_alloc_or_null(%p, %zu)", arena, size);
    void *mem = NULL;
    if (arena->begin == 0) {
        *arena = arena_init__(file, func, line, 1024); // ARENA_DEFAULT_SIZE assumed as 1024
    }
    size_t current = (size_t)arena->current - (size_t)arena->begin;
    if (arena->capacity <= current || arena->capacity - current < size) {
        raise_message(LOG_LEVEL_DEBUG, file, func, line,
	    "Arena %p (capacity %zu) used %zu cannot allocate %zu bytes",
                               arena->begin, arena->capacity, current, size);
	return NULL;
    } else {
        raise_message(LOG_LEVEL_DEBUG, file, func, line,
	    "Arena %p (capacity %zu) used %zu will allocate %zu bytes",
                               arena->begin, arena->capacity, current, size);
        mem = arena->current;
        arena->current = (char*)arena->current + size;
    }
    raise_message(LOG_LEVEL_DEBUG, file, func, line, "Allocated at %p", mem);
    return mem;
}

void* arena_alloc__(const char *file, const char *func, int line, Arena *arena, size_t size) {
    void *mem = arena_alloc_or_null__(file, func, line, arena, size);
    if (!mem) {
        raise_message(LOG_LEVEL_DEBUG, file, func, line, 
	  "Arena out of memory when trying to allocate %zu bytes", size);
        raise_message(LOG_LEVEL_EXCEPTION, file, func, line, 
	  "Arena out of memory");
        exit(1);
    }
    return mem;
}

void arena_reset__(const char *file, const char *func, int line, Arena *arena) {
  arena->current = arena->begin;
  raise_message(LOG_LEVEL_DEBUG, file, func, line, 
    "Arena %p reset", arena->begin);
}

void arena_free__(const char *file, const char *func, int line, Arena *arena) {
  raise_message(LOG_LEVEL_DEBUG, file, func, line,
    "Freeing arena at %p", arena->begin);
  free(arena->begin);
}

char* arena_strdup__(const char *file, const char *func, int line, Arena *arena, const char *s) {
    char *result;
    if (s) {
        size_t len = strlen(s) + 1;
        result = (char*)arena_alloc__(file, func, line, arena, len);
        memcpy(result, s, len);
    } else {
        result = NULL;
    }
    return result;
}

char* arena_repstr__(const char *file, const char *func, int line, Arena *arena,
                             const char *src, size_t start, size_t len, const char *rep) {
  raise_message(LOG_LEVEL_TRACE, file, func, line, "arena_repstr__(%p, %p, %zu, \"%s\")", src, start, len, rep);
  int src_len = strlen(src);
  int rep_len = strlen(rep);
  int new_len = src_len - (int)len + rep_len;
  char *new_str = (char*)arena_alloc__(file, func, line, arena, new_len + 1);
  memcpy(new_str, src, start);
  memcpy(new_str + start, rep, rep_len);
  strcpy(new_str + start + rep_len, src + start + len);
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
    // Log function entry with all parameters.
    raise_message(LOG_LEVEL_TRACE, file, func, line,
        "substr_cloning(src=\"%s\", src_ptr=%p, dest=%p, from=%zu, len=%zu)",
        src, src, dest, from, len);

    size_t srclen = strlen(src);
    if (from >= srclen) {
        // Log warning with context when 'from' is out of range.
        raise_message(LOG_LEVEL_WARN, file, func, line,
            "Invalid 'from' index (%zu): exceeds source length (%zu)",
            from, srclen);
        dest[0] = '\0';
        return;
    }
    if (from + len > srclen)
        len = srclen - from;

    strncpy(dest, src + from, len);
    dest[len] = '\0';

    // Log success message with result.
    raise_message(LOG_LEVEL_TRACE, file, func, line,
        "Completed substr_cloning: result=\"%s\", copied_length=%zu",
        dest, len);
}

// ----------
// -- Json --
// ----------

/* Utility: Skip whitespace */
static const char *skip_whitespace(const char *s) {
    while (*s && isspace((unsigned char)*s))
        s++;
    return s;
}

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

/* Forward declaration */
static Json *json_parse_value__(const char *file, const char *func, int line, const char **s, Arena *arena);

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
    Json *result = json_parse_value__(file, func, line, s, arena);
    if (!result)
        raise_message(LOG_LEVEL_DEBUG, file, func, line, "json_parse failed at position: %p", *s);
    return result;
}

char *json_to_string__(const char* file, const char* func, int line, Arena *arena, const Json * const item) {
    return json_to_string_with_opts__(file, func, line, arena, item, JSON_NORAW);
}

/* Minimal JSON printer with raw output option.
   When raw is non-zero and the item is a JSON_STRING, it is printed without quotes.
*/
char *json_to_string_with_opts__(const char* file, const char* func, int line, Arena *arena, const Json * const item, JsonRawOpt raw) {
    char *out = arena_alloc__(file, func, line, arena, 1024);
    if (!out) {
        raise_message(LOG_LEVEL_DEBUG, file, func, line, "Memory allocation failed in json_to_string_with_opts");
        return NULL;
    }
    char *ptr = out;
    if (item->type == JSON_OBJECT) {
        ptr += sprintf(ptr, "{");
        Json *child = item->child;
        while (child) {
            ptr += sprintf(ptr, "\"%s\":", child->key ? child->key : "");
            char *child_str = json_to_string_with_opts__(file, func, line, arena, child, raw);
            ptr += sprintf(ptr, "%s", child_str);
            if (child->next)
                ptr += sprintf(ptr, ",");
            child = child->next;
        }
        sprintf(ptr, "}");
    } else if (item->type == JSON_ARRAY) {
        ptr += sprintf(ptr, "[");
        Json *child = item->child;
        while (child) {
            char *child_str = json_to_string_with_opts__(file, func, line, arena, child, raw);
            ptr += sprintf(ptr, "%s", child_str);
            if (child->next)
                ptr += sprintf(ptr, ",");
            child = child->next;
        }
        sprintf(ptr, "]");
    } else if (item->type == JSON_STRING) {
        if ((int)raw)
            sprintf(ptr, "%s", item->JsonValue.string);
        else
            sprintf(ptr, "\"%s\"", item->JsonValue.string);
    } else if (item->type == JSON_NUMBER) {
        sprintf(ptr, "%g", item->JsonValue.number);
    } else if (item->type == JSON_BOOL) {
        sprintf(ptr, item->JsonValue.boolean ? "true" : "false");
    } else if (item->type == JSON_NULL) {
        sprintf(ptr, "null");
    }
    raise_message(LOG_LEVEL_DEBUG, file, func, line, "Converted JSON to string: %s", out);
    return out;
}

/* Retrieve an object item by key (case-sensitive) */
Json *json_get_object_item__(const char* file, const char* func, int line, const Json * const object, const char * const key) {
    raise_message(LOG_LEVEL_DEBUG, file, func, line, "json_get_object_item: Searching for key \"%s\"", key);
    if (!object || object->type != JSON_OBJECT) {
        raise_message(LOG_LEVEL_DEBUG, file, func, line, "Invalid object passed to json_get_object_item");
        return NULL;
    }
    Json *child = object->child;
    while (child) {
        raise_message(LOG_LEVEL_DEBUG, file, func, line, "Comparing child key \"%s\" with \"%s\"", child->key, key);
        if (child->key && strcmp(child->key, key) == 0) {
            raise_message(LOG_LEVEL_DEBUG, file, func, line, "Key \"%s\" found", key);
            return child;
        }
        child = child->next;
    }
    raise_message(LOG_LEVEL_DEBUG, file, func, line, "Key \"%s\" not found in object", key);
    return NULL;
}

// -----------
// -- slice --
// -----------

// Create a slice from an array with boundary check.
Slice slice_create__(const char *file, const char *func, int line, size_t isize, void *array, size_t array_len, size_t start, size_t len) {
    raise_message(LOG_LEVEL_TRACE, file, func, line, "slice_create(<optimized>, <optimized>, <optimized>, <optimized>, <optimized>)");
    if (start + len > array_len)
        return (Slice){NULL, 0, isize};
    return (Slice){ (char *)array + start * isize, len, isize };
}

// Return a subslice from an existing slice.
Slice slice_subslice__(const char *file, const char *func, int line, Slice s, size_t start, size_t len) {
    raise_message(LOG_LEVEL_TRACE, file, func, line, "slice_subslice(<optimized>, <optimized>, <optimized>)");
    if (start + len > s.len)
        return (Slice){NULL, 0, s.isize};
    return (Slice){(char*)s.data + start * s.isize, len, s.isize};
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
  // Создадим полную информацию о структуре Slice
  char buffer_meta[128];
  snprintf(buffer_meta, sizeof(buffer_meta), "Slice{addr=%p, data=%p, len=%zu, isize=%zu, content=",
           (void*)&slice, slice.data, slice.len, slice.isize);
  
  size_t meta_len = strlen(buffer_meta);
  
  // Для NULL-данных выведем простое сообщение
  if (!slice.data) {
    char* result = arena_alloc(arena, meta_len + 6);
    strcpy(result, buffer_meta);
    strcat(result, "NULL}");
    return result;
  }
  
  // Allocate buffer with space for quotes, metadata and null terminator
  size_t buffer_size = meta_len + slice.len * 4 + 20; // Extra space for escaping and closing brace
  char* buffer = arena_alloc(arena, buffer_size);
  
  // Копируем метаданные
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
  *pos++ = '}'; // Закрывающая скобка для структуры
  *pos = '\0';

  raise_trace("slice_to_debug_str: %s", buffer);
  
  return buffer;
}

char* json_to_debug_str(Arena *arena, Json json) {
  // Добавляем информацию о самой структуре JSON
  char meta_buffer[256];
  const char* type_str = "";
  
  switch (json.type) {
    case JSON_NULL: type_str = "NULL"; break;
    case JSON_BOOL: type_str = "BOOL"; break;
    case JSON_NUMBER: type_str = "NUMBER"; break;
    case JSON_STRING: type_str = "STRING"; break;
    case JSON_ARRAY: type_str = "ARRAY"; break;
    case JSON_OBJECT: type_str = "OBJECT"; break;
    default: type_str = "UNKNOWN";
  }
  
  snprintf(meta_buffer, sizeof(meta_buffer), "Json{addr=%p, type=%s, key=%s, child=%p, next=%p, value=",
           (void*)&json, type_str, json.key ? json.key : "NULL", (void*)json.child, (void*)json.next);
  
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
      // Для массивов просто отметим количество элементов
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
      // Для объектов отметим количество пар ключ-значение
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
  
  // Создаем итоговую строку
  size_t result_len = meta_len + strlen(value_buffer) + 2; // +2 для закрывающей скобки и нулевого символа
  char* result = arena_alloc(arena, result_len);
  
  strcpy(result, meta_buffer);
  strcat(result, value_buffer);
  strcat(result, "}");
  
  return result;
}