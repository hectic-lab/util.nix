/*
 * hemar.c
 * Template parser implementation for Hemar
 */
#include "hemar.h"
#include "postgres.h"

#include <string.h>
#include <ctype.h>

#include "utils/elog.h"
#include "utils/memutils.h"
#include "mb/pg_wchar.h"
#include "fmgr.h"
#include "utils/builtins.h"
#include "lib/stringinfo.h"
#include "utils/jsonb.h"
#include "catalog/pg_type.h"
#include "executor/spi.h"
#include "funcapi.h"

/* Forward declarations */
static char *get_jsonb_path_value(Datum jsonb_context, const char *path, bool *found);
static Datum get_jsonb_array(Datum jsonb_context, const char *path, bool *found);
static int get_jsonb_array_length(Datum jsonb_array);
static Datum get_jsonb_array_element(Datum jsonb_array, int index);
static Datum create_iterator_context(Datum parent_context, const char *iterator_name, Datum item_context);
static Datum get_jsonb_include_template(Datum jsonb_context, const char *key, bool *found);
static void get_include_data(Datum include_data, char **template_out, Datum *context_out);
static void template_node_to_string(TemplateNode *node, StringInfo result, int indent);

/* Helper function to skip whitespace */
static const char *
skip_whitespace(const char *s)
{
    while (*s && isspace((unsigned char)*s))
        s++;
    return s;
}

/* Initialize template value based on type */
static TemplateValue
init_template_value(TemplateNodeType type)
{
    TemplateValue value;
    
    switch (type)
    {
        case TEMPLATE_NODE_TEXT:
            value.text.content = NULL;
            break;
        case TEMPLATE_NODE_INTERPOLATE:
            value.interpolate.key = NULL;
            break;
        case TEMPLATE_NODE_SECTION:
            value.section.iterator = NULL;
            value.section.collection = NULL;
            value.section.body = NULL;
            break;
        case TEMPLATE_NODE_EXECUTE:
            value.execute.code = NULL;
            break;
        case TEMPLATE_NODE_INCLUDE:
            value.include.key = NULL;
            break;
        default:
            elog(ERROR, "Unknown template node type: %d", type);
            /* This won't be reached due to elog(ERROR) */
            memset(&value, 0, sizeof(value));
            break;
    }
    
    return value;
}

/* Initialize a new template node */
static TemplateNode *
init_template_node(MemoryContext context, TemplateNodeType type)
{
    TemplateNode *node;
    
    node = (TemplateNode *) MemoryContextAlloc(context, sizeof(TemplateNode));
    node->next = NULL;
    node->type = type;
    node->value = (TemplateValue *) MemoryContextAlloc(context, sizeof(TemplateValue));
    *node->value = init_template_value(type);
    
    return node;
}

/* Error code to string conversion */
const char *
template_error_to_string(TemplateErrorCode code)
{
    switch (code)
    {
        case TEMPLATE_ERROR_NONE:
            return "No error";
        case TEMPLATE_ERROR_UNKNOWN_TAG:
            return "Unknown tag";
        case TEMPLATE_ERROR_NESTED_INTERPOLATION:
            return "Nested interpolation";
        case TEMPLATE_ERROR_NESTED_SECTION_ITERATOR:
            return "Nested section iterator";
        case TEMPLATE_ERROR_UNEXPECTED_SECTION_END:
            return "Unexpected section end";
        case TEMPLATE_ERROR_NESTED_INCLUDE:
            return "Nested include";
        case TEMPLATE_ERROR_NESTED_EXECUTE:
            return "Nested execute";
        case TEMPLATE_ERROR_INVALID_CONFIG:
            return "Invalid config";
        case TEMPLATE_ERROR_OUT_OF_MEMORY:
            return "Out of memory";
        case TEMPLATE_ERROR_UNEXPECTED_INCLUDE_END:
            return "Unexpected include end";
        case TEMPLATE_ERROR_UNEXPECTED_EXECUTE_END:
            return "Unexpected execute end";
        default:
            return "Unknown error";
    }
}

/* Default template configuration */
TemplateConfig
template_default_config(MemoryContext context)
{
    TemplateConfig config;
    
    config.Syntax.Braces.open = "{%";
    config.Syntax.Braces.close = "%}";
    config.Syntax.Section.control = "for ";
    config.Syntax.Section.source = "in ";
    config.Syntax.Section.begin = "do ";
    config.Syntax.Interpolate.invoke = "";
    config.Syntax.Include.invoke = "include ";
    config.Syntax.Execute.invoke = "exec ";
    config.Syntax.nesting = "->";
    
    return config;
}

/* Validate template configuration */
bool
template_validate_config(const TemplateConfig *config, TemplateErrorCode *error_code)
{
    if (!config)
    {
        if (error_code)
            *error_code = TEMPLATE_ERROR_INVALID_CONFIG;
        return false;
    }

    /* Check open brace */
    if (!config->Syntax.Braces.open || strlen(config->Syntax.Braces.open) > TEMPLATE_MAX_PREFIX_LEN)
    {
        if (error_code)
            *error_code = TEMPLATE_ERROR_INVALID_CONFIG;
        return false;
    }
    
    /* Check close brace */
    if (!config->Syntax.Braces.close || strlen(config->Syntax.Braces.close) > TEMPLATE_MAX_PREFIX_LEN)
    {
        if (error_code)
            *error_code = TEMPLATE_ERROR_INVALID_CONFIG;
        return false;
    }
    
    /* Check section control */
    if (!config->Syntax.Section.control || strlen(config->Syntax.Section.control) > TEMPLATE_MAX_PREFIX_LEN)
    {
        if (error_code)
            *error_code = TEMPLATE_ERROR_INVALID_CONFIG;
        return false;
    }
    
    /* Check section source */
    if (!config->Syntax.Section.source || strlen(config->Syntax.Section.source) > TEMPLATE_MAX_PREFIX_LEN)
    {
        if (error_code)
            *error_code = TEMPLATE_ERROR_INVALID_CONFIG;
        return false;
    }
    
    /* Check section begin */
    if (!config->Syntax.Section.begin || strlen(config->Syntax.Section.begin) > TEMPLATE_MAX_PREFIX_LEN)
    {
        if (error_code)
            *error_code = TEMPLATE_ERROR_INVALID_CONFIG;
        return false;
    }
    
    /* Check interpolate invoke */
    if (!config->Syntax.Interpolate.invoke || strlen(config->Syntax.Interpolate.invoke) > TEMPLATE_MAX_PREFIX_LEN)
    {
        if (error_code)
            *error_code = TEMPLATE_ERROR_INVALID_CONFIG;
        return false;
    }
    
    /* Check include invoke */
    if (!config->Syntax.Include.invoke || strlen(config->Syntax.Include.invoke) > TEMPLATE_MAX_PREFIX_LEN)
    {
        if (error_code)
            *error_code = TEMPLATE_ERROR_INVALID_CONFIG;
        return false;
    }
    
    /* Check execute invoke */
    if (!config->Syntax.Execute.invoke || strlen(config->Syntax.Execute.invoke) > TEMPLATE_MAX_PREFIX_LEN)
    {
        if (error_code)
            *error_code = TEMPLATE_ERROR_INVALID_CONFIG;
        return false;
    }
    
    /* Check nesting */
    if (!config->Syntax.nesting || strlen(config->Syntax.nesting) > TEMPLATE_MAX_PREFIX_LEN)
    {
        if (error_code)
            *error_code = TEMPLATE_ERROR_INVALID_CONFIG;
        return false;
    }
    
    if (error_code)
        *error_code = TEMPLATE_ERROR_NONE;
    return true;
}

