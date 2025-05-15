/*
 * hemar.h
 * Template parser for Hemar
 */
#ifndef HEMAR_TEMPLATE_H
#define HEMAR_TEMPLATE_H

#include "postgres.h"
#include "utils/memutils.h"

/* Maximum length for template syntax elements */
#define TEMPLATE_MAX_PREFIX_LEN 32

/* Template error codes */
typedef enum {
    TEMPLATE_ERROR_NONE = 0,
    TEMPLATE_ERROR_UNKNOWN_TAG,
    TEMPLATE_UNEXPECTED_OPEN_BRACES_AFFTER_SECTION_CONTROLE,
    TEMPLATE_UNEXPECTED_OPEN_BRACES_AFFTER_SECTION_SOURCE,
    TEMPLATE_ERROR_UNEXPECTED_INTERPOLATION_END,
    TEMPLATE_ERROR_NO_SOURSE_IN_SECTION,
    TEMPLATE_ERROR_NESTED_INTERPOLATION,
    TEMPLATE_ERROR_UNEXPECTED_SECTION_END,
    TEMPLATE_ERROR_NO_BEGIN_IN_SECTION,
    TEMPLATE_ERROR_NESTED_INCLUDE,
    TEMPLATE_ERROR_NESTED_EXECUTE,
    TEMPLATE_ERROR_INVALID_CONFIG,
    TEMPLATE_ERROR_OUT_OF_MEMORY,
    TEMPLATE_ERROR_UNEXPECTED_INCLUDE_END,
    TEMPLATE_ERROR_UNEXPECTED_EXECUTE_END
} TemplateErrorCode;

/* Template node types */
typedef enum {
    TEMPLATE_NODE_TEXT,
    TEMPLATE_NODE_INTERPOLATE,
    TEMPLATE_NODE_SECTION,
    TEMPLATE_NODE_EXECUTE,
    TEMPLATE_NODE_INCLUDE
} TemplateNodeType;

/* Template configuration structure */
typedef struct {
    struct {
        struct {
            const char *open;      /* Default: "{%" */
            const char *close;     /* Default: "%}" */
        } Braces;
        struct {
            const char *control;   /* default: "for " */
            const char *source;    /* default: "in " */
            const char *begin;     /* default: "do " */
        } Section;
        struct {
            const char *invoke;    /* default: "" */
        } Interpolate;
        struct {
            const char *invoke;    /* default: "include " */
        } Include;
        struct {
            const char *invoke;    /* default: "exec " */
        } Execute;
        const char *nesting;    /* default: "->" */
    } Syntax;
} TemplateConfig;

/* Forward declaration */
typedef struct TemplateNode TemplateNode;

/* Template value structures */
typedef struct {
    char *iterator;
    char *collection;
    TemplateNode *body;
} TemplateSectionValue;

typedef struct {
    char *key;
} TemplateInterpolateValue;

typedef struct {
    char *code;
} TemplateExecuteValue;

typedef struct {
    char *key;
} TemplateIncludeValue;

typedef struct {
    char *content;
} TemplateTextValue;

typedef union {
    TemplateSectionValue section;
    TemplateInterpolateValue interpolate;
    TemplateExecuteValue execute;
    TemplateIncludeValue include;
    TemplateTextValue text;
} TemplateValue;

/* Template node structure */
struct TemplateNode {
    TemplateNodeType type;
    TemplateValue *value;
    TemplateNode *next;
};

/* Function declarations */
TemplateConfig template_default_config(MemoryContext context);
bool template_validate_config(const TemplateConfig *config, TemplateErrorCode *error_code);
TemplateNode *template_parse(MemoryContext context, const char **s, const TemplateConfig *config, bool inner_parse, TemplateErrorCode *error_code);
void template_free_node(TemplateNode *node);
const char *template_error_to_string(TemplateErrorCode code, TemplateConfig *config);

#endif /* HEMAR_TEMPLATE_H */ 