// Independent Metal producer/consumer: this target never includes or links Skia.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <new>
#include <string>
#include <thread>
#include <vector>
#define API extern "C" __attribute__((visibility("default")))
static thread_local std::string last_error;
static int fail(const char* message) { last_error = message; return 0; }
struct Fixture {
    id<MTLDevice> device;
    id<MTLCommandQueue> producer_queue, consumer_queue;
    id<MTLTexture> texture, parent;
    id<MTLBuffer> upload;
    id<MTLCommandBuffer> producer;
    id<MTLSharedEvent> event;
    NSUInteger width = 37, height = 29;
};
static bool wait(id<MTLCommandBuffer> cb) {
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
    while (cb.status == MTLCommandBufferStatusCommitted || cb.status == MTLCommandBufferStatusScheduled) {
        if (std::chrono::steady_clock::now() >= deadline) return fail("fixture GPU timeout");
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    if (cb.status != MTLCommandBufferStatusCompleted) return fail("fixture command did not complete");
    return true;
}
static std::vector<uint8_t> pattern(NSUInteger w, NSUInteger h, NSUInteger pitch, bool straight) {
    std::vector<uint8_t> bytes(pitch*h, 0);
    for (NSUInteger y=0; y<h; ++y) for (NSUInteger x=0; x<w; ++x) {
        if (x == w/2) continue;
        auto* p = bytes.data() + y*pitch + x*4;
        const uint8_t a = (x%7 == 0) ? 128 : 255;
        const uint8_t c = straight ? 255 : a;
        const bool right = x > w/2, bottom = y >= h/2;
        p[0] = ((!right && !bottom) || (right && bottom)) ? c : 0;
        p[1] = right ? c : 0;
        p[2] = (!right && bottom) ? c : 0;
        p[3] = a;
    }
    return bytes;
}
API const char* smi_error() { return last_error.c_str(); }
API void* smi_new(void* raw_device, int variant) {
    @autoreleasepool {
      if (!raw_device) { fail("null fixture device"); return nullptr; }
      auto* f = new(std::nothrow) Fixture;
      if (!f) { fail("fixture allocation failed"); return nullptr; }
      f->device = (__bridge id<MTLDevice>)raw_device;
      f->producer_queue = [f->device newCommandQueue];
      f->consumer_queue = [f->device newCommandQueue];
      MTLTextureDescriptor* d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:
          (variant==3 ? MTLPixelFormatBGRA8Unorm : MTLPixelFormatRGBA8Unorm)
          width:f->width height:f->height mipmapped:NO];
      d.resourceOptions = MTLResourceStorageModePrivate | MTLResourceHazardTrackingModeTracked;
      d.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
      if (variant==2) d.usage = MTLTextureUsageShaderRead;
      if (variant==4) d.mipmapLevelCount = 2;
      if (variant==5) { d.textureType = MTLTextureType2DArray; d.arrayLength = 2; }
      if (variant==6) d.hazardTrackingMode = MTLHazardTrackingModeUntracked;
      // Metal rejects non-identity texture swizzles on RenderTarget textures.
      // Variant 9 exists only to exercise descriptor rejection of a real
      // non-identity swizzle, so keep it ShaderRead-only and let the wrapper
      // reject the swizzle itself instead of triggering a Metal assertion.
      if (variant==9) {
          d.usage = MTLTextureUsageShaderRead;
          d.swizzle = MTLTextureSwizzleChannelsMake(MTLTextureSwizzleBlue,
              MTLTextureSwizzleGreen, MTLTextureSwizzleRed, MTLTextureSwizzleAlpha);
      }
      if (variant==10) d.usage |= MTLTextureUsagePixelFormatView;
      if (variant==12) d.usage |= MTLTextureUsageShaderWrite;
      f->texture = [f->device newTextureWithDescriptor:d];
      if (variant==10 && f->texture) {
          f->parent = f->texture;
          f->texture = [f->parent newTextureViewWithPixelFormat:MTLPixelFormatRGBA8Unorm];
      }
      f->producer = variant==8 ? [f->producer_queue commandBufferWithUnretainedReferences]
                               : [f->producer_queue commandBuffer];
      if (!f->texture || !f->producer || !f->consumer_queue) {
          delete f; fail("Metal producer resources unavailable"); return nullptr;
      }
      const NSUInteger pitch = 256;
      auto bytes = pattern(f->width, f->height, pitch, variant==1);
      f->upload = [f->device newBufferWithBytes:bytes.data() length:bytes.size()
                                      options:MTLResourceStorageModeShared];
      if (!f->upload) { delete f; fail("upload buffer allocation failed"); return nullptr; }
      if (variant==11) {
          f->event = [f->device newSharedEvent];
          if (!f->event) { delete f; fail("shared event unavailable"); return nullptr; }
          [f->producer encodeWaitForEvent:f->event value:1];
      }
      id<MTLBlitCommandEncoder> blit = [f->producer blitCommandEncoder];
      if (!blit) { delete f; fail("producer encoder unavailable"); return nullptr; }
      [blit copyFromBuffer:f->upload sourceOffset:0 sourceBytesPerRow:pitch
            sourceBytesPerImage:pitch*f->height sourceSize:MTLSizeMake(f->width,f->height,1)
            toTexture:f->texture destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
      [blit endEncoding];
      if (variant!=7) [f->producer commit];
      return f;
    }
}
API void* smi_texture(void* p) { return (__bridge void*)static_cast<Fixture*>(p)->texture; }
API void* smi_producer(void* p) { return (__bridge void*)static_cast<Fixture*>(p)->producer; }
API int smi_describe(void* p, uint64_t* out, size_t count) {
    @autoreleasepool {
      if (!p || count!=19) return fail("invalid description destination");
      auto* f=static_cast<Fixture*>(p); id<MTLTexture> t=f->texture;
      auto s=t.swizzle;
      uint64_t a[19] = {t.width,t.height,t.depth,t.mipmapLevelCount,t.arrayLength,t.sampleCount,
          static_cast<uint64_t>(t.pixelFormat),static_cast<uint64_t>(t.textureType),
          static_cast<uint64_t>(t.usage),static_cast<uint64_t>(t.storageMode),
          static_cast<uint64_t>(t.hazardTrackingMode),static_cast<uint64_t>(t.framebufferOnly),
          static_cast<uint64_t>(t.shareable),static_cast<uint64_t>(f->producer.retainedReferences),
          static_cast<uint64_t>(s.red),static_cast<uint64_t>(s.green),
          static_cast<uint64_t>(s.blue),static_cast<uint64_t>(s.alpha),
          static_cast<uint64_t>(f->producer_queue != f->consumer_queue)};
      std::memcpy(out,a,sizeof(a)); return 1;
    }
}
API int smi_read(void* p, uint8_t* output, size_t count) {
    @autoreleasepool {
      if (!p) return fail("null fixture"); auto* f=static_cast<Fixture*>(p);
      if (count!=f->width*f->height*4 || !output) return fail("invalid readback destination");
      id<MTLBuffer> buffer=[f->device newBufferWithLength:256*f->height options:MTLResourceStorageModeShared];
      id<MTLCommandBuffer> cb=[f->consumer_queue commandBuffer];
      if (!buffer || !cb) return fail("consumer allocation failed");
      id<MTLBlitCommandEncoder> blit=[cb blitCommandEncoder];
      if (!blit) return fail("consumer encoder unavailable");
      [blit copyFromTexture:f->texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0)
            sourceSize:MTLSizeMake(f->width,f->height,1) toBuffer:buffer destinationOffset:0
            destinationBytesPerRow:256 destinationBytesPerImage:256*f->height];
      [blit endEncoding]; [cb commit]; if (!wait(cb)) return 0;
      auto* bytes=static_cast<const uint8_t*>(buffer.contents);
      for (NSUInteger y=0;y<f->height;++y) std::memcpy(output+y*f->width*4,bytes+y*256,f->width*4);
      return 1;
    }
}
API int smi_unblock(void* p) {
    @autoreleasepool {
      if (!p) return fail("null fixture"); auto* f=static_cast<Fixture*>(p);
      if (!f->event) return fail("no timeout event");
      f->event.signaledValue=1;
      return wait(f->producer) ? 1 : 0;
    }
}
API int smi_close(void* p) {
    @autoreleasepool {
      if (!p) return 1; auto* f=static_cast<Fixture*>(p);
      const auto s=f->producer.status;
      // Uncommitted test buffers were never submitted. For actual submitted
      // work, never destroy an uncompleted fixture on an error path.
      if (s==MTLCommandBufferStatusCommitted || s==MTLCommandBufferStatusScheduled) {
          if (!wait(f->producer)) return 0;
      }
      delete f; return 1;
    }
}
