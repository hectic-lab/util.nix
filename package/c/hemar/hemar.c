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
static Datum get_jsonb_array_element(Datum jsonb_array, int index);
static Datum create_iterator_context(Datum parent_context, const char *iterator_name, Datum item_context);
static Datum get_jsonb_include_template(Datum jsonb_context, const char *key, bool *found);
static void get_include_data(Datum include_data, char **template_out, Datum *context_out);
static void template_node_to_string(TemplateNode *node, StringInfo result, int indent);
static bool is_jsonb_container_valid(JsonbContainer *container);

static const char *
jbt_type_to_string(JsonbIteratorToken type)
{
    switch (type)
    {
        case WJB_DONE:
            return "WJB_DONE";
        case WJB_KEY:
            return "WJB_KEY";
        case WJB_VALUE:
            return "WJB_VALUE";
        case WJB_ELEM:
            return "WJB_ELEM";
        case WJB_BEGIN_ARRAY:
            return "WJB_BEGIN_ARRAY";
        case WJB_END_ARRAY:
            return "WJB_END_ARRAY";
        case WJB_BEGIN_OBJECT:
            return "WJB_BEGIN_OBJECT";
        case WJB_END_OBJECT:
            return "WJB_END_OBJECT";
        default:
            return "Unknown";
    }
}

static char *
jbv_type_to_string(enum jbvType type)
{
    switch (type)
    {
        case jbvNull:
            return "jbvNull";
        case jbvString:
            return "jbvString";
        case jbvNumeric:
            return "jbvNumeric";
        case jbvBool:
            return "jbvBool";
        case jbvArray:
            return "jbvArray";
        case jbvObject:
            return "jbvObject";
        case jbvBinary:
            return "jbvBinary";
        case jbvDatetime:
            return "jbvDatetime";
        default:
            return "Unknown";
    }
}

