# Logging System Improvement Plan for Hectic Library

## Current Issues

After analyzing the logging in the hectic library, the following issues have been identified:

1. **Inconsistent message formatting** - messages are formatted differently in various parts of the code
2. **Inefficient use of logging levels** - levels don't always correspond to the nature of the message
3. **Incomplete logging** - some important operations aren't logged at all
4. **Lack of context** - messages don't always contain necessary context for debugging
5. **Mixed formats** - no unified style for logging different types of data

## Standardizing Logging by Function Types

### 1. Initialization and Resource Management Functions

**Logging pattern:**

1. `LOG_LEVEL_DEBUG` when entering a function with parameters
2. `LOG_LEVEL_DEBUG` when performing significant steps within the function
3. `LOG_LEVEL_LOG` on successful resource allocation/initialization
4. `LOG_LEVEL_WARN` for warning conditions
5. `LOG_LEVEL_EXCEPTION` for critical errors

**Example (arena_init):**

```c
Arena arena_init__(const char *file, const char *func, int line, size_t size) {
    raise_message(LOG_LEVEL_DEBUG, file, func, line, 
        "Initializing arena with size %zu bytes", size);
    
    Arena arena;
    arena.begin = malloc(size);
    
    if (!arena.begin) {
        raise_message(LOG_LEVEL_EXCEPTION, file, func, line,
            "Failed to allocate memory for arena (requested %zu bytes)", size);
        exit(1);
    }
    
    memset(arena.begin, 0, size);
    arena.current = arena.begin;
    arena.capacity = size;
    
    raise_message(LOG_LEVEL_LOG, file, func, line,
        "Arena initialized: address=%p, capacity=%zu bytes", arena.begin, size);
    return arena;
}
```

### 2. Data Processing Functions (parsers, serializers)

**Logging pattern:**

1. `LOG_LEVEL_DEBUG` when entering a function with main parameters
2. `LOG_LEVEL_TRACE` for detailed tracking of parsing/serialization steps
3. `LOG_LEVEL_DEBUG` when discovering intermediate results
4. `LOG_LEVEL_WARN` for recoverable format issues
5. `LOG_LEVEL_EXCEPTION` for unrecoverable format errors
6. `LOG_LEVEL_LOG` on successful completion of a significant operation

**Example (for json_parse):**

```c
Json *json_parse__(const char* file, const char* func, int line, Arena *arena, const char **s) {
    raise_message(LOG_LEVEL_DEBUG, file, func, line, 
        "Starting JSON parsing from position %p", *s);
    
    // Start parsing
    if (!s || !*s) {
        raise_message(LOG_LEVEL_EXCEPTION, file, func, line,
            "Invalid input: NULL pointer provided for JSON parsing");
        return NULL;
    }
    
    // Show first 20 characters for debugging
    raise_message(LOG_LEVEL_TRACE, file, func, line,
        "JSON input preview: '%.20s%s'", *s, strlen(*s) > 20 ? "..." : "");
    
    Json *result = json_parse_value__(file, func, line, s, arena);
    
    if (!result) {
        raise_message(LOG_LEVEL_WARN, file, func, line, 
            "JSON parsing failed at position: %p", *s);
    } else {
        raise_message(LOG_LEVEL_LOG, file, func, line, 
            "JSON parsed successfully, type: %d", result->type);
    }
    
    return result;
}
```

### 3. Utility Functions

**Logging pattern:**

1. `LOG_LEVEL_TRACE` when entering a function with full parameters
2. `LOG_LEVEL_DEBUG` for logging important intermediate steps
3. `LOG_LEVEL_LOG` for successful operation completion
4. `LOG_LEVEL_WARN` for unusual but handled situations
5. `LOG_LEVEL_TRACE` when exiting with a result

**Example (substr_clone):**

```c
void substr_clone__(const char *file, const char *func, int line, 
                    const char * const src, char *dest, size_t from, size_t len) {
    raise_message(LOG_LEVEL_TRACE, file, func, line,
        "Entering substring clone: src=%p (\"%s\"), dest=%p, from=%zu, len=%zu",
        src, src ? (strlen(src) < 20 ? src : "<long string>") : "<null>", 
        dest, from, len);
    
    if (!src || !dest) {
        raise_message(LOG_LEVEL_EXCEPTION, file, func, line,
            "Invalid NULL pointer: %s%s",
            (!src ? "src " : ""), (!dest ? "dest" : ""));
        if (dest) dest[0] = '\0';
        return;
    }
    
    size_t srclen = strlen(src);
    if (from >= srclen) {
        raise_message(LOG_LEVEL_WARN, file, func, line,
            "Out of range: 'from' index (%zu) exceeds source length (%zu)",
            from, srclen);
        dest[0] = '\0';
        return;
    }
    
    if (from + len > srclen) {
        size_t old_len = len;
        len = srclen - from;
        raise_message(LOG_LEVEL_DEBUG, file, func, line,
            "Adjusted length from %zu to %zu to fit source bounds",
            old_len, len);
    }
    
    strncpy(dest, src + from, len);
    dest[len] = '\0';
    
    raise_message(LOG_LEVEL_TRACE, file, func, line,
        "Substring cloned: result=\"%s\", copied_length=%zu",
        dest, len);
}
```

