/* m119 GPU C-ABI inventory. No Skia library or GL context is loaded.
 * Define SKIA_C_TYPES_HEADER to a quoted pinned include/c/sk_types.h path
 * (and add the source-root include directory) to check the actual C header.
 * Without it, these are independent local mirrors, not an upstream build. */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#ifdef SKIA_C_TYPES_HEADER
#include SKIA_C_TYPES_HEADER
#else
typedef enum { OPENGL_GR_BACKEND=0, VULKAN_GR_BACKEND=1, METAL_GR_BACKEND=2,
               DIRECT3D_GR_BACKEND=3, UNSUPPORTED_GR_BACKEND=5 } gr_backend_t;
typedef enum { TOP_LEFT_GR_SURFACE_ORIGIN=0, BOTTOM_LEFT_GR_SURFACE_ORIGIN=1 } gr_surfaceorigin_t;
typedef struct { unsigned int fTarget, fID, fFormat; bool fProtected; } gr_gl_textureinfo_t;
typedef struct { unsigned int fFBOID, fFormat; bool fProtected; } gr_gl_framebufferinfo_t;
typedef struct { const void *fTexture; } gr_mtl_textureinfo_t;
typedef struct { void *colorspace; int32_t width, height; int colorType, alphaType; } sk_imageinfo_t;
#endif
#define CHECK(e) _Static_assert((e), #e)
CHECK(sizeof(bool)==1);
CHECK(sizeof(unsigned int)==4);
CHECK(sizeof(gr_backend_t)==4);
CHECK(OPENGL_GR_BACKEND==0 && METAL_GR_BACKEND==2);
CHECK(TOP_LEFT_GR_SURFACE_ORIGIN==0 && BOTTOM_LEFT_GR_SURFACE_ORIGIN==1);
CHECK(sizeof(gr_gl_framebufferinfo_t)==12);
CHECK(offsetof(gr_gl_framebufferinfo_t,fFBOID)==0);
CHECK(offsetof(gr_gl_framebufferinfo_t,fFormat)==4);
CHECK(offsetof(gr_gl_framebufferinfo_t,fProtected)==8);
CHECK(sizeof(gr_gl_textureinfo_t)==16);
CHECK(offsetof(gr_gl_textureinfo_t,fTarget)==0);
CHECK(offsetof(gr_gl_textureinfo_t,fID)==4);
CHECK(offsetof(gr_gl_textureinfo_t,fFormat)==8);
CHECK(offsetof(gr_gl_textureinfo_t,fProtected)==12);
CHECK(sizeof(gr_mtl_textureinfo_t)==sizeof(void*));
CHECK(offsetof(gr_mtl_textureinfo_t,fTexture)==0);
CHECK(offsetof(sk_imageinfo_t,width)==sizeof(void*));
CHECK(offsetof(sk_imageinfo_t,alphaType)==sizeof(void*)+12);
CHECK(sizeof(sk_imageinfo_t)==sizeof(void*)+16);
int main(void) {
    printf("GPU ABI: pointer=%zu framebuffer=%zu texture=%zu metal-texture=%zu image-info=%zu; ",
           sizeof(void*),sizeof(gr_gl_framebufferinfo_t),sizeof(gr_gl_textureinfo_t),
           sizeof(gr_mtl_textureinfo_t),sizeof(sk_imageinfo_t));
#ifdef SKIA_C_TYPES_HEADER
    puts("checked supplied upstream header");
#else
    puts("local pinned mirrors only");
#endif
    return 0;
}
