#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include "libhectic.h"

// Reusable test function for any raise_* logging function.
// The logging function must have the signature: char* func(const char* message)
void test_raise_generic(const char* (*raise_func)(const char*), LogLevel log_level, const char* level_str) {
    FILE *orig_stderr = stderr;
    FILE *temp = tmpfile();
    char result_buffer[256];

    if (!temp) {
        perror("tmpfile");
        exit(EXIT_FAILURE);
    }
    stderr = temp;

    logger_level(log_level);
    int line = __LINE__;
    char* time_str = raise_func("message");
    logger_level_reset();

    fflush(stderr);
    fseek(temp, 0, SEEK_SET);
    size_t nread = fread(result_buffer, 1, sizeof(result_buffer) - 1, temp);
    result_buffer[nread] = '\0';

    stderr = orig_stderr;
    fclose(temp);

    char expected_buffer[256];
    sprintf(expected_buffer, "%s %d %s: message\n", time_str, line + 1, level_str, message);
    assert(strcmp(result_buffer, expected_buffer) == 0);
}

int main(void) {
    set_output_color_mode(COLOR_MODE_DISABLE);

    test_raise_generic(raise_log,   LOG_LEVEL_LOG,   "LOG");
    test_raise_generic(raise_debug, LOG_LEVEL_DEBUG, "DEBUG");
    test_raise_generic(raise_warn,  LOG_LEVEL_INFO, "INFO");
    test_raise_generic(raise_notice,  LOG_LEVEL_NOTICE, "NOTICE");
    test_raise_generic(raise_warn,  LOG_LEVEL_WARN, "WARN");
    test_raise_generic(raise_exception,  LOG_LEVEL_EXCEPTION, "EXCEPTION");

    return 0;
}
