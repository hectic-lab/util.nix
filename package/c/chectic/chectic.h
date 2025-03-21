#ifndef EPRINTF_H
#define EPRINTF_H

#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdarg.h>
#include <time.h>
#include <string.h>

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
static ColorMode color_mode = COLOR_MODE_AUTO;

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

#define raise_debug(fmt, ...)     log_message(LOG_LEVEL_DEBUG,     __FILE__, __LINE__, fmt, ##__VA_ARGS__)
#define raise_log(fmt, ...)       log_message(LOG_LEVEL_LOG,       __FILE__, __LINE__, fmt, ##__VA_ARGS__)
#define raise_info(fmt, ...)      log_message(LOG_LEVEL_INFO,      __FILE__, __LINE__, fmt, ##__VA_ARGS__)
#define raise_notice(fmt, ...)    log_message(LOG_LEVEL_NOTICE,    __FILE__, __LINE__, fmt, ##__VA_ARGS__)
#define raise_warn(fmt, ...)      log_message(LOG_LEVEL_WARN,      __FILE__, __LINE__, fmt, ##__VA_ARGS__)
#define raise_exception(fmt, ...) log_message(LOG_LEVEL_EXCEPTION, __FILE__, __LINE__, fmt, ##__VA_ARGS__)

#endif // EPRINTF_H

// -----------
// -- arena --
// -----------

#define ARENA_DEFAULT_SIZE 1024

typedef struct {
  void *begin;
  void *current;
  size_t capacity; 
} Arena;

// NOTE(yukkop): This macro is used to define procedures so that `__LINE__` and `__FILE__`
// in `raise_debug` reflect the location where the macro is called, not where it's defined.
#define arena_alloc_or_null(arena, size) __extension__ ({                          \
    void *mem__ = NULL;                                                            \
    if ((arena)->begin == 0) {                                                     \
        *(arena) = arena_init(ARENA_DEFAULT_SIZE);                                 \
    }                                                                              \
    size_t current__ = (size_t)(arena)->current - (size_t)(arena)->begin;          \
    if ((arena)->capacity <= current__ || (arena)->capacity - current__ < (size)) {\
        raise_debug("Arena from %d with capacity %d allocated on %d cannot be allocated on %d", \
                    (arena)->begin, (arena)->capacity,                             \
	            (arena)->current - (arena)->begin, (size));                    \
    } else {                                                                       \
        raise_debug("Arena from %d with capacity %d allocated on %d will allocate on %d", \
                    (arena)->begin, (arena)->capacity,                             \
                    (arena)->begin, (arena)->capacity, (size));                    \
        mem__ = (arena)->current;                                                  \
        (arena)->current = (char*)(arena)->current + (size);                       \
    }                                                                              \
    mem__;                                                                         \
})

Arena arena_init(size_t size);

void arena_reset(Arena *arena);

void arena_free(Arena *arena);

#define arena_alloc(arena, size) __extension__ ({        \
    void *mem__ = arena_alloc_or_null((arena), (size));  \
    if (!mem__) {                                        \
        raise_exception("Arena out of memory");          \
        exit(1);                                         \
    }                                                    \
    mem__;                                               \
})


// TODO: mmap
// TODO: dynamic array style
// void *arena_realloc(Arena *arena, size_t size) {
//   void *mem = arena_alloc_or_null(arena, size);
//   if (!mem) {
//     raise_exception("Arena out of memory");
//     exit(1);
//   }
//   return mem;
// }