/* Parse interpolation tag */
static TemplateNode *
template_parse_interpolation(MemoryContext context, const char **s_ptr, 
                            const TemplateConfig *config, TemplateErrorCode *error_code)
{
    const char **s = s_ptr;
    const char *key_start;
    size_t key_len;
    TemplateNode *node;
    
    node = init_template_node(context, TEMPLATE_NODE_INTERPOLATE);
    
    /* Skip to the content */
    *s += strlen(config->Syntax.Braces.open);
    *s = skip_whitespace(*s);
    *s += strlen(config->Syntax.Interpolate.invoke);
    
    *s = skip_whitespace(*s);
    key_start = *s;
    
    while (**s != '\0')
    {
        if (isspace((unsigned char)**s) || 
            strncmp(*s, config->Syntax.Braces.close, strlen(config->Syntax.Braces.close)) == 0)
            break;
            
        if (strncmp(*s, config->Syntax.Braces.open, strlen(config->Syntax.Braces.open)) == 0)
        {
            if (error_code)
                *error_code = TEMPLATE_ERROR_NESTED_INTERPOLATION;
            template_free_node(node);
            return NULL;
        }
        
        (*s)++;
    }
    
    key_len = *s - key_start;
    node->value->interpolate.key = MemoryContextStrdup(context, pnstrdup(key_start, key_len));
    
    *s = skip_whitespace(*s);
    
    /* Check for closing brace */
    if (strncmp(*s, config->Syntax.Braces.close, strlen(config->Syntax.Braces.close)) != 0)
    {
        if (error_code)
            *error_code = TEMPLATE_ERROR_UNEXPECTED_SECTION_END;
        template_free_node(node);
        return NULL;
    }
    
    *s_ptr = *s + strlen(config->Syntax.Braces.close);
    
    return node;
}

/* Parse section tag */
static TemplateNode *
template_parse_section(MemoryContext context, const char **s_ptr,
                      const TemplateConfig *config, TemplateErrorCode *error_code)
{
    const char **s = s_ptr;
    const char *iterator_start, *collection_start;
    size_t iterator_len, collection_len;
    TemplateNode *node, *body_node;
    
    node = init_template_node(context, TEMPLATE_NODE_SECTION);
    
    /* Skip to the content */
    *s += strlen(config->Syntax.Braces.open);
    *s = skip_whitespace(*s);
    *s += strlen(config->Syntax.Section.control);
    
    /* Find the iterator name */
    *s = skip_whitespace(*s);
    iterator_start = *s;
    
    while (**s != '\0')
    {
        if (isspace((unsigned char)**s) || 
            strncmp(*s, config->Syntax.Section.source, strlen(config->Syntax.Section.source)) == 0)
            break;
            
        if (strncmp(*s, config->Syntax.Braces.open, strlen(config->Syntax.Braces.open)) == 0)
        {
            if (error_code)
                *error_code = TEMPLATE_ERROR_NESTED_SECTION_ITERATOR;
            template_free_node(node);
            return NULL;
        }
        
        if (strncmp(*s, config->Syntax.Braces.close, strlen(config->Syntax.Braces.close)) == 0)
        {
            if (error_code)
                *error_code = TEMPLATE_ERROR_UNEXPECTED_SECTION_END;
            template_free_node(node);
            return NULL;
        }
        
        (*s)++;
    }
    
    iterator_len = *s - iterator_start;
    node->value->section.iterator = MemoryContextStrdup(context, pnstrdup(iterator_start, iterator_len));
    
    /* Find the collection name */
    *s = skip_whitespace(*s);
    
    if (strncmp(*s, config->Syntax.Section.source, strlen(config->Syntax.Section.source)) != 0)
    {
        if (error_code)
            *error_code = TEMPLATE_ERROR_UNEXPECTED_SECTION_END;
        template_free_node(node);
        return NULL;
    }
    
    *s += strlen(config->Syntax.Section.source);
    *s = skip_whitespace(*s);
    collection_start = *s;
    
    while (**s != '\0')
    {
        if (isspace((unsigned char)**s) || 
            strncmp(*s, config->Syntax.Section.begin, strlen(config->Syntax.Section.begin)) == 0)
            break;
            
        if (strncmp(*s, config->Syntax.Braces.open, strlen(config->Syntax.Braces.open)) == 0)
        {
            if (error_code)
                *error_code = TEMPLATE_ERROR_NESTED_SECTION_ITERATOR;
            template_free_node(node);
            return NULL;
        }
        
        if (strncmp(*s, config->Syntax.Braces.close, strlen(config->Syntax.Braces.close)) == 0)
        {
            if (error_code)
                *error_code = TEMPLATE_ERROR_UNEXPECTED_SECTION_END;
            template_free_node(node);
            return NULL;
        }
        
        (*s)++;
    }
    
    collection_len = *s - collection_start;
    node->value->section.collection = MemoryContextStrdup(context, pnstrdup(collection_start, collection_len));
    
    /* Check for 'do' keyword */
    *s = skip_whitespace(*s);
    if (strncmp(*s, config->Syntax.Section.begin, strlen(config->Syntax.Section.begin)) != 0)
    {
        if (error_code)
            *error_code = TEMPLATE_ERROR_UNEXPECTED_SECTION_END;
        template_free_node(node);
        return NULL;
    }
    
    *s += strlen(config->Syntax.Section.begin);
    
    /* Parse the body */
    body_node = template_parse(context, s, config, true, error_code);
    if (!body_node)
    {
        template_free_node(node);
        return NULL;
    }
    
    node->value->section.body = body_node;
    
    /* Skip to the end of the section */
    *s = skip_whitespace(*s);
    
    /* Check for closing brace */
    if (strncmp(*s, config->Syntax.Braces.close, strlen(config->Syntax.Braces.close)) != 0)
    {
        if (error_code)
            *error_code = TEMPLATE_ERROR_UNEXPECTED_SECTION_END;
        template_free_node(node);
        return NULL;
    }
    
    *s_ptr = *s + strlen(config->Syntax.Braces.close);
    
    return node;
}

