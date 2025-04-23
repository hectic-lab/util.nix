#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <unistd.h>
#include "hectic.h"

#define ASSERT_STR_EQ(actual, expected) do {                                         \
    if (strcmp(actual, expected) != 0) {                                             \
        fprintf(stderr, "\n--- STRING COMPARISON ERROR ---\n");                      \
        fprintf(stderr, "Expected (%zu bytes):\n'%s'\n", strlen(expected), expected);\
        fprintf(stderr, "Got (%zu bytes):\n'%s'\n", strlen(actual), actual);         \
        fprintf(stderr, "----------------------------\n");                           \
        for (size_t i = 0; i < strlen(expected) && i < strlen(actual); i++) {        \
            if (expected[i] != actual[i]) {                                          \
                fprintf(stderr, "First mismatch at position %zu: '%c' != '%c'\n",    \
                       i, expected[i], actual[i]);                                   \
                break;                                                               \
            }                                                                        \
        }                                                                            \
        assert(0 && "Strings do not match");                                         \
    }                                                                                \
} while(0)

#define TEST_RAISE_GENERIC(LOG_MACRO, LEVEL, LEVEL_STR) do {                        \
    FILE *orig_stderr = stderr;                                                     \
    FILE *temp = tmpfile();                                                         \
    char result_buffer[256];                                                        \
    if (!temp) { perror("tmpfile"); exit(EXIT_FAILURE); }                           \
    stderr = temp;                                                                  \
    logger_level(LEVEL);                                                            \
    const char* time_str = LOG_MACRO("message");                                    \
    logger_level_reset();                                                           \
    fflush(stderr);                                                                 \
    fseek(temp, 0, SEEK_SET);                                                       \
    size_t nread = fread(result_buffer, 1, sizeof(result_buffer)-1, temp);          \
    result_buffer[nread] = '\0';                                                    \
    stderr = orig_stderr;                                                           \
    fclose(temp);                                                                   \
    char expected_buffer[256];                                                      \
    const char* func = __func__;                                                   \
    sprintf(expected_buffer, "%s " LEVEL_STR " " __FILE__ ":%s:%d message\n", time_str, func, __LINE__); \
    ASSERT_STR_EQ(result_buffer, expected_buffer);                                  \
} while(0)

#define TEST_FILE_LOGGING(LOG_MACRO, LEVEL_STR, MESSAGE) do {                        \
    char log_path[256];                                                              \
    snprintf(log_path, sizeof(log_path), "/tmp/hectic-test-%d.log", getpid());       \
    assert(logger_set_file(log_path) == 0);                                          \
    logger_set_output_mode(LOG_OUTPUT_FILE_ONLY);                                    \
    const char* time_str = LOG_MACRO(MESSAGE);                                       \
    fflush(NULL);                                                                    \
                                                                                     \
    FILE *log_file = fopen(log_path, "r");                                           \
    assert(log_file != NULL);                                                        \
    char file_buffer[256];                                                           \
    size_t file_read = fread(file_buffer, 1, sizeof(file_buffer)-1, log_file);       \
    file_buffer[file_read] = '\0';                                                   \
    fclose(log_file);                                                                \
    unlink(log_path);                                                                \
                                                                                     \
    char expected[256];                                                              \
    const char* func = __func__;                                                     \
    snprintf(expected, sizeof(expected), "%s %s %s:%s:%d %s\n",                      \
            time_str, LEVEL_STR, __FILE__, func, __LINE__, MESSAGE);                 \
    ASSERT_STR_EQ(file_buffer, expected);                                            \
    logger_free();                                                                   \
} while(0)

#define TEST_DUAL_LOGGING(MESSAGE) do {                                               \
    char log_path[256];                                                               \
    snprintf(log_path, sizeof(log_path), "/tmp/hectic-test-%d.log", getpid());        \
    assert(logger_set_file(log_path) == 0);                                           \
    logger_set_output_mode(LOG_OUTPUT_BOTH);                                          \
                                                                                      \
    FILE *orig_stderr = stderr;                                                       \
    FILE *temp_stderr = tmpfile();                                                    \
    assert(temp_stderr != NULL);                                                      \
    stderr = temp_stderr;                                                             \
                                                                                      \
    raise_info(MESSAGE);                                                              \
    fflush(stderr);                                                                   \
                                                                                      \
    stderr = orig_stderr;                                                             \
                                                                                      \
    FILE *log_file = fopen(log_path, "r");                                            \
    assert(log_file != NULL);                                                         \
    char file_buffer[256];                                                            \
    size_t file_read = fread(file_buffer, 1, sizeof(file_buffer)-1, log_file);        \
    file_buffer[file_read] = '\0';                                                    \
    fclose(log_file);                                                                 \
                                                                                      \
    fseek(temp_stderr, 0, SEEK_SET);                                                  \
    char stderr_buffer[256];                                                          \
    size_t stderr_read = fread(stderr_buffer, 1, sizeof(stderr_buffer)-1, temp_stderr);\
    stderr_buffer[stderr_read] = '\0';                                                \
    fclose(temp_stderr);                                                              \
                                                                                      \
    unlink(log_path);                                                                 \
                                                                                      \
    fprintf(stdout, "stderr content (%zu bytes):\n", stderr_read);                    \
    for (size_t i = 0; i < stderr_read; i++) {                                        \
        unsigned char c = (unsigned char)stderr_buffer[i];                            \
        if (c < 32 || c > 126)                                                        \
            fprintf(stdout, "\\x%02x", c);                                            \
        else                                                                          \
            fputc(c, stdout);                                                         \
    }                                                                                 \
    fprintf(stdout, "\n");                                                            \
                                                                                      \
    fprintf(stdout, "file content (%zu bytes):\n", file_read);                        \
    for (size_t i = 0; i < file_read; i++) {                                          \
        unsigned char c = (unsigned char)file_buffer[i];                              \
        if (c < 32 || c > 126)                                                        \
            fprintf(stdout, "\\x%02x", c);                                            \
        else                                                                          \
            fputc(c, stdout);                                                         \
    }                                                                                 \
    fprintf(stdout, "\n");                                                            \
                                                                                      \
    if (strstr(file_buffer, MESSAGE) == NULL) {                                       \
        fprintf(stderr, "Error: message not found in file.\n");                       \
        fprintf(stderr, "Expected message: %s\n", MESSAGE);                           \
        fprintf(stderr, "File content: %s\n", file_buffer);                           \
        assert(0);                                                                    \
    }                                                                                 \
    if (strstr(stderr_buffer, MESSAGE) == NULL) {                                     \
        fprintf(stderr, "Error: message not found in stderr.\n");                     \
        fprintf(stderr, "Expected message: %s\n", MESSAGE);                           \
        fprintf(stderr, "stderr content: %s\n", stderr_buffer);                       \
        assert(0);                                                                    \
    }                                                                                 \
                                                                                      \
    if (strstr(stderr_buffer, "\033") == NULL) {                                      \
        fprintf(stdout, "Note: ANSI color codes not found in stderr.\n");             \
        fprintf(stdout, "This is normal if the test is run without color support.\n");\
    }                                                                                 \
                                                                                      \
    if (strstr(file_buffer, "\033") != NULL) {                                        \
        fprintf(stderr, "Error: ANSI color codes found in file.\n");                  \
        fprintf(stderr, "File content: %s\n", file_buffer);                           \
        assert(0);                                                                    \
    }                                                                                 \
                                                                                      \
    logger_free();                                                                    \
} while(0)