## Log Naming Standards

### 1. Function Prefixes

To make logs easier to search, use prefixes in messages:

- **INIT:** - for initialization logs
- **ALLOC:** - for memory allocation logs  
- **PARSE:** - for parsing logs
- **PROCESS:** - for data processing logs
- **FREE:** - for resource freeing logs

### 2. Message Structure

All messages should have a consistent structure:

- **Action**: What is being done (verb in present continuous)
- **Object**: What is being acted upon (noun phrase)
- **Details**: Additional information (in parentheses or after a colon)

**Examples:**
- "Initializing arena (size: %zu bytes)"
- "Processing JSON object with %d members"
- "Allocating memory block: address=%p, size=%zu"

## Logging Levels

Recommendations for using logging levels in a low-level library:

1. **TRACE (Very detailed)** - For detailed tracking of function operation:
   - Function entry/exit
   - Data contents
   - Intermediate variable values
   - Processing loop details

2. **DEBUG (Detailed)** - For programmers working with the library:
   - Main algorithm steps
   - Resource allocation/freeing
   - Intermediate object states
   - Debugging information

3. **LOG (Operational)** - For important library operations:
   - Successful resource initialization
   - Successful operation completion
   - System state changes
   - Main execution points of working algorithms

4. **INFO (Informational)** - For informing the application user:
   - *This level should be used rarely in the library*
   - Only truly important events for the user
   - Version and configuration information
   - High-level public API calls

5. **NOTICE (Notable)** - Important state changes:
   - *Almost never used in a low-level library*
   - Events requiring user attention
   - Important business events (if applicable)

6. **WARN (Warning)** - Potentially problematic situations:
   - Recoverable errors
   - Edge cases in data
   - Requests with potentially bad results
   - Deprecated APIs

7. **EXCEPTION (Exceptional situation)** - Critical errors:
   - Unrecoverable errors
   - Data integrity violations
   - Resource exhaustion
   - Errors requiring termination

## Action Plan for Logging Improvement

1. **Automation**: Create a script to find inconsistencies in logging
2. **Prioritization**: First update the most critical components (memory management, parsers)
3. **Documentation**: Expand documentation with examples for developers
4. **Testing**: Add tests that check logging under various scenarios
5. **Review**: Conduct code reviews of all logging changes

## Examples for Different Modules

### Memory Management (arena)

```c
// Initialization
raise_message(LOG_LEVEL_DEBUG, file, func, line, "INIT: Creating new arena (size: %zu bytes)", size);

// Allocation
raise_message(LOG_LEVEL_DEBUG, file, func, line, "ALLOC: Requesting memory from arena (size: %zu bytes, available: %zu bytes)", size, available);

// Error
raise_message(LOG_LEVEL_EXCEPTION, file, func, line, "ERROR: Arena memory exhausted (requested: %zu bytes, available: %zu bytes)", size, available);

// Successful operation completion
raise_message(LOG_LEVEL_LOG, file, func, line, "ALLOC: Memory allocated successfully (address: %p, size: %zu bytes)", ptr, size);

// Freeing
raise_message(LOG_LEVEL_DEBUG, file, func, line, "FREE: Releasing arena resources (total size: %zu bytes, used: %zu bytes)", arena->capacity, used);
```

### JSON Parser

```c
// Start parsing
raise_message(LOG_LEVEL_DEBUG, file, func, line, "PARSE: Starting JSON parsing (input: %.20s%s)", *s, strlen(*s) > 20 ? "..." : "");

// Intermediate result
raise_message(LOG_LEVEL_TRACE, file, func, line, "PARSE: Found JSON %s at position %p", type_str, position);

// Parsing error
raise_message(LOG_LEVEL_WARN, file, func, line, "PARSE: Invalid JSON syntax at position %p (context: '%.10s')", *s, *s);

// Completion
raise_message(LOG_LEVEL_LOG, file, func, line, "PARSE: JSON parsing completed successfully (type: %s, size: %zu bytes)", type_str, size);
```

### Slice Operations

```c
// Creating a slice
raise_message(LOG_LEVEL_TRACE, file, func, line, "SLICE: Creating slice from array (source size: %zu, slice: %zu elements from index %zu)", array_len, len, start);

// Subslice
raise_message(LOG_LEVEL_TRACE, file, func, line, "SLICE: Extracting sub-slice (from: %zu, length: %zu)", start, len);

// Error 
raise_message(LOG_LEVEL_WARN, file, func, line, "SLICE: Out of bounds slice request (start: %zu, length: %zu, available: %zu)", start, len, available);

// Successful creation
raise_message(LOG_LEVEL_LOG, file, func, line, "SLICE: Successfully created slice (length: %zu, element size: %zu)", slice.len, slice.isize);
```

## Conclusion

Implementing these standards will:
1. Simplify library debugging
2. Speed up code understanding for new developers
3. Make it easier to find problems in production
4. Make the library more professional and maintainable 