# Native library location

This directory is the legacy developer installation destination,
not a Racket source module. The loaders in [private/](../private/README.md) locate
these libraries. Installed diagnostics and Windows acquisition helpers live in
`skia-lib/tools/`; repository installers and ABI probes live in root `tools/`.
This README is the directory's tracked source documentation. Platform-specific
library directories are populated by installation rather than maintained as
source code.

Ordinary macOS/Linux/Windows x86-64 catalog installs use the separate, generation-qualified
`skia-native-1` directory managed by Racket, containing both libraries and its
manifest. Managed data takes precedence over files here. Set both explicit
native-library overrides when testing developer builds. A selected broken
managed pair does not fall back here or to host libraries.

Windows uses `skia-native-win32-x86_64-1` as its normal dependency. The optional
`racket -l skia/tools/install-windows-natives` developer command installs
`skia-upstream-1` under Racket's library directory. Managed data takes precedence;
a broken installed native package fails before this optional cache is considered.
The developer-only `tools/install-native-windows.py --root /path/to/checkout/skia-lib`
route writes `native/win-x64` for the explicit-override acceptance gates.

This directory intentionally contains no binary in the source distribution.
Run `bash tools/install-native.sh` from the repository root. The installer writes
under `skia-lib/`; these paths are relative to that collection directory:

- macOS: `native/osx/libSkiaSharp.dylib`
- Linux x86-64: `native/linux-x64/libSkiaSharp.so`
- Linux ARM64: `native/linux-arm64/libSkiaSharp.so`

The ARM64 developer installer route is retained from earlier releases; it is
not a qualified automatic catalog target. See the publication validation report.

Alternatively set `RACKET_SKIA_LIBRARY` to an absolute native-library filename.
The library must match the pinned SkiaSharp 3.119.1 ABI, not just be named Skia.
Read the package README before using a different build.


Version 0.10 optionally installs HarfBuzz shaping beside Skia:

```text
native/osx/libHarfBuzzSharp.dylib
native/linux-x64/libHarfBuzzSharp.so
native/linux-arm64/libHarfBuzzSharp.so
```

Use `bash tools/install-harfbuzz.sh`. The pinned package is
HarfBuzzSharp.NativeAssets.* 8.3.1.2 (HarfBuzz 8.3.1).
