/* Layout/slot evidence only. Runtime COM aggregate-return calls are checked
   separately by comparing the Racket call with fixture.cpp's C++ GetDesc. */
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#if defined(_WIN32)
#define CINTERFACE
#define COBJMACROS
#include <windows.h>
#include <d3d12.h>
#define SLOT(t,m,n) _Static_assert(offsetof(t,m)==sizeof(void*)*(n), #t "." #m)
SLOT(ID3D12ResourceVtbl, GetDevice, 7);
SLOT(ID3D12ResourceVtbl, GetDesc, 10);
SLOT(ID3D12ResourceVtbl, GetHeapProperties, 14);
SLOT(ID3D12FenceVtbl, GetDevice, 7);
SLOT(ID3D12CommandQueueVtbl, Wait, 15);
SLOT(ID3D12GraphicsCommandListVtbl, CopyResource, 17);
_Static_assert(sizeof(D3D12_RESOURCE_DESC)==56,"resource descriptor");
_Static_assert(offsetof(D3D12_RESOURCE_DESC,Width)==16,"width");
_Static_assert(offsetof(D3D12_RESOURCE_DESC,Flags)==48,"flags");
_Static_assert(sizeof(D3D12_RESOURCE_BARRIER)==32,"barrier");
_Static_assert(D3D12_RESOURCE_DIMENSION_TEXTURE2D==3,"2D");
_Static_assert(DXGI_FORMAT_R8G8B8A8_UNORM==28,"RGBA");
_Static_assert(D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE==0x80,"shader state");
_Static_assert(D3D12_RESOURCE_STATE_COPY_SOURCE==0x800,"copy source");
_Static_assert(D3D12_RESOURCE_STATE_COPY_DEST==0x400,"copy dest");
_Static_assert(D3D12_HEAP_FLAG_DENY_BUFFERS==4,"deny buffers");
_Static_assert(D3D12_HEAP_FLAG_DENY_RT_DS_TEXTURES==0x40,"deny rt");
_Static_assert(D3D12_HEAP_FLAG_DENY_NON_RT_DS_TEXTURES==0x80,"deny other");
int main(void) { puts("{\"kind\":\"windows-sdk\",\"status\":\"passed\",\"slots\":6,\"resource_desc_bytes\":56}");return 0; }
#else
struct resource_desc {int32_t dim; uint64_t alignment,width; uint32_t height; uint16_t depth,levels; int32_t format; uint32_t samples,quality; int32_t layout; uint32_t flags;};
_Static_assert(sizeof(void*)==8,"64-bit host mirror");
_Static_assert(sizeof(struct resource_desc)==56,"host descriptor mirror");
_Static_assert(offsetof(struct resource_desc,width)==16,"host width offset");
_Static_assert(offsetof(struct resource_desc,flags)==48,"host flags offset");
int main(void) { puts("{\"kind\":\"host-mirror\",\"windows_execution_verified\":false}");return 0; }
#endif
