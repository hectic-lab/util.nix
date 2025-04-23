# File Logging in Hectic Library

This document covers the file logging functionality in the Hectic library, including its configuration and usage in different scenarios.

## Overview

Hectic's logging system now supports logging to files, offering three output modes:
1. Stderr only (default)
2. File only
3. Both stderr and file

This gives you flexibility to route logs where they're most needed while maintaining the same structured logging interface.

## Configuration Methods

### 1. Environment Variables

Configure logging with environment variables:

```sh
# Set log file path
export LOG_FILE=/path/to/your/logfile.log

# Set output mode (STDERR_ONLY, FILE_ONLY, BOTH)
export LOG_OUTPUT_MODE=BOTH

# Set log level as usual
export LOG_LEVEL=DEBUG

# Run your application
./your_program
```

### 2. Programmatic Configuration

Configure logging in your code:

```c
#include "hectic.h"

int main() {
    // Initialize logger
    logger_init();
    
    // Set log file (returns 0 on success, -1 on failure)
    if (logger_set_file("/path/to/logfile.log") != 0) {
        raise_exception("Failed to open log file");
        return 1;
    }
    
    // Set output mode
    logger_set_output_mode(LOG_OUTPUT_BOTH);
    
    // Your application code here
    raise_info("Application started");
    
    // Clean up on exit
    logger_free();
    
    return 0;
}
```

## Output Modes

### `LOG_OUTPUT_STDERR_ONLY` (Default)
- All log messages go to stderr only
- No file output even if a log file is set

### `LOG_OUTPUT_FILE_ONLY`
- All log messages go to the log file only
- Nothing is printed to stderr (useful for daemon processes)
- ANSI color codes are automatically stripped from file output

### `LOG_OUTPUT_BOTH`
- All log messages go to both stderr and the log file
- ANSI colors appear on stderr but are stripped from file output

## File Handling Details

- Log files are opened in append mode
- The library automatically flushes after each log message to ensure logs are written immediately
- ANSI color codes are automatically stripped from file output to avoid cluttering log files with escape sequences
- If a file cannot be opened, an error message is printed to stderr

## API Reference

### Setting the Log File

```c
int logger_set_file(const char *file_path);
```

- **Parameters**: `file_path` - Path to the log file, or NULL to disable file logging
- **Returns**: 0 on success, -1 on failure (e.g., unable to open file)
- **Notes**: 
  - Automatically closes any previously opened log file
  - Opens the new file in append mode
  - If NULL is passed, disables file logging and resets output mode to stderr only

### Setting the Output Mode

```c
void logger_set_output_mode(LogOutputMode mode);
```

- **Parameters**: `mode` - One of `LOG_OUTPUT_STDERR_ONLY`, `LOG_OUTPUT_FILE_ONLY`, or `LOG_OUTPUT_BOTH`
- **Notes**: 
  - Has no effect if file logging is not configured and mode is file-related
  - Does not check if the log file is successfully opened

## Example

See `examples/file_logging_example.c` for a complete working example of file logging.

## Best Practices

1. **Always check the return value of `logger_set_file()`**:
   ```c
   if (logger_set_file("/path/to/logfile.log") != 0) {
       // Handle error
   }
   ```

2. **Use appropriate output modes**:
   - For interactive CLI applications: `LOG_OUTPUT_STDERR_ONLY` or `LOG_OUTPUT_BOTH`
   - For daemon/service applications: `LOG_OUTPUT_FILE_ONLY`
   - For debugging sessions: `LOG_OUTPUT_BOTH`

3. **Consider log rotation**: The library doesn't handle log rotation, so for long-running applications, consider external log rotation solutions.

4. **Close properly**: Always call `logger_free()` to ensure log files are properly closed. 