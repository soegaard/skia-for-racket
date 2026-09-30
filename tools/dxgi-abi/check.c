#define CINTERFACE
#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <dxgi1_4.h>
#include <d3d12.h>
#include <stddef.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#define SLOT(T,F,N) _Static_assert(offsetof(T,F) == (N)*sizeof(void*), #T "." #F)
_Static_assert(sizeof(void*) == 8, "Win64 only");
_Static_assert(sizeof(DXGI_SWAP_CHAIN_DESC1)==48, "swap desc");
_Static_assert(offsetof(DXGI_SWAP_CHAIN_DESC1, SampleDesc)==16, "sample desc offset");
_Static_assert(offsetof(DXGI_SWAP_CHAIN_DESC1, BufferCount)==28, "buffer count offset");
_Static_assert(offsetof(DXGI_SWAP_CHAIN_DESC1, Flags)==44, "swap flags");
_Static_assert(sizeof(RECT)==16, "RECT");
_Static_assert(sizeof(D3D12_RESOURCE_BARRIER)==32, "barrier");
_Static_assert(offsetof(D3D12_RESOURCE_BARRIER, Transition)==8, "barrier union");
_Static_assert(offsetof(D3D12_RESOURCE_TRANSITION_BARRIER, StateBefore)==12, "transition before");
_Static_assert(offsetof(D3D12_RESOURCE_TRANSITION_BARRIER, StateAfter)==16, "transition after");
_Static_assert(sizeof(D3D12_HEAP_PROPERTIES)==20, "heap props");
_Static_assert(sizeof(D3D12_RESOURCE_DESC)==56, "resource desc");
_Static_assert(offsetof(D3D12_RESOURCE_DESC, Width)==16, "resource width");
_Static_assert(offsetof(D3D12_RESOURCE_DESC, Format)==32, "resource format");
_Static_assert(offsetof(D3D12_RESOURCE_DESC, Layout)==44, "resource layout");
_Static_assert(sizeof(D3D12_TEXTURE_COPY_LOCATION)==48, "copy location");
_Static_assert(offsetof(D3D12_TEXTURE_COPY_LOCATION, PlacedFootprint)==16, "placed offset");
_Static_assert(offsetof(D3D12_PLACED_SUBRESOURCE_FOOTPRINT, Footprint)==8, "footprint offset");
_Static_assert(offsetof(D3D12_SUBRESOURCE_FOOTPRINT, RowPitch)==16, "row pitch offset");
_Static_assert(sizeof(D3D12_RANGE)==16, "readback range");
_Static_assert(D3D12_RESOURCE_STATE_PRESENT==0 && D3D12_RESOURCE_STATE_RENDER_TARGET==4, "target states");
_Static_assert(D3D12_RESOURCE_STATE_COPY_SOURCE==0x800 && D3D12_RESOURCE_STATE_COPY_DEST==0x400, "copy states");
_Static_assert(DXGI_FORMAT_R8G8B8A8_UNORM==28 && DXGI_SWAP_EFFECT_FLIP_DISCARD==4, "swap format/effect");
_Static_assert(DXGI_ALPHA_MODE_IGNORE==3 && DXGI_USAGE_RENDER_TARGET_OUTPUT==0x20, "swap alpha/usage");
_Static_assert(D3D12_TEXTURE_DATA_PITCH_ALIGNMENT==256 && D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT==512, "copy alignment");
SLOT(IDXGIFactory4Vtbl, CreateSwapChainForHwnd, 15);
SLOT(IDXGIFactory4Vtbl, MakeWindowAssociation, 8);
SLOT(IDXGISwapChain3Vtbl, Present, 8);
SLOT(IDXGISwapChain3Vtbl, GetBuffer, 9);
SLOT(IDXGISwapChain3Vtbl, ResizeBuffers, 13);
SLOT(IDXGISwapChain3Vtbl, GetDesc1, 18);
SLOT(IDXGISwapChain3Vtbl, GetCurrentBackBufferIndex, 36);
SLOT(ID3D12DeviceVtbl, CreateCommandAllocator, 9);
SLOT(ID3D12DeviceVtbl, CreateCommandList, 12);
SLOT(ID3D12DeviceVtbl, CreateCommittedResource, 27);
SLOT(ID3D12DeviceVtbl, CreateFence, 36);
SLOT(ID3D12CommandAllocatorVtbl, Reset, 8);
SLOT(ID3D12GraphicsCommandListVtbl, Close, 9);
SLOT(ID3D12GraphicsCommandListVtbl, Reset, 10);
SLOT(ID3D12GraphicsCommandListVtbl, CopyTextureRegion, 16);
SLOT(ID3D12GraphicsCommandListVtbl, ResourceBarrier, 26);
SLOT(ID3D12CommandQueueVtbl, ExecuteCommandLists, 10);
SLOT(ID3D12CommandQueueVtbl, Signal, 14);
SLOT(ID3D12FenceVtbl, GetCompletedValue, 8);
SLOT(ID3D12FenceVtbl, SetEventOnCompletion, 9);
SLOT(ID3D12ResourceVtbl, Map, 8);
SLOT(ID3D12ResourceVtbl, Unmap, 9);
/* Pinned m119 C shim POD, not a C++ GrD3DTextureResourceInfo. */
typedef struct { void *resource, *allocation; uint32_t state, format, samples, levels, quality; bool protected_; } texture_info;
_Static_assert(sizeof(texture_info)==40 && offsetof(texture_info, protected_)==36, "Skia C POD");
extern int validate_dxgi_guids(void);
int main(void) {
  if (!validate_dxgi_guids()) { fputs("DXGI GUID mismatch\n", stderr); return 1; }
  puts("{\"kind\":\"windows-sdk\",\"status\":\"passed\",\"slots_verified\":22,\"guids_verified\":5,\"sizes\":{\"swap_desc\":48,\"rect\":16,\"texture_info\":40,\"transition\":32,\"heap_properties\":20,\"resource_desc\":56,\"copy_location\":48,\"range\":16}}");
  return 0;
}
