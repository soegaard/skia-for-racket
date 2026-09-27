/* Host mirror of m119's C/C++ boundary. Not a dynamic library ABI probe. */
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <assert.h>
typedef struct { int32_t left, top, right, bottom; } IRect;
typedef enum { DEFAULT, TRANSPARENT, FIXED_COLOR } CRectType;
typedef struct {
    const int *x_divs, *y_divs;
    const CRectType *rect_types;
    int x_count, y_count;
    const IRect *bounds;
    const uint32_t *colors;
} LatticeC;
typedef struct {
    const int *x_divs, *y_divs;
    const uint8_t *rect_types; /* Actual SkCanvas::Lattice::RectType storage. */
    int x_count, y_count;
    const IRect *bounds;
    const uint32_t *colors;
} LatticeNative;
typedef struct { float scos, ssin, tx, ty; } RSXform;
_Static_assert(sizeof(int) == 4, "native int must be 32-bit");
_Static_assert(sizeof(float) == 4, "native float must be 32-bit");
_Static_assert(sizeof(RSXform) == 16, "RSXform layout");
_Static_assert(sizeof(LatticeC) == sizeof(LatticeNative), "record ABI despite pointee enum mismatch");
_Static_assert(offsetof(LatticeC, bounds) == offsetof(LatticeNative, bounds), "bounds offset");
_Static_assert(offsetof(LatticeC, x_count) == 3 * sizeof(void *), "count offset");
int main(void) {
    const uint8_t types[] = {0,1,2,0,1,0,2,0,0};
    LatticeNative n = {0,0,types,2,2,0,0};
    assert(n.rect_types[1] == 1 && n.rect_types[2] == 2 && n.rect_types[6] == 2);
    assert(sizeof(LatticeC) == (sizeof(void*) == 8 ? 48 : 28));
    printf("Geometry ABI mirror passed: lattice=%zu RSXform=%zu cell-type=1 bounds-offset=%zu colors-offset=%zu\n",
           sizeof(LatticeC), sizeof(RSXform), offsetof(LatticeC,bounds), offsetof(LatticeC,colors));
    return 0;
}
