/* Host-C mirror of the additional m119 filter argument structures.
 * Does not load Skia or replace the Racket/native regression tests. */
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
struct sk_isize { int32_t width, height; };
struct sk_ipoint { int32_t x, y; };
struct sk_point3 { float x, y, z; };
_Static_assert(sizeof(int32_t) == 4 && sizeof(float) == 4, "32-bit scalars required");
_Static_assert(sizeof(struct sk_isize) == 8, "sk_isize size");
_Static_assert(sizeof(struct sk_ipoint) == 8, "sk_ipoint size");
_Static_assert(sizeof(struct sk_point3) == 12, "sk_point3 size");
_Static_assert(offsetof(struct sk_isize, height) == 4, "height offset");
_Static_assert(offsetof(struct sk_ipoint, y) == 4, "offset y");
_Static_assert(offsetof(struct sk_point3, y) == 4, "point3 y");
_Static_assert(offsetof(struct sk_point3, z) == 8, "point3 z");
int main(void) {
    puts("Filter ABI mirror passed: isize=8 ipoint=8 point3=12");
    return 0;
}
