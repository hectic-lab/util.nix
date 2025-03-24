#ifndef EPRINTF_HECTIC
#define EPRINTF_HECTIC

// NOTE(yukkop): definitions and features from the POSIX.1-2008 standard
#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdarg.h>
#include <time.h>
#include <string.h>
#include <ctype.h>
#include <stdbool.h>

// -------------
// -- Helpers --
// -------------

// Helper macros for argument counting
// NOTE(yukkop): this ugly macroses for avoid all posible warnings
#define PP_CAT(a, b) a##b

// ------------
// -- Colors --
// ------------

// Color mode enumeration
typedef enum {
  COLOR_MODE_AUTO, 
  COLOR_MODE_FORCE,
  COLOR_MODE_DISABLE
} ColorMode;

// Static color mode variable
static ColorMode color_mode __attribute__((unused)) = COLOR_MODE_AUTO;

// Function to set color mode
void set_output_color_mode(ColorMode mode);

// Macros for detecting terminal and color usage
#define IS_TERMINAL() (isatty(fileno(stderr)))
#define USE_COLOR() ((color_mode == COLOR_MODE_FORCE) || (color_mode == COLOR_MODE_AUTO && IS_TERMINAL()))

#define COLOR_RED (USE_COLOR() ? "\033[1;31m" : "")
#define COLOR_RESET (USE_COLOR() ? "\033[0m" : "")

// ------------ 
// -- Errors --
// ------------ 

// Define color macros based on output type
//#define ERROR_PREFIX PP_CAT(COLOR_RED, "Error: ")
//#define ERROR_SUFFIX PP_CAT(COLOR_RESET, "\n")
#define ERROR_PREFIX (USE_COLOR() ? "\033[1;31mError: " : "Error: ")
#define ERROR_SUFFIX (USE_COLOR() ? "\033[0m\n" : "\n")

// eprintf handling 1 or more arguments
#define eprintf(fmt, ...)     "%s" fmt "%s", ERROR_PREFIX, ##__VA_ARGS__, ERROR_SUFFIX

#define todo fprintf(stderr, "%sNot implimented yet%s", COLOR_RED, COLOR_RESET);exit(1)

// ------------
// -- Logger --
// ------------

typedef enum {
  LOG_LEVEL_TRACE,
  LOG_LEVEL_DEBUG,
  LOG_LEVEL_LOG,
  LOG_LEVEL_INFO,
  LOG_LEVEL_NOTICE,
  LOG_LEVEL_WARN,
  LOG_LEVEL_EXCEPTION
} LogLevel;

void logger_level_reset();

void logger_level(LogLevel level);

LogLevel log_level_from_string(const char *level_str);

char* log_message(LogLevel level, char *file, int line, const char *format, ...);

#define raise_trace_with_opt(file, line, fmt, ...)     log_message(LOG_LEVEL_TRACE, file, line, fmt, ##__VA_ARGS__)
#define raise_debug_with_opt(file, line, fmt, ...)     log_message(LOG_LEVEL_DEBUG, file, line, fmt, ##__VA_ARGS__)
#define raise_log_with_opt(file, line, fmt, ...)       log_message(LOG_LEVEL_LOG, file, line, fmt, ##__VA_ARGS__)
#define raise_info_with_opt(file, line, fmt, ...)      log_message(LOG_LEVEL_INFO, file, line, fmt, ##__VA_ARGS__)
#define raise_notice_with_opt(file, line, fmt, ...)    log_message(LOG_LEVEL_NOTICE, file, line, fmt, ##__VA_ARGS__)
#define raise_warn_with_opt(file, line, fmt, ...)      log_message(LOG_LEVEL_WARN, file, line, fmt, ##__VA_ARGS__)
#define raise_exception_with_opt(file, line, fmt, ...) log_message(LOG_LEVEL_EXCEPTION, file, line, fmt, ##__VA_ARGS__)

#define raise_trace(fmt, ...)     log_message(LOG_LEVEL_TRACE,     __FILE__, __LINE__, fmt, ##__VA_ARGS__)
#define raise_debug(fmt, ...)     log_message(LOG_LEVEL_DEBUG,     __FILE__, __LINE__, fmt, ##__VA_ARGS__)
#define raise_log(fmt, ...)       log_message(LOG_LEVEL_LOG,       __FILE__, __LINE__, fmt, ##__VA_ARGS__)
#define raise_info(fmt, ...)      log_message(LOG_LEVEL_INFO,      __FILE__, __LINE__, fmt, ##__VA_ARGS__)
#define raise_notice(fmt, ...)    log_message(LOG_LEVEL_NOTICE,    __FILE__, __LINE__, fmt, ##__VA_ARGS__)
#define raise_warn(fmt, ...)      log_message(LOG_LEVEL_WARN,      __FILE__, __LINE__, fmt, ##__VA_ARGS__)
#define raise_exception(fmt, ...) log_message(LOG_LEVEL_EXCEPTION, __FILE__, __LINE__, fmt, ##__VA_ARGS__)

// -----------
// -- arena --
// -----------

#define ARENA_DEFAULT_SIZE MEM_MiB

typedef struct {
  void *begin;
  void *current;
  size_t capacity; 
} Arena;

