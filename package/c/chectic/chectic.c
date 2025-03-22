#include "chectic.h"

void set_output_color_mode(ColorMode mode) {
    color_mode = mode;
}

// ------------
// -- Logger --
// ------------

const char* log_level_to_string(LogLevel level) {
    switch (level) {
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
    if (strcmp(level_str, "DEBUG") == 0)
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

char* log_message(LogLevel level, char *file, int line, const char *format, ...) {
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
// -- utils --
// -----------

void substr(const char *src, char *dest, size_t start, size_t len) {
    raise_debug("substring %s from %zu to %zu", src, start, len);
    size_t srclen = strlen(src);
    if (start >= srclen) {
        dest[0] = '\0';
        return;
    }
    if (start + len > srclen)
        len = srclen - start;
    strncpy(dest, src + start, len);
    dest[len] = '\0';
}

// ----------
// -- Json --
// ----------

/* Utility: Skip whitespace */
static const char *json_skip_whitespace(const char *s) {
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
    *s = json_skip_whitespace(*s);
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
        *s = json_skip_whitespace(*s);
        if (**s == ',') {
            (*s)++;
            *s = json_skip_whitespace(*s);
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
    *s = json_skip_whitespace(*s);
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
        *s = json_skip_whitespace(*s);
        if (**s != ':') return NULL;
        (*s)++; // skip ':'
        *s = json_skip_whitespace(*s);
        Json *value = json_parse_value__(s, arena);
        if (!value) return NULL;
        value->key = key; // assign key to the value
        if (!object->child)
            object->child = value;
        else {
            last->next = value;
        }
        last = value;
        *s = json_skip_whitespace(*s);
        if (**s == ',') {
            (*s)++;
            *s = json_skip_whitespace(*s);
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
    *s = json_skip_whitespace(*s);
    if (**s == '"') {
        Json *item = arena_alloc(arena, sizeof(Json));
        if (!item) return NULL;
        memset(item, 0, sizeof(Json));
        item->type = JSON_STRING;
        item->string = json_parse_string__(s, arena);
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
        item->boolean = 1;
        *s += 4;
        return item;
    } else if (strncmp(*s, "false", 5) == 0) {
        Json *item = arena_alloc(arena, sizeof(Json));
        if (!item) return NULL;
        memset(item, 0, sizeof(Json));
        item->type = JSON_BOOL;
        item->boolean = 0;
        *s += 5;
        return item;
    } else if ((**s == '-') || isdigit((unsigned char)**s)) {
        Json *item = arena_alloc(arena, sizeof(Json));
        if (!item) return NULL;
        memset(item, 0, sizeof(Json));
        item->type = JSON_NUMBER;
        item->number = json_parse_number__(s);
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

/* Minimal JSON printer.
   For simplicity, a fixed-size buffer is used.
   In production you’d dynamically size or use the arena. */
char *json_print(Arena *arena, Json *item) {
    char *out = arena_alloc(arena, 1024);
    if (!out) return NULL;
    char *ptr = out;
    if (item->type == JSON_OBJECT) {
        ptr += sprintf(ptr, "{");
        Json *child = item->child;
        while (child) {
            ptr += sprintf(ptr, "\"%s\":", child->key ? child->key : "");
            char *child_str = json_print(arena, child);
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
            char *child_str = json_print(arena, child);
            ptr += sprintf(ptr, "%s", child_str);
            if (child->next)
                ptr += sprintf(ptr, ",");
            child = child->next;
        }
        sprintf(ptr, "]");
    } else if (item->type == JSON_STRING) {
        sprintf(out, "\"%s\"", item->string);
    } else if (item->type == JSON_NUMBER) {
        sprintf(out, "%g", item->number);
    } else if (item->type == JSON_BOOL) {
        sprintf(out, item->boolean ? "true" : "false");
    } else if (item->type == JSON_NULL) {
        sprintf(out, "null");
    }
    return out;
}

/* Retrieve an object item by key (case-sensitive) */
Json *json_get_object_item(Json *object, const char *key) {
    if (!object || object->type != JSON_OBJECT)
        return NULL;
    Json *child = object->child;
    while (child) {
        if (child->key && strcmp(child->key, key) == 0)
            return child;
        child = child->next;
    }
    return NULL;
}
