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
                
                size_t text_len = *s - start;
                current->value->text.content = MemoryContextStrdup(context, pnstrdup(start, text_len));
                current_node_filled = true;
            }
            
            /* Parse the tag */
            tag_node = NULL;
            const char *tag_prefix = *s + strlen(config->Syntax.Braces.open);
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
        
        size_t text_len = *s - start;
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