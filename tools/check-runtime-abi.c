/* Layout mirror only; run native reflection tests as well. Pinned m119 ABI. */
#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

typedef struct {
    const char *name;
    size_t name_length;
    size_t offset;
    int type;
    int count;
    uint32_t flags;
} runtime_uniform;
typedef struct {
    const char *name;
    size_t name_length;
    int type;
    int index;
} runtime_child;
int main(void) {
    const size_t word = sizeof(void *);
    _Static_assert(sizeof(size_t) == sizeof(void *), "word sizes differ");
    _Static_assert(sizeof(int) == 4, "m119 enum/int ABI requires 32 bits");
    assert(sizeof(runtime_uniform) == (word == 8 ? 40 : 24));
    assert(sizeof(runtime_child) == 2 * word + 8);
    assert(offsetof(runtime_uniform, offset) == 2 * word);
    assert(offsetof(runtime_uniform, type) == 3 * word);
    assert(offsetof(runtime_uniform, count) == 3 * word + 4);
    assert(offsetof(runtime_uniform, flags) == 3 * word + 8);
    assert(offsetof(runtime_child, type) == 2 * word);
    assert(offsetof(runtime_child, index) == 2 * word + 4);
    printf("Runtime ABI mirror passed: uniform=%zu child=%zu offset=%zu type=%zu flags=%zu\n",
           sizeof(runtime_uniform), sizeof(runtime_child), offsetof(runtime_uniform, offset),
           offsetof(runtime_uniform, type), offsetof(runtime_uniform, flags));
    return 0;
}
