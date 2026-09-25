/* Host-C mirror of mono/skia 40f75dc0051d141913c07c20d4c19590c7da0cb7
 * include/c/sk_types.h. This verifies the declared ABI, not a loaded library.
 * cc -std=c11 -Wall -Wextra -pedantic tools/check-codec-abi.c -o /tmp/skia-codec-abi
 */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

typedef struct { int32_t left, top, right, bottom; } rect;
typedef struct { int zero; rect *subset; int frame, prior; } codec_options;
typedef struct {
  int required, duration;
  bool received;
  int alpha;
  bool has_alpha;
  int disposal, blend;
  rect bounds;
} frame_info;

_Static_assert(sizeof(int) == 4, "requires 32-bit C int");
_Static_assert(sizeof(bool) == 1, "requires one-byte C bool");
_Static_assert(sizeof(frame_info) == 44, "frame_info size");
_Static_assert(_Alignof(frame_info) == 4, "frame_info alignment");
_Static_assert(offsetof(frame_info, required) == 0, "required offset");
_Static_assert(offsetof(frame_info, duration) == 4, "duration offset");
_Static_assert(offsetof(frame_info, received) == 8, "received offset");
_Static_assert(offsetof(frame_info, alpha) == 12, "alpha offset");
_Static_assert(offsetof(frame_info, has_alpha) == 16, "has_alpha offset");
_Static_assert(offsetof(frame_info, disposal) == 20, "disposal offset");
_Static_assert(offsetof(frame_info, blend) == 24, "blend offset");
_Static_assert(offsetof(frame_info, bounds) == 28, "bounds offset");
_Static_assert(sizeof(codec_options) == (sizeof(void*) == 8 ? 24 : 16), "options size");
_Static_assert(offsetof(codec_options, zero) == 0, "zero offset");
_Static_assert(offsetof(codec_options, subset) == (sizeof(void*) == 8 ? 8 : 4), "subset offset");
_Static_assert(offsetof(codec_options, frame) == (sizeof(void*) == 8 ? 16 : 8), "frame offset");
_Static_assert(offsetof(codec_options, prior) == (sizeof(void*) == 8 ? 20 : 12), "prior offset");
int main(void) {
  printf("Codec ABI mirror passed: options=%zu frame-info=%zu pointer=%zu\n",
         sizeof(codec_options), sizeof(frame_info), sizeof(void*));
  return 0;
}