#define TEST_MODE_SWITCHING() do {                                                     \
    char log_path[256];                                                                \
    snprintf(log_path, sizeof(log_path), "/tmp/hectic-mode-switch-%d.log", getpid());  \
                                                                                       \
    logger_init();                                                                     \
    assert(logger_set_file(log_path) == 0);                                            \
                                                                                       \
    logger_set_output_mode(LOG_OUTPUT_FILE_ONLY);                                      \
    raise_info("File only message");                                                   \
                                                                                       \
    logger_set_output_mode(LOG_OUTPUT_BOTH);                                           \
    raise_info("Both stderr and file message");                                        \
                                                                                       \
    logger_set_output_mode(LOG_OUTPUT_STDERR_ONLY);                                    \
    raise_info("Stderr only message");                                                 \
                                                                                       \
    FILE *log_file = fopen(log_path, "r");                                             \
    assert(log_file != NULL);                                                          \
    char buffer[1024];                                                                 \
    size_t bytes_read = fread(buffer, 1, sizeof(buffer)-1, log_file);                  \
    buffer[bytes_read] = '\0';                                                         \
    fclose(log_file);                                                                  \
    unlink(log_path);                                                                  \
                                                                                       \
    if (strstr(buffer, "File only message") == NULL) {                                 \
        fprintf(stderr, "Error: 'File only message' not found in file.\n");            \
        fprintf(stderr, "File content:\n%s\n", buffer);                                \
        assert(0);                                                                     \
    }                                                                                  \
    if (strstr(buffer, "Both stderr and file message") == NULL) {                      \
        fprintf(stderr, "Error: 'Both stderr and file message' not found in file.\n"); \
        fprintf(stderr, "File content:\n%s\n", buffer);                                \
        assert(0);                                                                     \
    }                                                                                  \
    if (strstr(buffer, "Stderr only message") != NULL) {                               \
        fprintf(stderr, "Error: 'Stderr only message' found in file but should not be there.\n");\
        fprintf(stderr, "File content:\n%s\n", buffer);                                \
        assert(0);                                                                     \
    }                                                                                  \
                                                                                       \
    logger_free();                                                                     \
} while(0)

int main(void) {
    debug_color_mode = COLOR_MODE_DISABLE;
    printf("%sRunning %s%s%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_CYAN), __FILE__,  OPTIONAL_COLOR(COLOR_RESET));

    TEST_RAISE_GENERIC(raise_debug, LOG_LEVEL_DEBUG, "DEBUG");
    TEST_RAISE_GENERIC(raise_log,   LOG_LEVEL_LOG,   "LOG");
    TEST_RAISE_GENERIC(raise_info,  LOG_LEVEL_INFO, "INFO");
    TEST_RAISE_GENERIC(raise_notice,  LOG_LEVEL_NOTICE, "NOTICE");
    TEST_RAISE_GENERIC(raise_warn,  LOG_LEVEL_WARN, "WARN");
    TEST_RAISE_GENERIC(raise_exception,  LOG_LEVEL_EXCEPTION, "EXCEPTION");

    printf("%sTesting file logging functionality...%s\n", OPTIONAL_COLOR(COLOR_CYAN), OPTIONAL_COLOR(COLOR_RESET));
    
    logger_init();
    logger_level(LOG_LEVEL_DEBUG);
    
    TEST_FILE_LOGGING(raise_info, "INFO", "File output test");
    TEST_FILE_LOGGING(raise_debug, "DEBUG", "Debug message to file");
    TEST_FILE_LOGGING(raise_warn, "WARN", "Warning message to file");
    
    TEST_DUAL_LOGGING("Dual output test message");
    
    TEST_MODE_SWITCHING();

    printf("%sall tests passed.%s%s%s\n", OPTIONAL_COLOR(COLOR_GREEN), OPTIONAL_COLOR(COLOR_CYAN), __FILE__, OPTIONAL_COLOR(COLOR_RESET));
    return 0;
}