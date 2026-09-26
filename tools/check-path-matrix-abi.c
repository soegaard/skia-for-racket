/* Host layout mirror for the pinned m119 boundary; does NOT load Skia.
   Canvas entry points reinterpret a 16-float value as column-major SkM44.
   Path, shader and measurement entry points convert a 9-float sk_matrix_t. */
#include <stddef.h>
#include <stdio.h>

typedef struct { float xx, xy, x0, yx, yy, y0, p0, p1, p2; } matrix33;
typedef struct {
    float c0r0, c0r1, c0r2, c0r3;
    float c1r0, c1r1, c1r2, c1r3;
    float c2r0, c2r1, c2r2, c2r3;
    float c3r0, c3r1, c3r2, c3r3;
} matrix44_storage;
_Static_assert(sizeof(float) == 4, "four-byte floats required");
_Static_assert(sizeof(matrix33) == 36, "M33 size");
_Static_assert(offsetof(matrix33, x0) == 8, "M33 x translation");
_Static_assert(offsetof(matrix33, y0) == 20, "M33 y translation");
_Static_assert(offsetof(matrix33, p2) == 32, "M33 perspective word");
_Static_assert(sizeof(matrix44_storage) == 64, "M44 size");
_Static_assert(offsetof(matrix44_storage, c1r0) == 16, "M44 xy word");
_Static_assert(offsetof(matrix44_storage, c3r0) == 48, "M44 x translation");
_Static_assert(offsetof(matrix44_storage, c3r1) == 52, "M44 y translation");
_Static_assert(offsetof(matrix44_storage, c3r3) == 60, "M44 homogeneous word");
int main(void) {
    printf("Path/matrix ABI mirror passed: M33=%zu M44=%zu translation-offsets=%zu,%zu\n",
           sizeof(matrix33), sizeof(matrix44_storage),
           offsetof(matrix44_storage, c3r0), offsetof(matrix44_storage, c3r1));
    return 0;
}
