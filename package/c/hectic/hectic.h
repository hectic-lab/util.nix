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

/* 
 * Hectic Library - A C utility library
 * 
 * This library includes several components:
 * - Logging system with multiple severity levels
 * - Memory management with arenas
 * - JSON parsing and serialization
 * - Template engine
 * 
 * Logging System Usage:
 * - Set global log level: logger_level(LOG_LEVEL_DEBUG);
 * - Log messages: raise_debug("Debug message with %s", value);
 * 
 * File Logging:
 * - Set log file: logger_set_file("/path/to/logfile.log");
 * - Select output mode: logger_set_output_mode(LOG_OUTPUT_BOTH);
 * 
 * Environment Variables:
 * - LOG_LEVEL: Set global log level ("TRACE", "DEBUG", etc.)
 * - LOG_FILE: Set log file path
 * - LOG_OUTPUT_MODE: Set output mode ("STDERR_ONLY", "FILE_ONLY", "BOTH")
 */

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

// External color mode variable declaration
extern ColorMode color_mode;
extern ColorMode debug_color_mode;

const char* color_mode_to_string(ColorMode mode);

// Function to set color mode
void set_output_color_mode(ColorMode mode);

// Macros for detecting terminal and color usage
#define IS_TERMINAL() (isatty(fileno(stderr)))

/*
 * USE_COLOR() is true if color is forced or if color is auto and the output is a terminal.
 * used for all colorized output
 */
#define USE_COLOR() ((color_mode == COLOR_MODE_FORCE) || (color_mode == COLOR_MODE_AUTO && IS_TERMINAL()))

/*
 * DEBUG_COLOR_MODE is the color mode for debug output after USE_COLOR() check.
 * used for debug colorized output
 */
#define USE_COLOR_IN_DEBUG() (color_mode == COLOR_MODE_AUTO ? ((debug_color_mode == COLOR_MODE_FORCE) || (debug_color_mode == COLOR_MODE_AUTO && IS_TERMINAL())) : USE_COLOR())

#define COLOR_RED "\033[1;31m"
#define COLOR_GREEN "\033[1;32m"
#define COLOR_YELLOW "\033[1;33m"
#define COLOR_BLUE "\033[1;34m"
#define COLOR_MAGENTA "\033[1;35m"
#define COLOR_CYAN "\033[1;36m"
#define COLOR_WHITE "\033[1;37m"
#define COLOR_RESET "\033[0m"

#define OPTIONAL_COLOR(color) (USE_COLOR() ? color : "")
#define DEBUG_COLOR(color) (USE_COLOR_IN_DEBUG() ? color : "")

// ------------
// -- Errors --
// ------------

typedef enum {
  HECTIC_ERROR_NONE = 0,
  TEMPLATE_ERROR_NONE = 900000,
  TEMPLATE_ERROR_UNKNOWN_TAG = 900001,
  TEMPLATE_ERROR_NESTED_INTERPOLATION = 900002,
  TEMPLATE_ERROR_NESTED_SECTION_ITERATOR = 900003,
  TEMPLATE_ERROR_UNEXPECTED_SECTION_END = 900004,
  TEMPLATE_ERROR_NESTED_INCLUDE = 900005,
  TEMPLATE_ERROR_NESTED_EXECUTE = 900006,
  TEMPLATE_ERROR_INVALID_CONFIG = 900007,
  TEMPLATE_ERROR_OUT_OF_MEMORY = 900008,
  TEMPLATE_ERROR_UNEXPECTED_INCLUDE_END = 900009,
  TEMPLATE_ERROR_UNEXPECTED_EXECUTE_END = 900010,
  LOGGER_ERROR_INVALID_RULES_STRING = 800001,
  LOGGER_ERROR_OUT_OF_MEMORY = 800002,
  DEBUG_TO_JSON_PARSE_NO_EQUAL_SIGN_ERROR = 700003,
  DEBUG_TO_JSON_PARSE_NO_STRUCT_NAME_ERROR = 700004,
  DEBUG_TO_JSON_PARSE_LEFT_OPERAND_ERROR = 700005,
  DEBUG_TO_JSON_PARSE_NO_START_ERROR = 700006,
  DEBUG_TO_JSON_PARSE_NO_END_ERROR = 700007,
} HecticErrorCode;

