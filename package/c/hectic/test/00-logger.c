#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include "hectic.h"

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
    sprintf(expected_buffer, "%s " LEVEL_STR " " __FILE__ ":%d message\n", time_str, __LINE__); \
    printf("DEBUG: [%s] [%s]\n", result_buffer, expected_buffer);                   \
    assert(strcmp(result_buffer, expected_buffer) == 0);                            \
} while(0)

int main(void) {
    logger_level(LOG_LEVEL_DEBUG);

    TEST_RAISE_GENERIC(raise_debug, LOG_LEVEL_DEBUG, "DEBUG");
    TEST_RAISE_GENERIC(raise_log,   LOG_LEVEL_LOG,   "LOG");
    TEST_RAISE_GENERIC(raise_info,  LOG_LEVEL_INFO, "INFO");
    TEST_RAISE_GENERIC(raise_notice,  LOG_LEVEL_NOTICE, "NOTICE");
    TEST_RAISE_GENERIC(raise_warn,  LOG_LEVEL_WARN, "WARN");
    TEST_RAISE_GENERIC(raise_exception,  LOG_LEVEL_EXCEPTION, "EXCEPTION");

    printf("%s%s all tests passed.%s\n", OPTIONAL_COLOR(COLOR_GREEN), __FILE__, OPTIONAL_COLOR(COLOR_RESET));
    return 0;
}
