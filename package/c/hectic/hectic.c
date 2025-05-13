#include "hectic.h"
#include <fnmatch.h>
#include <string.h>
#include <assert.h>
#include <signal.h>
#include <errno.h>
#include <setjmp.h>

MemoryAllocator default_allocator = {
    .malloc = malloc,
    .free = free
};

void init_default_allocator(void) {
    default_allocator.malloc = malloc;
    default_allocator.free = free;
}

void set_memory_allocator(MemoryAllocator allocator) {
    default_allocator = allocator;
}

// TODO(yukkop): rename without arena_ prefix
void* arena_memory_alloc(size_t size) {
    return default_allocator.malloc(size);
}

void arena_memory_free(void* ptr) {
    default_allocator.free(ptr);
}

// On systems without strsep, provide a custom implementation
#ifndef _GNU_SOURCE
#define _GNU_SOURCE 1
#endif

#ifndef HAVE_STRSEP
char *strsep(char **stringp, const char *delim) {
    char *start = *stringp;
    char *p;

    if (!start)
        return NULL;

    p = start;
    while (*p && !strchr(delim, *p))
        p++;

    if (*p) {
        *p++ = '\0';
        *stringp = p;
    } else {
        *stringp = NULL;
    }

    return start;
}
#endif

// Forward declarations
const char* json_type_to_string(JsonType type);

// Global color mode variable definition
ColorMode color_mode = COLOR_MODE_AUTO;
ColorMode debug_color_mode = COLOR_MODE_AUTO;

// Global logging variables
LogLevel current_log_level = LOG_LEVEL_INFO;
LogRule *log_rules = NULL;
Arena *log_rules_arena = NULL;

// File logging configuration
static FILE *log_file = NULL;
static LogOutputMode log_output_mode = LOG_OUTPUT_STDERR_ONLY;
static char *log_file_path = NULL;

/**
 * Set log output mode
 * @param mode The output mode (stderr only, file only, or both)
 */
void logger_set_output_mode(LogOutputMode mode) {
    log_output_mode = mode;
}

/**
 * Set log file path
 * @param file_path Path to the log file. If NULL, file logging is disabled.
 * @return 0 on success, -1 on failure (e.g., unable to open file)
 */
int logger_set_file(const char *file_path) {
    // Close current log file if open
    if (log_file != NULL && log_file != stderr) {
        fclose(log_file);
        log_file = NULL;
    }
    
    // Free previous path if it exists
    if (log_file_path != NULL) {
        free(log_file_path);
        log_file_path = NULL;
    }
    
    // If path is NULL, disable file logging
    if (file_path == NULL) {
        log_output_mode = LOG_OUTPUT_STDERR_ONLY;
        return 0;
    }
    
    // Copy the file path
    log_file_path = strdup(file_path);
    if (log_file_path == NULL) {
        fprintf(stderr, "ERROR: Failed to allocate memory for log file path\n");
        return -1;
    }
    
    // Open the log file
    log_file = fopen(file_path, "a");
    if (log_file == NULL) {
        fprintf(stderr, "ERROR: Failed to open log file %s: %s\n", file_path, strerror(errno));
        free(log_file_path);
        log_file_path = NULL;
        return -1;
    }
    
    return 0;
}

const char* color_mode_to_string(ColorMode mode) {
    switch (mode) {
        case COLOR_MODE_AUTO: return "AUTO";
        case COLOR_MODE_FORCE: return "FORCE";
        case COLOR_MODE_DISABLE: return "DISABLE";
        default: return "UNKNOWN";
    }
}

void set_output_color_mode(ColorMode mode) {
    // Log the color mode change
    const char* mode_name = color_mode_to_string(mode);
    
    // Using fprintf since this might be called before logging is initialized
    raise_info__(__FILE__, __func__, __LINE__, "CONFIG: Setting output color mode to %s", mode_name);
    
    // Set the mode
    color_mode = mode;
}

#define POSITION_INFO_DECLARATION const char *file, const char *func, int line
#define POSITION_INFO file, func, line
#define CTX_DECLARATION POSITION_INFO_DECLARATION, Arena *arena
#define CTX(lifetimed_arena) POSITION_INFO, arena = (lifetimed_arena)

/* Utility: Skip whitespace */
static const char *skip_whitespace(const char *s) {
    while (*s && isspace((unsigned char)*s))
        s++;
    return s;
}

// -----------
// -- Error --
// -----------

const char* error_code_to_string(HecticErrorCode code) {
    switch (code) {
        case HECTIC_ERROR_NONE: return "NONE";
        case TEMPLATE_ERROR_NONE: return "NONE";
        case TEMPLATE_ERROR_UNKNOWN_TAG: return "UNKNOWN_TAG";
        case TEMPLATE_ERROR_NESTED_INTERPOLATION: return "NESTED_INTERPOLATION";
        case TEMPLATE_ERROR_NESTED_SECTION_ITERATOR: return "NESTED_SECTION_ITERATOR";
        case TEMPLATE_ERROR_UNEXPECTED_SECTION_END: return "UNEXPECTED_SECTION_END";
        case TEMPLATE_ERROR_NESTED_INCLUDE: return "NESTED_INCLUDE";
        case TEMPLATE_ERROR_NESTED_EXECUTE: return "NESTED_EXECUTE";
        case TEMPLATE_ERROR_INVALID_CONFIG: return "INVALID_CONFIG";
        case TEMPLATE_ERROR_OUT_OF_MEMORY: return "OUT_OF_MEMORY";
        case LOGGER_ERROR_INVALID_RULES_STRING: return "INVALID_RULES_STRING";
        case LOGGER_ERROR_OUT_OF_MEMORY: return "OUT_OF_MEMORY";
        default: return "UNKNOWN";
    }
}

// ------------
// -- Result --
// ------------