/* Parse include tag */
static TemplateNode *
template_parse_include(MemoryContext context, const char **s_ptr,
                      const TemplateConfig *config, TemplateErrorCode *error_code)
{
    const char **s = s_ptr;
    const char *include_start;
    size_t include_len;
    TemplateNode *node;
    
    node = init_template_node(context, TEMPLATE_NODE_INCLUDE);
    
    /* Skip to the content */
    *s += strlen(config->Syntax.Braces.open);
    *s = skip_whitespace(*s);
    *s += strlen(config->Syntax.Include.invoke);
    
    *s = skip_whitespace(*s);
    include_start = *s;
    
    while (**s != '\0')
    {
        if (isspace((unsigned char)**s) || 
            strncmp(*s, config->Syntax.Braces.close, strlen(config->Syntax.Braces.close)) == 0)
            break;
            
        if (strncmp(*s, config->Syntax.Braces.open, strlen(config->Syntax.Braces.open)) == 0)
        {
            if (error_code)
                *error_code = TEMPLATE_ERROR_NESTED_INCLUDE;
            template_free_node(node);
            return NULL;
        }
        
        (*s)++;
    }
    
    include_len = *s - include_start;
    node->value->include.key = MemoryContextStrdup(context, pnstrdup(include_start, include_len));
    
    *s = skip_whitespace(*s);
    
    /* Check for closing brace */
    if (strncmp(*s, config->Syntax.Braces.close, strlen(config->Syntax.Braces.close)) != 0)
    {
        if (error_code)
            *error_code = TEMPLATE_ERROR_UNEXPECTED_INCLUDE_END;
        template_free_node(node);
        return NULL;
    }
    
    *s_ptr = *s + strlen(config->Syntax.Braces.close);
    
    return node;
}

/* Parse execute tag */
static TemplateNode *
template_parse_execute(MemoryContext context, const char **s_ptr,
                      const TemplateConfig *config, TemplateErrorCode *error_code)
{
    const char **s = s_ptr;
    const char *code_start;
    size_t code_len;
    TemplateNode *node;
    
    node = init_template_node(context, TEMPLATE_NODE_EXECUTE);
    
    /* Skip to the content */
    *s += strlen(config->Syntax.Braces.open);
    *s = skip_whitespace(*s);
    *s += strlen(config->Syntax.Execute.invoke);
    
    *s = skip_whitespace(*s);
    code_start = *s;
    
    while (**s != '\0')
    {
        if (strncmp(*s, config->Syntax.Braces.close, strlen(config->Syntax.Braces.close)) == 0)
            break;
            
        if (strncmp(*s, config->Syntax.Braces.open, strlen(config->Syntax.Braces.open)) == 0)
        {
            if (error_code)
                *error_code = TEMPLATE_ERROR_NESTED_EXECUTE;
            template_free_node(node);
            return NULL;
        }
        
        (*s)++;
    }
    
    code_len = *s - code_start;
    node->value->execute.code = MemoryContextStrdup(context, pnstrdup(code_start, code_len));
    
    /* Check for closing brace */
    if (strncmp(*s, config->Syntax.Braces.close, strlen(config->Syntax.Braces.close)) != 0)
    {
        if (error_code)
            *error_code = TEMPLATE_ERROR_UNEXPECTED_EXECUTE_END;
        template_free_node(node);
        return NULL;
    }
    
    *s_ptr = *s + strlen(config->Syntax.Braces.close);
    
    return node;
}

