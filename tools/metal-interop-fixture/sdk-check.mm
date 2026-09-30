#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <cstddef>
#include <cstdio>
#include <type_traits>
static_assert(sizeof(void*) == 8 && sizeof(NSUInteger) == 8 && sizeof(BOOL) == 1);
static_assert(sizeof(MTLTextureSwizzleChannels) == 4);
static_assert(offsetof(MTLTextureSwizzleChannels, red) == 0);
static_assert(offsetof(MTLTextureSwizzleChannels, alpha) == 3);
static_assert(MTLTextureType2D == 2 && MTLPixelFormatRGBA8Unorm == 70);
static_assert(MTLStorageModeShared == 0 && MTLStorageModePrivate == 2);
static_assert(MTLHazardTrackingModeTracked == 2);
static_assert(MTLTextureUsageShaderRead == 1 && MTLTextureUsageRenderTarget == 4);
static_assert(MTLCommandBufferStatusCommitted == 2 && MTLCommandBufferStatusScheduled == 3);
static_assert(MTLCommandBufferStatusCompleted == 4 && MTLCommandBufferStatusError == 5);
static_assert(MTLTextureSwizzleRed == 2 && MTLTextureSwizzleGreen == 3 &&
              MTLTextureSwizzleBlue == 4 && MTLTextureSwizzleAlpha == 5);
// Compile the public protocol getter types; no GPU or window is created here.
static_assert(std::is_same<decltype(((id<MTLTexture>)nil).width), NSUInteger>::value);
static_assert(std::is_same<decltype(((id<MTLTexture>)nil).swizzle), MTLTextureSwizzleChannels>::value);
int main() {
    std::puts("{\"schema\":1,\"kind\":\"apple-metal-sdk\",\"status\":\"passed\",\"pointer_bytes\":8,\"nsuinteger_bytes\":8,\"bool_bytes\":1,\"swizzle_bytes\":4,\"gpu_execution_verified\":false}");
    return 0;
}
