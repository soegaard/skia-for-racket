/* Geometry/BOOL ABI used by the private 64-bit Cocoa layer adapter.
 * macOS checks actual SDK declarations; elsewhere this is a local mirror only.
 * No Skia/Cocoa rendering or Objective-C message is executed here. */
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#if defined(__APPLE__)
#include <CoreGraphics/CGGeometry.h>
#include <objc/objc.h>
_Static_assert(sizeof(CGFloat) == 8, "64-bit CGFloat");
_Static_assert(sizeof(CGSize) == 16, "CGSize");
_Static_assert(sizeof(CGRect) == 32, "CGRect");
_Static_assert(offsetof(CGRect, size) == 16, "CGRect nested size");
_Static_assert(offsetof(CGSize, height) == 8, "CGSize height");
_Static_assert(sizeof(BOOL) == 1, "Objective-C BOOL");
#define EVIDENCE "macOS SDK geometry/BOOL declarations"
#else
struct size_mirror { double width, height; };
struct rect_mirror { double x, y, width, height; };
_Static_assert(sizeof(struct size_mirror) == 16, "local CGSize mirror");
_Static_assert(sizeof(struct rect_mirror) == 32, "local CGRect mirror");
_Static_assert(offsetof(struct rect_mirror, width) == 16, "local CGRect size offset");
#define EVIDENCE "local mirrors only (macOS SDK NOT checked)"
#endif
int main(void) {
    printf("Presentation ABI: pointer=%zu; CGSize=16 CGRect=32; %s\n", sizeof(void*), EVIDENCE);
    return 0;
}