/* Main template parser function */
TemplateNode *
template_parse(MemoryContext context, const char **s, const TemplateConfig *config, 
              bool inner_parse, TemplateErrorCode *error_code)
{
    const char *start;
    TemplateNode *root, *current, *tag_node;
    bool current_node_filled = false;
    const char *tag_prefix;
    size_t text_len;
    
    if (!template_validate_config(config, error_code))
    {
        return NULL;
    }
    
    start = *s;
    root = init_template_node(context, TEMPLATE_NODE_TEXT);
    current = root;
    
    while (*s && **s != '\0')
    {
        /* Check for closing brace in inner parse */
        if (inner_parse && strncmp(*s, config->Syntax.Braces.close, strlen(config->Syntax.Braces.close)) == 0)
        {
            break;
        }
        
        if (strncmp(*s, config->Syntax.Braces.open, strlen(config->Syntax.Braces.open)) == 0)
        {
            /* Handle text before tag */
            if (start != *s)
            {
                if (current_node_filled)
                {
                    TemplateNode *new_node = init_template_node(context, TEMPLATE_NODE_TEXT);
                    current->next = new_node;
                    current = new_node;
                }
                else
                {
                    current->type = TEMPLATE_NODE_TEXT;
                    *current->value = init_template_value(TEMPLATE_NODE_TEXT);
                }
                
                text_len = *s - start;
                current->value->text.content = MemoryContextStrdup(context, pnstrdup(start, text_len));
                current_node_filled = true;
            }
            
            /* Parse the tag */
            tag_node = NULL;
            tag_prefix = *s + strlen(config->Syntax.Braces.open);
            tag_prefix = skip_whitespace(tag_prefix);
            
            /* Determine tag type by prefix */
            if (strncmp(tag_prefix, config->Syntax.Section.control, strlen(config->Syntax.Section.control)) == 0)
            {
                tag_node = template_parse_section(context, s, config, error_code);
            }
            else if (strncmp(tag_prefix, config->Syntax.Include.invoke, strlen(config->Syntax.Include.invoke)) == 0)
            {
                tag_node = template_parse_include(context, s, config, error_code);
            }
            else if (strncmp(tag_prefix, config->Syntax.Execute.invoke, strlen(config->Syntax.Execute.invoke)) == 0)
            {
                tag_node = template_parse_execute(context, s, config, error_code);
            }
            else if (strncmp(tag_prefix, config->Syntax.Interpolate.invoke, strlen(config->Syntax.Interpolate.invoke)) == 0)
            {
                tag_node = template_parse_interpolation(context, s, config, error_code);
            }
            else
            {
                if (error_code)
                    *error_code = TEMPLATE_ERROR_UNKNOWN_TAG;
                template_free_node(root);
                return NULL;
            }
            
            if (!tag_node)
            {
                template_free_node(root);
                return NULL;
            }
            
            if (current_node_filled)
            {
                current->next = tag_node;
                current = tag_node;
            }
            else
            {
                *current = *tag_node;
                pfree(tag_node);
            }
            
            current_node_filled = true;
            start = *s;
        }
        else
        {
            (*s)++;
        }
    }
    
    /* Handle remaining text */
    if (start != *s)
    {
        if (current_node_filled)
        {
            TemplateNode *new_node = init_template_node(context, TEMPLATE_NODE_TEXT);
            current->next = new_node;
            current = new_node;
        }
        else
        {
            current->type = TEMPLATE_NODE_TEXT;
            *current->value = init_template_value(TEMPLATE_NODE_TEXT);
        }
        
        text_len = *s - start;
        current->value->text.content = MemoryContextStrdup(context, pnstrdup(start, text_len));
        current_node_filled = true;
    }
    
    /* If no nodes were created, ensure we have at least an empty text node */
    if (!current_node_filled)
    {
        current->type = TEMPLATE_NODE_TEXT;
        *current->value = init_template_value(TEMPLATE_NODE_TEXT);
        current->value->text.content = MemoryContextStrdup(context, "");
    }
    
    if (error_code)
        *error_code = TEMPLATE_ERROR_NONE;
    
    return root;
}

/* Free a template node and all its children */
void
template_free_node(TemplateNode *node)
{
    TemplateNode *current, *next;
    
    if (!node)
        return;
    
    current = node;
    
    while (current)
    {
        next = current->next;
        
        if (current->value)
        {
            switch (current->type)
            {
                case TEMPLATE_NODE_TEXT:
                    if (current->value->text.content)
                        pfree(current->value->text.content);
                    break;
                    
                case TEMPLATE_NODE_INTERPOLATE:
                    if (current->value->interpolate.key)
                        pfree(current->value->interpolate.key);
                    break;
                    
                case TEMPLATE_NODE_SECTION:
                    if (current->value->section.iterator)
                        pfree(current->value->section.iterator);
                    if (current->value->section.collection)
                        pfree(current->value->section.collection);
                    if (current->value->section.body)
                        template_free_node(current->value->section.body);
                    break;
                    
                case TEMPLATE_NODE_EXECUTE:
                    if (current->value->execute.code)
                        pfree(current->value->execute.code);
                    break;
                    
                case TEMPLATE_NODE_INCLUDE:
                    if (current->value->include.key)
                        pfree(current->value->include.key);
                    break;
                    
                default:
                    /* Should not happen */
                    break;
            }
            
            pfree(current->value);
        }
        
        pfree(current);
        current = next;
    }
}

