#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <time.h>
#include "macros.h"

typedef enum {
  LOG_LEVEL_DEBUG,
  LOG_LEVEL_LOG,
  LOG_LEVEL_INFO,
  LOG_LEVEL_NOTICE,
  LOG_LEVEL_WARN,
  LOG_LEVEL_EXCEPTION
} LogLevel;

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

void init_logger(void) {
    current_log_level = log_level_from_string(getenv("LOG_LEVEL"));
}

void log_message(LogLevel level, int line, const char *format, ...) {
    if (level < current_log_level) {
        return;
    }

    time_t now = time(NULL);
    struct tm tm_info;
    localtime_r(&now, &tm_info);
    char timeStr[20];
    strftime(timeStr, sizeof(timeStr), "%Y-%m-%d %H:%M:%S", &tm_info);

    fprintf(stderr, "%s %d %s: ", timeStr, line, log_level_to_string(level));

    va_list args;
    va_start(args, format);
    vfprintf(stderr, format, args);
    va_end(args);

    fprintf(stderr, "\n");
}

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
