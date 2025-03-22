#ifndef EPRINTF_HMPL
#define EPRINTF_HMPL

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "chectic.h"
#include "cjson/cJSON.h"

void init_cjson_with_arenas(Arena *arena);

char *eval(Arena *arena, const cJSON * const context, const char * const key);

/* Modified: text is passed by reference so we can update it and free old allocations */
void render_template_placeholders(Arena *arena, char **text_ptr, cJSON *context, const char * const prefix);

void render_template_with_arena(Arena *arena, char **text, const cJSON * const ccontext);

void render_template(char **text, const cJSON * const context);

#endif // EPRINTF_HMPL
