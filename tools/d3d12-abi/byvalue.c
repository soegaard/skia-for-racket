#include <stdint.h>
#include <stdbool.h>
typedef struct { void *adapter, *device, *queue, *allocator; bool protected_context; } context;
#ifdef _WIN32
#define API __declspec(dllexport)
#else
#define API __attribute__((visibility("default")))
#endif
/* Fixture only: sentinel pointers are compared, never dereferenced. */
API uint64_t d3d12_abi_echo(context c) {
  return ((uintptr_t)c.adapter == 0x1110 ? 1u : 0u) |
         ((uintptr_t)c.device == 0x2220 ? 2u : 0u) |
         ((uintptr_t)c.queue == 0x3330 ? 4u : 0u) |
         (c.allocator == 0 ? 8u : 0u) | (c.protected_context ? 16u : 0u);
}
