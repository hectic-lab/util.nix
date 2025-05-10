#include <postgres.h>
#include <fmgr.h>
#include <utils/builtins.h>
#include <utils/json.h>
#include <utils/jsonb.h>
#include "hectic.h"
#include <string.h>

#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC;
#endif

#define LOG_FILE "/tmp/hemar.log"

#define INIT \
    logger_init(); \
    logger_set_file(LOG_FILE); \
    logger_set_output_mode(LOG_OUTPUT_BOTH); \
    Arena arena = arena_init(MEM_MiB);

#define FREE \
    DISPOSABLE_ARENA_FREE; \
    arena_free(&arena); \
    logger_free(); 

/* helper function to get a JSON value by key path */
static Json *json_get_by_path(Arena *arena, const Json *context, const char *key_path) {
    
    char *path_copy;
    char *token;
    Json *current;

    if (!context || !key_path || !*key_path) {
        return NULL;
    }

    path_copy = arena_strdup(arena, key_path);
    token = strtok(path_copy, ".");
    current = (Json*)context;
    
    while (token && current) {
        current = json_get_object_item(current, token);
        token = strtok(NULL, ".");
    }
    
    return current;
}

/* Convert JSON value to string */
static char *json_value_to_string(Arena *arena, const Json *json) {
    if (!json) {
        return "";
    }
    
    switch (json->type) {
        case JSON_STRING:
            return json->value.string;
        case JSON_NUMBER: {
            char *buf = arena_alloc(arena, 64);
            snprintf(buf, 64, "%.6g", json->value.number);
            return buf;
        }
        case JSON_BOOL:
            return json->value.boolean ? "true" : "false";
        case JSON_NULL:
            return "";
        case JSON_ARRAY:
        case JSON_OBJECT:
            return JSON_TO_STR(arena, json);
        default:
            return "";
    }
}

/* Forward declaration for recursive function */
static char *render_template_node(Arena *arena, const TemplateNode *node, const Json *context);

/* Render a text node */
static char *render_text_node(Arena *arena, const TemplateNode *node) {
    if (!node || node->type != TEMPLATE_NODE_TEXT) {
        return "";
    }
    
    return node->value->text.content;
}

/* Render an interpolation node */
static char *render_interpolation_node(Arena *arena, const TemplateNode *node, const Json *context) {
    const char *key;
    Json *value;

    if (!node || node->type != TEMPLATE_NODE_INTERPOLATE || !context) {
        return "";
    }

    key = node->value->interpolate.key;
    value = json_get_by_path(arena, context, key);
    
    if (!value) {
        return "";
    }
    
    return json_value_to_string(arena, value);
}

/* Render a section node (for loop) */
static char *render_section_node(Arena *arena, const TemplateNode *node, const Json *context) {
    const char *collection_key;
    const char *iterator_name; 
    TemplateNode *body;

    Json *collection;

    size_t buffer_size;
    char *buffer;
    size_t buffer_pos;

    Json *item;

    const char *empty_json;
    Json *iter_context;

    Json *item_json;

    char *rendered_body;
    size_t rendered_len;

    if (!node || node->type != TEMPLATE_NODE_SECTION || !context) {
        return "";
    }
    
    collection_key = node->value->section.collection;
    iterator_name = node->value->section.iterator;
    body = node->value->section.body;
    
    collection = json_get_by_path(arena, context, collection_key);
    
    if (!collection || collection->type != JSON_ARRAY) {
        return "";
    }
    
    buffer_size = 1024;
    buffer = arena_alloc(arena, buffer_size);
    buffer_pos = 0;
    
    item = collection->value.child;
    while (item) {
        empty_json = "{}";
        iter_context = json_parse(arena, &empty_json);
        if (!iter_context) {
            return "";
        }
        
        item_json = arena_alloc(arena, sizeof(Json));
        memcpy(item_json, item, sizeof(Json));
        item_json->key = arena_strdup(arena, iterator_name);
        item_json->next = NULL;
        
        rendered_body = render_template_node(arena, body, iter_context);
        
        rendered_len = strlen(rendered_body);
        if (buffer_pos + rendered_len + 1 > buffer_size) {
            buffer_size = (buffer_pos + rendered_len + 1) * 2;
            buffer = arena_realloc(arena, buffer, buffer_size / 2, buffer_size);
        }
        
        strcpy(buffer + buffer_pos, rendered_body);
        buffer_pos += rendered_len;
        
        item = item->next;
    }
    
    buffer[buffer_pos] = '\0';
    return buffer;
}

