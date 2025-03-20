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
#define PP_CAT(a, b) PP_CAT_I(a, b)
#define PP_CAT_I(a, b) a##b

#define PP_NARG(...) PP_NARG_(__VA_ARGS__, PP_RSEQ_N())
#define PP_NARG_(...) PP_ARG_N(__VA_ARGS__)
#define PP_ARG_N(_1,_2,_3,_4,_5,_6,_7,_8,_9,N,...) N
#define PP_RSEQ_N() 9,8,7,6,5,4,3,2,1,0

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
//#define ERROR_PREFIX PP_CAT_I(COLOR_RED, "Error: ")
//#define ERROR_SUFFIX PP_CAT_I(COLOR_RESET, "\n")
#define ERROR_PREFIX (USE_COLOR() ? "\033[1;31mError: " : "Error: ")
#define ERROR_SUFFIX (USE_COLOR() ? "\033[0m\n" : "\n")

// eprintf handling 1 or more arguments
#define eprintf_1(fmt) \
    fprintf(stderr, "%s" fmt "%s", ERROR_PREFIX, ERROR_SUFFIX)

#define eprintf_2(fmt, ...) \
    fprintf(stderr, "%s" fmt "%s", ERROR_PREFIX, __VA_ARGS__, ERROR_SUFFIX)

#define eprintf(...) \
    PP_CAT(eprintf_, PP_NARG(__VA_ARGS__))(__VA_ARGS__)

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

void logger_level(LogLevel level);

LogLevel log_level_from_string(const char *level_str);

char* log_message(LogLevel level, int line, const char *format, ...);

// DEBUG level
#define raise_debug_1(fmt) \
    log_message(LOG_LEVEL_DEBUG, __LINE__, fmt)
#define raise_debug_2(fmt, ...) \
    log_message(LOG_LEVEL_DEBUG, __LINE__, fmt, __VA_ARGS__)
#define raise_debug(...) \
    PP_CAT(raise_debug_, PP_NARG(__VA_ARGS__))(__VA_ARGS__)

// LOG level
#define raise_log_1(fmt) \
    log_message(LOG_LEVEL_LOG, __LINE__, fmt)
#define raise_log_2(fmt, ...) \
    log_message(LOG_LEVEL_LOG, __LINE__, fmt, __VA_ARGS__)
#define raise_log(...) \
    PP_CAT(raise_log_, PP_NARG(__VA_ARGS__))(__VA_ARGS__)

// INFO level
#define raise_info_1(fmt) \
    log_message(LOG_LEVEL_INFO, __LINE__, fmt)
#define raise_info_2(fmt, ...) \
    log_message(LOG_LEVEL_INFO, __LINE__, fmt, __VA_ARGS__)
#define raise_info(...) \
    PP_CAT(raise_info_, PP_NARG(__VA_ARGS__))(__VA_ARGS__)

// NOTICE level
#define raise_notice_1(fmt) \
    log_message(LOG_LEVEL_NOTICE, __LINE__, fmt)
#define raise_notice_2(fmt, ...) \
    log_message(LOG_LEVEL_NOTICE, __LINE__, fmt, __VA_ARGS__)
#define raise_notice(...) \
    PP_CAT(raise_notice_, PP_NARG(__VA_ARGS__))(__VA_ARGS__)

// WARN level
#define raise_warn_1(fmt) \
    log_message(LOG_LEVEL_WARN, __LINE__, fmt)
#define raise_warn_2(fmt, ...) \
    log_message(LOG_LEVEL_WARN, __LINE__, fmt, __VA_ARGS__)
#define raise_warn(...) \
    PP_CAT(raise_warn_, PP_NARG(__VA_ARGS__))(__VA_ARGS__)

// EXCEPTION level
#define raise_exception_1(fmt) \
    log_message(LOG_LEVEL_EXCEPTION, __LINE__, fmt)
#define raise_exception_2(fmt, ...) \
    log_message(LOG_LEVEL_EXCEPTION, __LINE__, fmt, __VA_ARGS__)
#define raise_exception(...) \
    PP_CAT(raise_exception_, PP_NARG(__VA_ARGS__))(__VA_ARGS__)

#endif // EPRINTF_H
