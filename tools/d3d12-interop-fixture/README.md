# Independent Direct3D texture producer

This fixture creates and consumes Direct3D resources independently of Skia.
Tests use it to verify ownership, state handoff, fence synchronization, and pixels
across the real interop boundary.

| File | Contents |
| --- | --- |
| [CMakeLists.txt](CMakeLists.txt) | Builds the Windows DLL and SDK check, or only a marked host mirror on other systems. |
| [fixture.cpp](fixture.cpp) | Implements texture creation, fences, descriptor access, independent readback, reference release, unsignaled-fence cases, and foreign-resource rejection fixtures. |
| [sdk-check.c](sdk-check.c) | Checks resource descriptors, barriers, state/format constants, and SDK interface assumptions; its non-Windows branch is a mirror only. |

The Racket wrapper is
[tests/d3d12-interop-fixture.rkt](../../tests/d3d12-interop-fixture.rkt).
[tests/gpu-interop-native-test.rkt](../../tests/gpu-interop-native-test.rkt) and
[gpu-d3d12-interop-doctor.rkt](../gpu-d3d12-interop-doctor.rkt) run regression
checks and capture evidence. Timeout/quarantine cases run separately because
their intentional retention is not normal successful teardown.
