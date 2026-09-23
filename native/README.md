# Native library location

This directory intentionally contains no binary in the source distribution.
Run `bash tools/install-native.sh` from the package root. The installer writes:

- macOS: `native/osx/libSkiaSharp.dylib`
- Linux x86-64: `native/linux-x64/libSkiaSharp.so`
- Linux ARM64: `native/linux-arm64/libSkiaSharp.so`

Alternatively set `RACKET_SKIA_LIBRARY` to an absolute native-library filename.
The library must match the pinned SkiaSharp 3.119.1 ABI, not just be named Skia.
Read the package README before using a different build.