/* Render a template with the given context */
static char *
template_render(MemoryContext context, TemplateNode *node, Datum jsonb_context, bool *error)
{
    StringInfoData result;
    TemplateNode *current;
    
    if (!node || !context || error == NULL)
    {
        if (error)
            *error = true;
        return NULL;
    }
    
    *error = false;
    initStringInfo(&result);
    current = node;
    
    while (current)
    {
        switch (current->type)
        {
            case TEMPLATE_NODE_TEXT:
                if (current->value->text.content)
                    appendStringInfoString(&result, current->value->text.content);
                break;
                
            case TEMPLATE_NODE_INTERPOLATE:
                {
                    char *value = NULL;
                    bool found = false;
                    
                    if (current->value->interpolate.key)
                    {
                        /* Extract value from JSONB context */
                        value = get_jsonb_path_value(jsonb_context, current->value->interpolate.key, &found);
                        
                        if (found && value)
                        {
                            appendStringInfoString(&result, value);
                            pfree(value);
                        }
                    }
                }
                break;
                
            case TEMPLATE_NODE_SECTION:
                {
                    /* Handle sections (loops) */
                    char *collection_path = current->value->section.collection;
                    Datum array_value;
                    bool found = false;
                    int array_length;
                    int i;
                    
                    if (collection_path && current->value->section.body)
                    {
                        /* Get array from context */
                        array_value = get_jsonb_array(jsonb_context, collection_path, &found);
                        
                        if (found)
                        {
                            array_length = get_jsonb_array_length(array_value);
                            
                            /* Handle empty arrays gracefully */
                            if (array_length <= 0)
                                break;
                                
                            for (i = 0; i < array_length; i++)
                            {
                                Datum item_context = get_jsonb_array_element(array_value, i);
                                Datum merged_context;
                                char *item_result;
                                bool item_error = false;
                                
                                if (item_context == (Datum) 0)
                                {
                                    /* Create an empty object for null array elements */
                                    JsonbParseState *parse_state = NULL;
                                    JsonbValue *empty_obj;
                                    
                                    pushJsonbValue(&parse_state, WJB_BEGIN_OBJECT, NULL);
                                    empty_obj = pushJsonbValue(&parse_state, WJB_END_OBJECT, NULL);
                                    item_context = PointerGetDatum(JsonbValueToJsonb(empty_obj));
                                }
                                
                                /* Create context with iterator variable */
                                merged_context = create_iterator_context(jsonb_context, current->value->section.iterator, item_context);
                                
                                if (merged_context == (Datum) 0)
                                    continue;
                                
                                /* Render section body with new context */
                                item_result = template_render(context, current->value->section.body, merged_context, &item_error);
                                
                                if (!item_error && item_result)
                                {
                                    appendStringInfoString(&result, item_result);
                                    pfree(item_result);
                                }
                                else if (item_error)
                                {
                                    *error = true;
                                    return result.data;
                                }
                            }
                        }
                    }
                }
                break;
                
            case TEMPLATE_NODE_INCLUDE:
                {
                    /* Handle includes */
                    char *template_key = current->value->include.key;
                    Datum include_data;
                    bool found = false;
                    
                    if (template_key)
                    {
                        /* Find include template in context */
                        include_data = get_jsonb_include_template(jsonb_context, template_key, &found);
                        
                        if (found)
                        {
                            char *include_template = NULL;
                            Datum include_context = (Datum) 0;
                            char *include_result;
                            bool include_error = false;
                            
                            /* Extract template and context */
                            get_include_data(include_data, &include_template, &include_context);
                            
                            /* Parse and render included template */
                            if (include_template)
                            {
                                TemplateConfig config = template_default_config(context);
                                TemplateErrorCode error_code;
                                const char *template_str = include_template;
                                TemplateNode *include_node = template_parse(context, &template_str, &config, false, &error_code);
                                
                                if (include_node && error_code == TEMPLATE_ERROR_NONE)
                                {
                                    include_result = template_render(context, include_node, 
                                                                    include_context != (Datum) 0 ? include_context : jsonb_context, 
                                                                    &include_error);
                                    
                                    if (!include_error && include_result)
                                    {
                                        appendStringInfoString(&result, include_result);
                                        pfree(include_result);
                                    }
                                    else
                                    {
                                        *error = true;
                                    }
                                    
                                    template_free_node(include_node);
                                }
                                else
                                {
                                    *error = true;
                                }
                                
                                pfree(include_template);
                            }
                        }
                    }
                }
                break;
                
            case TEMPLATE_NODE_EXECUTE:
                /* Execute is not implemented in this version */
                break;
                
            default:
                /* Unknown node type */
                break;
        }
        
        if (*error)
            break;
            
        current = current->next;
    }
    
    return result.data;
}

/* Helper functions for JSONB handling */
static char *
get_jsonb_path_value(Datum jsonb_context, const char *path, bool *found)
{
    Jsonb *jb = (Jsonb *) DatumGetPointer(jsonb_context);
    JsonbValue *jbv_result;
    JsonbValue key;
    JsonbIterator *it;
    JsonbIteratorToken token;
    char *result = NULL;
    
    *found = false;
    
    if (!jb || !path)
        return NULL;
    
    /* Handle simple top-level key */
    if (strchr(path, '.') == NULL && strchr(path, '[') == NULL)
    {
        key.type = jbvString;
        key.val.string.val = (char *) path;
        key.val.string.len = strlen(path);
        
        jbv_result = findJsonbValueFromContainer(&jb->root, JB_FOBJECT, &key);
        
        if (jbv_result)
        {
            *found = true;
            
            if (jbv_result->type == jbvString)
            {
                result = pnstrdup(jbv_result->val.string.val, jbv_result->val.string.len);
            }
            else if (jbv_result->type == jbvNumeric)
            {
                Numeric num = jbv_result->val.numeric;
                result = DatumGetCString(DirectFunctionCall1(numeric_out, NumericGetDatum(num)));
            }
            else if (jbv_result->type == jbvBool)
            {
                result = pstrdup(jbv_result->val.boolean ? "true" : "false");
            }
            else if (jbv_result->type == jbvNull)
            {
                result = pstrdup("");
            }
            else if (jbv_result->type == jbvBinary)
            {
                /* Convert binary type to string representation */
                StringInfoData buf;
                JsonbValue v;
                
                initStringInfo(&buf);
                
                it = JsonbIteratorInit((JsonbContainer *)&jbv_result->val.binary);
                
                while ((token = JsonbIteratorNext(&it, &v, false)) != WJB_DONE)
                {
                    if (token == WJB_VALUE)
                    {
                        if (v.type == jbvString)
                        {
                            appendBinaryStringInfo(&buf, v.val.string.val, v.val.string.len);
                        }
                        else if (v.type == jbvNumeric)
                        {
                            Numeric num = v.val.numeric;
                            char *numstr = DatumGetCString(DirectFunctionCall1(numeric_out, NumericGetDatum(num)));
                            appendStringInfoString(&buf, numstr);
                            pfree(numstr);
                        }
                        else if (v.type == jbvBool)
                        {
                            appendStringInfoString(&buf, v.val.boolean ? "true" : "false");
                        }
                    }
                }
                
                result = buf.data;
            }
        }
    }
    else
    {
        /* Handle nested paths using a JSON path expression */
        /* This is a simplified implementation and would need to be expanded for a full solution */
        char *current_path = pstrdup(path);
        char *token;
        char *saveptr;
        JsonbValue *current_jbv;
        
        token = strtok_r(current_path, ".", &saveptr);
        while (token != NULL)
        {
            key.type = jbvString;
            key.val.string.val = token;
            key.val.string.len = strlen(token);
            
            current_jbv = findJsonbValueFromContainer(&jb->root, JB_FOBJECT, &key);
            
            if (!current_jbv)
            {
                pfree(current_path);
                return NULL;
            }
            
            token = strtok_r(NULL, ".", &saveptr);
            
            /* If there are more path segments, current value must be an object */
            if (token != NULL)
            {
                if (current_jbv->type != jbvBinary)
                {
                    pfree(current_path);
                    return NULL;
                }
                
                jb = (Jsonb *) DatumGetPointer(JsonbValueToJsonb(current_jbv));
            }
            else
            {
                /* We found the value */
                *found = true;
                
                if (current_jbv->type == jbvString)
                {
                    result = pnstrdup(current_jbv->val.string.val, current_jbv->val.string.len);
                }
                else if (current_jbv->type == jbvNumeric)
                {
                    Numeric num = current_jbv->val.numeric;
                    result = DatumGetCString(DirectFunctionCall1(numeric_out, NumericGetDatum(num)));
                }
                else if (current_jbv->type == jbvBool)
                {
                    result = pstrdup(current_jbv->val.boolean ? "true" : "false");
                }
                else if (current_jbv->type == jbvNull)
                {
                    result = pstrdup("");
                }
            }
        }
        
        pfree(current_path);
    }
    
    return result;
}