char *result_type_to_string(ResultType type) {
    switch (type) {
        case RESULT_ERROR: return "ERROR";
        case RESULT_SOME: return "SOME";
        default: return "UNKNOWN";
    }
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

const char* log_level_to_color(LogLevel level) {
    switch (level) {
        case LOG_LEVEL_TRACE: return OPTIONAL_COLOR(COLOR_GREEN);
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

void logger_level_reset() {
    current_log_level = LOG_LEVEL_INFO;
    logger_free();
}

void logger_level(LogLevel level) {
    current_log_level = level;
    logger_free();
}

// NOTE(yukkop): This function not uses POSITION_INFO because it's not have a user error. All possible errors are realization errors.
void logger_init(void) {
    log_rules_arena = arena_memory_alloc(sizeof(Arena));
    if (!log_rules_arena) {
        fprintf(stderr, "INIT: Failed to allocate memory for logger arena\n");
        exit(1);
    }
    
    *log_rules_arena = arena_init__(__FILE__, __func__, __LINE__, 1024);
    const char* env_level = getenv("LOG_LEVEL");
    printf("INIT: env_level: %s\n", env_level);
    
    if (env_level) {
        // Check if it's a complex rule format (contains '=' or ',')
        if (strchr(env_level, '=') || strchr(env_level, ',')) {
            printf("INIT: env_level is complex\n");
            LogRuleResult parse_result = logger_parse_rules__(__FILE__, __func__, __LINE__, log_rules_arena, env_level);
            if (IS_RESULT_ERROR(parse_result)) {
                fprintf(stderr, "INIT: Failed to parse complex log rules, using default level INFO\n");
                current_log_level = LOG_LEVEL_INFO;
                log_rules = arena_alloc__(__FILE__, __func__, __LINE__, log_rules_arena, sizeof(LogRule));
                *log_rules = RESULT_SOME_VALUE(parse_result);
            } else {
                fprintf(stderr, "INIT: Logger initialized with complex rules from environment\n");
            }
        } else {
            printf("INIT: env_level is simple\n");
            current_log_level = log_level_from_string(env_level);
            fprintf(stderr, "INIT: Logger initialized with level %s from environment\n", 
                    log_level_to_string(current_log_level));
        }
    } else {
        fprintf(stderr, "INIT: Logger initialized with default level %s\n", 
                log_level_to_string(current_log_level));
    }
    
    // Check for file logging environment variables
    const char* log_file_env = getenv("LOG_FILE");
    if (log_file_env) {
        if (logger_set_file(log_file_env) == 0) {
            fprintf(stderr, "INIT: Logging to file: %s\n", log_file_env);
            
            // Check for output mode
            const char* log_mode_env = getenv("LOG_OUTPUT_MODE");
            if (log_mode_env) {
                if (strcmp(log_mode_env, "FILE_ONLY") == 0) {
                    logger_set_output_mode(LOG_OUTPUT_FILE_ONLY);
                    fprintf(stderr, "INIT: Log output mode set to FILE_ONLY\n");
                } else if (strcmp(log_mode_env, "BOTH") == 0) {
                    logger_set_output_mode(LOG_OUTPUT_BOTH);
                    fprintf(stderr, "INIT: Log output mode set to BOTH\n");
                } else {
                    logger_set_output_mode(LOG_OUTPUT_STDERR_ONLY);
                    fprintf(stderr, "INIT: Log output mode set to STDERR_ONLY\n");
                }
            } else {
                // Default to both if file is specified but mode isn't
                logger_set_output_mode(LOG_OUTPUT_BOTH);
                fprintf(stderr, "INIT: Log output mode set to BOTH (default)\n");
            }
        } else {
            fprintf(stderr, "INIT: Failed to open log file: %s\n", log_file_env);
        }
    }
}

void logger_free(void) {
    log_rules = NULL;
    if (log_rules_arena) {
        arena_free__(__FILE__, __func__, __LINE__, log_rules_arena);
        arena_memory_free(log_rules_arena);
        log_rules_arena = NULL;
    }
    
    // Close log file if open
    if (log_file != NULL && log_file != stderr) {
        fclose(log_file);
        log_file = NULL;
    }
    
    // Free log file path if allocated
    if (log_file_path != NULL) {
        arena_memory_free(log_file_path);
        log_file_path = NULL;
    }
    
    // Reset output mode
    log_output_mode = LOG_OUTPUT_STDERR_ONLY;
}

char* raise_message(
  LogLevel level,
  const char *file,
  const char *func,
  int line,
  const char *format,
  ...) {
    // Check against the effective log level for this context
    LogLevel effective_level = logger_get_effective_level(file, func, line);
    if (level < effective_level) {
        return NULL;
    }

    time_t now = time(NULL);
    struct tm tm_info;
    localtime_r(&now, &tm_info);
    static char timeStr[20];
    strftime(timeStr, sizeof(timeStr), "%Y-%m-%d %H:%M:%S", &tm_info);

    // Format the message first
    va_list args;
    va_start(args, format);
    
    // Create a buffer for the message
    char message_buffer[4096]; // Adjust size as needed
    int header_len = snprintf(message_buffer, sizeof(message_buffer), 
                             "%s %s%s%s %s:%s:%s%d%s ", 
                             timeStr, 
                             log_level_to_color(level), 
                             log_level_to_string(level), 
                             OPTIONAL_COLOR(COLOR_RESET),
                             file,
                             func,
                             OPTIONAL_COLOR(COLOR_GREEN),
                             line,
                             OPTIONAL_COLOR(COLOR_RESET));
    
    // Add the formatted message
    vsnprintf(message_buffer + header_len, sizeof(message_buffer) - header_len, format, args);
    va_end(args);
    
    // Add newline
    strcat(message_buffer, "\n");
    
    // Write to stderr if needed
    if (log_output_mode == LOG_OUTPUT_STDERR_ONLY || log_output_mode == LOG_OUTPUT_BOTH) {
        fprintf(stderr, "%s", message_buffer);
    }
    
    // Write to file if configured
    if ((log_output_mode == LOG_OUTPUT_FILE_ONLY || log_output_mode == LOG_OUTPUT_BOTH) && log_file != NULL) {
        // Remove ANSI color codes for file output
        char file_buffer[4096];
        char *src = message_buffer;
        char *dst = file_buffer;
        
        while (*src) {
            if (*src == '\033') {
                // Skip ANSI escape sequence
                while (*src && *src != 'm') src++;
                if (*src) src++; // Skip the 'm'
            } else {
                *dst++ = *src++;
            }
        }
        *dst = '\0';
        
        fprintf(log_file, "%s", file_buffer);
        fflush(log_file); // Ensure log is written immediately
    }

    return timeStr;
}

// -----------
// -- debug --
// -----------

PtrSet *ptrset_init__(POSITION_INFO_DECLARATION, Arena *arena) {
    PtrSet *set = arena_alloc__(file, func, line, arena, sizeof(PtrSet));
    set->data = arena_alloc__(file, func, line, arena, 4 * sizeof(struct { void const *ptr; const char *type; const char *field_name; }));
    set->size = 0;
    set->capacity = 4;
    return set;
}

bool debug_ptrset_contains__(PtrSet *set, const void *ptr, const char *type, const char *field_name) {
    if (!set) return false;
    for (size_t i = 0; i < set->size; i++) {
        if (set->data[i].ptr == ptr && 
            strcmp(set->data[i].type, type) == 0 && 
            strcmp(set->data[i].field_name, field_name) == 0)
            return true;
    }
    return false;
}

void debug_ptrset_add__(CTX_DECLARATION, PtrSet *set, const void *ptr, const char *type, const char *field_name) {
    if (!set) return;
    if (set->size == set->capacity) {
        set->capacity = set->capacity ? set->capacity * 2 : 4;
        set->data = arena_realloc__(CTX(arena), set->data, set->capacity * sizeof(struct { void const *ptr; const char *type; const char *field_name; }), 
                                  set->capacity * 2 * sizeof(struct { void const *ptr; const char *type; const char *field_name; }));
    }
    set->data[set->size].ptr = ptr;
    set->data[set->size].type = type;
    set->data[set->size].field_name = field_name;
    set->size++;
}


static sigjmp_buf jmp_env;

void segfault_handler(int signo) {
    (void)signo;
    siglongjmp(jmp_env, 1);
}

int is_readable(const void *ptr) {
    struct sigaction sa, old_sa;
    sa.sa_handler = segfault_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    sigaction(SIGSEGV, &sa, &old_sa);

    if (sigsetjmp(jmp_env, 1) == 0) {
        volatile char c = *(volatile const char *)ptr;
        (void)c;  // Suppress unused variable warning
        sigaction(SIGSEGV, &old_sa, NULL);
        return 1;  // Read success
    } else {
        sigaction(SIGSEGV, &old_sa, NULL);
        return 0;  // Read caused segmentation fault
    }
}

char *enum_to_debug_str__(CTX_DECLARATION, const char *name, size_t enum_value, const char *enum_str) {
    return arena_strdup_fmt__(CTX(arena), "%senum%s %s = %s%s%s %zu ", DEBUG_COLOR(COLOR_GREEN), DEBUG_COLOR(COLOR_RESET), name, DEBUG_COLOR(COLOR_CYAN), enum_str, DEBUG_COLOR(COLOR_RESET), enum_value);
}

char *string_to_debug_str__(CTX_DECLARATION, const char *name, const char *string) {
    if (!string)
        return arena_strdup_fmt__(CTX(arena), "%s = NULL", name);

    // Check if the pointer is readable.
    if (!is_readable(string))
        return arena_strdup_fmt__(CTX(arena), "%s = <memory unreadable>", name);

    return arena_strdup_fmt__(CTX(arena), "%s = %s%p%s \"%s\"",
                              name, DEBUG_COLOR(COLOR_CYAN), string,
                              DEBUG_COLOR(COLOR_RESET), string);
}

char *int_to_debug_str__(CTX_DECLARATION, const char *name, int number) {
    return arena_strdup_fmt__(CTX(arena), "%s = %d", name, number);
}

char *float_to_debug_str__(CTX_DECLARATION, const char *name, double number) {
    return arena_strdup_fmt__(CTX(arena), "%s = %f", name, number);
}

char *bool_to_debug_str__(CTX_DECLARATION, const char *name, int boolean) {
    return arena_strdup_fmt__(CTX(arena), "%s = %s", name, boolean ? "true" : "false");
}

char *size_t_to_debug_str__(CTX_DECLARATION, const char *name, size_t number) {
    return arena_strdup_fmt__(CTX(arena), "%s = %zu", name, number);
}

char *ptr_to_debug_str__(CTX_DECLARATION, const char *name, void *ptr) {
    if (!ptr) {
        return arena_strdup_fmt__(CTX(arena), "%s = NULL", name);
    }
    return arena_strdup_fmt__(CTX(arena), "%s = %p", name, ptr);
}

char *char_to_debug_str__(CTX_DECLARATION, const char *name, char c) {
    return arena_strdup_fmt__(CTX(arena), "%s = %c", name, c);
}

char *union_to_debug_str__(POSITION_INFO_DECLARATION, Arena *arena, const char *type, const char *name, const void *ptr, size_t active_variant, size_t count, ...) {
    if (count % 2 == 0) {
        raise_exception__(file, func, line, "HECTICLIB ERROR: Union to debug str: count is even");
        assert(0);
    }
    
    va_list args;
    va_start(args, count);
    
    char *value = NULL;
    bool variant_exists = false;
    
    // Find the matching value for the active variant
    while (count--) {
        size_t variant = va_arg(args, size_t);
        if (variant == (size_t)-1) break; // End marker
        
        if (variant == active_variant) {
            variant_exists = true;
            value = va_arg(args, char*);
            break;
        }
        // Skip the string value for non-matching variants
        va_arg(args, char*);
    }
    
    va_end(args);
    
    if (!variant_exists) {
        return arena_strdup_fmt__(file, func, line, arena, 
            "%sunion%s %s %s = <invalid variant %d> %s%p%s", 
            DEBUG_COLOR(COLOR_GREEN), DEBUG_COLOR(COLOR_RESET), 
            type, name, active_variant, DEBUG_COLOR(COLOR_CYAN), ptr, DEBUG_COLOR(COLOR_RESET));
    }
    
    if (!value) {
        return arena_strdup_fmt__(file, func, line, arena, 
            "%sunion%s %s %s = <unknown variant> %s%p%s", 
            DEBUG_COLOR(COLOR_GREEN), DEBUG_COLOR(COLOR_RESET), 
            type, name, DEBUG_COLOR(COLOR_CYAN), ptr, DEBUG_COLOR(COLOR_RESET));
    }
    
    return arena_strdup_fmt__(file, func, line, arena, 
        "%sunion%s %s %s = {%s} %s%p%s", 
        DEBUG_COLOR(COLOR_GREEN), DEBUG_COLOR(COLOR_RESET), 
        type, name, value, DEBUG_COLOR(COLOR_CYAN), ptr, DEBUG_COLOR(COLOR_RESET));
}

/* Private function */
char *debug_join_debug_strings_v(CTX_DECLARATION, int count, va_list args) {
    raise_trace__(file, func, line, "DEBUG JOIN: Joining %d strings", count);
    int total_len = 1;

    va_list args_copy;
    va_copy(args_copy, args);
    raise_trace__(file, func, line, "DEBUG JOIN: Starting first pass");
    for (int i = 0; i < count; i++) {
        char *s = va_arg(args_copy, char*);
        int len = strlen(s);
        raise_trace__(file, func, line, "DEBUG JOIN: String %d: [%s] %p len: %d", i, s, s, len);
        total_len += len;
    }
    va_end(args_copy);

    char *joined = arena_alloc__(CTX(arena), total_len);
    joined[0] = '\0';

    raise_trace__(file, func, line, "DEBUG JOIN: concatenating strings");
    va_copy(args_copy, args);
    for (int i = 0; i < count; i++) {
        char *s = va_arg(args_copy, char*);
        strcat(joined, s);
        if (i < count - 1) {
            strcat(joined, ", ");
        }
    }
    va_end(args_copy);

    return joined;
}

char *struct_to_debug_str__(CTX_DECLARATION, const char *type, const char *name, const void *ptr, int count, ...) {
    raise_trace__(file, func, line, "DEBUG STR: type: %s, name: %s, ptr: %p, count: %d", type, name, ptr, count);

    va_list args;
    va_start(args, count);
    char *joined = debug_join_debug_strings_v(CTX(arena), count, args);
    va_end(args);

    return arena_strdup_fmt__(CTX(arena), "%sstruct%s %s %s = {%s} %s%p%s", DEBUG_COLOR(COLOR_GREEN), DEBUG_COLOR(COLOR_RESET), type, name, joined, DEBUG_COLOR(COLOR_CYAN), ptr, DEBUG_COLOR(COLOR_RESET));
}

char *debug_to_pretty_str__(POSITION_INFO_DECLARATION, Arena *arena, const char *s) {
  int indent = 0;
  size_t len = strlen(s) * 3; // Estimate for extra spaces, newlines, and indents
  char *result = arena_alloc__(file, func, line, arena, len);
  char *current = result;
  size_t remaining = len;

  #define INDENT_STR "  "

  while (*s) {
    if (*s == '{') {
      int written = snprintf(current, remaining, "{\n");
      current += written;
      remaining -= written;
      
      indent++;
      for (int i = 0; i < indent; i++) {
        written = snprintf(current, remaining, INDENT_STR);
        current += written;
        remaining -= written;
      }
      s++;
    } else if (*s == '}') {
      int written = snprintf(current, remaining, "\n");
      current += written;
      remaining -= written;
      
      indent--;
      for (int i = 0; i < indent; i++) {
        written = snprintf(current, remaining, INDENT_STR);
        current += written;
        remaining -= written;
      }
      
      written = snprintf(current, remaining, "}");
      current += written;
      remaining -= written;
      s++;
    } else if (*s == ',') {
      int written = snprintf(current, remaining, ",\n");
      current += written;
      remaining -= written;
      
      for (int i = 0; i < indent; i++) {
        written = snprintf(current, remaining, INDENT_STR);
        current += written;
        remaining -= written;
      }
      s++;
      s = skip_whitespace(s);
    } else {
      if (remaining > 1) {
        *current++ = *s;
        remaining--;
      }
      s++;
    }
    
    // If we're running low on space, expand the buffer
    if (remaining < 20) {
      size_t used = current - result;
      size_t new_len = len * 2;
      result = arena_realloc__(file, func, line, arena, result, len, new_len);
      current = result + used;
      remaining = new_len - used;
      len = new_len;
    }
  }
  
  // Add final newline and null terminator
  if (remaining > 2) {
    *current++ = '\n';
    *current = '\0';
  } else {
    // Ensure null-termination even if we can't add the newline
    result[len - 1] = '\0';
  }
  
  return result;
}

// ------------
// -- arena --
// ------------

Arena arena_init__(POSITION_INFO_DECLARATION, size_t size) {
    // Function entry logging
    raise_debug__(file, func, line, 
        "ARENA INIT: Creating arena (size: %zu bytes)", size);
    
    Arena arena;
    arena.begin = arena_memory_alloc(size);
    
    // Check for allocation failure
    if (!arena.begin) {
        raise_exception__(file, func, line,
            "ARENA INIT: Failed to allocate memory for arena (requested: %zu bytes)", size);
        exit(1);
    }
    
    memset(arena.begin, 0, size);
    arena.current = arena.begin;
    arena.capacity = size;
    
    // Success logging at LOG level
    raise_log__(file, func, line,
	"ARENA INIT: Arena initialized successfully (address: %p, capacity: %zu bytes)", arena.begin, size);
    return arena;
}

void* arena_alloc_or_null__(POSITION_INFO_DECLARATION, Arena *arena, size_t size, bool expand) {
    raise_trace__(file, func, line, 
        "ARENA ALLOC: Requesting memory from arena (arena: %p, size: %zu bytes)", arena, size);

    if (arena->begin == 0) {
        raise_debug__(file, func, line,
            "ARENA ALLOC: Arena not initialized, creating new arena");
        *arena = arena_init__(file, func, line, 1024);
    }

    // align size to 8
    size = (size + 7) & ~((size_t)7);

    size_t used = (size_t)arena->current - (size_t)arena->begin;
    size_t available = arena->capacity - used;

    if (available < size) {
        if (expand) {
            // FIXME(yukkop): All pointers to the arena will be invalidated
            // We need to use a virtual memory allocator to avoid this issue
            size_t new_capacity = arena->capacity * 2 + size;
            raise_warn__(file, func, line,
                "ARENA ALLOC: Expanding arena (old: %zu, new: %zu)", arena->capacity, new_capacity);

            void *new_mem = arena_memory_alloc(new_capacity);
            if (!new_mem) {
                raise_warn__(file, func, line,
                    "ARENA ALLOC: Failed to expand arena (requested: %zu bytes)", new_capacity);
                return NULL;
            }

            memcpy(new_mem, arena->begin, used);
            arena_memory_free(arena->begin);
            arena->begin = new_mem;
            arena->current = (char *)new_mem + used;
            arena->capacity = new_capacity;

            raise_warn__(file, func, line,
                "ARENA ALLOC: Arena expanded successfully (address: %p, capacity: %zu)", new_mem, new_capacity);
        } else {
            raise_warn__(file, func, line,
                "ARENA ALLOC: Insufficient memory in arena (address: %p, capacity: %zu bytes, used: %zu bytes, requested: %zu bytes)",
                arena->begin, arena->capacity, used, size);
            return NULL;
        }
    }

    void *mem = arena->current;
    arena->current = (char*)arena->current + size;

    raise_debug__(file, func, line,
        "ARENA ALLOC: Memory allocated (address: %p, size: %zu)", mem, size);
    return mem;
}

void* arena_alloc__(POSITION_INFO_DECLARATION, Arena *arena, size_t size) {
    // Function entry logging
    raise_debug__(file, func, line, 
                 "ARENA ALLOC: Allocating memory (arena: %p, size: %zu bytes)", arena, size);
    
    void *mem = arena_alloc_or_null__(file, func, line, arena, size, false);
    if (!mem) {
        raise_debug__(file, func, line, 
      "ARENA ALLOC: Allocation failed (arena: %p, requested: %zu bytes)", arena, size);
        raise_exception__(file, func, line, 
	  "ARENA ALLOC: Arena out of memory (requested: %zu bytes)", size);
        exit(1);
    }
    
    // Success logging
    raise_log__(file, func, line,
                 "ARENA ALLOC: Memory allocated successfully (address: %p, size: %zu bytes)", mem, size);
    return mem;
}

/*
 * Reallocates a memory block and copies the contents of the old block to the new one.
 * NOTE(yukkop): We need to provide the old size to avoid copying more than needed.
 */
void* arena_realloc__(POSITION_INFO_DECLARATION, Arena *arena,
                           void *ptr, size_t size, size_t new_size) {
    void *new_ptr = NULL;
    if (ptr == NULL) {
        new_ptr = arena_alloc__(file, func, line, arena, new_size);
    } else if (new_size <= size) {
        new_ptr = ptr;
    } else {
        // FIXME(yukkop): Must tries to expand the arena before allocating new memory
        new_ptr = arena_alloc_or_null__(file, func, line, arena, new_size, false);
        if (new_ptr)
            memcpy(new_ptr, ptr, size);
    }
    return new_ptr;
}

void arena_reset__(POSITION_INFO_DECLARATION, Arena *arena) {
  // Function entry logging
  raise_debug__(file, func, line, 
    "ARENA RESET: Resetting arena (address: %p)", arena);
  
  // Check for NULL arena
  if (!arena) {
    raise_warn__(file, func, line,
      "ARENA RESET: Attempted to reset NULL arena");
    return;
  }
  
  // Reset the arena
  arena->current = arena->begin;
  
  // Operation success logging
  raise_log__(file, func, line,
    "ARENA RESET: Arena reset successfully (address: %p, capacity: %zu bytes)", 
    arena->begin, arena->capacity);
}

void arena_free__(POSITION_INFO_DECLARATION, Arena *arena) {
  // Function entry logging
  raise_debug__(file, func, line,
    "ARENA FREE: Releasing arena memory (address: %p)", arena);
  
  // Check for NULL arena
  if (!arena) {
    raise_warn__(file, func, line,
      "ARENA FREE: Attempted to free NULL arena");
    return;
  }
  
  // Check for NULL begin pointer
  if (!arena->begin) {
    raise_warn__(file, func, line,
      "ARENA FREE: Attempted to free arena with NULL memory block");
    return;
  }
  
  // Calculate used memory for logging
  size_t used = (size_t)arena->current - (size_t)arena->begin;
  
  // Free the memory
  arena_memory_free(arena->begin);
  
  // Success logging
  raise_log__(file, func, line,
    "ARENA FREE: Arena released successfully (address: %p, capacity: %zu bytes, used: %zu bytes)",
    arena->begin, arena->capacity, used);
    
  // Clear the pointers
  arena->begin = NULL;
  arena->current = NULL;
  arena->capacity = 0;
}

/* 
 * Duplicates a string and returns a pointer to the new string.
*/
char* arena_strdup__(POSITION_INFO_DECLARATION, Arena *arena, const char *s) {
    // Function entry logging
    raise_trace__(file, func, line,
        "ARENA STRDUP: Duplicating string (arena: %p, source: %p, preview: %.20s%s)",
        arena, s, s ? s : "", s && strlen(s) > 20 ? "..." : "");
    
    // Check for NULL string
    if (!s) {
        raise_debug__(file, func, line,
            "ARENA STRDUP: Source string is NULL, returning NULL");
        return NULL;
    }
    
    // Calculate string length and allocate memory
    size_t len = strlen(s) + 1;
    
    // Success case
    char *result = (char*)arena_alloc__(file, func, line, arena, len);
    
    // Copy the string
    memcpy(result, s, len);
    
    // Success logging
    raise_debug__(file, func, line,
        "ARENA STRDUP: String duplicated successfully (result: %p, length: %zu bytes)", 
        result, len);
    
    return result;
}

/*
 * Duplicates a string and returns a pointer to the new string.
 * The string is formatted using the provided format string and arguments.
 */
char* arena_strdup_fmt__(POSITION_INFO_DECLARATION, Arena *arena, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    int len = vsnprintf(NULL, 0, fmt, args);
    va_end(args);

    if (len < 0) return NULL;

    char *temp = arena_alloc__(file, func, line, DISPOSABLE_ARENA, len + 1);
    va_start(args, fmt);
    vsnprintf(temp, len + 1, fmt, args);
    va_end(args);

    return arena_strdup__(file, func, line, arena, temp);
}

char* arena_strncpy__(POSITION_INFO_DECLARATION, Arena *arena, const char *start, size_t len) {
    // Function entry logging
    raise_trace__(file, func, line,
        "ARENA STRNCPY: Copying string (arena: %p, source: %p, length: %zu, preview: %.20s%s)",
        arena, start, len, start ? start : "", start && strlen(start) > 20 ? "..." : "");
    
    // Check for NULL string
    if (!start) {
        raise_debug__(file, func, line,
            "ARENA STRNCPY: Source string is NULL, returning NULL");
        return NULL;
    }
    
    // Allocate memory for the string plus null terminator
    char *result = (char*)arena_alloc__(file, func, line, arena, len + 1);
    if (!result) {
        raise_debug__(file, func, line,
            "ARENA STRNCPY: Memory allocation failed");
        return NULL;
    }
    
    // Copy the string and ensure null termination
    strncpy(result, start, len);
    result[len] = '\0';
    
    // Success logging
    raise_debug__(file, func, line,
        "ARENA STRNCPY: String copied successfully (result: %p, length: %zu bytes)", 
        result, len + 1);
    
    return result;
}

/*
 * Replaces a substring in a string with a new string.
 */
char* arena_repstr__(POSITION_INFO_DECLARATION, Arena *arena,
                             const char *src, size_t start, size_t len, const char *rep) {
  // Function entry logging
  raise_trace__(file, func, line, 
    "ARENA REPSTR: Replacing substring (source: %p, start: %zu, length: %zu, replacement: %.20s%s)", 
    src, start, len, rep, strlen(rep) > 20 ? "..." : "");
  
  // Check inputs
  if (!src) {
    raise_warn__(file, func, line,
      "ARENA REPSTR: Source string is NULL");
    return NULL;
  }
  
  if (!rep) {
    raise_warn__(file, func, line,
      "ARENA REPSTR: Replacement string is NULL");
    return NULL;
  }
  
  // Calculate lengths
  int src_len = strlen(src);
  int rep_len = strlen(rep);
  
  // Validate start and length
  if (start > (size_t)src_len) {
    raise_warn__(file, func, line,
      "ARENA REPSTR: Start position %zu exceeds source length %d", start, src_len);
    // Return a copy of the source string
    return arena_strdup__(file, func, line, arena, src);
  }
  
  if (start + len > (size_t)src_len) {
    size_t old_len = len;
    len = src_len - start;
    raise_debug__(file, func, line,
      "ARENA REPSTR: Adjusted length from %zu to %zu to fit source bounds", old_len, len);
  }
  
  // Calculate new length and allocate memory
  int new_len = src_len - (int)len + rep_len;
  char *new_str = (char*)arena_alloc__(file, func, line, arena, new_len + 1);
  
  // Perform the replacement operation
  memcpy(new_str, src, start);
  memcpy(new_str + start, rep, rep_len);
  strcpy(new_str + start + rep_len, src + start + len);
  
  // Success logging
  raise_debug__(file, func, line,
    "ARENA REPSTR: Replacement complete (result: %p, new length: %d)", new_str, new_len);
  
  return new_str;
}

// ----------
// -- misc --
// ----------

void substr_clone__(POSITION_INFO_DECLARATION, const char * const src, char *dest, size_t from, size_t len) {
    // Log function entry at TRACE level
    raise_trace__(file, func, line,
        "Function called with src=%p, dest=%p, from=%zu, len=%zu",
        src, dest, from, len);

    if (!src || !dest) {
        raise_exception__(file, func, line,
            "Invalid NULL pointer: %s%s",
            (!src ? "src " : ""),
            (!dest ? "dest" : ""));
        if (dest) dest[0] = '\0';
        return;
    }

    size_t srclen = strlen(src);
    if (from >= srclen) {
        // Log warning with context when 'from' is out of range
        raise_warn__(file, func, line,
            "Out of range: 'from' index (%zu) exceeds source length (%zu)",
            from, srclen);
        dest[0] = '\0';
        return;
    }

    // Adjust length if needed
    if (from + len > srclen) {
        size_t old_len = len;
        len = srclen - from;
        raise_debug__(file, func, line,
            "Adjusted length from %zu to %zu to fit source bounds",
            old_len, len);
    }

    // Copy the substring
    strncpy(dest, src + from, len);
    dest[len] = '\0';

    // Log success at TRACE level
    raise_trace__(file, func, line,
        "Successfully copied %zu bytes: \"%.*s\"",
        len, (int)len, dest);
}

// ----------
// -- Json --
// ----------

char *json_to_pretty_str__(POSITION_INFO_DECLARATION, Arena *arena, const Json * const item, int indent_level) {
    raise_debug__(file, func, line, 
                  "PRETTY: Starting JSON prettification (item: %p, indent: %d)", 
                  item, indent_level);
    
    if (!item) {
        raise_exception__(file, func, line, 
                     "PRETTY: Invalid JSON object (NULL) provided for prettification");
        return NULL;
    }
    
    if (!arena) {
        raise_exception__(file, func, line,
                     "PRETTY: Invalid arena (NULL) provided for prettification");
        return NULL;
    }
    
    char *out = arena_alloc__(file, func, line, arena, 1024);
    if (!out) {
        raise_exception__(file, func, line, 
                     "PRETTY: Memory allocation failed during JSON prettification");
        return NULL;
    }
    
    char *ptr = out;
    
    if (item->type == JSON_OBJECT) {
        ptr += sprintf(ptr, "{\n");
        
        Json *child = item->value.child;
        int child_count = 0;
        
        raise_trace__(file, func, line, 
                      "PRETTY: Processing JSON object children");
        
        while (child) {
            for (int i = 0; i < indent_level + 1; i++) {
                ptr += sprintf(ptr, "  ");
            }
            
            ptr += sprintf(ptr, "\"%s\": ", child->key ? child->key : "");
            char *child_str = json_to_pretty_str__(file, func, line, arena, child, indent_level + 1);
            if (child_str) {
                ptr += sprintf(ptr, "%s", child_str);
            } else {
                raise_warn__(file, func, line, 
                              "PRETTY: Failed to prettify child element (key=%s)", 
                              child->key ? child->key : "<null>");
            }
            
            if (child->next) {
                ptr += sprintf(ptr, ",\n");
            } else {
                ptr += sprintf(ptr, "\n");
            }
            child = child->next;
            child_count++;
        }
        
        for (int i = 0; i < indent_level; i++) {
            ptr += sprintf(ptr, "  ");
        }
        sprintf(ptr, "}");
        raise_trace__(file, func, line, 
                      "PRETTY: Object prettification complete with %d child elements", child_count);
    } else if (item->type == JSON_ARRAY) {
        ptr += sprintf(ptr, "[\n");
        
        Json *child = item->value.child;
        int child_count = 0;
        
        raise_trace__(file, func, line, 
                      "PRETTY: Processing JSON array elements");
        
        while (child) {
            // Add indentation
            for (int i = 0; i < indent_level + 1; i++) {
                ptr += sprintf(ptr, "  ");
            }
            
            char *child_str = json_to_pretty_str__(file, func, line, arena, child, indent_level + 1);
            if (child_str) {
                ptr += sprintf(ptr, "%s", child_str);
            } else {
                raise_warn__(file, func, line, 
                              "PRETTY: Failed to prettify array element at index %d", child_count);
            }
            
            if (child->next) {
                ptr += sprintf(ptr, ",\n");
            } else {
                ptr += sprintf(ptr, "\n");
            }
            child = child->next;
            child_count++;
        }
        
        for (int i = 0; i < indent_level; i++) {
            ptr += sprintf(ptr, "  ");
        }
        sprintf(ptr, "]");
        raise_trace__(file, func, line, 
                      "PRETTY: Array prettification complete with %d elements", child_count);
    } else if (item->type == JSON_STRING) {
        sprintf(ptr, "\"%s\"", item->value.string ? item->value.string : "");
    } else if (item->type == JSON_NUMBER) {
        sprintf(ptr, "%g", item->value.number);
    } else if (item->type == JSON_BOOL) {
        sprintf(ptr, item->value.boolean ? "true" : "false");
    } else if (item->type == JSON_NULL) {
        sprintf(ptr, "null");
    }
    
    raise_log__(file, func, line, 
                  "PRETTY: JSON %s prettified (length=%zu)", 
                  json_type_to_string(item->type), strlen(out));
    
    return out;
}

const char* json_type_to_string(JsonType type) {
    switch (type) {
        case JSON_NULL: return "NULL";
        case JSON_BOOL: return "BOOL";
        case JSON_NUMBER: return "NUMBER";
        case JSON_STRING: return "STRING";
        case JSON_ARRAY: return "ARRAY";
        case JSON_OBJECT: return "OBJECT";
        default: return "UNKNOWN";
    }
}

static Json *json_parse_value__(POSITION_INFO_DECLARATION, const char **s, Arena *arena);

/* Parse a JSON string (does not handle full escaping) */
static char *json_parse_string__(POSITION_INFO_DECLARATION, const char **s_ptr, Arena *arena) {
    const char *s = *s_ptr;
    raise_debug__(file, func, line, "Entering json_parse_string__ at position: %p", s);
    if (*s != '"') {
        raise_debug__(file, func, line, "Expected '\"' at start of string, got: %c", *s);
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
        raise_debug__(file, func, line, "Unterminated string starting at: %p", start);
        return NULL;
    }
    size_t len = s - start;
    char *str = arena_alloc__(file, func, line, arena, len + 1);
    if (!str) {
        raise_debug__(file, func, line, "Memory allocation failed in json_parse_string__");
        return NULL;
    }
    memcpy(str, start, len);
    str[len] = '\0';
    *s_ptr = s + 1; // skip closing quote
    raise_debug__(file, func, line, "Parsed string: \"%s\" (length: %zu)", str, len);
    return str;
}

/* Parse a number using strtod */
static double json_parse_number__(POSITION_INFO_DECLARATION, const char **s_ptr) {
    raise_debug__(file, func, line, "Parsing number at position: %p", *s_ptr);
    char *end;
    double num = strtod(*s_ptr, &end);
    if (*s_ptr == end)
        raise_debug__(file, func, line, "No valid number found at: %p", *s_ptr);
    *s_ptr = end;
    raise_debug__(file, func, line, "Parsed number: %g", num);
    return num;
}

/* Parse a JSON array: [ value, value, ... ] */
static Json *json_parse_array__(POSITION_INFO_DECLARATION, const char **s, Arena *arena) {
    raise_debug__(file, func, line, "Entering json_parse_array__ at position: %p", *s);
    if (**s != '[') return NULL;
    (*s)++; // skip '['
    *s = skip_whitespace(*s);
    Json *array = arena_alloc__(file, func, line, arena, sizeof(Json));
    if (!array) {
        raise_debug__(file, func, line, "Memory allocation failed in json_parse_array__");
        return NULL;
    }
    memset(array, 0, sizeof(Json));
    array->type = JSON_ARRAY;
    Json *last = NULL;
    if (**s == ']') { // empty array
        (*s)++;
        raise_debug__(file, func, line, "Parsed empty array");
        return array;
    }
    while (**s) {
        Json *element = json_parse_value__(file, func, line, s, arena);
        if (!element) {
            raise_debug__(file, func, line, "Failed to parse array element");
            return NULL;
        }
        if (!array->value.child)
            array->value.child = element;
        else
            last->next = element;
        last = element;
        *s = skip_whitespace(*s);
        if (**s == ',') {
            (*s)++;
            *s = skip_whitespace(*s);
        } else if (**s == ']') {
            (*s)++;
            raise_debug__(file, func, line, "Completed parsing array");
            break;
        } else {
            raise_debug__(file, func, line, "Unexpected character '%c' in array", **s);
            return NULL;
        }
    }
    raise_debug__(file, func, line, "Completed parsing array");
    return array;
}

/* Parse a JSON object: { "key": value, ... } */
static Json *json_parse_object__(POSITION_INFO_DECLARATION, const char **s, Arena *arena) {
    raise_debug__(file, func, line, "Entering json_parse_object__ at position: %p", *s);
    if (**s != '{') return NULL;
    (*s)++; // skip '{'
    *s = skip_whitespace(*s);
    Json *object = arena_alloc__(file, func, line, arena, sizeof(Json));
    if (!object) {
        raise_debug__(file, func, line, "Memory allocation failed in json_parse_object__");
        return NULL;
    }
    memset(object, 0, sizeof(Json));
    object->type = JSON_OBJECT;
    Json *last = NULL;
    if (**s == '}') {
        (*s)++;
        raise_debug__(file, func, line, "Parsed empty object");
        return object;
    }
    while (**s) {
        char *key = json_parse_string__(file, func, line, s, arena);
        if (!key) {
            raise_debug__(file, func, line, "Failed to parse key in object");
            return NULL;
        }
        *s = skip_whitespace(*s);
        if (**s != ':') {
            raise_debug__(file, func, line, "Expected ':' after key \"%s\", got: %c", key, **s);
            return NULL;
        }
        (*s)++; // skip ':'
        *s = skip_whitespace(*s);
        Json *value = json_parse_value__(file, func, line, s, arena);
        if (!value) {
            raise_debug__(file, func, line, "Failed to parse value for key \"%s\"", key);
            return NULL;
        }
        value->key = key; // assign key to the value
        if (!object->value.child)
            object->value.child = value;
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
            raise_debug__(file, func, line, "Unexpected character '%c' in object", **s);
            return NULL;
        }
    }
    raise_debug__(file, func, line, "Completed parsing object");
    return object;
}

/* Full JSON value parser */
static Json *json_parse_value__(POSITION_INFO_DECLARATION, const char **s, Arena *arena) {
    *s = skip_whitespace(*s);
    raise_debug__(file, func, line, "Parsing JSON value at position: %p", *s);
    if (**s == '"') {
        Json *item = arena_alloc__(file, func, line, arena, sizeof(Json));
        if (!item) {
            raise_debug__(file, func, line, "Memory allocation failed in json_parse_value for string");
            return NULL;
        }
        memset(item, 0, sizeof(Json));
        item->type = JSON_STRING;
        item->value.string = json_parse_string__(file, func, line, s, arena);
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
        item->value.boolean = 1;
        *s += 4;
        return item;
    } else if (strncmp(*s, "false", 5) == 0) {
        Json *item = arena_alloc__(file, func, line, arena, sizeof(Json));
        if (!item) return NULL;
        memset(item, 0, sizeof(Json));
        item->type = JSON_BOOL;
        item->value.boolean = 0;
        *s += 5;
        return item;
    } else if ((**s == '-') || isdigit((unsigned char)**s)) {
        Json *item = arena_alloc__(file, func, line, arena, sizeof(Json));
        if (!item) {
            raise_debug__(file, func, line, "Memory allocation failed in json_parse_value for number");
            return NULL;
        }
        memset(item, 0, sizeof(Json));
        item->type = JSON_NUMBER;
        item->value.number = json_parse_number__(file, func, line, s);
        return item;
    } else if (**s == '[') {
        return json_parse_array__(file, func, line, s, arena);
    } else if (**s == '{') {
        return json_parse_object__(file, func, line, s, arena);
    }
    raise_debug__(file, func, line, "Unrecognized JSON value at position: %p", *s);
    return NULL;
}

// FIXME(yukkop): **s changes in the function. Need to fix.
Json *json_parse__(POSITION_INFO_DECLARATION, Arena *arena, const char **s) {
    // Function entry logging with DEBUG level
    raise_debug__(file, func, line, 
        "PARSE: Starting JSON parsing (input: %p)", *s);
    
    // Check input parameters
    if (!s || !*s) {
        raise_exception__(file, func, line,
            "PARSE: Invalid input parameters (NULL pointer provided for JSON parsing)");
        return NULL;
    }
    
    if (!arena) {
        raise_exception__(file, func, line,
            "PARSE: Invalid arena (NULL) provided for JSON parsing");
        return NULL;
    }
    
    // Show input preview for debugging with TRACE level
    raise_trace__(file, func, line,
        "PARSE: Input preview: '%.20s%s'", *s, strlen(*s) > 20 ? "..." : "");
    
    // Process JSON value
    Json *result = json_parse_value__(file, func, line, s, arena);
    
    // Log parsing result
    if (!result) {
        raise_warn__(file, func, line, 
            "PARSE: Failed to parse JSON at position %p (context: '%.10s')", 
            *s, *s && strlen(*s) > 0 ? *s : "<empty>");
    } else {
        raise_log__(file, func, line, 
            "PARSE: JSON parsing completed successfully (type: %s)", json_type_to_string(result->type));
    }
    
    return result;
}

char *json_to_str__(POSITION_INFO_DECLARATION, Arena *arena, const Json * const item) {
    return json_to_str_with_opts__(file, func, line, arena, item, JSON_NORAW);
}

/* Minimal JSON printer with raw output option.
   When raw is non-zero and the item is a JSON_STRING, it is printed without quotes.
*/
char *json_to_str_with_opts__(POSITION_INFO_DECLARATION, Arena *arena, const Json * const item, JsonRawOpt raw) {
    // Function entry with DEBUG level
    raise_debug__(file, func, line, 
                  "FORMAT: Starting JSON conversion to string (item: %p, raw_mode: %s)", 
                  item, raw == JSON_RAW ? "enabled" : "disabled");
    
    // Check input parameters
    if (!item) {
        raise_exception__(file, func, line, 
                     "FORMAT: Invalid JSON object (NULL) provided for string conversion");
        return NULL;
    }
    
    if (!arena) {
        raise_exception__(file, func, line,
                     "FORMAT: Invalid arena (NULL) provided for string conversion");
        return NULL;
    }
    
    // Allocate memory for the string
    char *out = arena_alloc__(file, func, line, arena, 1024);
    if (!out) {
        raise_exception__(file, func, line, 
                     "FORMAT: Memory allocation failed during JSON string conversion");
        return NULL;
    }
    
    char *ptr = out;
    const char* type_name = "unknown";
    
    // Formatting based on type
    if (item->type == JSON_OBJECT) {
        ptr += sprintf(ptr, "{");
        type_name = "object";
        
        Json *child = item->value.child;
        int child_count = 0;
        
        raise_trace__(file, func, line, 
                      "FORMAT: Processing JSON object children");
        
        while (child) {
            ptr += sprintf(ptr, "\"%s\":", child->key ? child->key : "");
            char *child_str = json_to_str_with_opts__(file, func, line, arena, child, raw);
            if (child_str) {
                ptr += sprintf(ptr, "%s", child_str);
            } else {
                raise_warn__(file, func, line, 
                              "FORMAT: Failed to stringify child element (key=%s)", 
                              child->key ? child->key : "<null>");
            }
            
            if (child->next) {
                ptr += sprintf(ptr, ",");
            }
            child = child->next;
            child_count++;
        }
        
        sprintf(ptr, "}");
        raise_trace__(file, func, line, 
                      "FORMAT: Object conversion complete with %d child elements", child_count);
    } else if (item->type == JSON_ARRAY) {
        ptr += sprintf(ptr, "[");
        type_name = "array";
        
        Json *child = item->value.child;
        int child_count = 0;
        
        raise_trace__(file, func, line, 
                      "FORMAT: Processing JSON array elements");
        
        while (child) {
            char *child_str = json_to_str_with_opts__(file, func, line, arena, child, raw);
            if (child_str) {
                ptr += sprintf(ptr, "%s", child_str);
            } else {
                raise_warn__(file, func, line, 
                              "FORMAT: Failed to stringify array element at index %d", child_count);
            }
            
            if (child->next) {
                ptr += sprintf(ptr, ",");
            }
            child = child->next;
            child_count++;
        }
        
        sprintf(ptr, "]");
        raise_trace__(file, func, line, 
                      "FORMAT: Array conversion complete with %d elements", child_count);
    } else if (item->type == JSON_STRING) {
        type_name = "string";
        if ((int)raw) {
            sprintf(ptr, "%s", item->value.string ? item->value.string : "");
        } else {
            sprintf(ptr, "\"%s\"", item->value.string ? item->value.string : "");
        }
    } else if (item->type == JSON_NUMBER) {
        type_name = "number";
        sprintf(ptr, "%g", item->value.number);
    } else if (item->type == JSON_BOOL) {
        type_name = "boolean";
        sprintf(ptr, item->value.boolean ? "true" : "false");
    } else if (item->type == JSON_NULL) {
        type_name = "null";
        sprintf(ptr, "null");
    }
    
    raise_log__(file, func, line, 
                  "FORMAT: JSON %s converted to string (length=%zu)", 
                  type_name, strlen(out));
    
    return out;
}

/* Retrieve an object item by key (case-sensitive) */
Json *json_get_object_item__(POSITION_INFO_DECLARATION, const Json * const object, const char * const key) {
    raise_trace__(file, func, line, 
                 "ACCESS: Searching for key \"%s\" in JSON object %p", 
                 key ? key : "<null>", object);
    
    // Check input parameters
    if (!object) {
        raise_warn__(file, func, line, 
                     "ACCESS: Invalid object (NULL) passed to json_get_object_item");
        return NULL;
    }
    
    if (!key) {
        raise_warn__(file, func, line, 
                     "ACCESS: Invalid key (NULL) passed to json_get_object_item");
        return NULL;
    }
    
    if (object->type != JSON_OBJECT) {
        raise_warn__(file, func, line, 
                     "ACCESS: JSON value is not an object (actual type: %d)", object->type);
        return NULL;
    }
    
    // Count the total number of keys for debugging
    int total_keys = 0;
    Json *debug_scan = object->value.child;
    while (debug_scan) {
        total_keys++;
        debug_scan = debug_scan->next;
    }
    
    raise_trace__(file, func, line, 
                 "ACCESS: Object has %d key-value pairs", total_keys);
    
    // Perform key search
    Json *child = object->value.child;
    int position = 0;
    
    while (child) {
        if (child->key) {
            raise_trace__(file, func, line, 
                         "ACCESS: Comparing key \"%s\" with \"%s\" at position %d", 
                         child->key, key, position);
            
            if (strcmp(child->key, key) == 0) {
                raise_log__(file, func, line, 
                             "ACCESS: Found value for key \"%s\" (type: %s)", 
                             key, json_type_to_string(child->type));
                return child;
            }
        } else {
            raise_trace__(file, func, line, 
                         "ACCESS: Skipping element at position %d with NULL key", position);
        }
        
        child = child->next;
        position++;
    }
    
    raise_debug__(file, func, line, 
                 "ACCESS: Key \"%s\" not found in object (checked %d items)", 
                 key, position);
    return NULL;
}

char *json_value_to_debug_str__(POSITION_INFO_DECLARATION, Arena *arena, const char *name, const JsonValue *self, JsonType active_variant, PtrSet *visited) {
    char *child_str = json_to_debug_str__(file, func, line, arena, "child", self->child, visited);
    char *result = arena_alloc__(file, func, line, arena, 1024);
    UNION_TO_DEBUG_STR(arena, result, JsonValue, name, self, visited, active_variant, 5,
        JSON_STRING, string_to_debug_str__(file, func, line, arena, "string", self->string),
        JSON_NUMBER, float_to_debug_str__(file, func, line, arena, "number", self->number),
        JSON_BOOL, bool_to_debug_str__(file, func, line, arena, "boolean", self->boolean),
        JSON_OBJECT, child_str,
        JSON_ARRAY, child_str
    );
    return result;
}

char* json_to_debug_str__(POSITION_INFO_DECLARATION, Arena *arena, const char *name, const Json *self, PtrSet *visited) {
  raise_trace__(file, func, line, "json_to_debug_str(<optimized>, <optimized>)");

  char *result = arena_alloc__(file, func, line, arena, 1024);
  STRUCT_TO_DEBUG_STR(arena, result, Json, name, self, visited, 3,
    enum_to_debug_str__(file, func, line, arena, "type", self->type, json_type_to_string(self->type)),
    string_to_debug_str__(file, func, line, arena, "key", self->key),
    json_value_to_debug_str__(file, func, line, arena, "value", &self->value, self->type, visited),
    json_to_debug_str__(file, func, line, arena, "next", self->next, visited)
  );
  return result;
}

JsonResult debug_str_to_json__(POSITION_INFO_DECLARATION, Arena *arena, const char **s) {
    raise_trace__(file, func, line, "DEBUG STR TO JSON: debug_str: %s", *s);

    // Remove the unused 'start' variable
    Json *json = arena_alloc__(file, func, line, arena, sizeof(Json));
    memset(json, 0, sizeof(Json));

    // Extract the name/key
    const char *equal_sign = strstr(*s, "=");
    if (!equal_sign) {
        raise_exception__(file, func, line, "DEBUG STR TO JSON: no equal sign found");
        return RESULT_ERROR(JsonResult, DEBUG_TO_JSON_PARSE_NO_EQUAL_SIGN_ERROR, "No equal sign found");
    }

    Slice full_name = slice_create__(file, func, line, 1, *s, strlen(*s), 0, equal_sign - *s);
    if (full_name.len == 0) {
        raise_exception__(file, func, line, "DEBUG STR TO JSON: no name found");
        return RESULT_ERROR(JsonResult, DEBUG_TO_JSON_PARSE_LEFT_OPERAND_ERROR, "No left operand found");
    }

    // Move past the equal sign
    *s = skip_whitespace(equal_sign + 1);

    // Check for struct, union, enum, or other types
    const char *name_str = full_name.data;
    name_str = skip_whitespace(name_str);

    if (strncmp(name_str, "struct ", 7) == 0) {
        // Handle struct
        json->type = JSON_OBJECT;
        
        // Extract struct type and name
        name_str += 7; // Skip "struct "
        const char *space = strchr(name_str, ' ');
        
        if (!space) {
            raise_exception__(file, func, line, "DEBUG STR TO JSON: missing struct name");
            return RESULT_ERROR(JsonResult, DEBUG_TO_JSON_PARSE_NO_STRUCT_NAME_ERROR, "Struct without name");
        }
        
        // Extract type (between "struct " and space)
        
        // Extract name (after space, before any other character)
        name_str = skip_whitespace(space + 1);
        const char *name_end = name_str;
        while (*name_end && !isspace(*name_end) && *name_end != '{') name_end++;
        
        if (name_end == name_str) {
            raise_exception__(file, func, line, "DEBUG STR TO JSON: missing struct variable name");
            return RESULT_ERROR(JsonResult, DEBUG_TO_JSON_PARSE_NO_STRUCT_NAME_ERROR, "Struct without variable name");
        }
        
        size_t name_len = name_end - name_str;
        json->key = arena_strncpy__(file, func, line, arena, name_str, name_len);
        
        // Find struct body
        const char *body_start = strchr(name_end, '{');
        if (!body_start) {
            raise_exception__(file, func, line, "DEBUG STR TO JSON: no start found for struct");
            return RESULT_ERROR(JsonResult, DEBUG_TO_JSON_PARSE_NO_START_ERROR, "Struct without start");
        }
        
        const char *body_end = strrchr(body_start, '}');
        if (!body_end) {
            raise_exception__(file, func, line, "DEBUG STR TO JSON: no end found for struct");
            return RESULT_ERROR(JsonResult, DEBUG_TO_JSON_PARSE_NO_END_ERROR, "Struct without end");
        }
        
        // Move pointer past the struct
        *s = body_end + 1;
        
        // TODO: Parse struct fields
        // For now, we're just creating an empty object
    } 
    else if (strncmp(name_str, "union ", 6) == 0) {
        // Handle union
        json->type = JSON_OBJECT;
        
        // Extract union name
        name_str += 6; // Skip "union "
        const char *space = strchr(name_str, ' ');
        
        if (!space) {
            raise_exception__(file, func, line, "DEBUG STR TO JSON: missing union name");
            return RESULT_ERROR(JsonResult, DEBUG_TO_JSON_PARSE_NO_STRUCT_NAME_ERROR, "Union without name");
        }
        
        // Extract type (between "union " and space)
        
        // Extract name (after space, before any other character)
        name_str = skip_whitespace(space + 1);
        const char *name_end = name_str;
        while (*name_end && !isspace(*name_end) && *name_end != '{') name_end++;
        
        size_t name_len = name_end - name_str;
        json->key = arena_strncpy__(file, func, line, arena, name_str, name_len);
        
        // Find body
        const char *body_start = strchr(name_end, '{');
        if (!body_start) {
            raise_exception__(file, func, line, "DEBUG STR TO JSON: no start found for union");
            return RESULT_ERROR(JsonResult, DEBUG_TO_JSON_PARSE_NO_START_ERROR, "Union without start");
        }
        
        const char *body_end = strrchr(body_start, '}');
        if (!body_end) {
            raise_exception__(file, func, line, "DEBUG STR TO JSON: no end found for union");
            return RESULT_ERROR(JsonResult, DEBUG_TO_JSON_PARSE_NO_END_ERROR, "Union without end");
        }
        
        // Move pointer past the union
        *s = body_end + 1;
        
        // TODO: Parse union variant
        // For now, we're just creating an empty object
    }
    else if (strncmp(name_str, "enum ", 5) == 0) {
        // Handle enum
        json->type = JSON_STRING;
        
        // Find enum value (typically at the end)
        const char *value_start = strrchr(*s, ' ');
        if (!value_start) {
            raise_exception__(file, func, line, "DEBUG STR TO JSON: missing enum value");
            return RESULT_ERROR(JsonResult, DEBUG_TO_JSON_PARSE_LEFT_OPERAND_ERROR, "Invalid enum format");
        }
        
        // Extract name
        name_str += 5; // Skip "enum "
        const char *space = strchr(name_str, ' ');
        
        if (space) {
            size_t name_len = space - name_str;
            json->key = arena_strncpy__(file, func, line, arena, name_str, name_len);
        }
        
        // Extract value as string
        value_start = skip_whitespace(value_start + 1);
        json->value.string = arena_strdup__(file, func, line, arena, value_start);
        
        // Move pointer to the end
        *s += strlen(*s);
    }
    else if (strchr(name_str, '[') && strchr(name_str, ']')) {
        // Handle array
        json->type = JSON_ARRAY;
        
        // Extract array name
        const char *bracket = strchr(name_str, '[');
        if (bracket > name_str) {
            const char *name_end = bracket;
            while (name_end > name_str && isspace(*(name_end-1))) name_end--;
            
            size_t name_len = name_end - name_str;
            json->key = arena_strncpy__(file, func, line, arena, name_str, name_len);
        }
        
        // Find array body
        const char *body_start = strchr(*s, '[');
        if (!body_start) {
            raise_exception__(file, func, line, "DEBUG STR TO JSON: no start found for array");
            return RESULT_ERROR(JsonResult, DEBUG_TO_JSON_PARSE_NO_START_ERROR, "Array without start");
        }
        
        const char *body_end = strrchr(body_start, ']');
        if (!body_end) {
            raise_exception__(file, func, line, "DEBUG STR TO JSON: no end found for array");
            return RESULT_ERROR(JsonResult, DEBUG_TO_JSON_PARSE_NO_END_ERROR, "Array without end");
        }
        
        // Move pointer past the array
        *s = body_end + 1;
        
        // TODO: Parse array elements
        // For now, we're just creating an empty array
    }
    else {
        // Try to determine value type (string, number, bool, null)
        const char *value = *s;
        
        if (strncmp(value, "NULL", 4) == 0 || strncmp(value, "null", 4) == 0) {
            json->type = JSON_NULL;
            *s += 4;
        }
        else if (strncmp(value, "true", 4) == 0) {
            json->type = JSON_BOOL;
            json->value.boolean = true;
            *s += 4;
        }
        else if (strncmp(value, "false", 5) == 0) {
            json->type = JSON_BOOL;
            json->value.boolean = false;
            *s += 5;
        }
        else if (*value == '"') {
            // String value
            json->type = JSON_STRING;
            value++; // Skip opening quote
            
            const char *end_quote = strchr(value, '"');
            if (!end_quote) {
                raise_exception__(file, func, line, "DEBUG STR TO JSON: unterminated string");
                return RESULT_ERROR(JsonResult, DEBUG_TO_JSON_PARSE_LEFT_OPERAND_ERROR, "Unterminated string");
            }
            
            size_t str_len = end_quote - value;
            json->value.string = arena_strncpy__(file, func, line, arena, value, str_len);
            *s = end_quote + 1;
        }
        else if (isdigit(*value) || *value == '-' || *value == '+') {
            // Numeric value
            json->type = JSON_NUMBER;
            
            // Use strtod to parse the number
            char *end;
            json->value.number = strtod(value, &end);
            *s = end;
        }
        else {
            // Default to string for unknown types
            json->type = JSON_STRING;
            
            // Find the end of the value (space, comma, etc.)
            const char *end = value;
            while (*end && !isspace(*end) && *end != ',' && *end != '}' && *end != ']') end++;
            
            size_t str_len = end - value;
            json->value.string = arena_strncpy__(file, func, line, arena, value, str_len);
            *s = end;
        }
        
        // Extract name for simple types
        const char *name_end = name_str;
        while (*name_end && !isspace(*name_end) && *name_end != '=') name_end++;
        
        size_t name_len = name_end - name_str;
        json->key = arena_strncpy__(file, func, line, arena, name_str, name_len);
    }

    return RESULT_SOME(JsonResult, *json);
}

// -----------
// -- slice --
// -----------

// Create a slice from an array with boundary check.
Slice slice_create__(POSITION_INFO_DECLARATION, size_t isize, const void *array, size_t array_len, size_t start, size_t len) {
    // Function entry logging
    raise_trace__(file, func, line, 
        "SLICE: Creating slice (source: %p, array_length: %zu, start: %zu, length: %zu, item_size: %zu)", 
        array, array_len, start, len, isize);
    
    // Boundary check
    if (start + len > array_len) {
        raise_warn__(file, func, line,
            "SLICE: Slice boundaries exceed array length (start: %zu, length: %zu, array_length: %zu)",
            start, len, array_len);
        return (Slice){NULL, 0, isize};
    }
    
    // Create valid slice
    Slice result = (Slice){ (char *)array + start * isize, len, isize };
    
    // Success logging
    raise_trace__(file, func, line,
        "SLICE: Slice created successfully (data: %p, length: %zu, item_size: %zu)",
        result.data, result.len, result.isize);
    
    return result;
}

// Return a subslice from an existing slice.
Slice slice_subslice__(POSITION_INFO_DECLARATION, Slice s, size_t start, size_t len) {
    // Function entry logging
    raise_trace__(file, func, line, 
        "SLICE: Creating subslice (source: %p, source_length: %zu, start: %zu, length: %zu)", 
        s.data, s.len, start, len);
    
    // Boundary check
    if (start + len > s.len) {
        raise_warn__(file, func, line,
            "SLICE: Subslice boundaries exceed source slice length (start: %zu, length: %zu, source_length: %zu)",
            start, len, s.len);
        return (Slice){NULL, 0, s.isize};
    }
    
    // Create valid subslice
    Slice result = (Slice){(char*)s.data + start * s.isize, len, s.isize};
    
    // Success logging
    raise_trace__(file, func, line,
        "SLICE: Subslice created successfully (data: %p, length: %zu, item_size: %zu)",
        result.data, result.len, result.isize);
    
    return result;
}

int* arena_slice_copy__(POSITION_INFO_DECLARATION, Arena *arena, Slice s) {
    raise_trace__(file, func, line, "arena_slice_copy(<optimized>, <optimized>)");
    int *copy = (void*) arena_alloc__(file, func, line, arena, s.len * sizeof(int));
    if (copy)
        memcpy(copy, s.data, s.len * s.isize);
    return copy;
}

char* slice_to_debug_str__(POSITION_INFO_DECLARATION, Arena *arena, Slice slice) {
  // Create complete information about the Slice structure
  char buffer_meta[128];
  snprintf(buffer_meta, sizeof(buffer_meta), "Slice{addr=%p, data=%p, len=%zu, isize=%zu, content=",
           (void*)&slice, slice.data, slice.len, slice.isize);
  
  size_t meta_len = strlen(buffer_meta);
  
  // For NULL data, output a simple message
  if (!slice.data) {
    char* result = arena_alloc(arena, meta_len + 6);
    strcpy(result, buffer_meta);
    strcat(result, "NULL}");
    return result;
  }
  
  // Allocate buffer with space for quotes, metadata and null terminator
  size_t buffer_size = meta_len + slice.len * 4 + 20; // Extra space for escaping and closing brace
  char* buffer = arena_alloc(arena, buffer_size);
  
  // Copy metadata
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
  *pos++ = '}'; // Closing brace for the structure
  *pos = '\0';

  raise_trace__(file, func, line, "slice_to_debug_str: %s", buffer);
  
  return buffer;
}

/*
 * Construct a new log rule
 */
LogRuleResult log_rule_init(Arena *arena, LogLevel level, const char *file_pattern, const char *function_pattern, int line_start, int line_end) {
    LogRule *rule = arena_alloc__(__FILE__, __func__, __LINE__, arena, sizeof(LogRule));
    if (!rule) return RESULT_ERROR(LogRuleResult, LOGGER_ERROR_OUT_OF_MEMORY, "Out of memory");
    
    rule->level = level;
    rule->file_pattern = file_pattern ? arena_strdup__(__FILE__, __func__, __LINE__, arena, file_pattern) : NULL;
    rule->function_pattern = function_pattern ? arena_strdup__(__FILE__, __func__, __LINE__, arena, function_pattern) : NULL;
    rule->line_start = line_start;
    rule->line_end = line_end;
    rule->next = NULL;
    
    return RESULT_SOME(LogRuleResult, *rule);
}

// Parse a line range specification (start:end)
void parse_line_range(const char *range_str, int *start, int *end) {
    if (!range_str) {
        *start = -1;
        *end = -1;
        return;
    }
    
    char *endptr;
    *start = strtol(range_str, &endptr, 10);
    
    if (*endptr == ':') {
        *end = strtol(endptr + 1, NULL, 10);
    } else {
        *end = *start;
    }
    
    if (*start <= 0) *start = -1;
    if (*end <= 0) *end = -1;
}

// Parse a complex rule string and set up log rules
LogRuleResult logger_parse_rules__(CTX_DECLARATION, const char *rules_str) {
    if (!rules_str || !*rules_str) return RESULT_ERROR(LogRuleResult, LOGGER_ERROR_INVALID_RULES_STRING, "Invalid rules string");
    
    // Make a copy of the rules string since we'll be modifying it
    char *rules_copy = arena_strdup__(CTX(arena), rules_str);
    if (!rules_copy) return RESULT_ERROR(LogRuleResult, LOGGER_ERROR_OUT_OF_MEMORY, "Out of memory");

    // Initialize the rules list
    LogRule *rules = NULL;
    LogRule **current = &rules;
    
    // First rule sets the default level
    char *next_rule = rules_copy;
    char *token = strsep(&next_rule, ",");
    current_log_level = log_level_from_string(token);
    
    // Process the remaining rules
    while (next_rule && *next_rule) {
        // Extract rule definition: pattern=level
        char *rule_def = strsep(&next_rule, ",");
        char *level_str = strchr(rule_def, '=');
        
        if (!level_str) continue; // Invalid rule
        
        *level_str = '\0'; // Split pattern and level
        level_str++;
        
        // Parse the rule pattern
        char *pattern = rule_def;
        char *file_pattern = NULL;
        char *function_pattern = NULL;
        char *line_range = NULL;
        
        // Check for line range in file pattern
        char *at_sign = strchr(pattern, '@');
        if (at_sign) {
            *at_sign = '\0';
            file_pattern = pattern;
            pattern = at_sign + 1;
            
            // Check for line range or another @ for function
            char *colon = strchr(pattern, ':');
            char *second_at = strchr(pattern, '@');
            
            if (second_at && (!colon || second_at < colon)) {
                // Format: file@function@line_range
                *second_at = '\0';
                function_pattern = pattern;
                line_range = second_at + 1;
            } else if (colon) {
                // Format: file@line_range
                line_range = pattern;
            } else {
                // Format: file@function
                function_pattern = pattern;
            }
        } else {
            // Just file pattern
            file_pattern = pattern;
        }
        
        // If file pattern is empty, set to NULL
        if (file_pattern && !*file_pattern) file_pattern = NULL;
        
        // If function pattern is empty, set to NULL
        if (function_pattern && !*function_pattern) function_pattern = NULL;
        
        // Parse line range
        int line_start = -1, line_end = -1;
        parse_line_range(line_range, &line_start, &line_end);
        
        // Create a new rule
        LogLevel level = log_level_from_string(level_str);
        LogRuleResult rule_result = log_rule_init(arena, level, file_pattern, function_pattern, line_start, line_end);
        
        if (IS_RESULT_ERROR(rule_result)) {
            free(rules_copy);
            return rule_result;
        }
        
        // Add the rule to the list
        *current = arena_alloc__(CTX(arena), sizeof(LogRule));
        if (!*current) {
            free(rules_copy);
            return RESULT_ERROR(LogRuleResult, LOGGER_ERROR_OUT_OF_MEMORY, "Out of memory");
        }
        
        **current = RESULT_SOME_VALUE(rule_result);
        current = &(*current)->next;
    }
    
    return RESULT_SOME(LogRuleResult, *rules);
}

// Check if a file matches a pattern
static int match_file_pattern(const char *file, const char *pattern) {
    if (!pattern) return 1; // NULL pattern matches any file
    
    // Extract the filename part without the path
    const char *filename = strrchr(file, '/');
    if (!filename) filename = file;
    else filename++; // Skip the '/'
    
    return fnmatch(pattern, filename, 0) == 0 || fnmatch(pattern, file, 0) == 0;
}

// Check if a function matches a pattern
static int match_function_pattern(const char *func, const char *pattern) {
    if (!pattern) return 1; // NULL pattern matches any function
    return fnmatch(pattern, func, 0) == 0;
}

// Get the effective log level for a specific context
LogLevel logger_get_effective_level(const char *file, const char *func, int line) {
    // If no rules are defined, use the global level
    if (!log_rules) return current_log_level;
    
    // Default to the global log level
    LogLevel effective_level = current_log_level;
    
    // Check each rule in order
    for (LogRule *rule = log_rules; rule; rule = rule->next) {
        int file_match = match_file_pattern(file, rule->file_pattern);
        int function_match = match_function_pattern(func, rule->function_pattern);
        int line_match = (rule->line_start == -1 || (line >= rule->line_start && 
                         (rule->line_end == -1 || line <= rule->line_end)));
        
        // If all conditions match, use this rule's level
        if (file_match && function_match && line_match) {
            effective_level = rule->level;
            // Don't break here - later rules can override earlier ones
        }
    }
    
    return effective_level;
}

// Add a new log rule programmatically
HecticError logger_add_rule(Arena *arena, LogRule *rules, LogLevel level, const char *file_pattern, const char *function_pattern, int line_start, int line_end) {
    LogRuleResult init_result = log_rule_init(arena, level, file_pattern, function_pattern, line_start, line_end);
    if (IS_RESULT_ERROR(init_result)) {
        return RESULT_ERROR_VALUE(init_result);
    }
    if (!rules) {
        *rules = RESULT_SOME_VALUE(init_result);
    } else {
        LogRule *last = rules;
        while (last->next) {
            last = last->next;
        }
        *last->next = RESULT_SOME_VALUE(init_result);
    }
    return (HecticError){ .code = HECTIC_ERROR_NONE, .message = NULL };
}

// Print all current logging rules to stderr
void logger_print_rules() {
    fprintf(stderr, "Current logging rules:\n");
    fprintf(stderr, "  Default level: %s\n", log_level_to_string(current_log_level));
    
    int rule_count = 0;
    for (LogRule *rule = log_rules; rule; rule = rule->next) {
        fprintf(stderr, "  Rule %d: Level=%s, File=%s, Function=%s, Lines=%d:%d\n",
                ++rule_count,
                log_level_to_string(rule->level),
                rule->file_pattern ? rule->file_pattern : "<any>",
                rule->function_pattern ? rule->function_pattern : "<any>",
                rule->line_start, rule->line_end);
    }
    
    if (rule_count == 0) {
        fprintf(stderr, "  No specific rules defined\n");
    }
}

char *log_rules_to_debug_str__(CTX_DECLARATION, char *name, LogRule *self, PtrSet *visited) {
    char *result = arena_alloc(arena, MEM_KiB);
    STRUCT_TO_DEBUG_STR(arena, result, LogRule, name, self, visited, 6,
      enum_to_debug_str__(file, func, line, arena, "level", self->level, log_level_to_string(self->level)),
      string_to_debug_str__(file, func, line, arena, "file_pattern", self->file_pattern),
      string_to_debug_str__(file, func, line, arena, "function_pattern", self->function_pattern),
      int_to_debug_str__(file, func, line, arena, "line_start", self->line_start),
      int_to_debug_str__(file, func, line, arena, "line_end", self->line_end),
      log_rules_to_debug_str__(file, func, line, arena, "next", self->next, visited)
    );
    return result;
}

// ----------
// -- View --
// ----------

View view_create(const void *data, size_t len, size_t isize) {
  View view = { .data = data, .len = len, .isize = isize };
  return view;
}

View string_to_view(const char *str) {
  return view_create(str, strlen(str), sizeof(char));
}

View *string_to_view_ptr__(POSITION_INFO_DECLARATION, Arena *arena, const char *str) {
  View *view = arena_alloc__(file, func, line, arena, sizeof(View));
  const View tmp = string_to_view(str);
  *(void **)&view->data = (void *)tmp.data;
  *(size_t *)&view->len = tmp.len;
  *(size_t *)&view->isize = tmp.isize;
  return view;
}

// ---------------
// -- Templater --
// ---------------

// Look at package\c\hectic\docs\templater.md

TemplateConfig template_default_config__(POSITION_INFO_DECLARATION, Arena *arena) {
  raise_trace__(file, func, line, "TEMPLATE: Default config");
  TemplateConfig config = {
    .Syntax = {
      .Braces = {
        .open = string_to_view_ptr__(file, func, line, arena, "{%"),
        .close = string_to_view_ptr__(file, func, line, arena, "%}")
      },
      .Section = {
        .control = string_to_view_ptr__(file, func, line, arena, "for "),
        .source = string_to_view_ptr__(file, func, line, arena, "in "),
        .begin = string_to_view_ptr__(file, func, line, arena, "do ")
      },
      .Interpolate = {
        .invoke = string_to_view_ptr__(file, func, line, arena, "")
      },
      .Include = {
        .invoke = string_to_view_ptr__(file, func, line, arena, "include ")
      },
      .Execute = {
        .invoke = string_to_view_ptr__(file, func, line, arena, "exec ")
      },
      .nesting = string_to_view_ptr__(file, func, line, arena, "->")
    }
  };

  return config;
}

#define CHECK_CONFIG_STR(field, name)                                      \
do {                                                                       \
  if (config->Syntax.field->data == NULL) {                                                  \
    raise_exception__(file, func, line, "VALIDATE: " name " is NULL");     \
    return false;                                                          \
  }                                                                        \
  if (config->Syntax.field->len > TEMPLATE_MAX_PREFIX_LEN) {                   \
    raise_exception__(file, func, line, "VALIDATE: " name " is too long"); \
    return false;                                                          \
  }                                                                        \
} while (0)

bool template_validate_config__(POSITION_INFO_DECLARATION, const TemplateConfig *config) {
  raise_trace("VALIDATE: config %p", config);
  if (!config) {
    raise_exception__(file, func, line, "VALIDATE: Config is NULL");
    return false;
  }

  CHECK_CONFIG_STR(Braces.open, "Open brace");
  CHECK_CONFIG_STR(Braces.close, "Close brace");
  CHECK_CONFIG_STR(Section.control, "Section control");
  CHECK_CONFIG_STR(Section.source, "Section source");
  CHECK_CONFIG_STR(Section.begin, "Section begin");
  CHECK_CONFIG_STR(Interpolate.invoke, "Interpolation invoke");
  CHECK_CONFIG_STR(Include.invoke, "Include invoke");
  CHECK_CONFIG_STR(Execute.invoke, "Execute invoke");
  CHECK_CONFIG_STR(nesting, "Nesting");

  return true;
}

#undef CHECK_CONFIG_STR

#define TEMPLATE_ASSERT_SYNTAX(pattern, message_arg, code_arg) \
  if (strncmp(*s, pattern, strlen(pattern)) == 0) { \
    raise_exception__(file, func, line, "PARSE: " message_arg); \
    return RESULT_ERROR(TemplateResult, code_arg, message_arg); \
  }

TemplateValue init_template_value__(POSITION_INFO_DECLARATION, TemplateNodeType type) {
  TemplateValue value;
  switch (type) {
    case TEMPLATE_NODE_TEXT:
      value.text.content = NULL;
      break;
    case TEMPLATE_NODE_INTERPOLATE:
      value.interpolate.key = NULL;
      break;
    case TEMPLATE_NODE_SECTION:
      value.section.iterator = NULL;
      value.section.collection = NULL;
      value.section.body = NULL;
      break;
    case TEMPLATE_NODE_EXECUTE:
      value.execute.code = NULL;
      break;
    case TEMPLATE_NODE_INCLUDE:
      value.include.key = NULL;
      break;
    default:
      raise_exception__(file, func, line, "INIT: Unknown node type");
      exit(1);
  }
  return value;
}

TemplateNode init_template_node__(POSITION_INFO_DECLARATION, Arena *arena, TemplateNodeType type) {
  TemplateNode node;
  node.next = NULL;
  node.type = type;
  node.value = arena_alloc__(file, func, line, arena, sizeof(TemplateValue));
  *node.value = init_template_value__(file, func, line, type);
  return node;
}

TemplateResult init_template_result__(POSITION_INFO_DECLARATION, Arena *arena, TemplateNodeType type) {
  TemplateResult result;
  result.type = RESULT_SOME;
  result.Result.some = arena_alloc__(file, func, line, arena, sizeof(TemplateNode));
  *result.Result.some = init_template_node__(file, func, line, arena, type);
  return result;
}

TemplateNode new_template_node__(TemplateNodeType type, TemplateValue *value) {
  TemplateNode node;
  node.next = NULL;
  node.type = type;
  node.value = value;
  return node;
}

TemplateResult template_parse__(POSITION_INFO_DECLARATION, Arena *arena, const char **s, const TemplateConfig *config, bool inner_parse);

TemplateResult template_parse_interpolation__(POSITION_INFO_DECLARATION, Arena *arena, const char **s_ptr, const TemplateConfig *config) {
  raise_trace__(file, func, line, "PARSE: Interpolation");

  TemplateResult result = init_template_result__(file, func, line, arena, TEMPLATE_NODE_INTERPOLATE);

  const char **s = s_ptr;

  // Skip to the content of the interpolation
  *s += config->Syntax.Braces.open->len;
  *s = skip_whitespace(*s);
  *s += config->Syntax.Interpolate.invoke->len;

  *s = skip_whitespace(*s);
  const char *key_start = *s;

  while (**s != '\0') {
    if (isspace(**s) || strncmp(*s, config->Syntax.Braces.close->data, config->Syntax.Braces.close->len) == 0) break;
    TEMPLATE_ASSERT_SYNTAX(config->Syntax.Braces.open->data, "Nested tag in interpolation", TEMPLATE_ERROR_NESTED_INTERPOLATION);

    (*s)++;
  }

  size_t key_len = *s - key_start;
  
  char *key = arena_strncpy__(file, func, line, arena, key_start, key_len);
  
  result.Result.some->value->interpolate.key = key;

  *s = skip_whitespace(*s);
  *s_ptr = *s + config->Syntax.Braces.close->len;

  return result;
}

TemplateResult template_parse_section__(POSITION_INFO_DECLARATION, Arena *arena, const char **s_ptr, const TemplateConfig *config) {
  raise_trace__(file, func, line, "PARSE: Section");

  TemplateResult result = init_template_result__(file, func, line, arena, TEMPLATE_NODE_SECTION);

  const char **s = s_ptr;

  // Skip to the content of the section
  *s += config->Syntax.Braces.open->len;
  *s = skip_whitespace(*s);
  *s += config->Syntax.Section.control->len;

  // Find the iterator name
  *s = skip_whitespace(*s);
  const char *iterator_start = *s;

  while (**s != '\0') {
    if (isspace(**s) || strncmp(*s, config->Syntax.Section.source->data, config->Syntax.Section.source->len) == 0) break;
    TEMPLATE_ASSERT_SYNTAX(config->Syntax.Braces.open->data, "Nested tag in section element name", TEMPLATE_ERROR_NESTED_SECTION_ITERATOR);
    TEMPLATE_ASSERT_SYNTAX(config->Syntax.Braces.close->data, "Unexpected section end", TEMPLATE_ERROR_UNEXPECTED_SECTION_END);
    (*s)++;
  }

  size_t iterator_len = *s - iterator_start;
  result.Result.some->value->section.iterator = arena_strncpy__(file, func, line, arena, iterator_start, iterator_len);

  // Find the collection name
  *s = skip_whitespace(*s);
  *s += config->Syntax.Section.source->len;
  *s = skip_whitespace(*s);
  const char *collection_start = *s;
  
  while (**s != '\0') {
    if (isspace(**s) || strncmp(*s, config->Syntax.Section.begin->data, config->Syntax.Section.begin->len) == 0) break;
    TEMPLATE_ASSERT_SYNTAX(config->Syntax.Braces.open->data, "Nested tag in section collection", TEMPLATE_ERROR_NESTED_SECTION_ITERATOR);
    TEMPLATE_ASSERT_SYNTAX(config->Syntax.Braces.close->data, "Unexpected section end", TEMPLATE_ERROR_UNEXPECTED_SECTION_END);
    (*s)++;
  }

  size_t collection_len = *s - collection_start;
  result.Result.some->value->section.collection = arena_strncpy__(file, func, line, arena, collection_start, collection_len);

  // Skip to the body
  *s = skip_whitespace(*s);

  // Parse the body
  TemplateResult body_result = template_parse__(file, func, line, arena, s, config, true);
  if (body_result.type == RESULT_ERROR) {
    return body_result;
  }

  result.Result.some->value->section.body = body_result.Result.some;

  // Skip to the end of the section
  *s = skip_whitespace(*s);
  if (strncmp(*s, config->Syntax.Braces.close->data, config->Syntax.Braces.close->len) != 0) {
    raise_exception__(file, func, line, "PARSE: Expected section end");
    return RESULT_ERROR(TemplateResult, TEMPLATE_ERROR_UNEXPECTED_SECTION_END, "Expected section end");
  }
  *s_ptr = *s + config->Syntax.Braces.close->len;

  return result;
}

TemplateResult template_parse_include__(POSITION_INFO_DECLARATION, Arena *arena, const char **s_ptr, const TemplateConfig *config) {
  raise_trace__(file, func, line, "PARSE: Include");

  TemplateResult result = init_template_result__(file, func, line, arena, TEMPLATE_NODE_INCLUDE);

  const char **s = s_ptr;

  // Skip to the content of the include
  *s += config->Syntax.Braces.open->len;
  *s = skip_whitespace(*s);
  *s += config->Syntax.Include.invoke->len;

  *s = skip_whitespace(*s);
  const char *include_start = *s;

  while (**s != '\0') {
    if (isspace(**s) || strncmp(*s, config->Syntax.Braces.close->data, config->Syntax.Braces.close->len) == 0) break;
    TEMPLATE_ASSERT_SYNTAX(config->Syntax.Braces.open->data, "Nested tag in include", TEMPLATE_ERROR_NESTED_INCLUDE);
    (*s)++;
  }

  size_t include_len = *s - include_start;
  result.Result.some->value->include.key = arena_strncpy__(file, func, line, arena, include_start, include_len);

  // Skip to the end of the include
  *s = skip_whitespace(*s);
  if (strncmp(*s, config->Syntax.Braces.close->data, config->Syntax.Braces.close->len) != 0) {
    raise_exception__(file, func, line, "PARSE: Expected include end");
    return RESULT_ERROR(TemplateResult, TEMPLATE_ERROR_UNEXPECTED_INCLUDE_END, "Expected include end");
  }
  *s_ptr = *s + config->Syntax.Braces.close->len;

  return result;
}

TemplateResult template_parse_execute__(POSITION_INFO_DECLARATION, Arena *arena, const char **s_ptr, const TemplateConfig *config) {
  raise_trace__(file, func, line, "PARSE: Execute");

  TemplateResult result = init_template_result__(file, func, line, arena, TEMPLATE_NODE_EXECUTE);

  const char **s = s_ptr;

  // Skip to the content of the execute
  *s += config->Syntax.Braces.open->len;
  *s = skip_whitespace(*s);
  *s += config->Syntax.Execute.invoke->len;

  *s = skip_whitespace(*s);
  const char *code_start = *s;

  // Find the end of the code
  while (**s != '\0') {
    if (strncmp(*s, config->Syntax.Braces.close->data, config->Syntax.Braces.close->len) == 0) break;
    TEMPLATE_ASSERT_SYNTAX(config->Syntax.Braces.open->data, "Nested tag in execute", TEMPLATE_ERROR_NESTED_EXECUTE);
    (*s)++;
  }

  size_t code_len = *s - code_start;
  result.Result.some->value->execute.code = arena_strncpy__(file, func, line, arena, code_start, code_len);

  // Skip to the end of the execute
  if (strncmp(*s, config->Syntax.Braces.close->data, config->Syntax.Braces.close->len) != 0) {
    raise_exception__(file, func, line, "PARSE: Expected execute end");
    return RESULT_ERROR(TemplateResult, TEMPLATE_ERROR_UNEXPECTED_EXECUTE_END, "Expected execute end");
  }
  *s_ptr = *s + config->Syntax.Braces.close->len;

  return result;
}

TemplateResult template_parse__(POSITION_INFO_DECLARATION, Arena *arena, const char **s, const TemplateConfig *config, bool inner_parse) {
  raise_trace__(file, func, line, "PARSE: Iteration start");

  if (!template_validate_config__(file, func, line, config)) {
    raise_exception__(file, func, line, "PARSE: Invalid config");
    return RESULT_ERROR(TemplateResult, TEMPLATE_ERROR_INVALID_CONFIG, "Invalid config");
  }

  if (!arena) {
    raise_exception__(file, func, line, "PARSE: Arena is NULL");
    return RESULT_ERROR(TemplateResult, TEMPLATE_ERROR_OUT_OF_MEMORY, "Out of memory");
  }

  const char *start = *s;

  TemplateNode *root = arena_alloc__(file, func, line, arena, sizeof(TemplateNode));
  *root = init_template_node__(file, func, line, arena, TEMPLATE_NODE_TEXT);
  
  TemplateNode *current = root;
  bool current_node_filled = false;

  int open_brace_len = config->Syntax.Braces.open->len;


  while (*s && **s != '\0') {
    // Check for closing brace if this is inner parse
    if (inner_parse && strncmp(*s, config->Syntax.Braces.close->data, config->Syntax.Braces.close->len) == 0) {
      raise_trace__(file, func, line, "PARSE: Found closing brace in inner parse");
      break;
    }
    if (strncmp(*s, config->Syntax.Braces.open->data, open_brace_len) == 0) {
      if (start != *s) {
        raise_trace__(file, func, line, "PARSE: Text node: %s", arena_strncpy__(POSITION_INFO, DISPOSABLE_ARENA, start, *s - start));
        
        if (current_node_filled) {
          TemplateNode *new_node = arena_alloc__(file, func, line, arena, sizeof(TemplateNode));
          *new_node = init_template_node__(file, func, line, arena, TEMPLATE_NODE_TEXT);
          current->next = new_node;
          current = new_node;
        } else {
          current->type = TEMPLATE_NODE_TEXT;
          *current->value = init_template_value__(file, func, line, TEMPLATE_NODE_TEXT);
        }
        
        current->value->text.content = arena_strncpy__(file, func, line, arena, start, *s - start);
        current_node_filled = true;
      }

      // Determine tag type by prefix
      TemplateResult current_result;
      {
        raise_trace__(file, func, line, "PARSE: Found tag");

        const char *tag_prefix = *s + open_brace_len;
        tag_prefix = skip_whitespace(tag_prefix);
        raise_trace("tag_prefix: %p", tag_prefix);

        typedef struct {
          const View * const prefix;
          int tag_type;
        } PrefixMatch;

        PrefixMatch matches[] = {
          {config->Syntax.Section.control, 1},
          {config->Syntax.Interpolate.invoke, 2},
          {config->Syntax.Include.invoke, 3},
          {config->Syntax.Execute.invoke, 4}
        };

        int matched_type = 0;
        size_t max_length = 0;

        // Find longest match (in case when one name of tage is part of another)
        for (int i = 0; i < 4; i++) {
          if (strncmp(tag_prefix, matches[i].prefix->data, matches[i].prefix->len) == 0) {
            // NOTE(yukkop): >= becouse one of the strings may be ""
            if (matches[i].prefix->len >= max_length) {
              max_length = matches[i].prefix->len;
              matched_type = matches[i].tag_type;
            }
          }
        }

        if (matched_type == 1) {
          raise_trace__(file, func, line, "PARSE: Section tag");
          current_result = template_parse_section__(file, func, line, arena, s, config);
          start = *s;
        } else if (matched_type == 2) {
          raise_trace__(file, func, line, "PARSE: Interpolation tag");
          current_result = template_parse_interpolation__(file, func, line, arena, s, config);
          start = *s;
        } else if (matched_type == 3) {
          raise_trace__(file, func, line, "PARSE: Include tag");
          current_result = template_parse_include__(file, func, line, arena, s, config);
          start = *s;
        } else if (matched_type == 4) {
          raise_trace__(file, func, line, "PARSE: Execute tag");
          current_result = template_parse_execute__(file, func, line, arena, s, config);
          start = *s;
        } else {
          raise_exception__(file, func, line, "PARSE: Unknown tag prefix: %s", slice_create__(POSITION_INFO, 1, (char *)tag_prefix, strlen(tag_prefix), 0, TEMPLATE_MAX_PREFIX_LEN));
          return RESULT_ERROR(TemplateResult, TEMPLATE_ERROR_UNKNOWN_TAG, "Unknown tag prefix");
        }

        TRY(current_result);
      }

      if (current_node_filled) {
        // SAFETY(yukkop): NO init necessary here
        TemplateNode *new_node = arena_alloc__(file, func, line, arena, sizeof(TemplateNode));
        *new_node = *current_result.Result.some;
        current->next = new_node;
        current = new_node;
      } else {
        *current = *current_result.Result.some;
      }
      current_node_filled = true;
    }

    if (**s != '\0') {
      (*s)++;
    }
  }

  // Add text node if there is any text after the last tag
  if (start != *s) {
    if (current_node_filled) {
      TemplateNode *new_node = arena_alloc__(file, func, line, arena, sizeof(TemplateNode));
      *new_node = init_template_node__(file, func, line, arena, TEMPLATE_NODE_TEXT);
      current->next = new_node;
      current = new_node;
    } else {
      current->type = TEMPLATE_NODE_TEXT;
      *current->value = init_template_value__(file, func, line, TEMPLATE_NODE_TEXT);
    }
    
    current->value->text.content = arena_strncpy__(file, func, line, arena, start, *s - start);
    current_node_filled = true;
  }

  // Set null when node is not filled
  if (!current_node_filled && current == root) {
    root->type = TEMPLATE_NODE_TEXT;
    *root->value = init_template_value__(file, func, line, TEMPLATE_NODE_TEXT);
    root->value->text.content = arena_strncpy__(file, func, line, arena, "", 0);
  }

  return RESULT_SOME(TemplateResult, *root);
}

#undef TEMPLATE_ASSERT_SYNTAX

#define TEMPLATE_NODE_MAX_DEBUG_DEPTH 20

char *template_node_type_to_string(TemplateNodeType type) {
  switch (type) {
    case TEMPLATE_NODE_SECTION: return "SECTION";
    case TEMPLATE_NODE_INTERPOLATE: return "INTERPOLATE";
    case TEMPLATE_NODE_EXECUTE: return "EXECUTE";
    case TEMPLATE_NODE_INCLUDE: return "INCLUDE";
    case TEMPLATE_NODE_TEXT: return "TEXT";
    default: { 
        raise_exception("HECTICLIB ERROR: Unknown template node type: %d", type);
        return "UNKNOWN";
    };
  }
}

char *template_section_value_to_debug_str__(POSITION_INFO_DECLARATION, Arena *arena, const char *name, const TemplateSectionValue *self, PtrSet *visited) {
    char *result = arena_alloc(arena, MEM_KiB);
    STRUCT_TO_DEBUG_STR(arena, result, TemplateSectionValue, name, self, visited, 3,
      string_to_debug_str__(file, func, line, arena, "iterator", self->iterator),
      string_to_debug_str__(file, func, line, arena, "collection", self->collection),
      template_node_to_debug_str__(file, func, line, arena, "body", self->body, visited)
    );
    return result;
}

char *template_interpolate_value_to_debug_str__(POSITION_INFO_DECLARATION, Arena *arena, const char *name, const TemplateInterpolateValue *self, PtrSet *visited) {
    char *result = arena_alloc(arena, MEM_KiB);
    STRUCT_TO_DEBUG_STR(arena, result, TemplateInterpolateValue, name, self, visited, 1,
      string_to_debug_str__(file, func, line, arena, "key", self->key)
    );
    return result;
}

char *template_execute_value_to_debug_str__(POSITION_INFO_DECLARATION, Arena *arena, const char *name, const TemplateExecuteValue *self, PtrSet *visited) {
    char *result = arena_alloc(arena, MEM_KiB);
    STRUCT_TO_DEBUG_STR(arena, result, TemplateExecuteValue, name, self, visited, 1,
      string_to_debug_str__(file, func, line, arena, "code", self->code)
    );
    return result;
}

char *template_include_value_to_debug_str__(POSITION_INFO_DECLARATION, Arena *arena, const char *name, const TemplateIncludeValue *self, PtrSet *visited) {
    char *result = arena_alloc(arena, MEM_KiB);
    STRUCT_TO_DEBUG_STR(arena, result, TemplateIncludeValue, name, self, visited, 1,
      string_to_debug_str__(file, func, line, arena, "key", self->key)
    );
    return result;
}

char *template_text_value_to_debug_str__(POSITION_INFO_DECLARATION, Arena *arena, const char *name, const TemplateTextValue *self, PtrSet *visited) {
    char *result = arena_alloc(arena, MEM_KiB);
    STRUCT_TO_DEBUG_STR(arena, result, TemplateTextValue, name, self, visited, 1,
      string_to_debug_str__(file, func, line, arena, "content", self->content)
    );
    return result;
}

char *template_value_to_debug_str__(POSITION_INFO_DECLARATION, Arena *arena, const char *name, const TemplateValue *self, TemplateNodeType active_variant, PtrSet *visited) {
    char *result = arena_alloc(arena, MEM_KiB);

    UNION_TO_DEBUG_STR(arena, result, TemplateValue, name, self, visited, active_variant, 5,
      TEMPLATE_NODE_SECTION, template_section_value_to_debug_str__(file, func, line, arena, "section", &self->section, visited),
      TEMPLATE_NODE_INTERPOLATE, template_interpolate_value_to_debug_str__(file, func, line, arena, "interpolate", &self->interpolate, visited),
      TEMPLATE_NODE_EXECUTE, template_execute_value_to_debug_str__(file, func, line, arena, "execute", &self->execute, visited),
      TEMPLATE_NODE_INCLUDE, template_include_value_to_debug_str__(file, func, line, arena, "include", &self->include, visited),
      TEMPLATE_NODE_TEXT, template_text_value_to_debug_str__(file, func, line, arena, "text", &self->text, visited)
    );
    return result;
}

char *template_node_to_debug_str__(POSITION_INFO_DECLARATION, Arena *arena, const char *name, const TemplateNode *self, PtrSet *visited) {
    char *result = arena_alloc(arena, MEM_KiB);
    STRUCT_TO_DEBUG_STR(arena, result, TemplateNode, name, self, visited, 3,
      enum_to_debug_str__(file, func, line, arena, "type", self->type, template_node_type_to_string(self->type)),
      template_value_to_debug_str__(file, func, line, arena, "value", self->value, self->type, visited),
      template_node_to_debug_str__(file, func, line, arena, "next", self->next, visited)
    );
    return result;
}


char *template_node_to_json_str__(POSITION_INFO_DECLARATION, Arena *arena, const TemplateNode *node, int depth) {
    if (!node) return arena_strncpy__(file, func, line, arena, "", 0);

    if (depth > TEMPLATE_NODE_MAX_DEBUG_DEPTH) {
      return arena_strncpy__(file, func, line, arena, "...", 3);
    }

    // Use a temporary buffer on the stack for building the string
    char temp_buf[MEM_MiB];
    size_t len = 0;
    
    #define APPEND(...) do { \
        int written = snprintf(temp_buf + len, sizeof(temp_buf) - len, ##__VA_ARGS__); \
        if (written < 0) return NULL; \
        len += written; \
    } while (0)

    if (depth == 0) {
      APPEND("[");
    }

    APPEND("{\"type\":\"%s\",", template_node_type_to_string(node->type));

    switch (node->type) {
        case TEMPLATE_NODE_SECTION:
            APPEND("\"content\":{\"iterator\":\"%s\",\"collection\":\"%s\"}",
                node->value->section.iterator,
                node->value->section.collection);
            char *body_str = template_node_to_json_str__(file, func, line, arena, node->value->section.body, depth + 1);
            if (body_str) {
                APPEND(",\"body\":[%s]", body_str);
            }
            break;
        case TEMPLATE_NODE_INTERPOLATE:
            APPEND("\"content\":{\"key\":\"%s\"}", node->value->interpolate.key);
            break;
        case TEMPLATE_NODE_EXECUTE:
            APPEND("\"content\":{\"code\":\"%s\"}", node->value->execute.code);
            break;
        case TEMPLATE_NODE_INCLUDE:
            APPEND("\"content\":{\"key\":\"%s\"}", node->value->include.key);
            break;
        case TEMPLATE_NODE_TEXT:
            APPEND("\"content\":{\"content\":\"%s\"}", node->value->text.content);
            break;
        default:
            break;
    }

    APPEND("}");

    if (node->next) {
        char *next_str = template_node_to_json_str__(file, func, line, arena, node->next, depth + 1);
        if (next_str) {
            APPEND(",%s", next_str);
        }
    }

    if (depth == 0) {
      APPEND("]");
    }

    // Copy the final string to arena-allocated memory
    char *result = arena_strncpy__(file, func, line, arena, temp_buf, len);
    return result;
}

// ----------
// -- diff --
// ----------

//int diff_str__(POSITION_INFO_DECLARATION, Arena *arena, const char **str1, const char **str2) {
//    if (!str1 || !str2) {
//        return 0;
//    }
//
//    const char *s1 = *str1;
//    const char *s2 = *str2;
//
//    int diff = 0;
//
//    while (*s1 && *s2) {
//        if (*s1 != *s2) {
//            diff++;
//        }
//        s1++;
//        s2++;
//    }
//
//    return diff;
//}

// --------------
// -- Colorize --
// --------------

char *colorize_partial_patterns(char *output, const char *input, PatternHighlight *patterns, size_t pattern_count) {
    size_t len = strlen(input);
    if (!output) return NULL;
    size_t out_idx = 0;

    for (size_t i = 0; i < len;) {
        int matched = 0;
        for (size_t j = 0; j < pattern_count; j++) {
            size_t pat_len = strlen(patterns[j].pattern);
            if (strncmp(&input[i], patterns[j].pattern, pat_len) == 0) {
                const char *pre = &input[i];
                const char *hl_start = &input[i + patterns[j].highlight_start];
                const char *hl_end = &input[i + patterns[j].highlight_start + patterns[j].highlight_len];

                // Copy pre-highlight part
                size_t pre_len = patterns[j].highlight_start;
                memcpy(&output[out_idx], pre, pre_len);
                out_idx += pre_len;

                // Add color code and highlighted part
                size_t color_len = strlen(patterns[j].color);
                memcpy(&output[out_idx], patterns[j].color, color_len);
                out_idx += color_len;

                memcpy(&output[out_idx], hl_start, patterns[j].highlight_len);
                out_idx += patterns[j].highlight_len;

                memcpy(&output[out_idx], "\033[0m", 4);
                out_idx += 4;

                // Copy post-highlight part
                size_t post_len = pat_len - patterns[j].highlight_start - patterns[j].highlight_len;
                memcpy(&output[out_idx], hl_end, post_len);
                out_idx += post_len;

                i += pat_len;
                matched = 1;
                break;
            }
        }
        if (!matched) {
            output[out_idx++] = input[i++];
        }
    }

    output[out_idx] = '\0';
    return output;
}

// ---------
// -- End --
// ---------

#undef POSITION_INFO_DECLARATION
#undef POSITION_INFO