// NOTE(yukkop): This macro is used to define procedures so that `__LINE__` and `__FILE__`
// in `raise_debug` reflect the location where the macro is called, not where it's defined.
#define arena_alloc_or_null(arena, size) __extension__ ({                          \
    raise_trace("arena_alloc_or_null(%p, %zu)", (arena), (size));                       \
    void *mem__ = NULL;                                                            \
    if ((arena)->begin == 0) {                                                     \
        *(arena) = arena_init(ARENA_DEFAULT_SIZE);                                 \
    }                                                                              \
    size_t current__ = (size_t)(arena)->current - (size_t)(arena)->begin;          \
    if ((arena)->capacity <= current__ || (arena)->capacity - current__ < (size)) {\
        raise_debug("Arena %p (capacity %zu) used %zu cannot allocate %zu bytes",  \
                  (arena)->begin, (arena)->capacity, current__, (size));           \
    } else {                                                                       \
        raise_debug("Arena %p (capacity %zu) used %zu will allocate %zu bytes",    \
                  (arena)->begin, (arena)->capacity, current__, (size));           \
        mem__ = (arena)->current;                                                  \
        (arena)->current = (char*)(arena)->current + (size);                       \
    }                                                                              \
    raise_debug("Allocated at %p", mem__);                                         \
    mem__;                                                                         \
})

#define arena_init(size) __extension__ ({     \
    Arena arena__;                            \
    arena__.begin = malloc(size);             \
    memset(arena__.begin, 0, size);           \
    arena__.current = arena__.begin;          \
    arena__.capacity = size;                  \
    raise_debug("Initialized arena at %p with capacity %zu", arena__.begin, size);   \
    arena__;                                  \
})

#define arena_reset(arena) __extension__ ({        \
    (arena)->current = (arena)->begin;             \
    raise_debug("Arena %p reset", (arena)->begin); \
})

#define arena_free(arena) __extension__ ({              \
    raise_debug("Freeing arena at %p", (arena)->begin); \
    free((arena)->begin);                               \
})

#define arena_alloc(arena, size) __extension__ ({           \
    void *mem__ = arena_alloc_or_null((arena), (size));     \
    if (!mem__) {                                           \
        raise_debug("Arena out of memory when trying to allocate %zu bytes", (size)); \
        raise_exception("Arena out of memory");             \
        exit(1);                                            \
    }                                                       \
    mem__;                                                  \
})

#define arena_strdup(arena, s) __extension__ ({         \
    const char *s__ = (s);                              \
    char *result__;                                     \
    if (s__) {                                          \
        size_t len__ = strlen(s__) + 1;                 \
        result__ = (char *)arena_alloc(arena, len__);   \
        memcpy(result__, s__, len__);                   \
    } else {                                            \
        result__ = NULL;                                \
    }                                                   \
    result__;                                           \
})

#define arena_repstr(arena, src, start, len, rep) __extension__ ({        \
    const char *src__ = (src);                                            \
    const char *rep__ = (rep);                                            \
    size_t start__ = (start);                                             \
    size_t len__ = (len);                                                 \
    int src_len__ = strlen(src__);                                        \
    int rep_len__ = strlen(rep__);                                        \
    int new_len__ = src_len__ - len__ + 1 + rep_len__;                    \
    char *new_str__ = (char *)arena_alloc(arena, new_len__ + 1);          \
    memcpy(new_str__, src__, start__);                                    \
    memcpy(new_str__ + start__, rep__, rep_len__);                        \
    strcpy(new_str__ + start__ + rep_len__, src__ + start__ + len__ + 1); \
    new_str__;                                                            \
})

#define arena_realloc_copy(arena, old_ptr, old_size, new_size) __extension__ ({      \
    void *old__ = (old_ptr);                                                         \
    size_t old_size__ = (old_size);                                                  \
    size_t new_size__ = (new_size);                                                  \
    void *new__ = NULL;                                                              \
    if (old__ == NULL) {                                                             \
        new__ = arena_alloc((arena), new_size__);                                    \
    } else if (new_size__ <= old_size__) {                                           \
        new__ = old__;                                                               \
    } else {                                                                         \
        new__ = arena_alloc_or_null((arena), new_size__);                            \
        if (new__) memcpy(new__, old__, old_size__);                                 \
    }                                                                                \
    new__;                                                                           \
})

// ----------
// -- misc --
// ----------

#define MEM_b   1
#define MEM_KiB 1024
#define MEM_MiB (MEM_KiB * 1024)
#define MEM_GiB (MEM_MiB * 1024)
#define MEM_TiB (MEM_TiB * 1024)
#define MEM_PiB (MEM_TiB * 1024)
#define MEM_EiB (MEM_PiB * 1024)
#define MEM_ZiB (MEM_EiB * 1024)
#define MEM_YiB (MEM_ZiB * 1024)
#define MEM_RiB (MEM_YiB * 1024)
#define MEM_QiB (MEM_RiB * 1024)

// ----------
// -- Json --
// ----------

typedef enum {
    JSON_NORAW = 0,
    JSON_RAW = 1,
} JsonRawOpt;

typedef enum {
    JSON_NULL,
    JSON_BOOL,
    JSON_NUMBER,
    JSON_STRING,
    JSON_ARRAY,
    JSON_OBJECT,
} JsonType;

/* Full JSON structure */
typedef struct Json {
    struct Json *next;   /* Next sibling */
    struct Json *child;  /* Child element (for arrays/objects) */
    JsonType type;
    char *key;           /* Key if item is in an object */
    union {
        double number;
        char *string;
        int boolean;
    } JsonValue;
} Json;

Json *json_parse(Arena *arena, const char **s);

char *json_to_string(Arena *arena, const Json * const item);

char *json_to_string_with_opts(Arena *arena, const Json * const item, JsonRawOpt raw);

/* Retrieve an object item by key (case-sensitive) */
Json *json_get_object_item(Json *object, const char *key);

#endif // EPRINTF_H
