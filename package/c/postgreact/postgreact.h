#ifndef POSTGREACT_H
#define POSTGREACT_H

#include "postgres.h"

#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC;
#endif

void _PG_init(void);
void _PG_fini(void);

Datum hello(PG_FUNCTION_ARGS);
PG_FUNCTION_INFO_V1(hello);

#endif // POSTGREACT_H
