/* Host-C mirrors only. Not Windows SDK or actual DXGI/Skia validation. */
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdio.h>
typedef struct { uint32_t w,h; int32_t fmt,stereo; uint32_t samples,quality,usage,count; int32_t scaling,effect,alpha; uint32_t flags; } swap_desc;
typedef struct { int32_t type,flags; void *p; uint32_t sub,before,after; } transition;
typedef struct { int32_t dim; uint64_t alignment,width; uint32_t height; uint16_t depth,levels; int32_t fmt; uint32_t samples,quality; int32_t layout; uint32_t flags; } resource_desc;
typedef struct { void *p; int32_t type; uint32_t padding; uint64_t offset; int32_t fmt; uint32_t w,h,depth,pitch,tail; } copy_location;
typedef struct { void *p,*allocation; uint32_t state,fmt,samples,levels,quality; bool protected_; } texture_info;
_Static_assert(sizeof(void*)==8, "64-bit host");
_Static_assert(sizeof(swap_desc)==48, "swap desc");
_Static_assert(sizeof(transition)==32 && offsetof(transition,after)==24, "transition");
_Static_assert(sizeof(resource_desc)==56 && offsetof(resource_desc,layout)==44, "resource desc");
_Static_assert(sizeof(copy_location)==48 && offsetof(copy_location,pitch)==40, "copy location");
_Static_assert(sizeof(texture_info)==40 && offsetof(texture_info,protected_)==36, "Skia C POD");
int main(void) { puts("DXGI host-C mirrors passed; Windows SDK and GPU execution NOT RUN"); return 0; }
