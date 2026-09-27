/* Pinned SkM44 storage mirror: host C only, not a linked Skia test. */
#include <stddef.h>
#include <stdio.h>

typedef struct {
    float c0r0, c0r1, c0r2, c0r3;
    float c1r0, c1r1, c1r2, c1r3;
    float c2r0, c2r1, c2r2, c2r3;
    float c3r0, c3r1, c3r2, c3r3;
} matrix44_storage;
_Static_assert(sizeof(float) == 4, "binary32 ABI required");
_Static_assert(sizeof(matrix44_storage) == 64, "SkM44 size");
_Static_assert(offsetof(matrix44_storage, c0r3) == 12, "W from X");
_Static_assert(offsetof(matrix44_storage, c1r3) == 28, "W from Y");
_Static_assert(offsetof(matrix44_storage, c2r3) == 44, "W from Z");
_Static_assert(offsetof(matrix44_storage, c3r2) == 56, "Z translation");
_Static_assert(offsetof(matrix44_storage, c3r3) == 60, "W constant");
int main(void) {
    const float row_major[16] = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16};
    float columns[16];
    for (int c = 0; c < 4; ++c)
        for (int r = 0; r < 4; ++r)
            columns[c*4+r] = row_major[r*4+c];
    if (columns[3] != 13 || columns[7] != 14 || columns[11] != 15 ||
        columns[12] != 4 || columns[13] != 8 || columns[14] != 12) return 1;
    puts("Projective ABI mirror passed: M44=64; W offsets=12,28,44,60; Z translation=56");
    return 0;
}