/* Implementation of a simplified validity check for JsonbContainer */
static bool
is_jsonb_container_valid(JsonbContainer *container)
{
    PG_TRY();
    {
        container->header;
        container->children;
    }
    PG_CATCH();
    {
        elog(ERROR, "Invalid JSONB container");
        return false;
    }
    PG_END_TRY();
    
    if (container == NULL)
        return false;
            
    uint32 header = *(uint32 *)container;
    if (header == 0)
        return false;

    return true;
}

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
template_error_to_string(TemplateErrorCode code, TemplateConfig *config)
{
    char *message = "";
    switch (code)
    {
        case TEMPLATE_ERROR_NONE:
            return "No error";
        case TEMPLATE_ERROR_UNKNOWN_TAG:
            return "Unknown tag";
        case TEMPLATE_ERROR_NESTED_INTERPOLATION:
            return "Nested interpolation";
        case TEMPLATE_UNEXPECTED_OPEN_BRACES_AFFTER_SECTION_CONTROLE:
	    message = "Found `";
	    strcat(message, config->Syntax.Braces.open);
	    strcat(message, "` in `");
	    strcat(message, config->Syntax.Section.control);
	    strcat(message, "` in section block");
            return message;
        case TEMPLATE_UNEXPECTED_OPEN_BRACES_AFFTER_SECTION_SOURCE:
	    message = "Found `";
	    strcat(message, config->Syntax.Braces.open);
	    strcat(message, "` in `");
	    strcat(message, config->Syntax.Section.source);
	    strcat(message, "` in section block");
            return message;
        case TEMPLATE_ERROR_UNEXPECTED_INTERPOLATION_END:
            return "Unexpected interpolation end";
        case TEMPLATE_ERROR_NO_SOURSE_IN_SECTION:
	    message = "Not found `";
	    strcat(message, config->Syntax.Section.source);
	    strcat(message, "` keyword in section block");
	    return message;
        case TEMPLATE_ERROR_NO_BEGIN_IN_SECTION:
	    message = "Not found `";
	    strcat(message, config->Syntax.Section.begin);
	    strcat(message, "` keyword in section block");
	    return message;
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
    
    config.Syntax.Braces.open = "{{";
    config.Syntax.Braces.close = "}}";
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
    elog(DEBUG1, "TPI: Parsing: %s", node->value->interpolate.key);
    
    *s = skip_whitespace(*s);
    
    /* Check for closing brace */
    if (strncmp(*s, config->Syntax.Braces.close, strlen(config->Syntax.Braces.close)) != 0)
    {
        if (error_code)
            *error_code = TEMPLATE_ERROR_UNEXPECTED_INTERPOLATION_END;
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
                *error_code = TEMPLATE_UNEXPECTED_OPEN_BRACES_AFFTER_SECTION_CONTROLE;
            template_free_node(node);
            return NULL;
        }
        
        if (strncmp(*s, config->Syntax.Braces.close, strlen(config->Syntax.Braces.close)) == 0)
        {
            if (error_code)
                *error_code = TEMPLATE_ERROR_NO_SOURSE_IN_SECTION;
            template_free_node(node);
            return NULL;
        }
        
        (*s)++;
    }
    
    iterator_len = *s - iterator_start;
    node->value->section.iterator = MemoryContextStrdup(context, pnstrdup(iterator_start, iterator_len));
    elog(DEBUG1, "TPS: Parsed section iterator: %s", node->value->section.iterator);
    
    /* Find the collection name */
    *s = skip_whitespace(*s);
    
    if (strncmp(*s, config->Syntax.Section.source, strlen(config->Syntax.Section.source)) != 0)
    {
        if (error_code)
            *error_code = TEMPLATE_ERROR_NO_SOURSE_IN_SECTION;
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
                *error_code = TEMPLATE_UNEXPECTED_OPEN_BRACES_AFFTER_SECTION_SOURCE;
            template_free_node(node);
            return NULL;
        }
        
        if (strncmp(*s, config->Syntax.Braces.close, strlen(config->Syntax.Braces.close)) == 0)
        {
            if (error_code)
                *error_code = TEMPLATE_ERROR_NO_BEGIN_IN_SECTION;
            template_free_node(node);
            return NULL;
        }
        
        (*s)++;
    }
    
    collection_len = *s - collection_start;
    node->value->section.collection = MemoryContextStrdup(context, pnstrdup(collection_start, collection_len));
    elog(DEBUG1, "TPS: Parsed section collection: %s", node->value->section.collection);
    
    /* Check for 'do' keyword */
    *s = skip_whitespace(*s);
    // TODO: why check begin second time, first in while
    if (strncmp(*s, config->Syntax.Section.begin, strlen(config->Syntax.Section.begin)) != 0)
    {
        if (error_code)
            *error_code = TEMPLATE_UNEXPECTED_OPEN_BRACES_AFFTER_SECTION_SOURCE;
        template_free_node(node);
        return NULL;
    }
    
    *s += strlen(config->Syntax.Section.begin);
    *s = skip_whitespace(*s);
    
    /* Check if there's a closing brace right after 'do' */
    if (strncmp(*s, config->Syntax.Braces.close, strlen(config->Syntax.Braces.close)) == 0)
    {
        /* Empty section body */
        elog(DEBUG1, "TPS: Parsed empty section body");
        *s_ptr = *s + strlen(config->Syntax.Braces.close);
        node->value->section.body = NULL;
        return node;
    }

    /* Parse the body as a normal template */
    const char *body_start = *s;
    const char *original_s = *s;

    int inner_braces_opened_count = 0;
    
    /* Find the end of the section */
    while (**s) {
	// s = {% a %} %}
        elog(DEBUG2, "TPS: Step, braces opened: %d, s: %s", inner_braces_opened_count, *s);
            if (strncmp(*s, config->Syntax.Braces.open, strlen(config->Syntax.Braces.open)) == 0) {
                elog(DEBUG2, "TPS: inner_braces_opened_count++");
	        inner_braces_opened_count++;
	    }
        if (strncmp(*s, config->Syntax.Braces.close, strlen(config->Syntax.Braces.close)) == 0) {
            if (inner_braces_opened_count > 0) {
                elog(DEBUG2, "TPS: inner_braces_opened_count--");
	            inner_braces_opened_count--;
	        }
	        else {
                elog(DEBUG2, "TPS: exit");
                break;
	        }
	    }
        (*s)++;
    }
    
    if (!**s)
    {
        /* Unexpected end of string before closing brace */
        if (error_code)
            *error_code = TEMPLATE_ERROR_UNEXPECTED_SECTION_END;
        template_free_node(node);
        return NULL;
    }
    
    /* Extract the body content */
    size_t body_len = *s - body_start;
    char *body_content = pnstrdup(body_start, body_len);
    
    elog(DEBUG1, "TPS: Section body content: %s", body_content);
    
    /* Parse the body content as a template */
    const char *body_ptr = body_content;
    body_node = template_parse(context, &body_ptr, config, false, error_code);
    
    if (!body_node)
    {
        elog(WARNING, "TPS: Failed to parse section body: %s", body_content);
        pfree(body_content);
        template_free_node(node);
        return NULL;
    }
    
    pfree(body_content);
    node->value->section.body = body_node;
    
    /* Set the pointer to after the closing brace */
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
    
    /* Check for empty template */
    if (!s || !*s || !**s)
    {
        TemplateNode *empty_node = init_template_node(context, TEMPLATE_NODE_TEXT);
        empty_node->value->text.content = MemoryContextStrdup(context, "");
        if (error_code)
            *error_code = TEMPLATE_ERROR_NONE;
        return empty_node;
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
    
    elog(DEBUG1, "Starting template rendering");
    
    PG_TRY();
    {
        while (current)
        {
            switch (current->type)
            {
                case TEMPLATE_NODE_TEXT:
                    /* Process text node */
                    elog(DEBUG1, "");
                    elog(DEBUG1, "> TEXT");
                    if (current->value->text.content)
                    {
                        elog(DEBUG1, "N*TEXT: Rendering text node: %s", current->value->text.content);
                        appendStringInfoString(&result, current->value->text.content);
                    }
                    break;
                    
                case TEMPLATE_NODE_INTERPOLATE:
                            /* Process interpolation node */
                    elog(DEBUG1, "");
                    elog(DEBUG1, "> INTERPOLATE");

                            char *value = NULL;
                    bool found_interpolate = false;
                            
                            if (current->value->interpolate.key)
                            {
                        elog(DEBUG1, "N*INTR: Processing interpolation for key: %s", current->value->interpolate.key);
                                
                                /* First try to get as a direct path */
                                /* Extract value from JSONB context */
                        value = // ??
                                
                        if (found_interpolate && value)
                                {
                            elog(DEBUG1, "N*INTR: Found value for key %s: %s", current->value->interpolate.key, value);
                                    appendStringInfoString(&result, value);
                                    pfree(value);
                                }
                                else
                                {
                                    /* If not found as direct path, check if it's an array */
                                    Datum array_value;
                                    bool array_found = false;
                                    
                                    array_value = get_jsonb_array(jsonb_context, current->value->interpolate.key, &array_found);
                                    
                                    if (array_found)
                                    {
                                        /* Convert array to string representation */
                                elog(DEBUG1, "N*INTR: Found array for key %s, converting to string", current->value->interpolate.key);
                                        
                                        /* Create a string representation of the array */
                                        StringInfoData array_str;
                                        initStringInfo(&array_str);
                                        appendStringInfoString(&array_str, "[");
                                        
                                        Jsonb *array_jb = (Jsonb *) DatumGetPointer(array_value);
                                        if (array_jb && is_jsonb_container_valid(&array_jb->root))
                                        {
                                    /* Check if it's actually an array */
                                    JsonbContainer *jc = &array_jb->root;
                                    if (!(jc->header & JB_FARRAY))
                                    {
                                        elog(DEBUG1, "N*INTR: JSONB value is not an array");
                                        appendStringInfoString(&array_str, "[Not an array]");
                                    }
                                    else
                                    {
                                        /* Iterate through array elements */
                                        JsonbIterator *it = JsonbIteratorInit(jc);
                                        JsonbValue v;
                                        JsonbIteratorToken token;
                                        bool first_element = true;
                                        
                                        /* Skip the WJB_BEGIN_ARRAY token */
                                        token = JsonbIteratorNext(&it, &v, false);
                                        
                                        /* Process each array element */
                                        while ((token = JsonbIteratorNext(&it, &v, false)) != WJB_DONE)
                                            {
                                            if (token != WJB_ELEM)
                                                continue;
                                            
                                            if (!first_element)
                                                    appendStringInfoString(&array_str, ", ");
                                            else
                                                first_element = false;
                                            
                                            if (v.type == jbvString)
                                            {
                                                appendStringInfoChar(&array_str, '"');
                                                appendBinaryStringInfo(&array_str, v.val.string.val, v.val.string.len);
                                                appendStringInfoChar(&array_str, '"');
                                            }
                                            else if (v.type == jbvNumeric)
                                            {
                                                char *num_str = DatumGetCString(DirectFunctionCall1(numeric_out, NumericGetDatum(v.val.numeric)));
                                                appendStringInfoString(&array_str, num_str);
                                                pfree(num_str);
                                            }
                                            else if (v.type == jbvBool)
                                            {
                                                appendStringInfoString(&array_str, v.val.boolean ? "true" : "false");
                                            }
                                            else if (v.type == jbvNull)
                                            {
                                                appendStringInfoString(&array_str, "null");
                                            }
                                            else if (v.type == jbvBinary)
                                            {
                                                /* For complex values, convert to string */
                                                Datum elem = PointerGetDatum(JsonbValueToJsonb(&v));
                                                bool elem_found = false;
                                                char *elem_str = get_jsonb_path_value(elem, "value", &elem_found);
                                                    
                                                    if (elem_found && elem_str)
                                                    {
                                                        appendStringInfoString(&array_str, elem_str);
                                                        pfree(elem_str);
                                                    }
                                                    else
                                                    {
                                                    appendStringInfoString(&array_str, "[Complex Value]");
                                                    }
                                                }
                                                }
                                            }
                                        }
                                        
                                        appendStringInfoString(&array_str, "]");
                                        appendStringInfoString(&result, array_str.data);
                                        pfree(array_str.data);
                                    }
                                    else
                                    {
                                elog(DEBUG1, "N*INTR: Key %s not found in context", current->value->interpolate.key);
                                        /* Optionally append something to indicate missing key */
                                        appendStringInfoString(&result, "");
                                    }
                                }
                            }
                case TEMPLATE_NODE_SECTION:
                    elog(DEBUG1, "");
                    elog(DEBUG1, "> SECTION");
                            /* Handle sections (loops) */
                            char *collection_path = current->value->section.collection;
                            Datum array_value;
                    bool found_section = false;
                            int array_length;
                            int i;
                            JsonbParseState *parse_state = NULL;
                            JsonbValue *empty_obj;
                            Datum item_context;
                            Datum merged_context;
                            char *item_result;
                            bool item_error = false;
                            
                            if (collection_path)
                            {
                        elog(DEBUG1, "N*SECT: Processing section with collection path: %s", collection_path);
                                
                        /* Use the improved get_jsonb_array function that handles nested paths */
                        array_value = get_jsonb_array(jsonb_context, collection_path, &found_section);
                                
                        if (found_section)
                                {
                            elog(DEBUG1, "N*SECT: Found array for section: %s", collection_path);
                                    
                                    /* Make sure we have a valid array */
                                    Jsonb *array_jb = (Jsonb *) DatumGetPointer(array_value);
                                    if (!array_jb || !is_jsonb_container_valid(&array_jb->root))
                                    {
                                elog(WARNING, "N*SECT: Invalid JSONB array container for path: %s", collection_path);
                                        break;
                                    }
                                    
                            /* Check if it's actually an array */
                            JsonbContainer *jc = &array_jb->root;
                            if (!(jc->header & JB_FARRAY))
                            {
                                elog(DEBUG1, "N*SECT: JSONB value is not an array");
                                        break;
                                    }
                                    
                                    /* If section body is empty, nothing to do */
                                    if (current->value->section.body == NULL)
                                    {
                                elog(DEBUG1, "N*SECT: Section body is empty, skipping");
                                        break;
                                    }
                                    
                            elog(DEBUG1, "N*SECT: Rendering section body for each array element");
                                    
                                    /* Log the section body structure for debugging */
                                    if (current->value->section.body)
                                    {
                                        StringInfoData section_info;
                                        initStringInfo(&section_info);
                                        template_node_to_string(current->value->section.body, &section_info, 0);
                                elog(DEBUG1, "N*SECT: Section body structure: %s", section_info.data);
                                        pfree(section_info.data);
                                    }
                                    
                            /* Iterate through array elements */
                            JsonbIterator *it = JsonbIteratorInit(jc);
                            JsonbValue v;
                            JsonbIteratorToken token;
                            int i = 0;
                            int nesting_level = 0;
                            bool in_element = false;
                            JsonbParseState *element_state = NULL;
                            JsonbValue *element_value = NULL;
                            
                            /* Skip the WJB_BEGIN_ARRAY token */
                            token = JsonbIteratorNext(&it, &v, false);
                            elog(DEBUG1, "N*SECT: Iterator started, first token: %d", token);
                            
                            /* Process each array element */
                            while ((token = JsonbIteratorNext(&it, &v, false)) != WJB_DONE)
                            {
                                elog(DEBUG1, "N*SECT: Token: %d, Type: %s, Nesting: %d", 
                                     token, jbv_type_to_string(v.type), nesting_level);
                                
                                /* Handle array elements */
                                if (token == WJB_ELEM)
                                    {
                                        item_context = (Datum) 0;
                                        item_error = false;
                                        
                                    elog(DEBUG1, "N*SECT: Processing array element %d", i);
                                        
                                    /* Convert the JsonbValue to a Datum */
                                        PG_TRY();
                                        {
                                        if (v.type == jbvBinary)
                                        {
                                            /* For binary values, just convert directly */
                                            item_context = PointerGetDatum(JsonbValueToJsonb(&v));
                                        }
                                        else if (v.type == jbvNull)
                                        {
                                            /* Handle null values by creating an empty object */
                                            parse_state = NULL;
                                            pushJsonbValue(&parse_state, WJB_BEGIN_OBJECT, NULL);
                                            empty_obj = pushJsonbValue(&parse_state, WJB_END_OBJECT, NULL);
                                            item_context = PointerGetDatum(JsonbValueToJsonb(empty_obj));
                                        }
                                        else
                                        {
                                            /* For scalar values, create a proper JSON object */
                                            parse_state = NULL;
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
                                            empty_obj = pushJsonbValue(&parse_state, WJB_END_OBJECT, NULL);
                                            
                                            /* Convert to Jsonb */
                                            item_context = PointerGetDatum(JsonbValueToJsonb(empty_obj));
                                        }
                                        
                                        /* Process this element */
                                        process_array_element:
                                        
                                        /* Validate we got a valid item back */
                                        if (item_context != (Datum) 0)
                                        {
                                            Jsonb *item_jb = (Jsonb *) DatumGetPointer(item_context);
                                            if (item_jb && is_jsonb_container_valid(&item_jb->root))
                                            {
                                                elog(DEBUG1, "N*SECT: Got valid array element %d", i);
                                                elog(DEBUG1, "N*SECT: Array Element: %s", JsonbToCString(NULL, &item_jb->root, VARSIZE_ANY_EXHDR(item_jb)));
                                        
                                        /* Create context with iterator variable */
                                        PG_TRY();
                                        {
                                            merged_context = create_iterator_context(jsonb_context, current->value->section.iterator, item_context);
                                        }
                                        PG_CATCH();
                                        {
                                                    elog(WARNING, "N*SECT: Error creating merged context for array element %d", i);
                                            /* Use parent context as fallback */
                                            merged_context = jsonb_context;
                                            
                                            /* Reset error state */
                                            FlushErrorState();
                                        }
                                        PG_END_TRY();
                                        
                                        if (merged_context == (Datum) 0)
                                        {
                                                    elog(WARNING, "N*SECT: Failed to create merged context for array element %d", i);
                                                    i++;
                                            continue;
                                        }
                                        
                                        /* Render section body with new context */
                                        PG_TRY();
                                        {
                                            item_result = template_render(context, current->value->section.body, merged_context, &item_error);
                                            
                                            if (!item_error && item_result)
                                            {
                                                appendStringInfoString(&result, item_result);
                                                pfree(item_result);
                                            }
                                            else if (item_error)
                                            {
                                                        elog(WARNING, "N*SECT: Error rendering template section for array element %d", i);
                                                *error = true;
                                                return result.data;
                                            }
                                        }
                                        PG_CATCH();
                                        {
                                                    elog(WARNING, "N*SECT: Exception during template rendering for array element %d", i);
                                            /* Continue with next element */
                                            FlushErrorState();
                                        }
                                        PG_END_TRY();
                                    }
                                            else
                                            {
                                                elog(WARNING, "N*SECT: Got invalid JSONB container for array element %d", i);
                                    }
                                }
                                else
                                {
                                            elog(DEBUG1, "N*SECT: Array element %d is null, creating empty object", i);
                                            /* Create an empty object for null array elements */
                                            parse_state = NULL;
                                            
                                            pushJsonbValue(&parse_state, WJB_BEGIN_OBJECT, NULL);
                                            empty_obj = pushJsonbValue(&parse_state, WJB_END_OBJECT, NULL);
                                            item_context = PointerGetDatum(JsonbValueToJsonb(empty_obj));
                                            goto process_array_element;
                                        }
                                    }
                                    PG_CATCH();
                                    {
                                        elog(WARNING, "N*SECT: Error processing array element %d, creating empty object instead", i);
                                        /* Create an empty object for problematic array elements */
                                        parse_state = NULL;
                                        
                                        pushJsonbValue(&parse_state, WJB_BEGIN_OBJECT, NULL);
                                        empty_obj = pushJsonbValue(&parse_state, WJB_END_OBJECT, NULL);
                                        item_context = PointerGetDatum(JsonbValueToJsonb(empty_obj));
                                        
                                        /* Reset error state */
                                        FlushErrorState();
                                        goto process_array_element;
                                    }
                                    PG_END_TRY();
                                    
                                    i++;
                                }
                                /* Handle complex objects within the array */
                                else if (token == WJB_BEGIN_OBJECT || token == WJB_BEGIN_ARRAY)
                                {
                                    if (nesting_level == 0)
                                    {
                                        /* Starting a new complex element */
                                        elog(DEBUG1, "N*SECT: Starting complex element %d", i);
                                        element_state = NULL;
                                        element_value = pushJsonbValue(&element_state, token, NULL);
                                        in_element = true;
                                    }
                                    nesting_level++;
                                }
                                else if ((token == WJB_END_OBJECT || token == WJB_END_ARRAY) && in_element)
                                {
                                    nesting_level--;
                                    
                                    if (nesting_level == 0)
                                    {
                                        /* Finished a complex element */
                                        elog(DEBUG1, "N*SECT: Finished complex element %d", i);
                                        element_value = pushJsonbValue(&element_state, token, NULL);
                                        in_element = false;
                                        
                                        /* Convert to Datum and process */
                                        item_context = PointerGetDatum(JsonbValueToJsonb(element_value));
                                        item_error = false;
                                        
                                        /* Process this complex element */
                                        goto process_array_element;
                            }
                        }
                                else if (in_element)
                                {
                                    /* Add to the current element being built */
                                    pushJsonbValue(&element_state, token, &v);
                                }
                            }
                        }
                        else
                        {
                            elog(DEBUG1, "N*SECT: Collection not found: %s", collection_path);
                        }
                    }
                case TEMPLATE_NODE_EXECUTE:
                    elog(DEBUG1, "");
                    elog(DEBUG1, "> EXECUTE");
                    /* Execute is not implemented in this version */
                    elog(DEBUG1, "N*EXEC: Execute node type not implemented");
                case TEMPLATE_NODE_INCLUDE:
                    elog(DEBUG1, "");
                    elog(DEBUG1, "> INCLUDE");
                            /* Handle includes */
                            char *template_key = current->value->include.key;
                            Datum include_data;
                    bool found_include = false;
                            
                            if (template_key)
                            {
                        elog(DEBUG1, "N*INCL: Processing include with key: %s", template_key);
                                
                                /* Find include template in context */
                        include_data = get_jsonb_include_template(jsonb_context, template_key, &found_include);
                                
                        if (found_include)
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
                                        elog(WARNING, "N*INCL: Error rendering included template: %s", template_key);
                                                *error = true;
                                            }
                                            
                                            template_free_node(include_node);
                                        }
                                        else
                                        {
                                    elog(WARNING, "N*INCL: Error parsing included template: %s", template_key);
                                            *error = true;
                                        }
                                        
                                        pfree(include_template);
                                    }
                                    else
                                    {
                                elog(WARNING, "N*INCL: Included template is null: %s", template_key);
                                    }
                                }
                                else
                                {
                            elog(DEBUG1, "N*INCL: Include key not found: %s", template_key);
                                }
                            }
                    break;
                default:
                    /* Unknown node type */
                    elog(WARNING, "N*UNKN: Unknown node type: %d", current->type);
                    break;
            }
            
            if (*error)
                break;
                
            current = current->next;
        }
    }
    PG_CATCH();
    {
        elog(WARNING, "Unhandled exception during template rendering");
        FlushErrorState();
        *error = true;
        return result.data;
    }
    PG_END_TRY();
    
    elog(DEBUG1, "Template rendering completed successfully");
    return result.data;
}