// Define color macros based on output type
//#define ERROR_PREFIX PP_CAT(COLOR_RED, "Error: ")
//#define ERROR_SUFFIX PP_CAT(COLOR_RESET, "\n")
#define ERROR_PREFIX (USE_COLOR() ? "\033[1;31mError: " : "Error: ")
#define ERROR_SUFFIX (USE_COLOR() ? "\033[0m\n" : "\n")

// eprintf handling 1 or more arguments
#define eprintf(fmt, ...)     "%s" fmt "%s", ERROR_PREFIX, ##__VA_ARGS__, ERROR_SUFFIX

#define todo fprintf(stderr, "%sNot implimented yet%s", COLOR_RED, COLOR_RESET);exit(1)

// ------------
// -- Result --
// ------------

typedef enum {
  RESULT_ERROR,
  RESULT_SOME,
} ResultType;

char *result_type_to_string(ResultType type);

typedef struct {
  HecticErrorCode code;
  char *message;
} HecticError;

#define RESULT(name, some_type) \
    typedef struct {                          \
        ResultType type;                      \
        union {                               \
            HecticError error;                \
            some_type *some;                  \
        } Result;                             \
    } name##Result

typedef struct {
    ResultType type;
    union {
        HecticError error;
    } Result;
} EmptyResult;

#define IS_RESULT_ERROR(result) (result.type == RESULT_ERROR)
#define IS_RESULT_SOME(result) (result.type == RESULT_SOME)

#define TRY(result) if (IS_RESULT_ERROR(result)) { return result; }

#define RESULT_ERROR_CODE(result) (result.Result.error.code)
#define RESULT_ERROR_MESSAGE(result) (result.Result.error.message)

#define RESULT_SOME_VALUE(result) (*result.Result.some)
#define RESULT_ERROR_VALUE(result) (result.Result.error)

#define RESULT_SOME(result_type, value) \
    (result_type) { .type = RESULT_SOME, .Result.some = &value }

#define RESULT_ERROR(result_type, error_code, error_message) \
    (result_type) { .type = RESULT_ERROR, .Result.error = { .code = error_code, .message = error_message } }

// ------------
// -- Logger --
// ------------

/*
 * Log levels following a consistent severity-based hierarchy.
 * Each level includes specific guidance on when it should be used.
 */
typedef enum {
  /*
   * TRACE: Most detailed information for in-depth debugging
   * Use for: Deep diagnostic details, function entry/exit, variable dumps
   * Visibility: Development environments only, rarely used in production
   */
  LOG_LEVEL_TRACE,
  
  /*
   * DEBUG: Detailed information useful during development
   * Use for: Development-time debugging, showing variable states, internal flows
   * Visibility: Development and debugging environments, rarely in production
   */
  LOG_LEVEL_DEBUG,
  
  /*
   * LOG: General operational events
   * Use for: Runtime events worth logging but not requiring attention
   * Visibility: Always written to logs, useful for auditing/diagnostics
   */
  LOG_LEVEL_LOG,
  
  /*
   * INFO: Informational messages highlighting progress
   * Use for: Normal but noteworthy events, state changes, startup/shutdown events
   * Visibility: Visible to client applications if configured
   */
  LOG_LEVEL_INFO,
  
  /*
   * NOTICE: More important events than INFO, but not warnings
   * Use for: Important state changes, significant operations, configuration changes
   * Visibility: Displayed to client by default, meant to be seen
   */
  LOG_LEVEL_NOTICE,
  
  /*
   * WARN: Potential problems that don't prevent normal operation
   * Use for: Unexpected behaviors, deprecated feature usage, recoverable errors
   * Visibility: Alerts both client and server logs, needs attention
   */
  LOG_LEVEL_WARN,
  
  /*
   * EXCEPTION: Serious errors requiring immediate attention
   * Use for: Critical failures, data loss risks, business rule violations
   * Visibility: Highest priority, often leads to operation termination
   */
  LOG_LEVEL_EXCEPTION
} LogLevel;

