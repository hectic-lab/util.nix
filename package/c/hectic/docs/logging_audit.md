# Logging Audit Guide for Hectic

This guide provides a systematic approach to auditing and improving logging in existing functions of the Hectic library.

## Checklist for Function Audit

### 1. Basic Logging Check

- [ ] Function has entry logging (DEBUG or TRACE level)
- [ ] Function has result/exit logging
- [ ] Failures and errors are logged with appropriate levels (WARN or EXCEPTION)
- [ ] Intermediate steps are logged at TRACE or DEBUG level
- [ ] Successful operation completions are logged at LOG level

### 2. Level Consistency Check

- [ ] `LOG_LEVEL_TRACE` is used for detailed execution tracking
- [ ] `LOG_LEVEL_DEBUG` is used for significant internal steps
- [ ] `LOG_LEVEL_LOG` is used for important operational events and successful operation completions
- [ ] `LOG_LEVEL_INFO` is used *rarely*, only for user-critical events
- [ ] `LOG_LEVEL_NOTICE` is used *very rarely*, almost not needed for a low-level library
- [ ] `LOG_LEVEL_WARN` is used for recoverable problems
- [ ] `LOG_LEVEL_EXCEPTION` is used only for critical errors

### 3. Message Formatting Check

- [ ] Messages start with a domain prefix (PARSE:, ALLOC:, FORMAT:, etc.)
- [ ] Message structure follows the pattern "Action: object (details)"
- [ ] Messages contain sufficient context for understanding (pointers, sizes, values)
- [ ] Messages don't contain redundant information
- [ ] Pointers use %p format
- [ ] Sizes use %zu format
- [ ] Strings use length limitation when necessary (%.20s)
- [ ] NULL pointer checks are added before using pointers in logs

## Logging Level Usage Rules

### TRACE
- Function calls and exits
- Detailed loop iteration information
- Variable values during execution
- Any detailed debugging information

### DEBUG
- Entries to public API functions
- Resource allocation and deallocation
- Key algorithm steps
- Data processing details

### LOG
- Successful component initialization
- Completion of significant operations
- State changes important for operation
- Key business logic points

### INFO (use rarely!)
- Library startup and shutdown
- Version and configuration information
- Extremely important events visible to users
- Large operations requested by users

### NOTICE (almost never use)
- Events that users should pay attention to
- Significant planned actions

### WARN
- Unexpected but handled errors
- Edge cases
- Warnings about potential problems
- Use of deprecated APIs

### EXCEPTION
- Serious errors affecting system operation
- Data integrity violations
- Resource exhaustion
- Critical security failures

## Audit and Update Process

### Step 1: Function Analysis

1. Determine the function type:
   - Initialization/resource management function
   - Data processing function
   - Utility function
   - Other

2. Identify key logging points:
   - Function entry
   - Parameter checks
   - Main processing steps
   - Error conditions
   - Function exit

### Step 2: Update Planning

1. Create a list of necessary logs at each level
2. Determine the right prefixes for each message type
3. Prepare detailed messages with necessary context
4. Ensure parameter checks are logged before use

### Step 3: Implementing Changes

1. Add/update function entry logging
2. Add/update input parameter checks
3. Update intermediate step logging
4. Add/update error condition logging
5. Add/update result logging

### Step 4: Testing

1. Check message output correctness
2. Verify proper level usage
3. Check that all necessary information is included in logs
4. Compare with other already updated functions for consistency

## Examples for Typical Functions

### Memory Allocation Function:

```c
void* memory_function__(const char *file, const char *func, int line, size_t size) {
    // Function entry
    raise_message(LOG_LEVEL_DEBUG, file, func, line, 
                 "ALLOC: Requesting memory allocation (size: %zu bytes)", size);
    
    // Parameter check
    if (size == 0) {
        raise_message(LOG_LEVEL_WARN, file, func, line, 
                     "ALLOC: Zero-sized memory allocation requested");
        return NULL;
    }
    
    // Memory allocation
    void *ptr = malloc(size);
    if (!ptr) {
        raise_message(LOG_LEVEL_EXCEPTION, file, func, line, 
                     "ALLOC: Memory allocation failed (requested: %zu bytes)", size);
        return NULL;
    }
    
    // Result
    raise_message(LOG_LEVEL_LOG, file, func, line, 
                 "ALLOC: Memory allocated successfully (address: %p, size: %zu bytes)", 
                 ptr, size);
    return ptr;
}
```

### Data Conversion Function:

```c
char* convert_function__(const char *file, const char *func, int line, 
                        const void *input, size_t input_size) {
    // Function entry
    raise_message(LOG_LEVEL_DEBUG, file, func, line, 
                 "CONVERT: Starting data conversion (input: %p, size: %zu)", 
                 input, input_size);
    
    // Parameter check
    if (!input) {
        raise_message(LOG_LEVEL_WARN, file, func, line, 
                     "CONVERT: NULL input provided");
        return NULL;
    }
    
    if (input_size == 0) {
        raise_message(LOG_LEVEL_WARN, file, func, line, 
                     "CONVERT: Zero input size provided");
        return NULL;
    }
    
    // Processing start
    raise_message(LOG_LEVEL_TRACE, file, func, line, 
                 "CONVERT: Processing input data...");
    
    // Processing...
    
    // Result
    char *result = NULL; // conversion result
    if (!result) {
        raise_message(LOG_LEVEL_WARN, file, func, line, 
                     "CONVERT: Conversion failed");
        return NULL;
    }
    
    raise_message(LOG_LEVEL_LOG, file, func, line, 
                 "CONVERT: Data conversion completed successfully (result: %p)", result);
    return result;
}
```

## Update Priorities

Recommended order for updating functions:

1. Memory management functions (`arena_*`)
2. Parsing functions (`json_parse_*`)
3. Formatting functions (`json_to_string_*`)
4. Data processing functions (`slice_*`)
5. Utility functions

## Conclusion

Consistent application of these recommendations to functions in the library will significantly improve logging quality and facilitate debugging and code maintenance in the future. 