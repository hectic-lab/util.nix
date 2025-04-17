#include "postgres.h"
#include "fmgr.h"
#include "utils/builtins.h" /* for text_to_cstring and cstring_to_text */

#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC;
#endif

Datum hello(PG_FUNCTION_ARGS) 
{
    PG_RETURN_TEXT_P(cstring_to_text("Eblan!"));
}

void _PG_init(void) {

}
void _PG_fini(void) {

}