static Datum
get_jsonb_array(Datum jsonb_context, const char *path, bool *found)
{
    Jsonb *jb = (Jsonb *) DatumGetPointer(jsonb_context);
    JsonbValue *jbv_result;
    JsonbValue key;
    Datum result = (Datum) 0;
    
    *found = false;
    
    if (!jb || !path)
        return result;
    
    /* Handle simple top-level key */
    if (strchr(path, '.') == NULL)
    {
        key.type = jbvString;
        key.val.string.val = (char *) path;
        key.val.string.len = strlen(path);
        
        jbv_result = findJsonbValueFromContainer(&jb->root, JB_FOBJECT, &key);
        
        if (jbv_result && jbv_result->type == jbvBinary)
        {
            JsonbIterator *it;
            JsonbValue v;
            JsonbIteratorToken token;
            
            it = JsonbIteratorInit((JsonbContainer *)&jbv_result->val.binary);
            token = JsonbIteratorNext(&it, &v, false);
            
            if (token == WJB_BEGIN_ARRAY)
            {
                *found = true;
                result = PointerGetDatum(JsonbValueToJsonb(jbv_result));
            }
        }
    }
    else
    {
        /* Handle nested paths */
        /* This is a simplified implementation */
        char *current_path = pstrdup(path);
        char *token;
        char *saveptr;
        JsonbValue *current_jbv;
        
        token = strtok_r(current_path, ".", &saveptr);
        while (token != NULL)
        {
            key.type = jbvString;
            key.val.string.val = token;
            key.val.string.len = strlen(token);
            
            current_jbv = findJsonbValueFromContainer(&jb->root, JB_FOBJECT, &key);
            
            if (!current_jbv)
            {
                pfree(current_path);
                return result;
            }
            
            token = strtok_r(NULL, ".", &saveptr);
            
            /* If there are more path segments, current value must be an object */
            if (token != NULL)
            {
                if (current_jbv->type != jbvBinary)
                {
                    pfree(current_path);
                    return result;
                }
                
                jb = (Jsonb *) DatumGetPointer(JsonbValueToJsonb(current_jbv));
            }
            else
            {
                /* Check if the final value is an array */
                if (current_jbv->type == jbvBinary)
                {
                    JsonbIterator *it;
                    JsonbValue v;
                    JsonbIteratorToken token;
                    
                    it = JsonbIteratorInit((JsonbContainer *)&current_jbv->val.binary);
                    token = JsonbIteratorNext(&it, &v, false);
                    
                    if (token == WJB_BEGIN_ARRAY)
                    {
                        *found = true;
                        result = PointerGetDatum(JsonbValueToJsonb(current_jbv));
                    }
                }
            }
        }
        
        pfree(current_path);
    }
    
    return result;
}

static int
get_jsonb_array_length(Datum jsonb_array)
{
    Jsonb *jb = (Jsonb *) DatumGetPointer(jsonb_array);
    JsonbIterator *it;
    JsonbValue v;
    JsonbIteratorToken token;
    int count = 0;
    
    if (!jb)
        return 0;
    
    it = JsonbIteratorInit((JsonbContainer *)&jb->root);
    
    /* Skip the WJB_BEGIN_ARRAY token */
    token = JsonbIteratorNext(&it, &v, false);
    
    if (token != WJB_BEGIN_ARRAY)
        return 0;
    
    /* Count array elements */
    while ((token = JsonbIteratorNext(&it, &v, false)) != WJB_DONE)
    {
        if (token == WJB_ELEM)
            count++;
    }
    
    return count;
}

static Datum
get_jsonb_array_element(Datum jsonb_array, int index)
{
    Jsonb *jb = (Jsonb *) DatumGetPointer(jsonb_array);
    JsonbIterator *it;
    JsonbValue v;
    JsonbIteratorToken token;
    int current_index = 0;
    Datum result = (Datum) 0;
    JsonbParseState *parse_state = NULL;
    JsonbValue *jbv_result;
    
    if (!jb || index < 0)
        return result;
    
    it = JsonbIteratorInit((JsonbContainer *)&jb->root);
    
    /* Skip the WJB_BEGIN_ARRAY token */
    token = JsonbIteratorNext(&it, &v, false);
    
    if (token != WJB_BEGIN_ARRAY)
        return result;
    
    /* Find the element at the specified index */
    while ((token = JsonbIteratorNext(&it, &v, false)) != WJB_DONE)
    {
        if (token == WJB_ELEM)
        {
            if (current_index == index)
            {
                /* Found the element */
                if (v.type == jbvBinary)
                {
                    /* For binary values, just convert directly */
                    result = PointerGetDatum(JsonbValueToJsonb(&v));
                }
                else
                {
                    /* For scalar values, we need to create a proper JSON value */
                    pushJsonbValue(&parse_state, WJB_BEGIN_OBJECT, NULL);
                    
                    /* Add a dummy key "value" */
                    JsonbValue key;
                    key.type = jbvString;
                    key.val.string.val = "value";
                    key.val.string.len = 5;
                    
                    pushJsonbValue(&parse_state, WJB_KEY, &key);
                    
                    /* Add the value */
                    pushJsonbValue(&parse_state, WJB_VALUE, &v);
                    
                    /* Finish the object */
                    jbv_result = pushJsonbValue(&parse_state, WJB_END_OBJECT, NULL);
                    
                    /* Convert to Jsonb */
                    result = PointerGetDatum(JsonbValueToJsonb(jbv_result));
                }
                break;
            }
            current_index++;
        }
    }
    
    return result;
}

