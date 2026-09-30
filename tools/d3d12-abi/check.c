/* Layout mirror plus actual SDK/vtable assertions on Windows. Not a GPU test. */
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdio.h>
typedef struct { void *adapter, *device, *queue, *allocator; bool protected_context; } context;
_Static_assert(sizeof(void *) == 8, "D3D12 wrapper requires x64");
_Static_assert(sizeof(context) == 40, "by-value context size");
_Static_assert(offsetof(context, protected_context) == 32, "trailing bool offset");
#ifdef _WIN32
#define CINTERFACE
#define COBJMACROS
#include <windows.h>
#include <dxgi1_4.h>
#include <d3d12.h>
#define SLOT(t, member, n) _Static_assert(offsetof(t, member) == (n) * sizeof(void *), "wrong vtable slot: " #member)
SLOT(IDXGIFactory4Vtbl, EnumWarpAdapter, 27);
SLOT(IDXGIFactory4Vtbl, EnumAdapters1, 12);
SLOT(IDXGIAdapter1Vtbl, GetDesc1, 10);
SLOT(ID3D12DeviceVtbl, CreateCommandQueue, 8);
SLOT(ID3D12DeviceVtbl, GetDeviceRemovedReason, 37);
SLOT(ID3D12CommandQueueVtbl, Release, 2);
_Static_assert(sizeof(DXGI_ADAPTER_DESC1) == 312, "adapter descriptor size");
_Static_assert(offsetof(DXGI_ADAPTER_DESC1, VendorId) == 256, "vendor offset");
_Static_assert(offsetof(DXGI_ADAPTER_DESC1, AdapterLuid) == 296, "LUID offset");
_Static_assert(offsetof(DXGI_ADAPTER_DESC1, Flags) == 304, "flags offset");
_Static_assert(sizeof(D3D12_COMMAND_QUEUE_DESC) == 16, "queue descriptor size");
_Static_assert(DXGI_ADAPTER_FLAG_SOFTWARE == 2, "software adapter flag");
_Static_assert(D3D_FEATURE_LEVEL_11_0 == 0xb000, "minimum feature level");
_Static_assert(D3D12_COMMAND_LIST_TYPE_DIRECT == 0, "direct queue enum");
extern int check_d3d12_guids(void);
#endif
int main(void) {
#ifdef _WIN32
  if (!check_d3d12_guids()) return 1;
  puts("D3D12 Windows SDK layouts, GUIDs and vtable slots verified (not rendering).");
#else
  puts("D3D12 host-C by-value layout mirror verified; Windows SDK checks NOT RUN.");
#endif
  return 0;
}
