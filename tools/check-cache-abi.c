/* Local mirrors of pinned m119 cache call scalars/prototypes, not DLL execution. */
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
typedef void (*cache_usage_fn)(void *, int *, size_t *);
typedef void (*cache_limit_fn)(void *, size_t);
typedef void (*cache_age_fn)(void *, long long);
typedef void (*cache_bytes_fn)(void *, size_t, bool);
_Static_assert(sizeof(int) == 4, "Skia cache count is a 32-bit int");
_Static_assert(sizeof(long long) == 8, "Skia cleanup age is int64 milliseconds");
_Static_assert(sizeof(bool) == 1, "Skia boolean ABI");
_Static_assert(sizeof(size_t) == sizeof(void *), "cache byte count is pointer-sized");
static void usage(void *context, int *count, size_t *bytes) {
    (void)context;
    *count = 37;
    *bytes = SIZE_MAX - 1024;
}
int main(void) {
    cache_usage_fn call = usage;
    struct { unsigned char before[8]; int count; unsigned char after[8]; } c;
    memset(&c, 0x5a, sizeof(c));
    size_t bytes = 0;
    call(NULL, &c.count, &bytes);
    assert(c.count == 37 && bytes == SIZE_MAX - 1024);
    for (unsigned i=0; i<8; ++i) assert(c.before[i] == 0x5a && c.after[i] == 0x5a);
    printf("Cache ABI mirror: int=%zu size_t=%zu int64-age=%zu bool=%zu; local prototypes only\n",
           sizeof(int), sizeof(size_t), sizeof(long long), sizeof(bool));
    return 0;
}
