/* C layout mirror only: no Skia library, no Racket FFI execution. */
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
typedef struct { float g,a,b,c,d,e,f; } transfer_fn;
typedef struct { float vals[3][3]; } xyz_d50;
typedef struct { float rx,ry,gx,gy,bx,by,wx,wy; } primaries;
typedef struct { int filters,level; void *comments,*icc,*description; } png_options;
typedef struct { int quality,downsample,alpha; void *xmp,*icc,*description; } jpeg_options;
typedef struct { int compression; float quality; void *icc,*description; } webp_options;
_Static_assert(sizeof(float)==4, "binary32 ABI required");
_Static_assert(sizeof(transfer_fn)==28, "transfer size");
_Static_assert(sizeof(xyz_d50)==36, "gamut size");
_Static_assert(sizeof(primaries)==32, "primaries size");
_Static_assert(offsetof(transfer_fn,e)==20, "nonlinear additive coefficient");
_Static_assert(offsetof(primaries,wx)==24, "white-point position");
int main(void) {
  if (sizeof(void*)==8) {
    if (sizeof(png_options)!=32 || sizeof(jpeg_options)!=40 || sizeof(webp_options)!=24 ||
        offsetof(png_options,icc)!=16 || offsetof(jpeg_options,icc)!=24 || offsetof(webp_options,icc)!=8)
      return 1;
  }
  printf("Color-output ABI mirror passed: transfer=%zu XYZ=%zu primaries=%zu ICC offsets=%zu,%zu,%zu\n",
         sizeof(transfer_fn),sizeof(xyz_d50),sizeof(primaries),
         offsetof(png_options,icc),offsetof(jpeg_options,icc),offsetof(webp_options,icc));
  return 0;
}
