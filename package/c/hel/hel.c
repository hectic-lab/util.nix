#include <postgres.h>
#include <fmgr.h>
#include <utils/builtins.h>
#include <utils/json.h>
#include <hectic.h>
#include <string.h>

#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC;
#endif

/* Helper function to get a JSON value by key path */
static Json *json_get_by_path(Arena *arena, const Json *context, const char *key_path) {
    if (!context || !key_path || !*key_path) {
        return NULL;
    }
    
    char *path_copy = arena_strdup(arena, key_path);
    char *token = strtok(path_copy, ".");
    Json *current = (Json*)context;
    
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
            return json_to_string(arena, json);
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
    
    return node->value.text.content;
}

/* Render an interpolation node */
static char *render_interpolation_node(Arena *arena, const TemplateNode *node, const Json *context) {
    if (!node || node->type != TEMPLATE_NODE_INTERPOLATE || !context) {
        return "";
    }
    
    const char *key = node->value.interpolate.key;
    Json *value = json_get_by_path(arena, context, key);
    
    if (!value) {
        return "";
    }
    
    return json_value_to_string(arena, value);
}

/* Render a section node (for loop) */
static char *render_section_node(Arena *arena, const TemplateNode *node, const Json *context) {
    if (!node || node->type != TEMPLATE_NODE_SECTION || !context) {
        return "";
    }
    
    const char *collection_key = node->value.section.collection;
    const char *iterator_name = node->value.section.iterator;
    TemplateNode *body = node->value.section.body;
    
    Json *collection = json_get_by_path(arena, context, collection_key);
    
    if (!collection || collection->type != JSON_ARRAY) {
        return "";
    }
    
    size_t buffer_size = 1024;
    char *buffer = arena_alloc(arena, buffer_size);
    size_t buffer_pos = 0;
    
    Json *item = collection->value.child;
    while (item) {
        const char *empty_json = "{}";
        Json *iter_context = json_parse(arena, &empty_json);
        if (!iter_context) {
            return "";
        }
        
        Json *item_json = arena_alloc(arena, sizeof(Json));
        memcpy(item_json, item, sizeof(Json));
        item_json->key = arena_strdup(arena, iterator_name);
        item_json->next = NULL;
        
        char *rendered_body = render_template_node(arena, body, iter_context);
        
        size_t rendered_len = strlen(rendered_body);
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
    if (!node || node->type != TEMPLATE_NODE_INCLUDE || !context) {
        return "";
    }
    
    const char *include_key = node->value.include.key;
    Json *include_value = json_get_by_path(arena, context, include_key);
    
    if (!include_value || include_value->type != JSON_ARRAY) {
        return "";
    }
    
    char *buffer = arena_alloc(arena, 1024);
    size_t buffer_pos = 0;
    
    Json *include_item = include_value->value.child;
    while (include_item) {
        if (include_item->type == JSON_OBJECT) {
            Json *template_json = json_get_object_item(include_item, "template");
            Json *content_json = json_get_object_item(include_item, "content");
            Json *context_json = json_get_object_item(include_item, "context");
            
            if (template_json && template_json->type == JSON_STRING) {
                const char *template_str = template_json->value.string;
                const Json *include_context = context_json ? context_json : context;
                
                TemplateConfig config = template_default_config();
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
    if (!node) {
        return "";
    }
    
    size_t buffer_size = 4096;
    char *output = arena_alloc(arena, buffer_size);
    size_t output_pos = 0;
    
    const TemplateNode *current = node;
    while (current) {
        char *rendered = NULL;
        
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
        
        size_t rendered_len = strlen(rendered);
        if (output_pos + rendered_len + 1 > buffer_size) {
            buffer_size = (output_pos + rendered_len + 1) * 2;
            output = arena_realloc(arena, output, buffer_size / 2, buffer_size);
        }
        
        strcpy(output + output_pos, rendered);
        output_pos += rendered_len;
        
        if (current->children) {
            char *children_rendered = render_template_node(arena, current->children, context);
            size_t children_len = strlen(children_rendered);
            
            if (output_pos + children_len + 1 > buffer_size) {
                buffer_size = (output_pos + children_len + 1) * 2;
                output = arena_realloc(arena, output, buffer_size / 2, buffer_size);
            }
            
            strcpy(output + output_pos, children_rendered);
            output_pos += children_len;
        }
        
        current = current->next;
    }
    
    output[output_pos] = '\0';
    return output;
}

/* Define the function render */
PG_FUNCTION_INFO_V1(render);

/* 
 * Function to render templates using hectic library with JSON context
 * Arguments:
 *   1. declare - JSON context for rendering
 *   2. template - The template text to render
 */
Datum render(PG_FUNCTION_ARGS)
{
    text *context_text = PG_GETARG_TEXT_PP(0);
    text *template_text = PG_GETARG_TEXT_PP(1);
    
    /* Convert input text to C string */
    char *template_str = text_to_cstring(template_text);
    char *context_str = text_to_cstring(context_text);
    
    /* Initialize arena for memory management */
    Arena arena = arena_init(MEM_MiB);
    
    /* Parse the JSON context */
    const char *json_ptr = context_str;
    Json *context = json_parse(&arena, &json_ptr);
    
    if (!context) {
        arena_free(&arena);
        ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                 errmsg("Invalid JSON context")));
    }
    
    /* Parse the template text */
    const char *template_ptr = template_str;
    TemplateConfig config = template_default_config();
    TemplateResult template_result = template_parse(&arena, &template_ptr, &config);
    
    if (IS_RESULT_ERROR(template_result)) {
        arena_free(&arena);
        ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                 errmsg("Failed to parse template: %s", 
                        RESULT_ERROR_MESSAGE(template_result))));
    }
    
    /* Render the template */
    TemplateNode root_node = RESULT_SOME_VALUE(template_result);
    char *result_str = render_template_node(&arena, &root_node, context);
    
    /* Prepare return value */
    text *result = cstring_to_text(result_str);
    
    arena_free(&arena);
    
    PG_RETURN_TEXT_P(result);
}