/*
 * Structure for complex log level rule
 * Allows specifying log levels per file, function, and line range
 */
typedef struct LogRule {
    LogLevel level;           // Log level for this rule
    char *file_pattern;       // File pattern to match (can be NULL)
    char *function_pattern;   // Function pattern to match (can be NULL)
    int line_start;           // Start line number (-1 for any)
    int line_end;             // End line number (-1 for any)
    struct LogRule *next;     // Next rule in the chain
} LogRule;

/*
 * Log output mode - controls how logs are written to files
 */
typedef enum {
    LOG_OUTPUT_STDERR_ONLY,   // Write only to stderr (default)
    LOG_OUTPUT_FILE_ONLY,     // Write only to file
    LOG_OUTPUT_BOTH           // Write to both stderr and file
} LogOutputMode;

/**
 * Set log output mode
 * @param mode The output mode (stderr only, file only, or both)
 */
void logger_set_output_mode(LogOutputMode mode);

/**
 * Set log file path
 * @param file_path Path to the log file. If NULL, file logging is disabled.
 * @return 0 on success, -1 on failure (e.g., unable to open file)
 */
int logger_set_file(const char *file_path);

void logger_level_reset();

void logger_init(void);

void logger_free(void);

void logger_level(LogLevel level);

LogLevel log_level_from_string(const char *level_str);

/**
 * Core logging function that formats and outputs log messages.
 * 
 * @param level Severity level of the message
 * @param file Source file where log was generated
 * @param func Function where log was generated
 * @param line Line number where log was generated
 * @param format Printf-style format string
 * @param ... Variable arguments for format string
 * @return Timestamp string for the log message
 */
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

void* arena_alloc_or_null__(const char *file, const char *func, int line, Arena *arena, size_t size, bool expand);

// FIXME(yukkop): ptr % 8 == 0
void* arena_alloc__(const char *file, const char *func, int line, Arena *arena, size_t size);

void arena_reset__(const char *file, const char *func, int line, Arena *arena);

void arena_free__(const char *file, const char *func, int line, Arena *arena);

char* arena_strdup__(const char *file, const char *func, int line, Arena *arena, const char *s);
char* arena_strdup_fmt__(const char *file, const char *func, int line, Arena *arena, const char *fmt, ...);

char* arena_repstr__(const char *file, const char *func, int line, Arena *arena,
                             const char *src, size_t start, size_t len, const char *rep);

void* arena_realloc__(const char *file, const char *func, int line, Arena *arena,
                           void *ptr, size_t size, size_t new_size);

char* arena_strncpy__(const char *file, const char *func, int line, Arena *arena, const char *start, size_t len);

// NOTE(yukkop): This macro is used to define procedures so that `__LINE__` and `__FILE__`
// in `raise_debug` reflect the location where the macro is called, not where it's defined.
#define arena_alloc_or_null(arena, size) \
        arena_alloc_or_null__(__FILE__, __func__, __LINE__, arena, size, false)

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

#define arena_strdup_fmt(arena, ...) \
	arena_strdup_fmt__(__FILE__, __func__, __LINE__, arena, ##__VA_ARGS__)

#define arena_repstr(arena, src, start, len, rep) \
	arena_repstr__(__FILE__, __func__, __LINE__, arena, src, start, len, rep)

#define arena_realloc(arena, ptr, size, new_size) \
	arena_realloc__(__FILE__, __func__, __LINE__, arena, ptr, size, new_size)

#define arena_strncpy(arena, src, len) \
	arena_strncpy__(__FILE__, __func__, __LINE__, arena, src, len)

static Arena disposable_arena __attribute__((unused)) = {0};

#define DISPOSABLE_ARENA_FREE arena_free(&disposable_arena)

#define DISPOSABLE_ARENA __extension__ ({  \
    if (disposable_arena.begin == NULL) {  \
        disposable_arena = arena_init__(__FILE__, __func__, __LINE__, MEM_MiB * 8); \
    } else { \
        arena_reset(&disposable_arena); \
    } \
    &disposable_arena; \
})

// ------------
// -- Debug --
// ------------

