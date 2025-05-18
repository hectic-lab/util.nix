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
static void template_node_to_string(TemplateNode *node, StringInfo result, int indent);
static void render_template(TemplateNode *node, Jsonb *define, StringInfo result, MemoryContext context);
static void render_execute_tag(const char *code, Jsonb *define, StringInfo result, MemoryContext context);
static JsonbValue *jsonb_get_by_path_internal(Jsonb *jb, const char *path_str, MemoryContext context);

char *tnt_to_string(TemplateNodeType type) {
  switch (type) {
    case TEMPLATE_NODE_SECTION: return "SECTION";
    case TEMPLATE_NODE_INTERPOLATE: return "INTERPOLATE";
    case TEMPLATE_NODE_EXECUTE: return "EXECUTE";
    case TEMPLATE_NODE_INCLUDE: return "INCLUDE";
    case TEMPLATE_NODE_TEXT: return "TEXT";
    default: { 
        return "UNKNOWN";
    };
  }
}

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
            return "Missing end tag for section";
        case TEMPLATE_ERROR_UNEXPECTED_SECTION_END:
            return "Unexpected section end or missing end tag";
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
    config.Syntax.Section.control = "for";
    config.Syntax.Section.source = "in";
    config.Syntax.Section.begin = "";  /* No longer used, but keep for backward compatibility */
    config.Syntax.Interpolate.invoke = "";
    config.Syntax.Include.invoke = "include";
    config.Syntax.Execute.invoke = "exec";
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
    
    /* Trim trailing whitespace if it was terminated by whitespace */
    while (key_len > 0 && isspace((unsigned char)key_start[key_len - 1]))
        key_len--;
    
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
    
    /* Skip whitespace after control keyword */
    *s = skip_whitespace(*s);
    
    /* Find the iterator name */
    iterator_start = *s;
    
    while (**s != '\0')
    {
        if (isspace((unsigned char)**s))
            break;
            
        if (strncmp(*s, config->Syntax.Braces.open, strlen(config->Syntax.Braces.open)) == 0)
        {
            if (error_code)
                *error_code = TEMPLATE_UNEXPECTED_OPEN_BRACES_AFFTER_SECTION_CONTROLE;
            template_free_node(node);
            return NULL;
        }
        
        (*s)++;
    }
    
    iterator_len = *s - iterator_start;
    node->value->section.iterator = MemoryContextStrdup(context, pnstrdup(iterator_start, iterator_len));
    elog(DEBUG1, "TPS: Parsed section iterator: %s", node->value->section.iterator);
    
    /* Find the source keyword "in" */
    *s = skip_whitespace(*s);
    
    if (strncmp(*s, config->Syntax.Section.source, strlen(config->Syntax.Section.source)) != 0)
    {
        if (error_code)
            *error_code = TEMPLATE_ERROR_NO_SOURSE_IN_SECTION;
        template_free_node(node);
        return NULL;
    }
    
    *s += strlen(config->Syntax.Section.source);
    
    /* Skip whitespace after source keyword */
    *s = skip_whitespace(*s);
    
    /* Find the collection name */
    collection_start = *s;
    
    while (**s != '\0')
    {
        if (isspace((unsigned char)**s) || 
            strncmp(*s, config->Syntax.Braces.close, strlen(config->Syntax.Braces.close)) == 0)
            break;
            
        if (strncmp(*s, config->Syntax.Braces.open, strlen(config->Syntax.Braces.open)) == 0)
        {
            if (error_code)
                *error_code = TEMPLATE_UNEXPECTED_OPEN_BRACES_AFFTER_SECTION_SOURCE;
            template_free_node(node);
            return NULL;
        }
        
        (*s)++;
    }
    
    collection_len = *s - collection_start;
    node->value->section.collection = MemoryContextStrdup(context, pnstrdup(collection_start, collection_len));
    elog(DEBUG1, "TPS: Parsed section collection: %s", node->value->section.collection);
    
    /* Skip whitespace before closing brace */
    *s = skip_whitespace(*s);
    
    /* Check for closing brace */
    if (strncmp(*s, config->Syntax.Braces.close, strlen(config->Syntax.Braces.close)) != 0)
    {
        if (error_code)
            *error_code = TEMPLATE_ERROR_UNEXPECTED_SECTION_END;
        template_free_node(node);
        return NULL;
    }
    
    /* Move past the closing brace */
    *s += strlen(config->Syntax.Braces.close);
    
    /* Start of the body content */
    const char *body_start = *s;
    const char *end_tag_start = NULL;
    int nesting_level = 1;  /* Start at 1, our current section */
    
    elog(DEBUG1, "TPS: Starting to parse section body at position: %s", body_start);
    elog(DEBUG1, "TPS: Looking for end tag");
    
    /* Find the matching end tag, accounting for nested sections */
    while (**s != '\0')
    {
        if (strncmp(*s, config->Syntax.Braces.open, strlen(config->Syntax.Braces.open)) == 0)
        {
            /* We found an opening brace */
            const char *tag_start = *s + strlen(config->Syntax.Braces.open);
            const char *tag_ptr = tag_start;
            
            /* Skip whitespace after opening brace */
            while (*tag_ptr && isspace((unsigned char)*tag_ptr))
                tag_ptr++;
            
            /* Check if this is a new section tag */
            if (strncmp(tag_ptr, config->Syntax.Section.control, strlen(config->Syntax.Section.control)) == 0)
            {
                /* Found a nested section, increase nesting level */
                nesting_level++;
                elog(DEBUG1, "TPS: Found nested section, nesting level: %d, at position: %s", nesting_level, *s);
            }
            /* Check if this is an end tag */
            else if (strncmp(tag_ptr, "end", 3) == 0)
            {
                /* Found an end tag, decrease nesting level */
                nesting_level--;
                elog(DEBUG1, "TPS: Found end tag, nesting level: %d, at position: %s", nesting_level, *s);
                
                if (nesting_level == 0)
                {
                    /* This is our matching end tag */
                    end_tag_start = *s;
                break;
	        }
	    }
        }
        
        (*s)++;
    }
    
    /* Check if we found a matching end tag */
    if (nesting_level > 0 || !end_tag_start)
    {
        elog(WARNING, "TPS: No matching end tag found for section, nesting level: %d", nesting_level);
        if (error_code)
            *error_code = TEMPLATE_ERROR_UNEXPECTED_SECTION_END;
        template_free_node(node);
        return NULL;
    }
    
    /* Extract the body content */
    size_t body_len = end_tag_start - body_start;
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
    
    /* Skip past the end tag */
    *s = end_tag_start;
    *s += strlen(config->Syntax.Braces.open);
    *s = skip_whitespace(*s);
    *s += 3; /* Skip "end" */
    *s = skip_whitespace(*s);
    
    /* Check for closing brace of end tag */
    if (strncmp(*s, config->Syntax.Braces.close, strlen(config->Syntax.Braces.close)) != 0)
    {
        elog(WARNING, "TPS: No closing brace for end tag at position: %s", *s);
        if (error_code)
            *error_code = TEMPLATE_ERROR_UNEXPECTED_SECTION_END;
        template_free_node(node);
        return NULL;
    }
    
    /* Set the pointer to after the closing brace */
    *s_ptr = *s + strlen(config->Syntax.Braces.close);
    elog(DEBUG1, "TPS: Successfully parsed section, returning at position: %s", *s_ptr);
    
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
    
    /* Skip whitespace after include keyword */
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
    
    /* Trim trailing whitespace if it was terminated by whitespace */
    while (include_len > 0 && isspace((unsigned char)include_start[include_len - 1]))
        include_len--;
    
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
    
    /* Skip whitespace after execute keyword */
    *s = skip_whitespace(*s);
    
    code_start = *s;
    
    /* Track quote state and brace level to handle SQL content properly */
    bool in_single_quote = false;
    bool in_double_quote = false;
    bool escaped = false;
    int brace_level = 1;  /* Start with 1 for the opening braces we already consumed */
    
    while (**s != '\0')
    {
        /* Handle escaping */
        if (**s == '\\') {
            escaped = !escaped;
            (*s)++;
            continue;
        }
        
        /* Handle quotes - only toggle quote state if not escaped */
        if (!escaped) {
            if (**s == '\'') {
                in_single_quote = !in_single_quote;
            } else if (**s == '"') {
                in_double_quote = !in_double_quote;
            }
        }
        
        /* Only check for braces when not inside quotes */
        if (!in_single_quote && !in_double_quote) {
            /* Check for nested opening braces */
            if (strncmp(*s, config->Syntax.Braces.open, strlen(config->Syntax.Braces.open)) == 0) {
                brace_level++;
                *s += strlen(config->Syntax.Braces.open) - 1;  /* -1 because we'll increment s below */
            }
            /* Check for closing braces */
            else if (strncmp(*s, config->Syntax.Braces.close, strlen(config->Syntax.Braces.close)) == 0) {
                brace_level--;
                
                /* If we've reached the matching closing brace, we're done */
                if (brace_level == 0) {
            break;
                }
                
                *s += strlen(config->Syntax.Braces.close) - 1;  /* -1 because we'll increment s below */
            }
        }
        
        /* Reset escaped flag after processing a character */
        escaped = false;
        (*s)++;
    }
    
    code_len = *s - code_start;
    
    /* Trim trailing whitespace */
    while (code_len > 0 && isspace((unsigned char)code_start[code_len - 1]))
        code_len--;
    
    node->value->execute.code = MemoryContextStrdup(context, pnstrdup(code_start, code_len));
    
    /* Check for closing brace */
    if (brace_level != 0 || strncmp(*s, config->Syntax.Braces.close, strlen(config->Syntax.Braces.close)) != 0)
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
            
            /* Find the longest matching prefix to determine tag type */
            typedef struct {
                const char *prefix;
                int tag_type;
                bool requires_space_after; /* Whether this prefix requires whitespace after it */
            } PrefixMatch;
            
            PrefixMatch matches[] = {
                {config->Syntax.Section.control, 1, true},    /* "for" needs space after */
                {config->Syntax.Include.invoke, 2, true},     /* "include" needs space after */
                {config->Syntax.Execute.invoke, 3, true},     /* "exec" needs space after */
                {config->Syntax.Interpolate.invoke, 4, false} /* Empty prefix doesn't need space */
            };
            
            int matched_type = 0;
            size_t max_length = 0;
            
            /* Find longest match (in case when one prefix is part of another) */
            for (int i = 0; i < 4; i++) {
                if (strncmp(tag_prefix, matches[i].prefix, strlen(matches[i].prefix)) == 0) {
                    /* Check if the match requires a space after it */
                    bool valid_match = true;
                    if (matches[i].requires_space_after) {
                        /* If we need space after the prefix, verify it exists */
                        const char *after_prefix = tag_prefix + strlen(matches[i].prefix);
                        if (*after_prefix && !isspace((unsigned char)*after_prefix)) {
                            valid_match = false;
                        }
                    }
                    
                    if (valid_match && strlen(matches[i].prefix) >= max_length) {
                        max_length = strlen(matches[i].prefix);
                        matched_type = matches[i].tag_type;
                    }
                }
            }
            
            /* Choose the tag parser based on the matched type */
            if (matched_type == 1) {
                /* Section tag */
                elog(LOG, "TPE: Parsing section tag at position: %.50s", *s);
                tag_node = template_parse_section(context, s, config, error_code);
            } else if (matched_type == 2) {
                /* Include tag */
                elog(LOG, "TPE: Parsing include tag at position: %.50s", *s);
                tag_node = template_parse_include(context, s, config, error_code);
            } else if (matched_type == 3) {
                /* Execute tag */
                elog(LOG, "TPE: Parsing execute tag at position: %.50s", *s);
                tag_node = template_parse_execute(context, s, config, error_code);
            } else if (matched_type == 4) {
                /* Interpolation tag */
                elog(LOG, "TPE: Parsing interpolation tag at position: %.50s", *s);
                tag_node = template_parse_interpolation(context, s, config, error_code);
            } else {
                /* Unknown tag type */
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

/* Template rendering function */
PG_FUNCTION_INFO_V1(pg_template_render);
Datum
pg_template_render(PG_FUNCTION_ARGS)
{
    Jsonb *define = PG_GETARG_JSONB_P(0);
    text *template_text = PG_GETARG_TEXT_PP(1);
    char *template_str = text_to_cstring(template_text);
    const char *template_ptr = template_str;
    MemoryContext old_context, render_context;
    TemplateConfig config;
    TemplateNode *root = NULL;
    TemplateErrorCode error_code = TEMPLATE_ERROR_NONE;
    StringInfoData result;
    text *result_text = NULL;
    
    /* Create a memory context for rendering */
    render_context = AllocSetContextCreate(CurrentMemoryContext,
                                         "Template Render Context",
                                         ALLOCSET_DEFAULT_SIZES);
    
    /* Switch to the new context for rendering */
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
        
        /* Initialize the result buffer */
        initStringInfo(&result);
        
        /* Render the template */
        render_template(root, define, &result, render_context);
        
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

/* Helper function to render a template node */
static void
render_template(TemplateNode *node, Jsonb *define, StringInfo result, MemoryContext context)
{
    TemplateNode *current = node;
    JsonbValue *value;
    char *str_value;
    int debug_msg_size = 4096;
    char *debug_msg = palloc(debug_msg_size);

    elog(DEBUG1, "define: %s", JsonbToCString(NULL, &define->root, VARSIZE_ANY_EXHDR(define)));
    
    while (current)
    {
        snprintf(debug_msg, debug_msg_size, "Rendering node type: %.50s", tnt_to_string(current->type));
        switch (current->type)
        {
            case TEMPLATE_NODE_TEXT:
                snprintf(debug_msg, debug_msg_size, "%s TEXT: %.50s", debug_msg, current->value->text.content);
                if (current->value->text.content)
                {
                    /* Preserve whitespace in text nodes */
                    appendStringInfoString(result, current->value->text.content);
                }
                break;
                
            case TEMPLATE_NODE_INTERPOLATE:
                snprintf(debug_msg, debug_msg_size, "%s INTERPOLATE: %.50s", debug_msg, current->value->interpolate.key);
                if (current->value->interpolate.key)
                {
                    /* Get the value from the JSONB context using the path */
                    value = jsonb_get_by_path_internal(define, current->value->interpolate.key, context);
                    
                    if (value != NULL)
                    {
                        /* Convert the value to a string based on its type */
                        switch (value->type)
                        {
                            case jbvString:
                                /* Preserve whitespace in string values */
                                snprintf(debug_msg, debug_msg_size, "%s VALUE: %.50s", debug_msg, value->val.string.val);
                                appendStringInfoString(result, value->val.string.val);
                                break;
                                
                            case jbvNumeric:
                                str_value = DatumGetCString(DirectFunctionCall1(numeric_out, 
                                    NumericGetDatum(value->val.numeric)));
                                appendStringInfoString(result, str_value);
                                pfree(str_value);
                                break;
                                
                            case jbvBool:
                                appendStringInfoString(result, value->val.boolean ? "true" : "false");
                                break;
                                
                            case jbvNull:
                                /* For null values, we don't output anything */
                                break;
                                
                            case jbvBinary:
                                /* For complex types (objects/arrays), convert to JSON string */
                                str_value = DatumGetCString(DirectFunctionCall1(jsonb_out,
                                    JsonbPGetDatum(JsonbValueToJsonb(value))));
                                appendStringInfoString(result, str_value);
                                pfree(str_value);
                                break;
                                
                            default:
                                elog(WARNING, "Unsupported JSONB value type in interpolation: %s",
                                     jbv_type_to_string(value->type));
                                break;
                        }
                        
                        /* Free the value since it was allocated in our context */
                        pfree(value);
                    }
                }
                else
                {
                    elog(WARNING, "Interpolation key is not set");
                }
                break;
                
            case TEMPLATE_NODE_EXECUTE:
                snprintf(debug_msg, debug_msg_size, "%s EXECUTE: %.50s", debug_msg, current->value->execute.code);
                render_execute_tag(current->value->execute.code, define, result, context);
                break;

            case TEMPLATE_NODE_SECTION:
                snprintf(debug_msg, debug_msg_size, "%s SECTION: %.50s", debug_msg, current->value->section.iterator);
                if (!current->value->section.collection)
                {
                    elog(WARNING, "Section collection is not set");
                    break;  
                }

                if (!current->value->section.iterator)
                {
                    elog(WARNING, "Section iterator is not set");
                    break;  
                }

                value = jsonb_get_by_path_internal(define, current->value->section.collection, context);
                
                if (value != NULL)
                {
                    /* Convert the value to a string based on its type */
                    /* must render body with context (define) concatenated with iterator item */
                    switch (value->type)
                    {
                        case jbvString:
                            /* iterate by string, where item is char */
                            {
                                const char *str = value->val.string.val;
                                for (int i = 0; i < value->val.string.len; i++)
                                {
                                    /* Create a new context with the current character */
                                    JsonbValue char_val;
                                    char_val.type = jbvString;
                                    char_val.val.string.val = pstrdup((char[]){str[i], '\0'});
                                    char_val.val.string.len = 1;
                                    
                                    /* Create a new context with the iterator value */
                                    JsonbValue *new_context = palloc(sizeof(JsonbValue));
                                    new_context->type = jbvObject;
                                    
                                    /* Create a new JSONB object */
                                    JsonbParseState *parse_state = NULL;
                                    JsonbValue *res = pushJsonbValue(&parse_state, WJB_BEGIN_OBJECT, NULL);
                                    
                                    /* Copy the original context */
                                    JsonbIterator *it = JsonbIteratorInit(&define->root);
                                    JsonbIteratorToken token;
                                    JsonbValue v;
                                    
                                    while ((token = JsonbIteratorNext(&it, &v, true)) != WJB_DONE)
                                    {
                                        if (token == WJB_KEY)
                                        {
                                            /* Add the key */
                                            pushJsonbValue(&parse_state, WJB_KEY, &v);
                                        }
                                        else if (token == WJB_VALUE)
                                        {
                                            /* Add the value */
                                            pushJsonbValue(&parse_state, WJB_VALUE, &v);
                                        }
                                    }
                                    
                                    /* Add the iterator value */
                                    JsonbValue key_val;
                                    key_val.type = jbvString;
                                    key_val.val.string.val = pstrdup(current->value->section.iterator);
                                    key_val.val.string.len = strlen(current->value->section.iterator);
                                    pushJsonbValue(&parse_state, WJB_KEY, &key_val);
                                    pushJsonbValue(&parse_state, WJB_VALUE, &char_val);
                                    
                                    /* Finish the object */
                                    res = pushJsonbValue(&parse_state, WJB_END_OBJECT, NULL);
                                    
                                    /* Convert to Jsonb */
                                    Jsonb *context_jsonb = JsonbValueToJsonb(res);
                                    
                                    /* Render the section body with the new context */
                                    render_template(current->value->section.body, context_jsonb, result, context);
                                    
                                    /* Free the temporary values */
                                    pfree(char_val.val.string.val);
                                    pfree(key_val.val.string.val);
                                    pfree(new_context);
                                }
                            }
                            break;
                            
                        case jbvNumeric:
                            elog(WARNING, "Numeric values cannot be used as section collections");
                            break;
                            
                        case jbvBool:
                            if (value->val.boolean)
                            {
                                /* Render the section body with the original context */
                                render_template(current->value->section.body, define, result, context);
                            }
                            break;
                            
                        case jbvNull:
                            /* Don't render anything for null values */
                            break;

                        case jbvBinary:
                            /* iterate by array as expected or object where item is key/value pair */
                            {
                                JsonbIterator *it = JsonbIteratorInit((JsonbContainer *)value->val.binary.data);
                                JsonbIteratorToken token;
                                JsonbValue v;
                                
                                /* Get the container type */
                                token = JsonbIteratorNext(&it, &v, true);
                                
                                if (token == WJB_BEGIN_ARRAY)
                                {
                                    /* Iterate through array elements */
                                    int index = 0;
                                    while ((token = JsonbIteratorNext(&it, &v, true)) != WJB_END_ARRAY)
                                    {
                                        /* Create a new context with the current element */
                                        JsonbParseState *parse_state = NULL;
                                        JsonbValue *res = pushJsonbValue(&parse_state, WJB_BEGIN_OBJECT, NULL);
                                        
                                        /* Copy the original context */
                                        JsonbIterator *ctx_it = JsonbIteratorInit(&define->root);
                                        JsonbIteratorToken ctx_token;
                                        JsonbValue ctx_v;
                                        
                                        while ((ctx_token = JsonbIteratorNext(&ctx_it, &ctx_v, true)) != WJB_DONE)
                                        {
                                            if (ctx_token == WJB_KEY)
                                            {
                                                /* Add the key */
                                                pushJsonbValue(&parse_state, WJB_KEY, &ctx_v);
                                            }
                                            else if (ctx_token == WJB_VALUE)
                                            {
                                                /* Add the value */
                                                pushJsonbValue(&parse_state, WJB_VALUE, &ctx_v);
                                            }
                                        }
                                        
                                        /* Add the iterator value */
                                        JsonbValue key_val;
                                        key_val.type = jbvString;
                                        key_val.val.string.val = pstrdup(current->value->section.iterator);
                                        key_val.val.string.len = strlen(current->value->section.iterator);
                                        pushJsonbValue(&parse_state, WJB_KEY, &key_val);
                                        pushJsonbValue(&parse_state, WJB_VALUE, &v);
                                        
                                        /* Finish the object */
                                        res = pushJsonbValue(&parse_state, WJB_END_OBJECT, NULL);
                                        
                                        /* Convert to Jsonb */
                                        Jsonb *context_jsonb = JsonbValueToJsonb(res);
                                        
                                        /* Render the section body with the new context */
                                        render_template(current->value->section.body, context_jsonb, result, context);
                                        
                                        /* Free the temporary values */
                                        pfree(key_val.val.string.val);
                                        index++;
                                    }
                                }
                                else if (token == WJB_BEGIN_OBJECT)
                                {
                                    /* Iterate through object key-value pairs */
                                    while ((token = JsonbIteratorNext(&it, &v, true)) != WJB_END_OBJECT)
                                    {
                                        if (token == WJB_KEY)
                                        {
                                            /* Create a new context with the current key-value pair */
                                            JsonbParseState *parse_state = NULL;
                                            JsonbValue *res = pushJsonbValue(&parse_state, WJB_BEGIN_OBJECT, NULL);
                                            
                                            /* Copy the original context */
                                            JsonbIterator *ctx_it = JsonbIteratorInit(&define->root);
                                            JsonbIteratorToken ctx_token;
                                            JsonbValue ctx_v;
                                            
                                            while ((ctx_token = JsonbIteratorNext(&ctx_it, &ctx_v, true)) != WJB_DONE)
                                            {
                                                if (ctx_token == WJB_KEY)
                                                {
                                                    /* Add the key */
                                                    pushJsonbValue(&parse_state, WJB_KEY, &ctx_v);
                                                }
                                                else if (ctx_token == WJB_VALUE)
                                                {
                                                    /* Add the value */
                                                    pushJsonbValue(&parse_state, WJB_VALUE, &ctx_v);
                                                }
                                            }
                                            
                                            /* Add the iterator object with key and value */
                                            JsonbValue key_val;
                                            key_val.type = jbvString;
                                            key_val.val.string.val = pstrdup(current->value->section.iterator);
                                            key_val.val.string.len = strlen(current->value->section.iterator);
                                            pushJsonbValue(&parse_state, WJB_KEY, &key_val);
                                            
                                            /* Create an object for the iterator */
                                            JsonbParseState *item_parse_state = NULL;
                                            JsonbValue *item_res = pushJsonbValue(&item_parse_state, WJB_BEGIN_OBJECT, NULL);
                                            
                                            /* Add the key */
                                            key_val.val.string.val = pstrdup("key");
                                            key_val.val.string.len = strlen("key");
                                            pushJsonbValue(&item_parse_state, WJB_KEY, &key_val);
                                            pushJsonbValue(&item_parse_state, WJB_VALUE, &v);
                                            
                                            /* Get the value */
                                            token = JsonbIteratorNext(&it, &v, true);
                                            
                                            /* Add the value */
                                            key_val.val.string.val = pstrdup("value");
                                            key_val.val.string.len = strlen("value");
                                            pushJsonbValue(&item_parse_state, WJB_KEY, &key_val);
                                            pushJsonbValue(&item_parse_state, WJB_VALUE, &v);
                                            
                                            /* Finish the iterator object */
                                            item_res = pushJsonbValue(&item_parse_state, WJB_END_OBJECT, NULL);
                                            
                                            /* Add the iterator object to the context */
                                            pushJsonbValue(&parse_state, WJB_VALUE, item_res);
                                            
                                            /* Finish the context object */
                                            res = pushJsonbValue(&parse_state, WJB_END_OBJECT, NULL);
                                            
                                            /* Convert to Jsonb */
                                            Jsonb *context_jsonb = JsonbValueToJsonb(res);
                                            
                                            /* Render the section body with the new context */
                                            render_template(current->value->section.body, context_jsonb, result, context);
                                            
                                            /* Free the temporary values */
                                            pfree(key_val.val.string.val);
                                        }
                                    }
                                }
                            }
                            break;
                            
                        default:
                            elog(WARNING, "Unsupported JSONB value type in section: %s",
                                 jbv_type_to_string(value->type));
                            break;
                    }
                    
                    /* Free the value since it was allocated in our context */
                    pfree(value);
                }
                break;
                
            case TEMPLATE_NODE_INCLUDE:
                snprintf(debug_msg, debug_msg_size, "%s INCLUDE: %.50s", debug_msg, current->value->include.key);
                /* We'll implement include rendering later */
                break;
                
            default:
                elog(WARNING, "Unknown template node type: %d", current->type);
                break;
        }

        elog(DEBUG1, "%s", debug_msg);

        current = current->next;
    }

    pfree(debug_msg);
}

/* Helper function to calculate a simple hash of a string */
static uint32_t
calculate_string_hash(const char *str)
{
    uint32_t hash = 5381;
    int c;
    
    while ((c = *str++))
        hash = ((hash << 5) + hash) + c; /* hash * 33 + c */
    
    return hash;
}

/* Helper function to render an execute tag */
static void
render_execute_tag(const char *code, Jsonb *define, StringInfo result, MemoryContext context)
{
    int ret;
    StringInfoData query;
    StringInfoData exec_result;
    char *trimmed_code;
    size_t code_len;
    uint32_t code_hash;
    char func_name[64];
    bool isnull;
    bool function_exists;
    
    /* Connect to SPI */
    if ((ret = SPI_connect()) < 0)
        ereport(ERROR,
                (errcode(ERRCODE_CONNECTION_EXCEPTION),
                 errmsg("SPI_connect failed: %s", SPI_result_code_string(ret))));
    
    /* Create the query with the context variable */
    initStringInfo(&query);
    initStringInfo(&exec_result);
    
    /* Trim trailing semicolon if present to avoid double semicolons */
    code_len = strlen(code);
    trimmed_code = pstrdup(code);
    while (code_len > 0 && (trimmed_code[code_len-1] == ';' || isspace((unsigned char)trimmed_code[code_len-1]))) {
        trimmed_code[--code_len] = '\0';
    }
    
    /* Calculate hash of the code */
    code_hash = calculate_string_hash(trimmed_code);
    snprintf(func_name, sizeof(func_name), "cache-%x", code_hash);
    
    /* Check if function exists */
    appendStringInfo(&query, 
                    "SELECT EXISTS (SELECT 1 FROM pg_proc p "
                    "JOIN pg_namespace n ON p.pronamespace = n.oid "
                    "WHERE n.nspname = 'hemar' AND p.proname = '%s');",
                    func_name);
    
    ret = SPI_execute(query.data, true, 0);
    if (ret != SPI_OK_SELECT)
    {
        SPI_finish();
        ereport(ERROR,
                (errcode(ERRCODE_SYNTAX_ERROR),
                 errmsg("Failed to check function existence: %s", SPI_result_code_string(ret))));
    }
    
    function_exists = DatumGetBool(SPI_getbinval(SPI_tuptable->vals[0], SPI_tuptable->tupdesc, 1, &isnull));
    
    /* Reset query buffer for function creation */
    resetStringInfo(&query);
    
    /* Only create function if it doesn't exist */
    if (!function_exists)
    {
        elog(NOTICE, "Caching function %s", func_name);
        elog(DEBUG1, "Content: %s", trimmed_code);

        appendStringInfo(&query, 
                        "CREATE OR REPLACE FUNCTION \"hemar\".\"%s\"(context jsonb) RETURNS text LANGUAGE plpgsql AS $$ "
                        "BEGIN "
                        "  %s; "    
                        " RETURN '';" // NOTICE(yukkop): Trailing return in case user does not return anything
                        "END $$;",
                        func_name,
                        trimmed_code);
        
        /* Execute the query */
        ret = SPI_execute(query.data, false, 0);
        
        if (ret != SPI_OK_UTILITY)
        {
            SPI_finish();
            ereport(ERROR,
                    (errcode(ERRCODE_SYNTAX_ERROR),
                     errmsg("Failed to execute SQL in template: %s", SPI_result_code_string(ret))));
        }
    }
    
    /* Reset query buffer for function execution */
    resetStringInfo(&query);
    
    /* Execute the function */
    appendStringInfo(&query, "SELECT \"hemar\".\"%s\"($1);", func_name);
    
    /* Prepare arguments for SPI_execute_with_args */
    Oid argtypes[1] = {JSONBOID};
    Datum argvalues[1] = {JsonbPGetDatum(define)};
    
    ret = SPI_execute_with_args(query.data, 1, argtypes, argvalues, NULL, true, 0);
    
    if (ret != SPI_OK_SELECT)
    {
        SPI_finish();
        ereport(ERROR,
                (errcode(ERRCODE_SYNTAX_ERROR),
                 errmsg("Failed to execute function: %s", SPI_result_code_string(ret))));
    }
    
    /* Get the result */
    if (SPI_processed > 0)
    {
        Datum content = SPI_getbinval(SPI_tuptable->vals[0], SPI_tuptable->tupdesc, 1, &isnull);
        
        if (!isnull)
        {
            char *content_str = TextDatumGetCString(content);
            appendStringInfoString(&exec_result, content_str);
            pfree(content_str);
        }
    }
    
    /* Append any captured output to the result */
    if (exec_result.len > 0)
    {
        appendStringInfoString(result, exec_result.data);
    }
    
    /* Clean up */
    pfree(query.data);
    pfree(exec_result.data);
    pfree(trimmed_code);
    
    /* Disconnect from SPI */
    SPI_finish();
}

/* Function declarations */
PG_FUNCTION_INFO_V1(pg_jsonb_get_by_path);

/*
 * Parse a path string into segments for JSONB traversal
 * Path format: field.nested_field[0].array_field[1][2]
 * Returns an array of segments and the count of segments
 */
static char **
parse_path_string(const char *path_str, int *num_segments)
{
    char **segments;
    int max_segments = 32;  /* Initial capacity */
    int segment_count = 0;
    StringInfoData current_segment;
    const char *p = path_str;
    bool in_brackets = false;
    
    /* Allocate memory for segments */
    segments = (char **)palloc(sizeof(char *) * max_segments);
    if (segments == NULL)
        ereport(ERROR,
                (errcode(ERRCODE_OUT_OF_MEMORY),
                 errmsg("out of memory")));
    
    initStringInfo(&current_segment);
    
    /* Parse the path string */
    while (*p)
    {
        if (*p == '.' && !in_brackets)
        {
            /* End of segment */
            if (current_segment.len > 0)
            {
                segments[segment_count++] = pstrdup(current_segment.data);
                resetStringInfo(&current_segment);
                
                /* Resize if needed */
                if (segment_count >= max_segments)
                {
                    max_segments *= 2;
                    segments = (char **)repalloc(segments, sizeof(char *) * max_segments);
                    if (segments == NULL)
                        ereport(ERROR,
                                (errcode(ERRCODE_OUT_OF_MEMORY),
                                 errmsg("out of memory")));
                }
            }
        }
        else if (*p == '[')
        {
            /* Start of array index */
            if (in_brackets)
                ereport(ERROR,
                        (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                         errmsg("invalid path syntax: nested brackets")));
            
            /* Save the current field name if any */
            if (current_segment.len > 0)
            {
                segments[segment_count++] = pstrdup(current_segment.data);
                resetStringInfo(&current_segment);
                
                /* Resize if needed */
                if (segment_count >= max_segments)
                {
                    max_segments *= 2;
                    segments = (char **)repalloc(segments, sizeof(char *) * max_segments);
                    if (segments == NULL)
                        ereport(ERROR,
                                (errcode(ERRCODE_OUT_OF_MEMORY),
                                 errmsg("out of memory")));
                }
            }
            
            /* Add a special prefix to indicate this is an array index */
            appendStringInfoChar(&current_segment, '[');
            in_brackets = true;
        }
        else if (*p == ']')
        {
            /* End of array index */
            if (!in_brackets)
                ereport(ERROR,
                        (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                         errmsg("invalid path syntax: unmatched closing bracket")));
            
            /* Save the array index */
            if (current_segment.len > 0)
            {
                /* We don't need to append the closing bracket, just save the segment */
                segments[segment_count++] = pstrdup(current_segment.data);
                resetStringInfo(&current_segment);
                
                /* Resize if needed */
                if (segment_count >= max_segments)
                {
                    max_segments *= 2;
                    segments = (char **)repalloc(segments, sizeof(char *) * max_segments);
                    if (segments == NULL)
                        ereport(ERROR,
                                (errcode(ERRCODE_OUT_OF_MEMORY),
                                 errmsg("out of memory")));
                }
            }
            else
            {
                ereport(ERROR,
                        (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                         errmsg("invalid path syntax: empty array index")));
            }
            
            in_brackets = false;
        }
        else
        {
            /* Regular character */
            appendStringInfoChar(&current_segment, *p);
        }
        
        p++;
    }
    
    /* Handle the last segment if any */
    if (current_segment.len > 0)
    {
        if (in_brackets)
            ereport(ERROR,
                    (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                     errmsg("invalid path syntax: unclosed bracket")));
        
        segments[segment_count++] = pstrdup(current_segment.data);
    }
    
    pfree(current_segment.data);
    *num_segments = segment_count;
    
    return segments;
}

/*
 * Internal function to get JSONB value by path
 * Input: JSONB document, path string, and memory context
 * Output: JsonbValue at the specified path or NULL if path is invalid
 * Note: The returned JsonbValue is allocated in the provided context
 */
static JsonbValue *
jsonb_get_by_path_internal(Jsonb *jb, const char *path_str, MemoryContext context)
{
    JsonbValue *result = NULL;
    JsonbValue tmp_val;
    JsonbIterator *it;
    JsonbIteratorToken token;
    JsonbValue v;
    
    char **segments;
    int num_segments;
    int current_segment = 0;
    int array_index;
    int current_index;
    bool found;
    int i;
    
    /* Empty path returns NULL */
    if (path_str == NULL || *path_str == '\0')
    {
        elog(WARNING, "path is empty, returning NULL");
        return NULL;
    }
    
    /* Parse the path string */
    segments = parse_path_string(path_str, &num_segments);
    
    if (num_segments == 0)
    {
        /* Free allocated memory before returning */
        elog(WARNING, "no segments in path, returning NULL");
        pfree(segments);
        return NULL;
    }
    
    /* Start iterating through the JSONB document */
    it = JsonbIteratorInit(&jb->root);
    token = JsonbIteratorNext(&it, &v, true);
    
    if (token == WJB_BEGIN_ARRAY)
    {
        /* If the root is an array, the first segment must be an array index */
        if (current_segment < num_segments && segments[current_segment][0] != '[')
        {
            /* First segment is not an array index, but root is an array */
            /* Free allocated memory before returning */
            elog(WARNING, "root is an array, but first segment '%s' is not an array index", segments[current_segment]);
            for (i = 0; i < num_segments; i++)
                pfree(segments[i]);
            pfree(segments);
            return NULL;
        }
    }
    else if (token == WJB_BEGIN_OBJECT)
    {
        /* If the root is an object, the first segment must be a field name */
        if (current_segment < num_segments && segments[current_segment][0] == '[')
        {
            /* First segment is an array index, but root is an object */
            /* Free allocated memory before returning */
            elog(WARNING, "root is an object, but first segment '%s' is an array index", segments[current_segment]);
            for (i = 0; i < num_segments; i++)
                pfree(segments[i]);
            pfree(segments);
            return NULL;
        }
    }
    else
    {
        /* Root is a scalar value, can't navigate further */
        /* Free allocated memory before returning */
        elog(WARNING, "root is a scalar value, can't navigate further");
        for (i = 0; i < num_segments; i++)
            pfree(segments[i]);
        pfree(segments);
        return NULL;
    }
    
    /* Process each path segment */
    while (current_segment < num_segments)
    {
        char *segment = segments[current_segment];
        
        if (segment[0] == '[')
        {
            /* Array index segment */
            if (token != WJB_BEGIN_ARRAY)
            {
                /* Not an array, can't use array index */
                /* Free allocated memory before returning */
                elog(WARNING, "segment '%s' is not an array, can't use array index", segment);
                for (i = 0; i < num_segments; i++)
                    pfree(segments[i]);
                pfree(segments);
                return NULL;
            }
            
            /* Extract the array index */
            array_index = atoi(segment + 1);
            if (array_index < 0)
            {
                /* Free allocated memory before returning */
                elog(WARNING, "invalid array index: %d", array_index);
                for (i = 0; i < num_segments; i++)
                    pfree(segments[i]);
                pfree(segments);
                return NULL;
            }
            
            /* Navigate to the specified array element */
            current_index = 0;
            found = false;
            
            /* Move to the first element */
            token = JsonbIteratorNext(&it, &v, true);
            
            /* Iterate through array elements */
            while (token != WJB_END_ARRAY)
            {
                if (current_index == array_index)
                {
                    found = true;
                    
                    /* If this is the last segment, return the value */
                    if (current_segment == num_segments - 1)
                    {
                        /* Create a standalone JsonbValue for the result */
                        result = MemoryContextAlloc(context, sizeof(JsonbValue));
                        *result = v;
                        
                        /* For string values, we need to make a copy of the string data */
                        if (result->type == jbvString)
                        {
                            char *str_copy = palloc(result->val.string.len + 1);
                            memcpy(str_copy, result->val.string.val, result->val.string.len);
                            str_copy[result->val.string.len] = '\0';
                            result->val.string.val = str_copy;
                        }
                        /* Convert to a Jsonb container */
                        else if (result->type == jbvBinary)
                        {
                            tmp_val.type = jbvBinary;
                            tmp_val.val.binary.data = result->val.binary.data;
                            tmp_val.val.binary.len = result->val.binary.len;
                        }
                        else
                        {
                            tmp_val = *result;
                        }
                        
                        /* Free allocated memory before returning */
                        for (i = 0; i < num_segments; i++)
                            pfree(segments[i]);
                        pfree(segments);
                        
                        return result;
                    }
                    
                    /* Not the last segment, continue traversing */
                    if (v.type == jbvBinary)
                    {
                        /* Nested container, need to iterate into it */
                        JsonbIterator *nested_it = JsonbIteratorInit((JsonbContainer *) v.val.binary.data);
                        it = nested_it;
                        
                        /* Get the container type (array or object) */
                        token = JsonbIteratorNext(&it, &v, true);
                        
                        /* Move to the next segment */
                        current_segment++;
                        /* Continue processing from the next segment */
                        break;
                    }
                    else
                    {
                        /* Scalar value, can't navigate further */
                        /* Free allocated memory before returning */
                        elog(WARNING, "scalar value at segment '%s', can't navigate further", segment);
                        for (i = 0; i < num_segments; i++)
                            pfree(segments[i]);
                        pfree(segments);
                        return NULL;
                    }
                }
                
                /* Skip this element */
                if (v.type == jbvBinary)
                {
                    /* Skip over the entire container */
                    JsonbIterator *nested_it = JsonbIteratorInit((JsonbContainer *) v.val.binary.data);
                    JsonbIteratorToken nested_token;
                    JsonbValue nested_v;
                    
                    /* Skip until we reach the end of the container */
                    do
                    {
                        nested_token = JsonbIteratorNext(&nested_it, &nested_v, false);
                    } while (nested_token != WJB_DONE);
                }
                
                current_index++;
                token = JsonbIteratorNext(&it, &v, true);
            }
            
            if (!found)
            {
                /* Array index out of bounds */
                /* Free allocated memory before returning */
                elog(WARNING, "array index %d out of bounds", array_index);
                for (i = 0; i < num_segments; i++)
                    pfree(segments[i]);
                pfree(segments);
                return NULL;
            }
            
            /* If we found the element and broke out of the loop to process the next segment,
               we need to continue the outer loop */
            if (current_segment < num_segments)
                continue;
        }
        else
        {
            /* Field name segment */
            if (token != WJB_BEGIN_OBJECT)
            {
                /* Not an object, can't use field name */
                /* Free allocated memory before returning */
                elog(WARNING, "segment '%s' is not an object, can't use field name", segment);
                for (i = 0; i < num_segments; i++)
                    pfree(segments[i]);
                pfree(segments);
                return NULL;
            }
            
            /* Navigate to the specified field */
            found = false;
            
            token = JsonbIteratorNext(&it, &v, true);
            while (token != WJB_END_OBJECT)
            {
                /* We should be at a key */
                if (token != WJB_KEY)
                {
                    /* Free allocated memory before returning */
                    elog(WARNING, "unexpected token: expected WJB_KEY");
                    for (i = 0; i < num_segments; i++)
                        pfree(segments[i]);
                    pfree(segments);
                    ereport(ERROR,
                            (errcode(ERRCODE_INTERNAL_ERROR),
                             errmsg("unexpected JSONB iterator token")));
                }
                
                /* Check if this is the field we're looking for */
                if (v.type == jbvString && 
                    strlen(segment) == v.val.string.len &&
                    strncmp(segment, v.val.string.val, v.val.string.len) == 0)
                {
                    found = true;
                    
                    /* Get the value */
                    token = JsonbIteratorNext(&it, &v, true);
                    
                    /* If this is the last segment, return the value */
                    if (current_segment == num_segments - 1)
                    {
                        /* Create a standalone JsonbValue for the result */
                        result = MemoryContextAlloc(context, sizeof(JsonbValue));
                        *result = v;
                        
                        /* For string values, we need to make a copy of the string data */
                        if (result->type == jbvString)
                        {
                            char *str_copy = palloc(result->val.string.len + 1);
                            memcpy(str_copy, result->val.string.val, result->val.string.len);
                            str_copy[result->val.string.len] = '\0';
                            result->val.string.val = str_copy;
                        }
                        /* Convert to a Jsonb container */
                        else if (result->type == jbvBinary)
                        {
                            tmp_val.type = jbvBinary;
                            tmp_val.val.binary.data = result->val.binary.data;
                            tmp_val.val.binary.len = result->val.binary.len;
                        }
                        else
                        {
                            tmp_val = *result;
                        }
                        
                        /* Free allocated memory before returning */
                        for (i = 0; i < num_segments; i++)
                            pfree(segments[i]);
                        pfree(segments);
                        
                        return result;
                    }
                    
                    /* Not the last segment, continue traversing */
                    if (v.type == jbvBinary)
                    {
                        /* Nested container, need to iterate into it */
                        JsonbIterator *nested_it = JsonbIteratorInit((JsonbContainer *) v.val.binary.data);
                        it = nested_it;
                        
                        /* Get the container type (array or object) */
                        token = JsonbIteratorNext(&it, &v, true);
                        
                        /* Move to the next segment */
                        current_segment++;
                        /* Continue processing from the next segment */
                        break;
                    }
                    else
                    {
                        /* Scalar value, can't navigate further */
                        /* Free allocated memory before returning */
                        elog(WARNING, "scalar value at segment '%s', can't navigate further", segment);
                        for (i = 0; i < num_segments; i++)
                            pfree(segments[i]);
                        pfree(segments);
                        return NULL;
                    }
                }
                else
                {
                    /* Skip this field's value */
                    token = JsonbIteratorNext(&it, &v, true);
                    
                    if (v.type == jbvBinary)
                    {
                        /* Skip over the entire container */
                        JsonbIterator *nested_it = JsonbIteratorInit((JsonbContainer *) v.val.binary.data);
                        JsonbIteratorToken nested_token;
                        JsonbValue nested_v;
                        
                        /* Skip until we reach the end of the container */
                        do
                        {
                            nested_token = JsonbIteratorNext(&nested_it, &nested_v, false);
                        } while (nested_token != WJB_DONE);
                    }
                }
                
                token = JsonbIteratorNext(&it, &v, true);
            }
            
            if (!found)
            {
                /* Field not found */
                /* Free allocated memory before returning */
                elog(WARNING, "field not found, returning NULL");
                for (i = 0; i < num_segments; i++)
                    pfree(segments[i]);
                pfree(segments);
                return NULL;
            }
            
            /* If we found the field and broke out of the loop to process the next segment,
               we need to continue the outer loop */
            if (current_segment < num_segments)
                continue;
        }
        
        current_segment++;
    }
    
    /* We should have returned by now if we found the value */
    /* Free allocated memory before returning */
    elog(WARNING, "unexpected end of function, returning NULL");
    for (i = 0; i < num_segments; i++)
        pfree(segments[i]);
    pfree(segments);
    
    return NULL;
}

/*
 * Get JSONB value by path
 * Input: JSONB document and path string
 * Output: JSONB value at the specified path or NULL if path is invalid
 */
Datum
pg_jsonb_get_by_path(PG_FUNCTION_ARGS)
{
    Jsonb *jb = PG_GETARG_JSONB_P(0);
    text *path_text = PG_GETARG_TEXT_PP(1);
    char *path_str = text_to_cstring(path_text);
    JsonbValue *result;
    JsonbValue tmp_val;
    
    /* Use the internal function to get the value */
    result = jsonb_get_by_path_internal(jb, path_str, CurrentMemoryContext);
    
    if (result == NULL)
    {
        pfree(path_str);
        PG_RETURN_NULL();
    }
    
    /* Convert to a Jsonb container */
    if (result->type == jbvBinary)
    {
        tmp_val.type = jbvBinary;
        tmp_val.val.binary.data = result->val.binary.data;
        tmp_val.val.binary.len = result->val.binary.len;
    }
    else
    {
        tmp_val = *result;
    }
    
    /* Free allocated memory */
    pfree(result);
    pfree(path_str);
    
    /* Return the result as a new Jsonb */
    PG_RETURN_JSONB_P(JsonbValueToJsonb(&tmp_val));
}