static Datum
create_iterator_context(Datum parent_context, const char *iterator_name, Datum item_context)
{
    Jsonb *parent_jb = (Jsonb *) DatumGetPointer(parent_context);
    Jsonb *item_jb = (Jsonb *) DatumGetPointer(item_context);
    JsonbParseState *parse_state = NULL;
    JsonbValue *result;
    JsonbIterator *it;
    JsonbValue v;
    JsonbIteratorToken token;
    JsonbValue key;
    JsonbValue val;
    bool is_scalar = false;
    
    if (!parent_jb || !item_jb || !iterator_name)
        return parent_context;
    
    /* Start with a copy of the parent context */
    pushJsonbValue(&parse_state, WJB_BEGIN_OBJECT, NULL);
    
    /* Copy all fields from parent context */
    it = JsonbIteratorInit((JsonbContainer *)&parent_jb->root);
    
    /* Skip the WJB_BEGIN_OBJECT token */
    token = JsonbIteratorNext(&it, &v, false);
    
    if (token != WJB_BEGIN_OBJECT)
        return parent_context;
    
    /* Copy all key-value pairs from parent */
    while ((token = JsonbIteratorNext(&it, &v, false)) != WJB_DONE)
    {
        if (token == WJB_KEY)
        {
            /* Copy the key */
            key.type = jbvString;
            key.val.string.val = pnstrdup(v.val.string.val, v.val.string.len);
            key.val.string.len = v.val.string.len;
            
            pushJsonbValue(&parse_state, WJB_KEY, &key);
            
            /* Get and copy the value */
            token = JsonbIteratorNext(&it, &val, false);
            pushJsonbValue(&parse_state, WJB_VALUE, &val);
            
            pfree(key.val.string.val);
        }
    }
    
    /* Add the iterator variable */
    key.type = jbvString;
    key.val.string.val = (char *) iterator_name;
    key.val.string.len = strlen(iterator_name);
    
    pushJsonbValue(&parse_state, WJB_KEY, &key);
    
    /* Check if the item is a scalar value wrapped in an object */
    it = JsonbIteratorInit((JsonbContainer *)&item_jb->root);
    token = JsonbIteratorNext(&it, &v, false);
    
    if (token == WJB_BEGIN_OBJECT)
    {
        /* Check if it's our special scalar wrapper with "value" key */
        token = JsonbIteratorNext(&it, &v, false);
        if (token == WJB_KEY && v.type == jbvString && 
            v.val.string.len == 5 && strncmp(v.val.string.val, "value", 5) == 0)
        {
            /* Get the scalar value */
            token = JsonbIteratorNext(&it, &v, false);
            if (token == WJB_VALUE)
            {
                is_scalar = true;
                pushJsonbValue(&parse_state, WJB_VALUE, &v);
            }
        }
    }
    
    /* If not a scalar, use the whole item as is */
    if (!is_scalar)
    {
        it = JsonbIteratorInit((JsonbContainer *)&item_jb->root);
        token = JsonbIteratorNext(&it, &v, false);
        pushJsonbValue(&parse_state, WJB_VALUE, &v);
    }
    
    /* Finalize the new context object */
    result = pushJsonbValue(&parse_state, WJB_END_OBJECT, NULL);
    
    return PointerGetDatum(JsonbValueToJsonb(result));
}

static Datum
get_jsonb_include_template(Datum jsonb_context, const char *key, bool *found)
{
    Jsonb *jb = (Jsonb *) DatumGetPointer(jsonb_context);
    JsonbValue *jbv_result;
    JsonbValue search_key;
    Datum result = (Datum) 0;
    char *include_key;
    
    *found = false;
    
    if (!jb || !key)
        return result;
    
    /* Construct the include key */
    include_key = psprintf("include %s", key);
    
    /* Look for the include template in the context */
    search_key.type = jbvString;
    search_key.val.string.val = include_key;
    search_key.val.string.len = strlen(include_key);
    
    jbv_result = findJsonbValueFromContainer(&jb->root, JB_FOBJECT, &search_key);
    
    if (jbv_result && jbv_result->type == jbvBinary)
    {
        *found = true;
        result = PointerGetDatum(JsonbValueToJsonb(jbv_result));
    }
    
    pfree(include_key);
    return result;
}

static void
get_include_data(Datum include_data, char **template_out, Datum *context_out)
{
    Jsonb *jb = (Jsonb *) DatumGetPointer(include_data);
    JsonbIterator *it;
    JsonbValue v;
    JsonbIteratorToken token;
    JsonbValue template_key, context_key;
    JsonbValue *template_jbv, *context_jbv;
    
    *template_out = NULL;
    *context_out = (Datum) 0;
    
    if (!jb)
        return;
    
    /* Check if it's an array of include objects */
    it = JsonbIteratorInit((JsonbContainer *)&jb->root);
    token = JsonbIteratorNext(&it, &v, false);
    
    if (token != WJB_BEGIN_ARRAY)
        return;
    
    /* Get the first element (we only support one include for now) */
    token = JsonbIteratorNext(&it, &v, false);
    
    if (token != WJB_ELEM || v.type != jbvBinary)
        return;
    
    /* Get the include object */
    Jsonb *include_obj = (Jsonb *) DatumGetPointer(JsonbValueToJsonb(&v));
    
    /* Look for template and context keys */
    template_key.type = jbvString;
    template_key.val.string.val = "template";
    template_key.val.string.len = strlen("template");
    
    context_key.type = jbvString;
    context_key.val.string.val = "context";
    context_key.val.string.len = strlen("context");
    
    template_jbv = findJsonbValueFromContainer(&include_obj->root, JB_FOBJECT, &template_key);
    
    /* Extract template string */
    if (template_jbv && template_jbv->type == jbvString)
    {
        *template_out = pnstrdup(template_jbv->val.string.val, template_jbv->val.string.len);
    }
    
    context_jbv = findJsonbValueFromContainer(&include_obj->root, JB_FOBJECT, &context_key);
    
    /* Extract context object */
    if (context_jbv && context_jbv->type == jbvBinary)
    {
        *context_out = PointerGetDatum(JsonbValueToJsonb(context_jbv));
    }
}

