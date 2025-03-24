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
        case LOG_LEVEL_DEBUG: return "DEBUG";
        case LOG_LEVEL_LOG:  return "LOG";
        case LOG_LEVEL_INFO:  return "INFO";
        case LOG_LEVEL_NOTICE:  return "NOTICE";
        case LOG_LEVEL_WARN:  return "WARN";
        case LOG_LEVEL_EXCEPTION: return "EXCEPTION";
        default:              return "UNKNOWN";
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

char* raise_message(LogLevel level, const char *file, int line, const char *format, ...) {
    if (level < current_log_level) {
        return NULL;
    }

    time_t now = time(NULL);
    struct tm tm_info;
    localtime_r(&now, &tm_info);
    static char timeStr[20];
    strftime(timeStr, sizeof(timeStr), "%Y-%m-%d %H:%M:%S", &tm_info);

    fprintf(stderr, "%s %s %s:%d ", timeStr, log_level_to_string(level), file, line);

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

Arena arena_init__(const char *file, int line, size_t size) {
    Arena arena;
    arena.begin = malloc(size);
    memset(arena.begin, 0, size);
    arena.current = arena.begin;
    arena.capacity = size;
    raise_message(LOG_LEVEL_DEBUG, file, line,
	"Initialized arena at %p with capacity %zu", arena.begin, size);
    return arena;
}

void* arena_alloc_or_null__(const char *file, int line, Arena *arena, size_t size) {
    raise_message(LOG_LEVEL_TRACE, file, line, "arena_alloc_or_null(%p, %zu)", arena, size);
    void *mem = NULL;
    if (arena->begin == 0) {
        *arena = arena_init__(file, line, 1024); // ARENA_DEFAULT_SIZE assumed as 1024
    }
    size_t current = (size_t)arena->current - (size_t)arena->begin;
    if (arena->capacity <= current || arena->capacity - current < size) {
        raise_message(LOG_LEVEL_DEBUG, file, line,
	    "Arena %p (capacity %zu) used %zu cannot allocate %zu bytes",
                               arena->begin, arena->capacity, current, size);
	return NULL;
    } else {
        raise_message(LOG_LEVEL_DEBUG, file, line,
	    "Arena %p (capacity %zu) used %zu will allocate %zu bytes",
                               arena->begin, arena->capacity, current, size);
        mem = arena->current;
        arena->current = (char*)arena->current + size;
    }
    raise_message(LOG_LEVEL_DEBUG, file, line, "Allocated at %p", mem);
    return mem;
}

void* arena_alloc__(const char *file, int line, Arena *arena, size_t size) {
    void *mem = arena_alloc_or_null__(file, line, arena, size);
    if (!mem) {
        raise_message(LOG_LEVEL_DEBUG, file, line, 
	  "Arena out of memory when trying to allocate %zu bytes", size);
        raise_message(LOG_LEVEL_EXCEPTION, file, line, 
	  "Arena out of memory");
        exit(1);
    }
    return mem;
}

void arena_reset__(const char *file, int line, Arena *arena) {
  arena->current = arena->begin;
  raise_message(LOG_LEVEL_DEBUG, file, line, 
    "Arena %p reset", arena->begin);
}

void arena_free__(const char *file, int line, Arena *arena) {
  raise_message(LOG_LEVEL_DEBUG, file, line,
    "Freeing arena at %p", arena->begin);
  free(arena->begin);
}

char* arena_strdup__(const char *file, int line, Arena *arena, const char *s) {
    char *result;
    if (s) {
        size_t len = strlen(s) + 1;
        result = (char*)arena_alloc__(file, line, arena, len);
        memcpy(result, s, len);
    } else {
        result = NULL;
    }
    return result;
}

char* arena_repstr__(const char *file, int line, Arena *arena,
                             const char *src, size_t start, size_t len, const char *rep) {
  raise_message(LOG_LEVEL_TRACE, file, line, "arena_repstr__(%p, %p, %zu, \"%s\")", src, start, len, rep);
  int src_len = strlen(src);
  int rep_len = strlen(rep);
  int new_len = src_len - (int)len + rep_len;
  char *new_str = (char*)arena_alloc__(file, line, arena, new_len + 1);
  memcpy(new_str, src, start);
  memcpy(new_str + start, rep, rep_len);
  strcpy(new_str + start + rep_len, src + start + len);
  return new_str;
}

void* arena_realloc_copy__(const char *file, int line, Arena *arena,
                           void *old_ptr, size_t old_size, size_t new_size) {
    void *new_ptr = NULL;
    if (old_ptr == NULL) {
        new_ptr = arena_alloc__(file, line, arena, new_size);
    } else if (new_size <= old_size) {
        new_ptr = old_ptr;
    } else {
        new_ptr = arena_alloc_or_null__(file, line, arena, new_size);
        if (new_ptr)
            memcpy(new_ptr, old_ptr, old_size);
    }
    return new_ptr;
}

// ----------
// -- misc --
// ----------

void substr_clone__(const char *file, int line, const char * const src, char *dest, size_t from, size_t len) {
    // Log function entry with all parameters.
    raise_message(LOG_LEVEL_TRACE, file, line,
        "substr_cloning(src=\"%s\", src_ptr=%p, dest=%p, from=%zu, len=%zu)",
        src, src, dest, from, len);

    size_t srclen = strlen(src);
    if (from >= srclen) {
        // Log warning with context when 'from' is out of range.
        raise_message(LOG_LEVEL_WARN, file, line,
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
    raise_message(LOG_LEVEL_TRACE, file, line,
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
static char *json_parse_string__(const char **s_ptr, Arena *arena) {
    const char *s = *s_ptr;
    if (*s != '"') return NULL;
    s++; // skip opening quote
    const char *start = s;
    while (*s && *s != '"') {
        if (*s == '\\') s++; // skip escaped char
        s++;
    }
    if (*s != '"') return NULL;
    size_t len = s - start;
    char *str = arena_alloc(arena, len + 1);
    if (!str) return NULL;
    memcpy(str, start, len);
    str[len] = '\0';
    *s_ptr = s + 1; // skip closing quote
    return str;
}

/* Parse a number using strtod */
static double json_parse_number__(const char **s_ptr) {
    char *end;
    double num = strtod(*s_ptr, &end);
    *s_ptr = end;
    return num;
}

/* Forward declaration */
static Json *json_parse_value__(const char **s, Arena *arena);

/* Parse a JSON array: [ value, value, ... ] */
static Json *json_parse_array__(const char **s, Arena *arena) {
    if (**s != '[') return NULL;
    (*s)++; // skip '['
    *s = skip_whitespace(*s);
    Json *array = arena_alloc(arena, sizeof(Json));
    if (!array) return NULL;
    memset(array, 0, sizeof(Json));
    array->type = JSON_ARRAY;
    Json *last = NULL;
    if (**s == ']') { // empty array
        (*s)++;
        return array;
    }
    while (**s) {
        Json *element = json_parse_value__(s, arena);
        if (!element) return NULL;
        if (!array->child)
            array->child = element;
        else {
            last->next = element;
        }
        last = element;
        *s = skip_whitespace(*s);
        if (**s == ',') {
            (*s)++;
            *s = skip_whitespace(*s);
        } else if (**s == ']') {
            (*s)++;
            break;
        } else {
            return NULL; // error
        }
    }
    return array;
}

/* Parse a JSON object: { "key": value, ... } */
static Json *json_parse_object__(const char **s, Arena *arena) {
    if (**s != '{') return NULL;
    (*s)++; // skip '{'
    *s = skip_whitespace(*s);
    Json *object = arena_alloc(arena, sizeof(Json));
    if (!object) return NULL;
    memset(object, 0, sizeof(Json));
    object->type = JSON_OBJECT;
    Json *last = NULL;
    if (**s == '}') {
        (*s)++;
        return object;
    }
    while (**s) {
        char *key = json_parse_string__(s, arena);
        if (!key) return NULL;
        *s = skip_whitespace(*s);
        if (**s != ':') return NULL;
        (*s)++; // skip ':'
        *s = skip_whitespace(*s);
        Json *value = json_parse_value__(s, arena);
        if (!value) return NULL;
        value->key = key; // assign key to the value
        if (!object->child)
            object->child = value;
        else {
            last->next = value;
        }
        last = value;
        *s = skip_whitespace(*s);
        if (**s == ',') {
            (*s)++;
            *s = skip_whitespace(*s);
        } else if (**s == '}') {
            (*s)++;
            break;
        } else {
            return NULL; // error
        }
    }
    return object;
}

/* Full JSON value parser */
static Json *json_parse_value__(const char **s, Arena *arena) {
    *s = skip_whitespace(*s);
    if (**s == '"') {
        Json *item = arena_alloc(arena, sizeof(Json));
        if (!item) return NULL;
        memset(item, 0, sizeof(Json));
        item->type = JSON_STRING;
        item->JsonValue.string = json_parse_string__(s, arena);
        return item;
    } else if (strncmp(*s, "null", 4) == 0) {
        Json *item = arena_alloc(arena, sizeof(Json));
        if (!item) return NULL;
        memset(item, 0, sizeof(Json));
        item->type = JSON_NULL;
        *s += 4;
        return item;
    } else if (strncmp(*s, "true", 4) == 0) {
        Json *item = arena_alloc(arena, sizeof(Json));
        if (!item) return NULL;
        memset(item, 0, sizeof(Json));
        item->type = JSON_BOOL;
        item->JsonValue.boolean = 1;
        *s += 4;
        return item;
    } else if (strncmp(*s, "false", 5) == 0) {
        Json *item = arena_alloc(arena, sizeof(Json));
        if (!item) return NULL;
        memset(item, 0, sizeof(Json));
        item->type = JSON_BOOL;
        item->JsonValue.boolean = 0;
        *s += 5;
        return item;
    } else if ((**s == '-') || isdigit((unsigned char)**s)) {
        Json *item = arena_alloc(arena, sizeof(Json));
        if (!item) return NULL;
        memset(item, 0, sizeof(Json));
        item->type = JSON_NUMBER;
        item->JsonValue.number = json_parse_number__(s);
        return item;
    } else if (**s == '[') {
        return json_parse_array__(s, arena);
    } else if (**s == '{') {
        return json_parse_object__(s, arena);
    }
    return NULL;
}

Json *json_parse(Arena *arena, const char **s) {
    return json_parse_value__(s, arena);
}

char *json_to_string(Arena *arena, const Json * const item) {
  return json_to_string_with_opts(arena, item, JSON_NORAW);
}

/* Minimal JSON printer with raw output option.
   When raw is non-zero and the item is a JSON_STRING, it is printed without quotes.
*/
char *json_to_string_with_opts(Arena *arena, const Json * const item, JsonRawOpt raw) {
    char *out = arena_alloc(arena, 1024);
    if (!out)
        return NULL;
    char *ptr = out;
    if (item->type == JSON_OBJECT) {
        ptr += sprintf(ptr, "{");
        Json *child = item->child;
        while (child) {
            ptr += sprintf(ptr, "\"%s\":", child->key ? child->key : "");
            char *child_str = json_to_string_with_opts(arena, child, raw);
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
            char *child_str = json_to_string_with_opts(arena, child, raw);
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
    return out;
}

/* Retrieve an object item by key (case-sensitive) */
Json *json_get_object_item(const Json * const object, const char * const key) {
    raise_debug("json get object item for %s", key);
    if (!object || object->type != JSON_OBJECT)
        return NULL;
    Json *child = object->child;
    while (child) {
	raise_debug("child->key: %s, key: %s", child->key, key);
        if (child->key && strcmp(child->key, key) == 0)
            return child;
        child = child->next;
    }
    return NULL;
}

//bool json_is_string(const Json * const item) {
//  if (item == NULL) {
//    return false;
//  }
//  return item->type == JSON_STRING;
//}
