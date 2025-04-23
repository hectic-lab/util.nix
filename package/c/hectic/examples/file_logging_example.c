/**
 * File Logging Example for Hectic Library
 * 
 * This example demonstrates how to use the file logging capabilities
 * of the Hectic library, showing both programmatic configuration
 * and environment variable-based configuration.
 */

#include "../hectic.h"
#include <stdio.h>

int main(int argc, char *argv[]) {
    // Initialize the logger
    logger_init();
    
    // Log a message to stderr
    raise_info("Starting file logging example");
    
    // Enable file logging programmatically
    const char *log_file = "example_log.txt";
    if (logger_set_file(log_file) != 0) {
        raise_exception("Failed to open log file: %s", log_file);
        return 1;
    }
    
    // Set output mode to write to both stderr and file
    logger_set_output_mode(LOG_OUTPUT_BOTH);
    
    // Log messages at different levels
    raise_debug("This is a debug message");
    raise_info("This is an info message");
    raise_notice("This is a notice message");
    raise_warn("This is a warning message");
    raise_exception("This is an exception message");
    
    // Switch to file-only mode
    logger_set_output_mode(LOG_OUTPUT_FILE_ONLY);
    raise_info("This message will only appear in the log file");
    
    // Switch back to stderr-only mode
    logger_set_output_mode(LOG_OUTPUT_STDERR_ONLY);
    raise_info("This message will only appear on stderr");
    
    // Clean up
    logger_free();
    
    printf("\nLog file demonstration complete. Check %s for logged messages.\n", log_file);
    printf("\nYou can also run this program with environment variables:\n");
    printf("  LOG_FILE=custom.log LOG_OUTPUT_MODE=BOTH LOG_LEVEL=DEBUG ./file_logging_example\n");
    
    return 0;
} 