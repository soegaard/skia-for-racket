/* Optional host-C layout sanity check. These declarations mirror the pinned
 * ABI fields; this does NOT link Skia or validate Racket's FFI at runtime.
 * Run: cc -std=c11 tools/struct-layout.c -o /tmp/skia-layout && /tmp/skia-layout
 */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

typedef struct {
    void *colorspace;
    int32_t width, height;
    int color_type, alpha_type;
} image_info;
typedef struct { float left, top, right, bottom; } rect;
typedef struct {
    int max_aniso;
    bool use_cubic;
    float cubic_b, cubic_c;
    int filter, mipmap;
} sampling;
typedef struct {
    int filters, compression;
    void *comments, *icc_profile, *icc_description;
} png_options;
typedef struct {
    uint32_t flags;
    float top, ascent, descent, bottom, leading;
    float avg_char_width, max_char_width;
    float x_min, x_max, x_height, cap_height;
    float underline_thickness, underline_position;
    float strikeout_thickness, strikeout_position;
} font_metrics;

_Static_assert(sizeof(int) == 4, "32-bit C int required");
_Static_assert(sizeof(float) == 4, "32-bit float required");
_Static_assert(sizeof(bool) == 1, "one-byte C bool required");
_Static_assert(sizeof(image_info) == sizeof(void *) + 16, "image-info layout");
_Static_assert(offsetof(image_info, width) == sizeof(void *), "width offset");
_Static_assert(sizeof(rect) == 16, "rectangle layout");
_Static_assert(sizeof(sampling) == 24, "sampling layout");
_Static_assert(offsetof(sampling, cubic_b) == 8, "sampling padding");
_Static_assert(offsetof(sampling, filter) == 16, "filter offset");
_Static_assert(sizeof(png_options) == 8 + 3 * sizeof(void *), "PNG layout");
_Static_assert(offsetof(png_options, comments) == 8, "PNG pointer offset");
_Static_assert(sizeof(font_metrics) == 64, "font-metrics layout");
_Static_assert(offsetof(font_metrics, top) == 4, "font-metrics top offset");
_Static_assert(offsetof(font_metrics, cap_height) == 44, "font-metrics cap-height offset");
_Static_assert(offsetof(font_metrics, underline_thickness) == 48, "font-metrics underline offset");
_Static_assert(offsetof(font_metrics, strikeout_position) == 60, "font-metrics strikeout offset");
int main(void) {
    printf("host C: image-info=%zu rect=%zu sampling=%zu png-options=%zu font-metrics=%zu\n",
           sizeof(image_info), sizeof(rect), sizeof(sampling), sizeof(png_options), sizeof(font_metrics));
    puts("Layout assertions passed; no Skia or Racket code was executed.");
    return 0;
}
