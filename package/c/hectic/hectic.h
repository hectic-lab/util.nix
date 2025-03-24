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

void init_logger(void);

void logger_level(LogLevel level);

LogLevel log_level_from_string(const char *level_str);

char* raise_message(LogLevel level, const char *file, int line, const char *format, ...);

#ifndef PRECOMPILED_LOG_LEVEL
#define PRECOMPILED_LOG_LEVEL LOG_LEVEL_TRACE  // default level
#endif

#if PRECOMPILED_LOG_LEVEL > LOG_LEVEL_TRACE
#define raise_trace(...) ((void)0)  // log removed at compile time
#else
#define raise_trace(...) raise_message(LOG_LEVEL_TRACE, __FILE__, __LINE__, ##__VA_ARGS__)
#endif

#if PRECOMPILED_LOG_LEVEL > LOG_LEVEL_DEBUG
#define raise_debug(...) ((void)0)
#else
#define raise_debug(...) raise_message(LOG_LEVEL_DEBUG, __FILE__, __LINE__, ##__VA_ARGS__)
#endif

#if PRECOMPILED_LOG_LEVEL > LOG_LEVEL_LOG
#define raise_log(...) ((void)0)
#else
#define raise_log(...) raise_message(LOG_LEVEL_LOG, __FILE__, __LINE__, ##__VA_ARGS__)
#endif

#if PRECOMPILED_LOG_LEVEL > LOG_LEVEL_INFO
#define raise_info(...) ((void)0)
#else
#define raise_info(...) raise_message(LOG_LEVEL_INFO, __FILE__, __LINE__, ##__VA_ARGS__)
#endif

#if PRECOMPILED_LOG_LEVEL > LOG_LEVEL_NOTICE
#define raise_notice(...) ((void)0)
#else
#define raise_notice(...) raise_message(LOG_LEVEL_NOTICE, __FILE__, __LINE__, ##__VA_ARGS__)
#endif

#if PRECOMPILED_LOG_LEVEL > LOG_LEVEL_WARN
#define raise_warn(...) ((void)0)
#else
#define raise_warn(...) raise_message(LOG_LEVEL_WARN, __FILE__, __LINE__, ##__VA_ARGS__)
#endif

#if PRECOMPILED_LOG_LEVEL > LOG_LEVEL_EXCEPTION
#define raise_exception(...) ((void)0)
#else
#define raise_exception(...) raise_message(LOG_LEVEL_EXCEPTION, __FILE__, __LINE__, ##__VA_ARGS__)
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

Arena arena_init__(const char *file, int line, size_t size);

void* arena_alloc_or_null__(const char *file, int line, Arena *arena, size_t size);

void* arena_alloc__(const char *file, int line, Arena *arena, size_t size);

void arena_reset__(const char *file, int line, Arena *arena);

void arena_free__(const char *file, int line, Arena *arena);

char* arena_strdup__(const char *file, int line, Arena *arena, const char *s);

char* arena_repstr__(const char *file, int line, Arena *arena,
                             const char *src, size_t start, size_t len, const char *rep);

void* arena_realloc_copy__(const char *file, int line, Arena *arena,
                           void *old_ptr, size_t old_size, size_t new_size);

// NOTE(yukkop): This macro is used to define procedures so that `__LINE__` and `__FILE__`
// in `raise_debug` reflect the location where the macro is called, not where it's defined.
#define arena_alloc_or_null(arena, size) \
        arena_alloc_or_null__(__FILE__, __LINE__, arena, size)

#define arena_init(size) \
        arena_init__(__FILE__, __LINE__, size)

#define arena_reset(arena) \
        arena_reset__(__FILE__, __LINE__, arena)

#define arena_free(arena) \
        arena_free__(__FILE__, __LINE__, arena)

#define arena_alloc(arena, size) \
	arena_alloc__(__FILE__, __LINE__, arena, size)

#define arena_strdup(arena, s) \
	arena_strdup__(__FILE__, __LINE__, arena, s)

#define arena_repstr(arena, src, start, len, rep) \
	arena_repstr__(__FILE__, __LINE__, arena, src, start, len, rep)

#define arena_realloc_copy(arena, old_ptr, old_size, new_size) \
	arena_realloc_copy__(__FILE__, __LINE__, arena, old_ptr, old_size, new_size)

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

void substr_clone__(const char *file, int line, const char * const src, char *dest, size_t from, size_t len);
#define substr_clone(src, dest, from, len) substr_clone__(__FILE__, __LINE__, src, dest, from, len)

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
Json *json_get_object_item(const Json * const object, const char * const key);

#endif // EPRINTF_H
