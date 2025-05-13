#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <time.h>
#include <unistd.h>
#include "postgres.h"
#include "catalog/pg_type_d.h"
#include "fmgr.h"
#include "nodes/pg_list.h"
#include "parser/parse_func.h"
#include "utils/builtins.h"
#include "utils/datum.h"
#include "utils/json.h"
#include "utils/memutils.h"
#include "utils/regproc.h"
#include <string.h>
#include "hectic.h"

#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC;
#endif

static MemoryContext HemarContext = NULL;

#define LOG_FILE "/tmp/hemar.log"

#define INIT \
    MemoryContext oldctx; \
    oldctx = MemoryContextSwitchTo(HemarContext); \
    logger_init(); \
    logger_set_file(LOG_FILE); \
    logger_set_output_mode(LOG_OUTPUT_BOTH); \
    Arena arena = arena_init(MEM_MiB);


#define FREE \
    /*DISPOSABLE_ARENA_FREE*/; \
    /*arena_free(&arena);*/ \
    /*logger_free();*/ \
    MemoryContextSwitchTo(oldctx); \
    MemoryContextReset(HemarContext);

void noop_free(void* ptr) {
    (void)ptr; // suppress unused warning
}

void _PG_init(void)
{
   HemarContext = AllocSetContextCreate(TopMemoryContext,
                                            "HemarContext",
                                            ALLOCSET_DEFAULT_SIZES);

   MemoryAllocator allocators = {
       .malloc = palloc,
       .free = noop_free
   };

   set_memory_allocator(allocators);
}

PG_FUNCTION_INFO_V1(pg_template_parse);

Datum pg_template_parse(PG_FUNCTION_ARGS) {
    INIT;

    text *template_text = PG_GETARG_TEXT_PP(0);
    const char *template_str = text_to_cstring(template_text);
    raise_notice("%s", template_str);

    TemplateResult template_result;
    TemplateConfig config = template_default_config(&arena);

    raise_info("start parsing....");
    template_result = template_parse(&arena, &template_str, &config);
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
    text *result = cstring_to_text(result_str);

    FREE;

    PG_RETURN_TEXT_P(result);
}
