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

#define COLOR_RED "\033[1;31m"
#define COLOR_GREEN "\033[1;32m"
#define COLOR_YELLOW "\033[1;33m"
#define COLOR_BLUE "\033[1;34m"
#define COLOR_MAGENTA "\033[1;35m"
#define COLOR_CYAN "\033[1;36m"
#define COLOR_WHITE "\033[1;37m"
#define COLOR_RESET "\033[0m"

#define OPTIONAL_COLOR(color) (USE_COLOR() ? color : "")

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
  LOG_LEVEL_ZALUPA,
  LOG_LEVEL_DEBUG,
  LOG_LEVEL_LOG,
  LOG_LEVEL_INFO,
  LOG_LEVEL_NOTICE,
  LOG_LEVEL_WARN,
  LOG_LEVEL_EXCEPTION,
} LogLevel;

void logger_level_reset();

void init_logger(void);

void logger_level(LogLevel level);

LogLevel log_level_from_string(const char *level_str);

char* raise_message(LogLevel level, const char *file, const char *func, int line, const char *format, ...);

#ifndef PRECOMPILED_LOG_LEVEL
#define PRECOMPILED_LOG_LEVEL LOG_LEVEL_TRACE  // default level
#endif

#if PRECOMPILED_LOG_LEVEL > LOG_LEVEL_TRACE
#define raise_trace(...) ((void)0)  // log removed at compile time
#else
#define raise_trace(...) raise_message(LOG_LEVEL_TRACE, __FILE__, __func__, __LINE__, ##__VA_ARGS__)
#endif

#if PRECOMPILED_LOG_LEVEL > LOG_LEVEL_DEBUG
#define raise_debug(...) ((void)0)
#else
#define raise_debug(...) raise_message(LOG_LEVEL_DEBUG, __FILE__, __func__, __LINE__, ##__VA_ARGS__)
#endif

#if PRECOMPILED_LOG_LEVEL > LOG_LEVEL_LOG
#define raise_log(...) ((void)0)
#else
#define raise_log(...) raise_message(LOG_LEVEL_LOG, __FILE__, __func__, __LINE__, ##__VA_ARGS__)
#endif

#if PRECOMPILED_LOG_LEVEL > LOG_LEVEL_INFO
#define raise_info(...) ((void)0)
#else
#define raise_info(...) raise_message(LOG_LEVEL_INFO, __FILE__, __func__, __LINE__, ##__VA_ARGS__)
#endif

#if PRECOMPILED_LOG_LEVEL > LOG_LEVEL_NOTICE
#define raise_notice(...) ((void)0)
#else
#define raise_notice(...) raise_message(LOG_LEVEL_NOTICE, __FILE__, __func__, __LINE__, ##__VA_ARGS__)
#endif

#if PRECOMPILED_LOG_LEVEL > LOG_LEVEL_WARN
#define raise_warn(...) ((void)0)
#else
#define raise_warn(...) raise_message(LOG_LEVEL_WARN, __FILE__, __func__, __LINE__, ##__VA_ARGS__)
#endif

#if PRECOMPILED_LOG_LEVEL > LOG_LEVEL_EXCEPTION
#define raise_exception(...) ((void)0)
#else
#define raise_exception(...) raise_message(LOG_LEVEL_EXCEPTION, __FILE__, __func__, __LINE__, ##__VA_ARGS__)
#endif

#if PRECOMPILED_LOG_LEVEL > LOG_LEVEL_ZALUPA
#define raise_zalupa(...) ((void)0)
#else
#define raise_zalupa(...) raise_message(LOG_LEVEL_ZALUPA, __FILE__, __func__, __LINE__, ##__VA_ARGS__)
#endif

// -----------
// -- arena --
// -----------

#define ARENA_DEFAULT_SIZE MEM_MiB

typedef struct {
  void *begin;
  void *current;
  size_t capacity; 
} Arena;

Arena arena_init__(const char *file, const char *func, int line, size_t size);

void* arena_alloc_or_null__(const char *file, const char *func, int line, Arena *arena, size_t size);

void* arena_alloc__(const char *file, const char *func, int line, Arena *arena, size_t size);

void arena_reset__(const char *file, const char *func, int line, Arena *arena);

void arena_free__(const char *file, const char *func, int line, Arena *arena);

char* arena_strdup__(const char *file, const char *func, int line, Arena *arena, const char *s);

char* arena_repstr__(const char *file, const char *func, int line, Arena *arena,
                             const char *src, size_t start, size_t len, const char *rep);

void* arena_realloc_copy__(const char *file, const char *func, int line, Arena *arena,
                           void *old_ptr, size_t old_size, size_t new_size);

