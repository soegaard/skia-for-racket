# Independent Metal texture producer

This Apple-SDK-only Objective-C++ fixture supplies a producer and independent
readback path for checking imported-texture ownership and producer completion.
Skia does not generate the reference pixels.

| File | Contents |
| --- | --- |
| [CMakeLists.txt](CMakeLists.txt) | Requires the Apple SDK, builds with ARC, links Metal/Foundation, and registers the SDK check. |
| [fixture.mm](fixture.mm) | Implements texture/command-buffer creation, descriptor inspection, readback, delayed-producer unblocking, and cleanup through a C interface. |
| [sdk-check.mm](sdk-check.mm) | Checks Objective-C ABI widths, swizzle layouts, Metal constants, and property types against the SDK. |

[tests/metal-interop-fixture.rkt](../../tests/metal-interop-fixture.rkt) supplies the
Racket wrapper. [tests/gpu-metal-interop-native-test.rkt](../../tests/gpu-metal-interop-native-test.rkt)
and [gpu-metal-interop-doctor.rkt](../gpu-metal-interop-doctor.rkt) exercise it.
Build products and captures belong in the validation output directory, not here.
