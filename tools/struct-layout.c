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
typedef struct { float x, y; } point;
typedef struct { void *glyphs, *pos, *utf8text, *clusters; } textblob_runbuffer;
typedef struct { int32_t left, top, right, bottom; } irect;
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
    int quality, downsample, alpha_option;
    void *xmp_metadata, *icc_profile, *icc_description;
} jpeg_options;
typedef struct {
    int compression;
    float quality;
    void *icc_profile, *icc_description;
} webp_options;
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
_Static_assert(sizeof(point) == 8, "point layout");
_Static_assert(sizeof(textblob_runbuffer) == 4 * sizeof(void *), "textblob runbuffer layout");
_Static_assert(offsetof(textblob_runbuffer, clusters) == 3 * sizeof(void *), "textblob runbuffer clusters offset");
_Static_assert(offsetof(point, y) == 4, "point y offset");
_Static_assert(sizeof(irect) == 16, "integer rectangle layout");
_Static_assert(offsetof(irect, bottom) == 12, "integer rectangle bottom offset");
_Static_assert(sizeof(sampling) == 24, "sampling layout");
_Static_assert(offsetof(sampling, cubic_b) == 8, "sampling padding");
_Static_assert(offsetof(sampling, filter) == 16, "filter offset");
_Static_assert(sizeof(png_options) == 8 + 3 * sizeof(void *), "PNG layout");
_Static_assert(offsetof(png_options, comments) == 8, "PNG pointer offset");
_Static_assert(offsetof(jpeg_options, xmp_metadata) == (sizeof(void *) == 8 ? 16 : 12),
               "JPEG pointer alignment");
_Static_assert(sizeof(jpeg_options) ==
               (sizeof(void *) == 8 ? 16 : 12) + 3 * sizeof(void *),
               "JPEG options layout");
_Static_assert(offsetof(webp_options, icc_profile) == 8, "WebP pointer offset");
_Static_assert(sizeof(webp_options) == 8 + 2 * sizeof(void *), "WebP options layout");
_Static_assert(sizeof(font_metrics) == 64, "font-metrics layout");
_Static_assert(offsetof(font_metrics, top) == 4, "font-metrics top offset");
_Static_assert(offsetof(font_metrics, cap_height) == 44, "font-metrics cap-height offset");
_Static_assert(offsetof(font_metrics, underline_thickness) == 48, "font-metrics underline offset");
_Static_assert(offsetof(font_metrics, strikeout_position) == 60, "font-metrics strikeout offset");
int main(void) {
    printf("host C: image-info=%zu rect=%zu point=%zu textblob-runbuffer=%zu irect=%zu sampling=%zu png-options=%zu jpeg-options=%zu webp-options=%zu font-metrics=%zu\n",
           sizeof(image_info), sizeof(rect), sizeof(point), sizeof(textblob_runbuffer),
           sizeof(irect), sizeof(sampling), sizeof(png_options), sizeof(jpeg_options),
           sizeof(webp_options), sizeof(font_metrics));
    puts("Layout assertions passed; no Skia or Racket code was executed.");
    return 0;
}
