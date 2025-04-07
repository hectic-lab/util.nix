# Hectic Library Logging System

This document provides guidelines on how to use the logging system in the Hectic library effectively.

## Log Levels

The Hectic library implements a graduated severity-based logging system with the following levels (from lowest to highest severity):

### TRACE
**Purpose**: Most detailed information for in-depth debugging
- Use for: Deep diagnostic details, function entry/exit, variable dumps
- Visibility: Development environments only
- Performance Impact: High
- Example: `raise_trace("Entering function with value=%d, ptr=%p", value, ptr);`

### DEBUG
**Purpose**: Detailed information useful during development
- Use for: Development-time debugging, showing variable states, internal flows
- Visibility: Development and debugging environments
- Performance Impact: Medium-High
- Example: `raise_debug("Buffer allocated with size %zu bytes at %p", size, buffer);`

### LOG
**Purpose**: General operational events
- Use for: Runtime events worth logging but not requiring attention
- Visibility: Always written to logs, useful for auditing/diagnostics
- Performance Impact: Medium
- Example: `raise_log("Processing file %s, size: %zu bytes", filename, file_size);`

### INFO
**Purpose**: Informational messages highlighting progress
- Use for: Normal but noteworthy events, state changes, startup/shutdown events
- Visibility: Visible to client applications if configured
- Performance Impact: Low-Medium
- Example: `raise_info("Connection established to %s, session ID: %s", host, session_id);`

### NOTICE
**Purpose**: More important events than INFO, but not warnings
- Use for: Important state changes, significant operations, configuration changes
- Visibility: Displayed to client by default
- Performance Impact: Low
- Example: `raise_notice("Switching to backup server due to high load");`

### WARN
**Purpose**: Potential problems that don't prevent normal operation
- Use for: Unexpected behaviors, deprecated feature usage, recoverable errors
- Visibility: Alerts both client and server logs
- Performance Impact: Low
- Example: `raise_warn("API call retry limit (%d) reached for endpoint %s", retries, endpoint);`

### EXCEPTION
**Purpose**: Serious errors requiring immediate attention
- Use for: Critical failures, data loss risks, business rule violations
- Visibility: Highest priority, often leads to operation termination
- Performance Impact: Low
- Example: `raise_exception("Failed to open database: %s", error_msg);`

## Setting the Log Level

You can control the verbosity of logs in three ways:

1. **Environment Variable**: Set `LOG_LEVEL` environment variable
   ```sh
   export LOG_LEVEL=DEBUG
   ```

2. **Programmatically**: Use the `logger_level()` function
   ```c
   logger_level(LOG_LEVEL_DEBUG);
   ```

3. **Compile-Time**: Define `PRECOMPILED_LOG_LEVEL` before including hectic.h
   ```c
   #define PRECOMPILED_LOG_LEVEL LOG_LEVEL_INFO
   #include <hectic.h>
   ```

## Logging Best Practices

### DO

- **Be specific and concise**: Include relevant details but avoid verbose descriptions
- **Include context**: Add identifiers (IDs, filenames, pointers) to help with troubleshooting
- **Use the appropriate level**: Understand the purpose of each level and use it accordingly
- **Log state transitions**: Important changes in application state should be logged
- **Use structured data**: When possible, include structured information rather than unformatted text

### DON'T

- **Log sensitive information**: Never log passwords, tokens, or personal information
- **Overuse high-severity levels**: Reserve WARN and EXCEPTION for real issues
- **Log in tight loops**: Avoid excessive logging in performance-critical paths
- **Use inconsistent formats**: Follow a consistent message format throughout your code
- **Ignore log levels**: Don't use DEBUG for important operational events or EXCEPTION for minor issues

## Examples of Good Logging

### Error Handling Pattern

```c
void *allocate_resource(size_t size) {
    raise_debug("Allocating %zu bytes", size);
    
    void *ptr = malloc(size);
    if (!ptr) {
        raise_exception("Memory allocation failed for %zu bytes", size);
        return NULL;
    }
    
    raise_debug("Successfully allocated %zu bytes at %p", size, ptr);
    return ptr;
}
```

### State Transition Pattern

```c
void change_connection_state(Connection *conn, ConnState new_state) {
    raise_debug("Connection %p state change requested: %s -> %s", 
                conn, conn_state_to_string(conn->state), conn_state_to_string(new_state));
    
    if (!is_valid_transition(conn->state, new_state)) {
        raise_warn("Invalid state transition from %s to %s", 
                   conn_state_to_string(conn->state), conn_state_to_string(new_state));
        return;
    }
    
    ConnState old_state = conn->state;
    conn->state = new_state;
    
    raise_info("Connection %s state changed: %s -> %s", 
               conn->id, conn_state_to_string(old_state), conn_state_to_string(new_state));
}
```

### Operation Pattern

```c
int process_file(const char *filename) {
    raise_log("Processing file: %s", filename);
    
    FILE *f = fopen(filename, "r");
    if (!f) {
        raise_warn("Could not open file %s: %s", filename, strerror(errno));
        return -1;
    }
    
    // Process file...
    
    raise_info("Successfully processed file %s: %d records", filename, record_count);
    return 0;
}
``` 