/*
 * Set of pointers to track visited objects
 * Used to detect cycles in debug strings
 */
typedef struct PtrSet {
    struct {
        void const *ptr;
        const char *type;
        const char *field_name;  // Add field name to distinguish between same-type fields in unions
    } *data;
    size_t size;
    size_t capacity;
} PtrSet;

PtrSet *ptrset_init__(const char *file, const char *func, int line, Arena *arena);
#define ptrset_init(arena) ptrset_init__(__FILE__, __func__, __LINE__, arena)

bool debug_ptrset_contains__(PtrSet *set, const void *ptr, const char *type, const char *field_name);
void debug_ptrset_add__(const char *file, const char *func, int line, Arena *arena, PtrSet *set, const void *ptr, const char *type, const char *field_name);

#define DEBUGSTR(arena, type, value) DEBUGSTR_##type(arena, value)

#define DEBUGSTR_Slice(arena, value) slice_to_debug_str(arena, value)
#define DEBUGSTR_Json(arena, value)  json_to_debug_str(arena, value)

/*
 * Print all current logging rules to stderr for debugging
 */
void logger_print_rules();

/*
 * Dump all active logging rules into a string
 * 
 * @param arena Memory arena to allocate the string in
 * @return String representation of all rules, or NULL on error
 */
char* logger_rules_to_string(Arena *arena);

char *string_to_debug_str__(const char *file, const char *func, int line, Arena *arena, const char *name, const char *string);

char *int_to_debug_str__(const char *file, const char *func, int line, Arena *arena, const char *name, int number);

char *float_to_debug_str__(const char *file, const char *func, int line, Arena *arena, const char *name, double number);

char *size_t_to_debug_str__(const char *file, const char *func, int line, Arena *arena, const char *name, size_t number);

char *ptr_to_debug_str__(const char *file, const char *func, int line, Arena *arena, const char *name, void *ptr);

char *char_to_debug_str__(const char *file, const char *func, int line, Arena *arena, const char *name, char c);

char *bool_to_debug_str__(const char *file, const char *func, int line, Arena *arena, const char *name, int boolean);

char *union_to_debug_str__(const char *file, const char *func, int line, Arena *arena, const char *type, const char *name, const void *ptr, size_t active_variant, size_t count, ...);

char *struct_to_debug_str__(const char *file, const char *func, int line, Arena *arena, const char *type, const char *name, const void *ptr, int count, ...);

bool debug_ptrset_contains(PtrSet *set, void *ptr);

#define ENUM_TO_DEBUG_STR(arena, name, enum_value, enum_str) \
    enum_to_debug_str__(__FILE__, __func__, __LINE__, arena, name, enum_value, enum_str)
#define STRING_TO_DEBUG_STR(arena, name, string) \
    string_to_debug_str__(__FILE__, __func__, __LINE__, arena, name, string)
#define INT_TO_DEBUG_STR(arena, name, number) \
    int_to_debug_str__(__FILE__, __func__, __LINE__, arena, name, number)
#define FLOAT_TO_DEBUG_STR(arena, name, number) \
    float_to_debug_str__(__FILE__, __func__, __LINE__, arena, name, number)
#define SIZE_T_TO_DEBUG_STR(arena, name, number) \
    size_t_to_debug_str__(__FILE__, __func__, __LINE__, arena, name, number)
#define PTR_TO_DEBUG_STR(arena, name, ptr) \
    ptr_to_debug_str__(__FILE__, __func__, __LINE__, arena, name, ptr)
#define CHAR_TO_DEBUG_STR(arena, name, c) \
    char_to_debug_str__(__FILE__, __func__, __LINE__, arena, name, c)
#define BOOL_TO_DEBUG_STR(arena, name, boolean) \
    bool_to_debug_str__(__FILE__, __func__, __LINE__, arena, name, boolean)

