#ifndef EPRINTF_H
#define EPRINTF_H

#include <stdio.h>
#include <unistd.h>

// Color mode enumeration
typedef enum {
  COLOR_MODE_AUTO, 
  COLOR_MODE_FORCE,
  COLOR_MODE_DISABLE
} ColorMode;

// Static color mode variable
static ColorMode color_mode = COLOR_MODE_AUTO;

// Function to set color mode
void set_output_color_mode(ColorMode mode) {
    color_mode = mode;
}

// Macros for detecting terminal and color usage
#define IS_TERMINAL() (isatty(fileno(stderr)))
#define USE_COLOR() ((color_mode == COLOR_MODE_FORCE) || (color_mode == COLOR_MODE_AUTO && IS_TERMINAL()))

#define COLOR_RED (USE_COLOR() ? "\033[1;31m" : "")
#define COLOR_RESET (USE_COLOR() ? "\033[0m" : "")

// Define color macros based on output type
#define ERROR_PREFIX PP_CAT_I(COLOR_RED, "Error: ")
#define ERROR_SUFFIX PP_CAT_I(COLOR_RESET, "\n")

// Helper macros for argument counting
// NOTE(yukkop): this ugly macroses for avoid all posible warnings
#define PP_CAT(a, b) PP_CAT_I(a, b)
#define PP_CAT_I(a, b) a##b

#define PP_NARG(...) PP_NARG_(__VA_ARGS__, PP_RSEQ_N())
#define PP_NARG_(...) PP_ARG_N(__VA_ARGS__)
#define PP_ARG_N(_1,_2,_3,_4,_5,_6,_7,_8,_9,N,...) N
#define PP_RSEQ_N() 9,8,7,6,5,4,3,2,1,0

// eprintf handling 1 or more arguments
#define eprintf_1(fmt) \
    fprintf(stderr, "%s" fmt "%s", ERROR_PREFIX, ERROR_SUFFIX)

#define eprintf_2(fmt, ...) \
    fprintf(stderr, "%s" fmt "%s", ERROR_PREFIX, __VA_ARGS__, ERROR_SUFFIX)

#define eprintf(...) \
    PP_CAT(eprintf_, PP_NARG(__VA_ARGS__))(__VA_ARGS__)

#define todo fprintf(stderr, "%sNot implimented yet%s", COLOR_RED, COLOR_RESET);exit(1)

#endif // EPRINTF_H