/* Render an include node */
static char *render_include_node(Arena *arena, const TemplateNode *node, const Json *context) {
    
    const char *include_key;
    Json *include_value;
    
    char *buffer;
    size_t buffer_pos;

    Json *include_item;
    Json *template_json;
    Json *content_json;
    Json *context_json;

    if (!node || node->type != TEMPLATE_NODE_INCLUDE || !context) {
        return "";
    }
    include_key = node->value->include.key;
    include_value = json_get_by_path(arena, context, include_key);

    if (!include_value || include_value->type != JSON_ARRAY) {
        return "";
    }

    buffer = arena_alloc(arena, 1024);
    buffer_pos = 0;
    
    
    include_item = include_value->value.child;
    while (include_item) {
        if (include_item->type == JSON_OBJECT) {
            template_json = json_get_object_item(include_item, "template");
            content_json = json_get_object_item(include_item, "content");
            context_json = json_get_object_item(include_item, "context");
            
            if (template_json && template_json->type == JSON_STRING) {
                const char *template_str = template_json->value.string;
                const Json *include_context = context_json ? context_json : context;
                
                TemplateConfig config = template_default_config(arena);
                TemplateResult template_result = template_parse(arena, &template_str, &config);
                
                if (!IS_RESULT_ERROR(template_result)) {
                    TemplateNode template_node = RESULT_SOME_VALUE(template_result);
                    
                    char *rendered = render_template_node(arena, &template_node, include_context);
                    
                    buffer_pos += sprintf(buffer + buffer_pos, "%s", rendered);
                }
            } else if (content_json && content_json->type == JSON_STRING) {
                buffer_pos += sprintf(buffer + buffer_pos, "%s", content_json->value.string);
            }
        }
        
        include_item = include_item->next;
    }
    
    buffer[buffer_pos] = '\0';
    return buffer;
}

/* Render a template node tree recursively */
static char *render_template_node(Arena *arena, const TemplateNode *node, const Json *context) {
    
    size_t buffer_size = 4096;
    char *output = arena_alloc(arena, buffer_size);
    size_t output_pos = 0;
    size_t rendered_len;
    const TemplateNode *current;
    char *rendered;

    if (!node) {
        return "";
    }

    current = node;
    
    while (current) {
        rendered = NULL;
        
        switch (current->type) {
            case TEMPLATE_NODE_TEXT:
                rendered = render_text_node(arena, current);
                break;
                
            case TEMPLATE_NODE_INTERPOLATE:
                rendered = render_interpolation_node(arena, current, context);
                break;
                
            case TEMPLATE_NODE_SECTION:
                rendered = render_section_node(arena, current, context);
                break;
                
            case TEMPLATE_NODE_INCLUDE:
                rendered = render_include_node(arena, current, context);
                break;
                
            case TEMPLATE_NODE_EXECUTE:
                todo;
                rendered = "";
                break;
                
            default:
                rendered = "";
                break;
        }
        
        rendered_len = strlen(rendered);
        if (output_pos + rendered_len + 1 > buffer_size) {
            buffer_size = (output_pos + rendered_len + 1) * 2;
            output = arena_realloc(arena, output, buffer_size / 2, buffer_size);
        }
        
        strcpy(output + output_pos, rendered);
        output_pos += rendered_len;
        
        current = current->next;
    }
    
    output[output_pos] = '\0';
    return output;
}