static Datum
get_jsonb_array(Datum jsonb_context, const char *path, bool *found)
{
    Jsonb *jb = (Jsonb *) DatumGetPointer(jsonb_context);
    JsonbValue *jbv_result;
    JsonbIterator *it;
    JsonbValue v;
    JsonbIteratorToken token;
    Datum result = (Datum) 0;
    Jsonb *result_jb;
    
    *found = false;
    
    if (!jb || !path)
    {
        elog(DEBUG1, "Null JSONB or path in get_jsonb_array");
        return result;
    }
    
    /* Validate the container */
    if (!is_jsonb_container_valid(&jb->root))
    {
        elog(WARNING, "Invalid JSONB container in get_jsonb_array");
        return result;
    }
    
        elog(DEBUG1, "Looking for array at path: %s", path);
        
        /* Use PG_TRY/PG_CATCH to handle any errors during iteration */
        PG_TRY();
        {
        /* Use the path traversal function */
        bool path_found = false;
        jbv_result = // TODO: ?;
            
        if (path_found && jbv_result)
            {
            elog(DEBUG1, "Found value for key %s (%s)", path, jbv_type_to_string(jbv_result->type));
                
                if (jbv_result->type == jbvBinary)
                {
                    /* Get more details about the binary data */
                    elog(DEBUG1, "Binary value found, trying to examine structure");
                    
                    /* Validate the binary container before iterating */
                    if (!is_jsonb_container_valid(jbv_result->val.binary.data))
                    {
                        elog(WARNING, "Invalid binary JSONB container for key: %s", path);
                        return result;
                    }
                    
                    elog(DEBUG1, "Trying to initialize the iterator...");
                    /* Try to initialize the iterator */
                    PG_TRY();
                    {
                        /* Log raw pointer for debugging */
                    elog(DEBUG1, "Binary container address: %p", jbv_result->val.binary.data);
                        
                        /* Try to get the first 4 bytes of the binary data */
                    uint32 header = *(uint32 *)jbv_result->val.binary.data;
                        elog(DEBUG1, "Binary container header: %u", header);
                        
                        /* Initialize the iterator with careful error handling */
                        elog(DEBUG1, "Initializing iterator for binary container");
                        it = JsonbIteratorInit(jbv_result->val.binary.data);
                        elog(DEBUG1, "Iterator initialized successfully");
                        
                        elog(DEBUG1, "Getting first token");
                        token = JsonbIteratorNext(&it, &v, false);
                        elog(DEBUG1, "First token retrieved: %d", token);
                        
                        if (token == WJB_BEGIN_ARRAY)
                        {
                            /* It's a valid array */
                            *found = true;
                            result_jb = JsonbValueToJsonb(jbv_result);
                            result = PointerGetDatum(result_jb);
                            elog(DEBUG1, "Found array at path %s (result=%p)", path, DatumGetPointer(result));
                            elog(DEBUG1, "Array: %s", JsonbToCString(NULL, &result_jb->root, VARSIZE_ANY_EXHDR(result_jb)));
                            return result;
                        }
                        else
                        {
                            elog(DEBUG1, "Path %s exists but is not an array (token type: %d)", path, token);
                        }
                    }
                    PG_CATCH();
                    {
                        elog(WARNING, "Error initializing JSON iterator for path %s", path);
                        /* Get more details about the error */
                        ErrorData *edata = CopyErrorData();
                        elog(WARNING, "Error message: %s", edata->message);
                        elog(WARNING, "Error detail: %s", edata->detail ? edata->detail : "none");
                        elog(WARNING, "Error hint: %s", edata->hint ? edata->hint : "none");
                        elog(WARNING, "Error context: %s", edata->context ? edata->context : "none");
                        FreeErrorData(edata);
                        FlushErrorState();
                    }
                    PG_END_TRY();
                }
                else
                {
                    elog(DEBUG1, "Path %s exists but is not binary JSONB (type: %d)", path, jbv_result->type);
                }
            }
            else
            {
                elog(DEBUG1, "Path %s not found in JSONB", path);
            }
        }
        PG_CATCH();
        {
            elog(WARNING, "Exception while processing array at path %s", path);
            ErrorData *edata = CopyErrorData();
            elog(WARNING, "Error message: %s", edata->message);
            FreeErrorData(edata);
            FlushErrorState();
        }
        PG_END_TRY();
    
    return result;
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
    JsonbValue key;
    Jsonb *result_jb;
    
    if (!jb || index < 0)
    {
        elog(DEBUG1, "Invalid array or index: array=%p, index=%d", jb, index);
        return result;
    }
    
    /* Check if this is a valid Jsonb before proceeding */
    if (!is_jsonb_container_valid(&jb->root))
    {
        elog(WARNING, "Invalid JSONB container in get_jsonb_array_element");
        return result;
    }
    
    /* Use PG_TRY/PG_CATCH to handle any errors during iteration */
    PG_TRY();
    {
        it = JsonbIteratorInit((JsonbContainer *)&jb->root);
        
        /* Skip the WJB_BEGIN_ARRAY token */
        token = JsonbIteratorNext(&it, &v, false);
        
        if (token != WJB_BEGIN_ARRAY)
        {
            elog(DEBUG1, "JSON value is not an array (token=%d)", token);
            return result;
        }
        
        /* Find the element at the specified index */
        while ((token = JsonbIteratorNext(&it, &v, false)) != WJB_DONE)
        {
            if (token == WJB_ELEM)
            {
                if (current_index == index)
                {
                    /* Found the element */
                    elog(DEBUG1, "Found array element at index %d (type=%d)", index, v.type);
                    
                    if (v.type == jbvBinary)
                    {
                        /* For binary values, just convert directly */
                        result_jb = JsonbValueToJsonb(&v);
                        result = PointerGetDatum(result_jb);
                        elog(DEBUG1, "Array Element (Binary): %s", JsonbToCString(NULL, &result_jb->root, VARSIZE_ANY_EXHDR(result_jb)));
                    }
                    else if (v.type == jbvNull)
                    {
                        /* Handle null values by creating an empty object */
                        pushJsonbValue(&parse_state, WJB_BEGIN_OBJECT, NULL);
                        jbv_result = pushJsonbValue(&parse_state, WJB_END_OBJECT, NULL);
                        result = PointerGetDatum(JsonbValueToJsonb(jbv_result));
                        elog(DEBUG1, "Converted null array element to empty object");
                    }
                    else
                    {
                        /* For scalar values, we need to create a proper JSON value */
                        pushJsonbValue(&parse_state, WJB_BEGIN_OBJECT, NULL);
                        
                        /* Add a dummy key "value" */
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
                        elog(DEBUG1, "Wrapped scalar array element in object with 'value' key");
                    }
                    break;
                }
                current_index++;
            }
        }
    }
    PG_CATCH();
    {
        elog(WARNING, "Exception while processing array element at index %d", index);
        FlushErrorState();
        return (Datum) 0;
    }
    PG_END_TRY();
    
    if (result == (Datum) 0)
    {
        elog(DEBUG1, "Array element at index %d not found (array length = %d)", index, current_index);
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
    {
        elog(DEBUG1, "CIC: Invalid parameters for create_iterator_context: parent=%p, item=%p, iterator=%s", 
             parent_jb, item_jb, iterator_name ? iterator_name : "(null)");
        return parent_context;
    }
    
    /* Validate the containers */
    if (!is_jsonb_container_valid(&parent_jb->root))
    {
        elog(WARNING, "CIC: Invalid parent JSONB container in create_iterator_context");
        return parent_context;
    }
    
    if (!is_jsonb_container_valid(&item_jb->root))
    {
        elog(WARNING, "CIC: Invalid item JSONB container in create_iterator_context");
        return parent_context;
    }
    
    elog(DEBUG1, "CIC: Creating iterator context with iterator name: %s", iterator_name);
    
    /* Start with a copy of the parent context */
    pushJsonbValue(&parse_state, WJB_BEGIN_OBJECT, NULL);
    
    /* Copy all fields from parent context */
    it = JsonbIteratorInit((JsonbContainer *)&parent_jb->root);
    
    /* Skip the WJB_BEGIN_OBJECT token */
    token = JsonbIteratorNext(&it, &v, false);
    
    if (token != WJB_BEGIN_OBJECT)
    {
        elog(WARNING, "CIC: Parent context is not an object (token=%d)", token);
        return parent_context;
    }
    
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
        elog(DEBUG1, "CIC: Item context is an object");
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
                elog(DEBUG1, "CIC: Found scalar value with 'value' key (type=%s)", jbv_type_to_string(v.type));
                pushJsonbValue(&parse_state, WJB_VALUE, &v);
            }
        }
    }
    else
    {
        elog(DEBUG1, "CIC: Item context is not an object (token=%d)", token);
    }
    
    /* If not a scalar, use the whole item as is */
    if (!is_scalar)
    {
        elog(DEBUG1, "CIC: Using entire item as context value");
        it = JsonbIteratorInit((JsonbContainer *)&item_jb->root);
        token = JsonbIteratorNext(&it, &v, false);
        pushJsonbValue(&parse_state, WJB_VALUE, &v);
    }
    
    /* Finalize the new context object */
    result = pushJsonbValue(&parse_state, WJB_END_OBJECT, NULL);
    
    /* Validate the result before returning */
    Jsonb *result_jb = JsonbValueToJsonb(result);
    if (!result_jb || !is_jsonb_container_valid(&result_jb->root))
    {
        elog(WARNING, "CIC: Created invalid JSONB container in create_iterator_context");
        return parent_context;
    }
    
    return PointerGetDatum(result_jb);
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
    Jsonb *include_obj;
    
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
    include_obj = (Jsonb *) DatumGetPointer(JsonbValueToJsonb(&v));
    
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
                     errmsg("Template parsing error: %s", template_error_to_string(error_code, &config))));
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
    
    /* Log the template and context for debugging */
    elog(DEBUG1, " ==== Template ====");
    elog(DEBUG1, "%s", template_str);
    elog(DEBUG1, " ==== End Template ====");
    elog(DEBUG1, " ==== Context ====");
    elog(DEBUG1, "%s", JsonbToCString(NULL, &context_jsonb->root, VARSIZE_ANY_EXHDR(context_jsonb)));
    elog(DEBUG1, " ==== End Context ====");
    
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
                     errmsg("Template parsing error: %s", template_error_to_string(error_code, &config))));
        }
        
        elog(DEBUG1, "Template parsed successfully, starting render");
        elog(DEBUG1, "--------------------------------");
        
        /* Render the template with the provided context */
        rendered_result = template_render(render_context, root, PointerGetDatum(context_jsonb), &render_error);
        
        /* Check for rendering errors */
        if (render_error || !rendered_result)
        {
            ereport(ERROR,
                    (errcode(ERRCODE_INTERNAL_ERROR),
                     errmsg("Template rendering error")));
        }
        
        elog(DEBUG1, "Template rendered successfully: %s", rendered_result);
        
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