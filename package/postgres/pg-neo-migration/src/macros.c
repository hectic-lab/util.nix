#include "macros.h"

// Static color mode variable
static ColorMode color_mode = COLOR_MODE_AUTO;

// Function to set color mode
void set_output_color_mode(ColorMode mode) {
    color_mode = mode;
}
