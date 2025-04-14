
// External color mode variable declaration
extern ColorMode color_mode;
extern ColorMode debug_color_mode;

const char* color_mode_to_string(ColorMode mode);

// Function to set color mode
void set_output_color_mode(ColorMode mode);

// Macros for detecting terminal and color usage
#define IS_TERMINAL() (isatty(fileno(stderr)))

/*
 * USE_COLOR() is true if color is forced or if color is auto and the output is a terminal.
 * used for all colorized output
 */
#define USE_COLOR() ((color_mode == COLOR_MODE_FORCE) || (color_mode == COLOR_MODE_AUTO && IS_TERMINAL()))

/*
 * DEBUG_COLOR_MODE is the color mode for debug output after USE_COLOR() check.
 * used for debug colorized output
 */
#define USE_COLOR_IN_DEBUG() (color_mode == COLOR_MODE_AUTO ? ((debug_color_mode == COLOR_MODE_FORCE) || (debug_color_mode == COLOR_MODE_AUTO && IS_TERMINAL())) : USE_COLOR())

#define COLOR_RED "\033[1;31m"
#define COLOR_GREEN "\033[1;32m"
#define COLOR_YELLOW "\033[1;33m"
#define COLOR_BLUE "\033[1;34m"
#define COLOR_MAGENTA "\033[1;35m"
#define COLOR_CYAN "\033[1;36m"
#define COLOR_WHITE "\033[1;37m"
#define COLOR_RESET "\033[0m"

#define OPTIONAL_COLOR(color) (USE_COLOR() ? color : "")
#define DEBUG_COLOR(color) (USE_COLOR_IN_DEBUG() ? color : "")

">>>>"
DEBUG_COLOR(COLOR_RED) "Hello" DEBUG_COLOR(COLOR_RESET)
