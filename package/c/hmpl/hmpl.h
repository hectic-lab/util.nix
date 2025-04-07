#ifndef EPRINTF_HMPL
#define EPRINTF_HMPL

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <assert.h>
#include "hectic.h"

typedef struct {
  char *prefix_start;
  char *prefix_end;
  char *separator_pattern;
} HmplSectionTagsOptions;

typedef struct {
  char *prefix;
} HmplInterpolationTagsOptions;

typedef struct {
  HmplSectionTagsOptions section_tags_options;
  HmplInterpolationTagsOptions interpolation_tags_options;
} HmplOptions;

static const HmplOptions DEFAULT_OPTIONS = {
  .section_tags_options = {
    .prefix_start = "",
    .prefix_end = "/",
    .separator_pattern = "#"
  },
  .interpolation_tags_options = {
    .prefix = ""
  }
};

void init_cjson_with_arenas(Arena *arena);

char *eval_string(Arena *arena, const Json * const context, const char * const key);

/* Modified: text is passed by reference so we can update it and free old allocations */
void hmpl_render_interpolation_tags(Arena *arena, char **text_ptr, const Json * const context, const char * const prefix);

void hmpl_render_interpolation_tags_opts(Arena *arena, char **text_ptr, const Json *context, const HmplInterpolationTagsOptions *options);

void hmpl_render_section_tags(Arena *arena, char **text_ptr, Json *context, const char * const prefix_start, const char * const prefix_end, const char * const separator_pattern);

void hmpl_render_section_tags_opts(Arena *arena, char **text_ptr, const Json *context, const HmplSectionTagsOptions *options);

void hmpl_render_with_arena(Arena *arena, char **text, const Json * const context, const HmplOptions * const options);

void hmpl_render(char **text, const Json * const context, const HmplOptions * const options);

#endif // EPRINTF_HMPL
