# CI ABI mirror checks

This CMake project compiles local C structure mirrors used by the Racket bindings.
It checks layout consistency without loading Skia or HarfBuzz.

[CMakeLists.txt](CMakeLists.txt) registers C11 executables and CTest entries for the
adjacent `check-*-abi.c` sources: codecs, PDF, paths/matrices, filters, color
output, runtime effects, geometry, projective transforms, color filters, GPU,
presentation, and caches. The C sources live in the [parent directory](../README.md).

Passing mirror checks do **not** establish compatibility with an installed
library. Symbol resolution and real native calls are checked separately by the
[CI driver](../ci.py) and [native ABI diagnostic](../native-abi-doctor.rkt).