/* Define the function render */
PG_FUNCTION_INFO_V1(pg_render);

/* 
 * Function to render templates using hectic library with JSON context
 * Arguments:
 *   1. declare - JSON context for rendering
 *   2. template - The template text to render
 */
Datum pg_render(PG_FUNCTION_ARGS)
{
    INIT;

    printf("Rendering template\n");

    text *context_text = PG_GETARG_TEXT_PP(0);
    text *template_text = PG_GETARG_TEXT_PP(1);

    printf("Context: %s\n", text_to_cstring(context_text));
    
    /* Convert input text to C string */
    char *template_str = text_to_cstring(template_text);
    char *context_str = text_to_cstring(context_text);

    printf("Template: %s\n", template_str);

    TemplateNode root_node;
    TemplateResult template_result;

    Json *context;

    const char *template_ptr;

    char *result_str;
    text *result;
    
    /* Parse the JSON context */
    const char *json_ptr = context_str;
    TemplateConfig config = template_default_config(&arena);
    context = json_parse(&arena, &json_ptr);
    
    if (!context) {
        FREE;
        ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                 errmsg("Invalid JSON context")));
    }
    
    /* Parse the template text */
    template_ptr = template_str;
    template_result = template_parse(&arena, &template_ptr, &config);
    
    if (IS_RESULT_ERROR(template_result)) {
        FREE;
        ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                 errmsg("Failed to parse template: %s", 
                        RESULT_ERROR_MESSAGE(template_result))));
    }
    
    /* Render the template */
    root_node = RESULT_SOME_VALUE(template_result);
    result_str = render_template_node(&arena, &root_node, context);
    
    /* Prepare return value */
    result = cstring_to_text(result_str);
    
    FREE;
    PG_RETURN_TEXT_P(result);
}

PG_FUNCTION_INFO_V1(pg_test_log);

Datum pg_test_log(PG_FUNCTION_ARGS) {
    INIT;
    raise_info("Testing log");

    FREE;
    PG_RETURN_VOID();
}

PG_FUNCTION_INFO_V1(pg_test_log_2);

Datum pg_test_log_2(PG_FUNCTION_ARGS) {
    INIT;
    raise_info("Testing log");

    text *context_text = PG_GETARG_TEXT_PP(0);
    text *template_text = PG_GETARG_TEXT_PP(1);

    raise_info("Context: %s", text_to_cstring(context_text));
    raise_info("Template: %s", text_to_cstring(template_text));

    FREE;
    PG_RETURN_VOID();
}

PG_FUNCTION_INFO_V1(pg_template_parse);

Datum pg_template_parse(PG_FUNCTION_ARGS) {
    INIT;

    text *context_text = PG_GETARG_TEXT_PP(0);
    char *content = text_to_cstring(context_text);

    const char *template_ptr;
    TemplateResult template_result;
    TemplateConfig config = template_default_config(&arena);

    raise_info("start parsing....");
    template_result = template_parse(&arena, &template_ptr, &config);
    raise_info("parsing finished....");

    if (IS_RESULT_ERROR(template_result)) {
        FREE;
        ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                 errmsg("Failed to parse template: %s", 
                        RESULT_ERROR_MESSAGE(template_result))));
    }

    const char *json_str = TEMPLATE_NODE_TO_JSON_STR(&arena, &(RESULT_SOME_VALUE(template_result)));
    Json *json = json_parse(&arena, &json_str); \

    char *result_str = JSON_TO_STR(&arena, json);

    raise_notice("%s", result_str);

    char *result_str_clone = malloc(strlen(result_str) + 1);
    if (result_str_clone) strcpy(result_str_clone, result_str);

    FREE;

    text *result = cstring_to_text(result_str_clone);
    PG_RETURN_TEXT_P(result);
}