// NOTE(yukkop): This macro is used to define procedures so that `__LINE__` and `__FILE__`
// in `raise_debug` reflect the location where the macro is called, not where it's defined.
#define arena_alloc_or_null(arena, size) \
        arena_alloc_or_null__(__FILE__, __func__, __LINE__, arena, size)

#define arena_init(size) \
        arena_init__(__FILE__, __func__, __LINE__, size)

#define arena_reset(arena) \
        arena_reset__(__FILE__, __func__, __LINE__, arena)

#define arena_free(arena) \
        arena_free__(__FILE__, __func__, __LINE__, arena)

#define arena_alloc(arena, size) \
	arena_alloc__(__FILE__, __func__, __LINE__, arena, size)

#define arena_strdup(arena, s) \
	arena_strdup__(__FILE__, __func__, __LINE__, arena, s)

#define arena_repstr(arena, src, start, len, rep) \
	arena_repstr__(__FILE__, __func__, __LINE__, arena, src, start, len, rep)

#define arena_realloc_copy(arena, old_ptr, old_size, new_size) \
	arena_realloc_copy__(__FILE__, __func__, __LINE__, arena, old_ptr, old_size, new_size)

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

void substr_clone__(const char *file, const char *func, int line, const char * const src, char *dest, size_t from, size_t len);
#define substr_clone(src, dest, from, len) substr_clone__(__FILE__, __func__, __LINE__, src, dest, from, len)

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

#define json_parse(arena, s) json_parse__(__FILE__, __func__, __LINE__, arena, s)
Json *json_parse__(const char* file, const char* func, int line, Arena *arena, const char **s);

#define json_to_string(arena, item) json_to_string__(__FILE__, __func__, __LINE__, arena, item)
char *json_to_string__(const char* file, const char* func, int line, Arena *arena, const Json * const item);

#define json_to_string_with_opts(arena, item, raw) json_to_string_with_opts__(__FILE__, __func__, __LINE__, arena, item, raw)
char *json_to_string_with_opts__(const char* file, const char* func, int line, Arena *arena, const Json * const item, JsonRawOpt raw);

/* Retrieve an object item by key (case-sensitive) */
#define json_get_object_item(object, key) json_get_object_item__(__FILE__, __func__, __LINE__, object, key)
Json *json_get_object_item__(const char* file, const char* func, int line, const Json * const object, const char * const key);

// -----------
// -- Slice --
// -----------

typedef struct {
    void *data;
    size_t len;
    size_t isize;
} Slice;

// Usage:
// printf("Content: %.*s\n", SLICE_ARGS(slice, char));
// printf("Content: %d\n", SLICE_ARGS(slice, int));
#define SLICE_ARGS(slice, type) ((int)((slice).len / sizeof(type))), ((type*)((slice).data))

Slice slice_create__(const char *file, const char *func, int line, size_t isize, void *array, size_t array_len, size_t start, size_t len);

Slice slice_subslice__(const char *file, const char *func, int line, Slice s, size_t start, size_t len);

int* arena_slice_copy__(const char *file, const char *func, int line, Arena *arena, Slice s);

#define slice_create(type, array, array_len, start, len) \
  slice_create__(__FILE__, __func__, __LINE__, sizeof(type), array, array_len, start, len)

#define slice_subslice(s, start, len) \
  slice_subslice__(__FILE__, __func__, __LINE__, s, start, len)

#define arena_slice_copy(arena, s) \
  arena_slice_copy__(__FILE__, __func__, __LINE__, arena, s)

#define SLICE_TO_STRING(type, slice, fmt) __extension__ ({          \
    size_t count = (slice).len / (slice).isize;                     \
    size_t bufsize = count * 32 + 1;                                \
    char *buf = malloc(bufsize);                                    \
    if (buf) {                                                      \
        buf[0] = '\0';                                              \
        for (size_t i = 0; i < count; i++) {                        \
            char temp[32];                                          \
            snprintf(temp, sizeof(temp), fmt " ",                   \
                     ((type *)((slice).data))[i]);                  \
            strncat(buf, temp, bufsize - strlen(buf) - 1);          \
        }                                                           \
    }                                                               \
    buf;                                                            \
})

// Utility functions for debug output of Slice and Json structures
char* slice_to_debug_str(Arena *arena, Slice slice);
char* json_to_debug_str(Arena *arena, Json json);

#define DEBUGSTR(arena, type, value) DEBUGSTR_##type(arena, value)

#define DEBUGSTR_Slice(arena, value) slice_to_debug_str(arena, value)
#define DEBUGSTR_Json(arena, value)  json_to_debug_str(arena, value)

#endif // EPRINTF_H