// Independent D3D12 producer AND consumer. No Skia headers, Skia handles,
// Racket callbacks or calls into the implementation under test.
#include <windows.h>
#include <d3d12.h>
#include <dxgi1_4.h>
#include <wrl/client.h>
#include <cstdint>
#include <cstring>
#include <new>
#include <vector>
#include <atomic>
using Microsoft::WRL::ComPtr;
#define EXPORT extern "C" __declspec(dllexport)
struct Failure { HRESULT code; };
static void check(HRESULT h) { if(FAILED(h)) throw Failure{h}; }
static void wait(ID3D12Device* d, ID3D12Fence* f, uint64_t v) {
  const ULONGLONG until=GetTickCount64()+5000;
  for(;;) {
    check(d->GetDeviceRemovedReason());
    uint64_t done=f->GetCompletedValue();
    if(done==UINT64_MAX) throw Failure{DXGI_ERROR_DEVICE_REMOVED};
    if(done>=v) return;
    if(GetTickCount64()>=until) throw Failure{HRESULT_FROM_WIN32(WAIT_TIMEOUT)};
    Sleep(1);
  }
}
static D3D12_HEAP_PROPERTIES heap(D3D12_HEAP_TYPE type) {
  D3D12_HEAP_PROPERTIES p={};p.Type=type;p.CreationNodeMask=p.VisibleNodeMask=1;return p;
}
static D3D12_RESOURCE_DESC buffer_desc(uint64_t bytes) {
  D3D12_RESOURCE_DESC d={};d.Dimension=D3D12_RESOURCE_DIMENSION_BUFFER;d.Width=bytes;
  d.Height=1;d.DepthOrArraySize=1;d.MipLevels=1;d.SampleDesc.Count=1;d.Layout=D3D12_TEXTURE_LAYOUT_ROW_MAJOR;return d;
}
static void transition(ID3D12GraphicsCommandList* l,ID3D12Resource* r,D3D12_RESOURCE_STATES a,D3D12_RESOURCE_STATES b) {
  if(a==b) return;
  D3D12_RESOURCE_BARRIER x={};x.Type=D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
  x.Transition.pResource=r;x.Transition.Subresource=D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
  x.Transition.StateBefore=a;x.Transition.StateAfter=b;l->ResourceBarrier(1,&x);
}
struct Fixture {
  ComPtr<ID3D12Device> device;
  ComPtr<ID3D12CommandQueue> producer,consumer;
  ComPtr<ID3D12CommandAllocator> allocator;
  ComPtr<ID3D12GraphicsCommandList> list;
  ComPtr<ID3D12Resource> texture,upload;
  ComPtr<ID3D12Fence> fence;
  uint32_t width=0,height=0;bool submitted=false;
};
static std::vector<Fixture*> quarantines;
static HRESULT close_fixture(Fixture* f) {
  if(!f) return S_OK;
  try { if(f->submitted) wait(f->device.Get(),f->fence.Get(),1); delete f;return S_OK; }
  catch(Failure e) {quarantines.push_back(f);return e.code;}
}
EXPORT uint32_t interop_fixture_kind() { return 1; }
EXPORT HRESULT interop_fixture_create(ID3D12Device* device,uint32_t w,uint32_t h,uint32_t kind,void** out) {
  if(!out) return E_POINTER;*out=nullptr;
  if(!device || !w || !h || w>1024 || h>1024 || kind>6) return E_INVALIDARG;
  Fixture* f=nullptr;
  try {
    f=new Fixture;f->device=device;f->width=w;f->height=h;
    D3D12_COMMAND_QUEUE_DESC q={};q.Type=D3D12_COMMAND_LIST_TYPE_DIRECT;
    check(device->CreateCommandQueue(&q,IID_PPV_ARGS(&f->producer)));
    check(device->CreateCommandQueue(&q,IID_PPV_ARGS(&f->consumer)));
    check(device->CreateFence(0,D3D12_FENCE_FLAG_NONE,IID_PPV_ARGS(&f->fence)));
    D3D12_RESOURCE_DESC d={};d.Dimension=D3D12_RESOURCE_DIMENSION_TEXTURE2D;
    d.Width=w;d.Height=h;d.DepthOrArraySize=kind==3?2:1;d.MipLevels=kind==2?2:1;
    d.Format=kind==4?DXGI_FORMAT_B8G8R8A8_UNORM:DXGI_FORMAT_R8G8B8A8_UNORM;
    d.SampleDesc.Count=1;d.Layout=D3D12_TEXTURE_LAYOUT_UNKNOWN;
    d.Flags=kind==1?D3D12_RESOURCE_FLAG_NONE:D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;
    auto def=heap(D3D12_HEAP_TYPE_DEFAULT);
    check(device->CreateCommittedResource(&def,D3D12_HEAP_FLAG_NONE,&d,D3D12_RESOURCE_STATE_COPY_DEST,nullptr,IID_PPV_ARGS(&f->texture)));
    const uint32_t pitch=(w*4+255)&~255u;
    auto udesc=buffer_desc(uint64_t(pitch)*h);auto up=heap(D3D12_HEAP_TYPE_UPLOAD);
    check(device->CreateCommittedResource(&up,D3D12_HEAP_FLAG_NONE,&udesc,D3D12_RESOURCE_STATE_GENERIC_READ,nullptr,IID_PPV_ARGS(&f->upload)));
    uint8_t* dst=nullptr;D3D12_RANGE empty={0,0};check(f->upload->Map(0,&empty,reinterpret_cast<void**>(&dst)));
    std::memset(dst,0,size_t(pitch)*h);
    for(uint32_t y=0;y<h;++y) for(uint32_t x=0;x<w;++x) {
      auto p=dst+y*pitch+x*4;
      if(x%7) {
        if(kind==5||kind==6) {p[0]=kind==5?128:255;p[1]=p[2]=0;p[3]=128;}
        else {p[0]=(x*17+y*3)%256;p[1]=((x^y)*13)%256;p[2]=(x*5+y*11)%256;p[3]=255;}
      }
    }
    f->upload->Unmap(0,nullptr);
    check(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,IID_PPV_ARGS(&f->allocator)));
    check(device->CreateCommandList(0,D3D12_COMMAND_LIST_TYPE_DIRECT,f->allocator.Get(),nullptr,IID_PPV_ARGS(&f->list)));
    D3D12_TEXTURE_COPY_LOCATION a={},b={};a.pResource=f->texture.Get();a.Type=D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    b.pResource=f->upload.Get();b.Type=D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
    b.PlacedFootprint.Footprint.Format=d.Format;b.PlacedFootprint.Footprint.Width=w;
    b.PlacedFootprint.Footprint.Height=h;b.PlacedFootprint.Footprint.Depth=1;b.PlacedFootprint.Footprint.RowPitch=pitch;
    f->list->CopyTextureRegion(&a,0,0,0,&b,nullptr);
    transition(f->list.Get(),f->texture.Get(),D3D12_RESOURCE_STATE_COPY_DEST,D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE);
    check(f->list->Close());ID3D12CommandList* lists[]={f->list.Get()};
    f->submitted=true;f->producer->ExecuteCommandLists(1,lists);check(f->producer->Signal(f->fence.Get(),1));
    *out=f;return S_OK;
  } catch(Failure e) { if(f) {if(f->submitted) quarantines.push_back(f);else delete f;}return e.code; }
    catch(...) {if(f) {if(f->submitted) quarantines.push_back(f);else delete f;}return E_FAIL;}
}
EXPORT ID3D12Resource* interop_fixture_texture(void* p) {return p?static_cast<Fixture*>(p)->texture.Get():nullptr;}
EXPORT ID3D12Fence* interop_fixture_fence(void* p) {return p?static_cast<Fixture*>(p)->fence.Get():nullptr;}
EXPORT HRESULT interop_fixture_drop_texture(void* p) {
  if(!p) return E_POINTER;static_cast<Fixture*>(p)->texture.Reset();return S_OK;
}
EXPORT HRESULT interop_fixture_close(void* p) {return close_fixture(static_cast<Fixture*>(p));}
EXPORT HRESULT interop_fixture_descriptor(void* p,uint64_t* out,size_t n) {
  if(!p||!out||n!=9) return E_INVALIDARG;
  auto f=static_cast<Fixture*>(p);if(!f->texture) return E_POINTER;
  const auto d=f->texture->GetDesc();
  const uint64_t values[]={d.Dimension,d.Width,d.Height,d.DepthOrArraySize,d.MipLevels,d.Format,d.SampleDesc.Count,d.SampleDesc.Quality,d.Flags};
  std::memcpy(out,values,sizeof(values));return S_OK;
}
EXPORT HRESULT interop_fixture_unsignaled_fence(void* p,void** out) {
  if(!p||!out) return E_INVALIDARG;*out=nullptr;
  return static_cast<Fixture*>(p)->device->CreateFence(0,D3D12_FENCE_FLAG_NONE,__uuidof(ID3D12Fence),out);
}
EXPORT void interop_fixture_release(IUnknown* p) {if(p) p->Release();}
EXPORT HRESULT interop_fixture_readback(void* p,uint32_t declaredState,uint8_t* bytes,size_t capacity) {
  if(!p||!bytes) return E_INVALIDARG;auto f=static_cast<Fixture*>(p);
  if(!f->texture||capacity!=size_t(f->width)*f->height*4) return E_INVALIDARG;
  // Keep all command dependencies in one heap object on a failed completion.
  struct Read {
    ComPtr<ID3D12CommandAllocator>a;ComPtr<ID3D12GraphicsCommandList>l;
    ComPtr<ID3D12Resource>r,source;ComPtr<ID3D12Fence>f;
    ComPtr<ID3D12Device>device;ComPtr<ID3D12CommandQueue>queue;
  };
  Read* r=new(std::nothrow) Read;if(!r) return E_OUTOFMEMORY;bool issued=false;
  try {
    r->source=f->texture;r->device=f->device;r->queue=f->consumer;
    check(f->consumer->Wait(f->fence.Get(),1));
    const uint32_t pitch=(f->width*4+255)&~255u;auto desc=buffer_desc(uint64_t(pitch)*f->height);auto hp=heap(D3D12_HEAP_TYPE_READBACK);
    check(f->device->CreateCommittedResource(&hp,D3D12_HEAP_FLAG_NONE,&desc,D3D12_RESOURCE_STATE_COPY_DEST,nullptr,IID_PPV_ARGS(&r->r)));
    check(f->device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,IID_PPV_ARGS(&r->a)));
    check(f->device->CreateCommandList(0,D3D12_COMMAND_LIST_TYPE_DIRECT,r->a.Get(),nullptr,IID_PPV_ARGS(&r->l)));
    check(f->device->CreateFence(0,D3D12_FENCE_FLAG_NONE,IID_PPV_ARGS(&r->f)));
    transition(r->l.Get(),f->texture.Get(),D3D12_RESOURCE_STATES(declaredState),D3D12_RESOURCE_STATE_COPY_SOURCE);
    D3D12_TEXTURE_COPY_LOCATION a={},b={};a.pResource=r->r.Get();a.Type=D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
    a.PlacedFootprint.Footprint.Format=DXGI_FORMAT_R8G8B8A8_UNORM;a.PlacedFootprint.Footprint.Width=f->width;
    a.PlacedFootprint.Footprint.Height=f->height;a.PlacedFootprint.Footprint.Depth=1;a.PlacedFootprint.Footprint.RowPitch=pitch;
    b.pResource=f->texture.Get();b.Type=D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;r->l->CopyTextureRegion(&a,0,0,0,&b,nullptr);
    transition(r->l.Get(),f->texture.Get(),D3D12_RESOURCE_STATE_COPY_SOURCE,D3D12_RESOURCE_STATES(declaredState));
    check(r->l->Close());ID3D12CommandList* lists[]={r->l.Get()};issued=true;f->consumer->ExecuteCommandLists(1,lists);
    check(f->consumer->Signal(r->f.Get(),1));wait(f->device.Get(),r->f.Get(),1);issued=false;
    void* ptr=nullptr;D3D12_RANGE all={0,size_t(pitch)*f->height};check(r->r->Map(0,&all,&ptr));
    for(uint32_t y=0;y<f->height;++y) std::memcpy(bytes+size_t(y)*f->width*4,static_cast<uint8_t*>(ptr)+size_t(y)*pitch,size_t(f->width)*4);
    D3D12_RANGE none={0,0};r->r->Unmap(0,&none);delete r;return S_OK;
  } catch(Failure e) {if(!issued)delete r;return e.code;}catch(...) {if(!issued)delete r;return E_FAIL;}
}
// Deliberately foreign canonical IUnknown identity. This is an SDK COM test
// double, not a second hardware adapter. No method on it submits GPU work.
static std::atomic<unsigned> foreignRefs{0},foreignDescCalls{0};
class Identity final:public IUnknown {
  std::atomic<ULONG> n{1};
public:
  Identity(){++foreignRefs;}
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id,void** p) override {if(!p)return E_POINTER;*p=nullptr;if(id==__uuidof(IUnknown)||id==__uuidof(ID3D12Device)){*p=this;AddRef();return S_OK;}return E_NOINTERFACE;}
  ULONG STDMETHODCALLTYPE AddRef() override{return ++n;}
  ULONG STDMETHODCALLTYPE Release() override{auto v=--n;if(!v){--foreignRefs;delete this;}return v;}
};
class ForeignResource final:public ID3D12Resource {
  std::atomic<ULONG> n{1};Identity* identity=new Identity;
public:
  ForeignResource(){++foreignRefs;}
  ~ForeignResource(){identity->Release();--foreignRefs;}
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id,void** p) override{if(!p)return E_POINTER;*p=nullptr;if(id==__uuidof(IUnknown)||id==__uuidof(ID3D12Resource)){*p=this;AddRef();return S_OK;}return E_NOINTERFACE;}
  ULONG STDMETHODCALLTYPE AddRef() override{return ++n;}
  ULONG STDMETHODCALLTYPE Release() override{auto v=--n;if(!v)delete this;return v;}
  HRESULT STDMETHODCALLTYPE GetPrivateData(REFGUID,UINT*,void*) override{return E_NOTIMPL;}
  HRESULT STDMETHODCALLTYPE SetPrivateData(REFGUID,UINT,const void*) override{return E_NOTIMPL;}
  HRESULT STDMETHODCALLTYPE SetPrivateDataInterface(REFGUID,const IUnknown*) override{return E_NOTIMPL;}
  HRESULT STDMETHODCALLTYPE SetName(LPCWSTR) override{return S_OK;}
  HRESULT STDMETHODCALLTYPE GetDevice(REFIID id,void** out) override{return identity->QueryInterface(id,out);}
  HRESULT STDMETHODCALLTYPE Map(UINT,const D3D12_RANGE*,void**) override{return E_NOTIMPL;}
  void STDMETHODCALLTYPE Unmap(UINT,const D3D12_RANGE*) override{}
  D3D12_RESOURCE_DESC STDMETHODCALLTYPE GetDesc() override{++foreignDescCalls;return {};}
  D3D12_GPU_VIRTUAL_ADDRESS STDMETHODCALLTYPE GetGPUVirtualAddress() override{return 0;}
  HRESULT STDMETHODCALLTYPE WriteToSubresource(UINT,const D3D12_BOX*,const void*,UINT,UINT) override{return E_NOTIMPL;}
  HRESULT STDMETHODCALLTYPE ReadFromSubresource(void*,UINT,UINT,UINT,const D3D12_BOX*) override{return E_NOTIMPL;}
  HRESULT STDMETHODCALLTYPE GetHeapProperties(D3D12_HEAP_PROPERTIES*,D3D12_HEAP_FLAGS*) override{return E_NOTIMPL;}
};
EXPORT ID3D12Resource* interop_fixture_foreign_resource(){try {return new ForeignResource;} catch(...) {return nullptr;}}
EXPORT unsigned interop_fixture_foreign_live(){return foreignRefs.load();}
EXPORT unsigned interop_fixture_foreign_desc_calls(){return foreignDescCalls.load();}