#define UNION_TO_DEBUG_STR(arena, buffer, type, name, ptr, visited, active_variant, count, ...) do { \
    if (!name) \
        name = "$1"; \
    \
    if (debug_ptrset_contains__(visited, ptr, #type, name)) \
        return arena_strdup_fmt__(__FILE__, __func__, __LINE__, arena, "%sunion%s %s %s = <cycle detected> %s%p%s", DEBUG_COLOR(COLOR_GREEN), DEBUG_COLOR(COLOR_RESET), #type, name, DEBUG_COLOR(COLOR_CYAN), ptr, DEBUG_COLOR(COLOR_RESET)); \
    \
    if (!ptr) \
        return arena_strdup_fmt__(__FILE__, __func__, __LINE__, arena, "%sunion%s %s %s = NULL", DEBUG_COLOR(COLOR_GREEN), DEBUG_COLOR(COLOR_RESET), #type, name); \
    \
    debug_ptrset_add__(__FILE__, __func__, __LINE__, arena, visited, ptr, #type, name); \
    \
    buffer = union_to_debug_str__(__FILE__, __func__, __LINE__, arena, #type, name, ptr, active_variant, count, ##__VA_ARGS__); \
} while (0)

/*
 * STRUCT_TO_DEBUG_STR - Converts a structure into a debug string.
 *
 * Parameters:
 *   arena   - Pointer to the memory allocation arena.
 *   buffer  - Variable that will hold the resulting debug string.
 *   type    - Data type of the structure (used for formatting).
 *   name    - Name of the structure; if NULL, it is replaced with "$1".
 *   ptr     - Pointer to the structure.
 *   visited - Set of visited pointers (for cycle detection).
 *   count   - Count of fields or elements to output.
 *   ...     - Additional arguments for struct_to_debug_str__.
 *
 * Details:
 *   - If 'ptr' is already present in 'visited', the macro returns a string indicating "cycle detected".
 *   - If 'ptr' is NULL, the macro returns a string indicating that the structure is NULL.
 *   - Otherwise, 'ptr' is added to 'visited' and the structure is converted into a debug string.
 *
 * Restrictions:
 *   - This macro must be used at the function level only. Nested usage is not allowed,
 *     as the 'return' statements within the macro will exit the current function.
 *
 * Returns:
 *   - A debug string created by arena_strdup_fmt__ containing the structure's debugging information.
 */
#define STRUCT_TO_DEBUG_STR(arena, buffer, type, name, ptr, visited, count, ...) do { \
    if (!name) \
        name = "$1"; \
    \
    if (debug_ptrset_contains__(visited, ptr, #type, name)) \
        return arena_strdup_fmt__(__FILE__, __func__, __LINE__, arena, "%sstruct%s %s %s = <cycle detected> %s%p%s", DEBUG_COLOR(COLOR_GREEN), DEBUG_COLOR(COLOR_RESET), #type, name, DEBUG_COLOR(COLOR_CYAN), ptr, DEBUG_COLOR(COLOR_RESET)); \
    \
    if (!ptr) \
        return arena_strdup_fmt__(__FILE__, __func__, __LINE__, arena, "%sstruct%s %s %s = NULL", DEBUG_COLOR(COLOR_GREEN), DEBUG_COLOR(COLOR_RESET), #type, name); \
    \
    debug_ptrset_add__(__FILE__, __func__, __LINE__, arena, visited, ptr, #type, name); \
    \
    buffer = struct_to_debug_str__(__FILE__, __func__, __LINE__, arena, #type, name, ptr, count, ##__VA_ARGS__); \
} while (0)

// ------------------
// -- Logger Rules --
// ------------------

RESULT(LogRule, LogRule);

/*
 * Set complex logging rules from a string
 * Format: DEFAULT_LEVEL,<file>@<function>=LEVEL,<file>@<line_start>:<line_end>=LEVEL,...
 * Example: "INFO,main.c@main=DEBUG,helper.c@10:50=TRACE"
 *
 * @param rules_str The rule string to parse
 * @return a LogRuleResult containing the LogRule* or an Error
 */
LogRuleResult logger_parse_rules__(const char *file, const char *func, int line, Arena *arena, const char *rules_str);

/*
 * Set complex logging rule programmatically
 * 
 * @param level Log level for this rule
 * @param file_pattern File pattern to match (NULL for any file)
 * @param function_pattern Function pattern to match (NULL for any function)
 * @param line_start Start line number (-1 for any)
 * @param line_end End line number (-1 for any)
 * @return 1 on success, 0 on failure
 */
HecticError logger_add_rule(Arena *arena, LogRule *rules, LogLevel level, const char *file_pattern, const char *function_pattern, int line_start, int line_end);

/*
 * Get the effective log level for a message based on complex rules
 * 
 * @param file Source file where log was generated
 * @param func Function where log was generated
 * @param line Line number where log was generated
 * @return The effective log level for this context
 */
LogLevel logger_get_effective_level(const char *file, const char *func, int line);

char *log_rules_to_debug_str__(const char *file, const char *func, int line, Arena *arena, char *name, LogRule *self, PtrSet *visited);

#define LOG_RULES_TO_DEBUG_STR(arena, name, self) \
    log_rules_to_debug_str__(__FILE__, __func__, __LINE__, arena, name, self, ptrset_init(arena))

// ----------
// -- Json --
// ----------

typedef struct Json Json;

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

typedef union {
    double number;
    char *string;
    int boolean;
    Json *child;  /* Child element (for arrays/objects) */
} JsonValue;

/* Full JSON structure */
struct Json {
    struct Json *next;   /* Next sibling */
    JsonType type;
    JsonValue value;
    char *key;           /* Key if item is in an object */
};

RESULT(Json, Json);

Json *json_parse__(const char* file, const char* func, int line, Arena *arena, const char **s);
#define json_parse(arena, s) json_parse__(__FILE__, __func__, __LINE__, arena, s)

char *json_to_str__(const char* file, const char* func, int line, Arena *arena, const Json * const item);
#define JSON_TO_STR(arena, item) json_to_str__(__FILE__, __func__, __LINE__, arena, item)

char *json_to_str_with_opts__(const char* file, const char* func, int line, Arena *arena, const Json * const item, JsonRawOpt raw);
#define JSON_TO_STR_WITH_OPTS(arena, item, raw) json_to_str_with_opts__(__FILE__, __func__, __LINE__, arena, item, raw)

/* Retrieve an object item by key (case-sensitive) */
Json *json_get_object_item__(const char* file, const char* func, int line, const Json * const object, const char * const key);

#define json_get_object_item(object, key) json_get_object_item__(__FILE__, __func__, __LINE__, object, key)

char* json_to_debug_str__(const char* file, const char* func, int line, Arena *arena, const char *name, const Json *self, PtrSet *visited);

#define JSON_TO_DEBUG_STR(arena, name, json) json_to_debug_str__(__FILE__, __func__, __LINE__, arena, name, json, ptrset_init(arena))

char *json_to_pretty_str__(const char* file, const char* func, int line, Arena *arena, const Json * const item, int indent_level);

#define JSON_TO_PRETTY_STR(arena, json) json_to_pretty_str__(__FILE__, __func__, __LINE__, arena, json, 0)

// Prettify a flat debug string by adding line breaks and structure
char *debug_to_pretty_str__(const char* file, const char* func, int line, Arena *arena, const char *flat_str);
#define debug_to_pretty_str(arena, str) debug_to_pretty_str__(__FILE__, __func__, __LINE__, arena, str)

JsonResult debug_str_to_json__(const char* file, const char* func, int line, Arena *arena, const char **s);

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

Slice slice_create__(const char *file, const char *func, int line, size_t isize, const void *array, size_t array_len, size_t start, size_t len);

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

char* slice_to_debug_str__(const char* file, const char* func, int line, Arena *arena, Slice slice);

#define slice_to_debug_str(arena, slice) slice_to_debug_str__(__FILE__, __func__, __LINE__, arena, slice)

// ----------
// -- View --
// ----------

typedef struct {
    const void * const data;
    const size_t len;
    const size_t isize;
} View;

// ---------------
// -- Templater --
// ---------------

typedef enum {
    TEMPLATE_NODE_TEXT,        // Plain text content
    TEMPLATE_NODE_INTERPOLATE, // Variable interpolation
    TEMPLATE_NODE_SECTION,     // Section (for loops)
    TEMPLATE_NODE_INCLUDE,     // Include other templates
    TEMPLATE_NODE_EXECUTE,     // Execute code
} TemplateNodeType;

#define TEMPLATE_MAX_PREFIX_LEN 16

typedef struct {
  struct {
    struct {
      const View * const open;      // Default: "{%"
      const View * const close;     // Default: "%}"
    } Braces;
    struct {
      const View * const control;   // default: "for "
      const View * const source;    // default: " in "
      const View * const begin;     // default: " do "
    } Section;
    struct {
      const View * const invoke;    // default: ""
    } Interpolate;
    struct {
      const View * const invoke;    // default: "include "
    } Include;
    struct {
      const View * const invoke;    // default: "exec "
    } Execute;
    const View * const nesting;    // default: "->"
  } Syntax;
} TemplateConfig;

typedef struct TemplateNode TemplateNode; // forward declaration

typedef struct {
  char *iterator;
  char *collection;
  TemplateNode *body;
} TemplateSectionValue;

typedef struct {
  char *key;
} TemplateInterpolateValue;

typedef struct {
  char *code;
} TemplateExecuteValue;

typedef struct {
  char *key;
} TemplateIncludeValue;

typedef struct {
  char *content;
} TemplateTextValue;

typedef union {
  TemplateSectionValue section;
  TemplateInterpolateValue interpolate;
  TemplateExecuteValue execute;
  TemplateIncludeValue include;
  TemplateTextValue text;
} TemplateValue;

struct TemplateNode {
    TemplateNodeType type;
    TemplateValue *value;
    TemplateNode *next;
};

RESULT(Template, TemplateNode);

TemplateResult template_parse__(const char *file, const char *func, int line, Arena *arena, const char **s, const TemplateConfig *config, bool inner_parse);

TemplateConfig template_default_config__(const char *file, const char *func, int line, Arena *arena);

char *template_node_to_debug_str__(const char *file, const char *func, int line, Arena *arena, const char *name, const TemplateNode *self, PtrSet *visited);

char *template_node_to_json_str__(const char *file, const char *func, int line, Arena *arena, const TemplateNode *node, int depth);

#define template_parse(arena, s, config) template_parse__(__FILE__, __func__, __LINE__, arena, s, config, false)

#define template_default_config(arena) template_default_config__(__FILE__, __func__, __LINE__, arena)

#define TEMPLATE_NODE_TO_DEBUG_STR(arena, name, node) \
    template_node_to_debug_str__(__FILE__, __func__, __LINE__, arena, name, node, ptrset_init(arena))

#define TEMPLATE_NODE_TO_JSON_STR(arena, node) \
    template_node_to_json_str__(__FILE__, __func__, __LINE__, arena, node, 0)

TemplateNode init_template_node__(const char *file, const char *func, int line, Arena *arena, TemplateNodeType type);

#define init_template_node(arena, type) \
    init_template_node__(__FILE__, __func__, __LINE__, arena, type)

#define TEMPLATE_NODE_DISPOSABLE_JSON(node) __extension__ ({ \
    Arena *debug_arena = DISPOSABLE_ARENA; \
    const char *json_str = TEMPLATE_NODE_TO_JSON_STR(debug_arena, &node); \
    Json *json = json_parse(debug_arena, &json_str); \
    arena_strdup(debug_arena, JSON_TO_PRETTY_STR(debug_arena, json)); \
})

#define TEMPLATE_NODE_PRETTY_JSON(node, arena) __extension__ ({ \
    Arena *debug_arena = DISPOSABLE_ARENA; \
    const char *json_str = TEMPLATE_NODE_TO_JSON_STR(debug_arena, &node); \
    Json *json = json_parse(debug_arena, &json_str); \
    arena_strdup(arena, JSON_TO_PRETTY_STR(debug_arena, json)); \
})

// --------------
// -- Colorize --
// --------------

typedef struct {
    const char *pattern;
    int highlight_start;
    int highlight_len;
    const char *color;
} PatternHighlight;

char *colorize_partial_patterns(char *output, const char *input, PatternHighlight *patterns, size_t pattern_count);

#endif // EPRINTF_H