/* PostgreSQL function wrappers */
PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(pg_template_parse);
Datum
pg_template_parse(PG_FUNCTION_ARGS)
{
    text *template_text = PG_GETARG_TEXT_PP(0);
    char *template_str = text_to_cstring(template_text);
    const char *template_ptr = template_str;
    MemoryContext old_context;
    MemoryContext parse_context;
    TemplateConfig config;
    TemplateNode *root = NULL;
    TemplateErrorCode error_code = TEMPLATE_ERROR_NONE;
    text *result_text = NULL;
    StringInfoData result;
    
    /* Create a memory context for parsing */
    parse_context = AllocSetContextCreate(CurrentMemoryContext,
                                         "Template Parse Context",
                                         ALLOCSET_DEFAULT_SIZES);
    
    /* Switch to the new context for parsing */
    old_context = MemoryContextSwitchTo(parse_context);
    
    /* Initialize default config */
    config = template_default_config(parse_context);
    
    PG_TRY();
    {
        /* Parse the template */
        root = template_parse(parse_context, &template_ptr, &config, false, &error_code);
        
        /* Check for parsing errors */
        if (error_code != TEMPLATE_ERROR_NONE || !root)
        {
            ereport(ERROR,
                    (errcode(ERRCODE_SYNTAX_ERROR),
                     errmsg("Template parsing error: %s", template_error_to_string(error_code))));
        }
        
        /* Convert the parsed template to a string representation for debugging */
        initStringInfo(&result);
        appendStringInfo(&result, "Template parsed successfully. Structure:\n");
        template_node_to_string(root, &result, 0);
        
        /* Switch back to the original memory context */
        MemoryContextSwitchTo(old_context);
        
        /* Return the result */
        result_text = cstring_to_text(result.data);
        pfree(result.data);
    }
    PG_CATCH();
    {
        /* Switch back to the original memory context for error handling */
        MemoryContextSwitchTo(old_context);
        
        /* Clean up */
        if (template_str)
            pfree(template_str);
        
        /* Delete the parse context */
        MemoryContextDelete(parse_context);
        
        PG_RE_THROW();
    }
    PG_END_TRY();
    
    /* Clean up */
    MemoryContextDelete(parse_context);
    pfree(template_str);
    
    PG_RETURN_TEXT_P(result_text);
}

PG_FUNCTION_INFO_V1(pg_render);
Datum
pg_render(PG_FUNCTION_ARGS)
{
    text *template_text = PG_GETARG_TEXT_PP(1);
    Jsonb *context_jsonb = PG_GETARG_JSONB_P(0);
    char *template_str = text_to_cstring(template_text);
    const char *template_ptr = template_str;
    MemoryContext old_context;
    MemoryContext render_context;
    TemplateConfig config;
    TemplateNode *root = NULL;
    TemplateErrorCode error_code = TEMPLATE_ERROR_NONE;
    bool render_error = false;
    char *rendered_result = NULL;
    text *result_text = NULL;
    
    /* Create a memory context for rendering */
    render_context = AllocSetContextCreate(CurrentMemoryContext,
                                          "Template Render Context",
                                          ALLOCSET_DEFAULT_SIZES);
    
    /* Switch to the new context for parsing and rendering */
    old_context = MemoryContextSwitchTo(render_context);
    
    /* Initialize default config */
    config = template_default_config(render_context);
    
    PG_TRY();
    {
        /* Parse the template */
        root = template_parse(render_context, &template_ptr, &config, false, &error_code);
        
        /* Check for parsing errors */
        if (error_code != TEMPLATE_ERROR_NONE || !root)
        {
            ereport(ERROR,
                    (errcode(ERRCODE_SYNTAX_ERROR),
                     errmsg("Template parsing error: %s", template_error_to_string(error_code))));
        }
        
        /* Render the template with the provided context */
        rendered_result = template_render(render_context, root, PointerGetDatum(context_jsonb), &render_error);
        
        /* Check for rendering errors */
        if (render_error || !rendered_result)
        {
            ereport(ERROR,
                    (errcode(ERRCODE_INTERNAL_ERROR),
                     errmsg("Template rendering error")));
        }
        
        /* Convert the result to a text datum in the original memory context */
        MemoryContextSwitchTo(old_context);
        result_text = cstring_to_text(rendered_result);
    }
    PG_CATCH();
    {
        /* Switch back to the original memory context for error handling */
        MemoryContextSwitchTo(old_context);
        
        /* Clean up */
        if (template_str)
            pfree(template_str);
        
        /* Delete the render context */
        MemoryContextDelete(render_context);
        
        PG_RE_THROW();
    }
    PG_END_TRY();
    
    /* Clean up */
    MemoryContextDelete(render_context);
    pfree(template_str);
    
    PG_RETURN_TEXT_P(result_text);
}

/* Helper function to convert template node to string for debugging */
static void
template_node_to_string(TemplateNode *node, StringInfo result, int indent)
{
    TemplateNode *current = node;
    int i;
    
    while (current)
    {
        /* Add indentation */
        for (i = 0; i < indent; i++)
            appendStringInfoChar(result, ' ');
        
        /* Add node type */
        switch (current->type)
        {
            case TEMPLATE_NODE_TEXT:
                appendStringInfo(result, "TEXT: \"%s\"\n", 
                                current->value->text.content ? current->value->text.content : "");
                break;
                
            case TEMPLATE_NODE_INTERPOLATE:
                appendStringInfo(result, "INTERPOLATE: \"%s\"\n", 
                                current->value->interpolate.key ? current->value->interpolate.key : "");
                break;
                
            case TEMPLATE_NODE_SECTION:
                appendStringInfo(result, "SECTION: iterator=\"%s\", collection=\"%s\"\n", 
                                current->value->section.iterator ? current->value->section.iterator : "",
                                current->value->section.collection ? current->value->section.collection : "");
                
                if (current->value->section.body)
                {
                    template_node_to_string(current->value->section.body, result, indent + 2);
                }
                break;
                
            case TEMPLATE_NODE_EXECUTE:
                appendStringInfo(result, "EXECUTE: \"%s\"\n", 
                                current->value->execute.code ? current->value->execute.code : "");
                break;
                
            case TEMPLATE_NODE_INCLUDE:
                appendStringInfo(result, "INCLUDE: \"%s\"\n", 
                                current->value->include.key ? current->value->include.key : "");
                break;
                
            default:
                appendStringInfo(result, "UNKNOWN NODE TYPE: %d\n", current->type);
                break;
        }
        
        current = current->next;
    }
} 