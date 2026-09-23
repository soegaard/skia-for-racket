# Primary sources used

These are upstream references for the native interface and Racket FFI choices,
not evidence that this package's own tests have run. Checked on 2026-09-23.

## Pinned SkiaSharp interface

- [Generated C signatures, structs, and enumerations, v3.119.1](https://github.com/mono/SkiaSharp/blob/v3.119.1/binding/SkiaSharp/SkiaApi.generated.cs)
- [Native version checking, v3.119.1](https://github.com/mono/SkiaSharp/blob/v3.119.1/binding/SkiaSharp/SkiaSharpVersion.cs)
- [Canvas wrapper semantics, v3.119.1](https://github.com/mono/SkiaSharp/blob/v3.119.1/binding/SkiaSharp/SKCanvas.cs)
- [Font wrapper semantics, v3.119.1](https://github.com/mono/SkiaSharp/blob/v3.119.1/binding/SkiaSharp/SKFont.cs)
- [Typeface wrapper semantics, v3.119.1](https://github.com/mono/SkiaSharp/blob/v3.119.1/binding/SkiaSharp/SKTypeface.cs)
- [macOS native-assets package, 3.119.1](https://www.nuget.org/packages/SkiaSharp.NativeAssets.macOS/3.119.1)
- [Linux NoDependencies native-assets package, 3.119.1](https://www.nuget.org/packages/SkiaSharp.NativeAssets.Linux.NoDependencies/3.119.1)

The NuGet package version is pinned intentionally. Later releases exist and
are not automatically substituted.

## Upstream background

- [SkiaSharp native C API development guide](https://github.com/mono/SkiaSharp/blob/main/documentation/dev/adding-apis.md)
- [SkiaSharp repository and license](https://github.com/mono/SkiaSharp)
- [Skia native C shim source](https://github.com/mono/skia/tree/xamarin-mobile-bindings/src/c)
- [Skia API documentation](https://api.skia.org/)

The moving-branch sources explain the design; the pinned generated declarations
are the compatibility reference for this implementation.

## Racket

- [Foreign interface introduction](https://docs.racket-lang.org/foreign/intro.html)
- [Allocation and finalization](https://docs.racket-lang.org/foreign/Allocation_and_Finalization.html)
- [Foreign pointers and memory functions](https://docs.racket-lang.org/foreign/foreign_pointer-funcs.html)
- [bitmap% and its ARGB pixel methods](https://docs.racket-lang.org/draw/bitmap_.html)
