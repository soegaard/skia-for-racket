/* Mirror of pinned m119 sk_highcontrastconfig_t. No library is loaded here.
 * Set -DSKIA_C_TYPES_HEADER='"/path/include/c/sk_types.h"' to check the real
 * pinned C header instead of this declaration. */
#include <stddef.h>
#include <stdbool.h>
#include <stdio.h>
#ifdef SKIA_C_TYPES_HEADER
#include SKIA_C_TYPES_HEADER
#else
typedef enum {
    NO_INVERT_SK_HIGH_CONTRAST_CONFIG_INVERT_STYLE,
    INVERT_BRIGHTNESS_SK_HIGH_CONTRAST_CONFIG_INVERT_STYLE,
    INVERT_LIGHTNESS_SK_HIGH_CONTRAST_CONFIG_INVERT_STYLE
} sk_highcontrastconfig_invertstyle_t;
typedef struct {
    bool fGrayscale;
    sk_highcontrastconfig_invertstyle_t fInvertStyle;
    float fContrast;
} sk_highcontrastconfig_t;
#endif
_Static_assert(sizeof(bool) == 1, "C bool must occupy one byte");
_Static_assert(sizeof(sk_highcontrastconfig_invertstyle_t) == 4, "enum size");
_Static_assert(sizeof(float) == 4, "float size");
_Static_assert(sizeof(sk_highcontrastconfig_t) == 12, "config size");
_Static_assert(offsetof(sk_highcontrastconfig_t, fGrayscale) == 0, "grayscale offset");
_Static_assert(offsetof(sk_highcontrastconfig_t, fInvertStyle) == 4, "invert offset");
_Static_assert(offsetof(sk_highcontrastconfig_t, fContrast) == 8, "contrast offset");
_Static_assert(NO_INVERT_SK_HIGH_CONTRAST_CONFIG_INVERT_STYLE == 0, "none enum");
_Static_assert(INVERT_BRIGHTNESS_SK_HIGH_CONTRAST_CONFIG_INVERT_STYLE == 1, "brightness enum");
_Static_assert(INVERT_LIGHTNESS_SK_HIGH_CONTRAST_CONFIG_INVERT_STYLE == 2, "lightness enum");
int main(void) {
    printf("Color-filter ABI mirror passed: high-contrast=%zu; bool=1 invert-offset=4 contrast-offset=8\n",
           sizeof(sk_highcontrastconfig_t));
    return 0;
}
