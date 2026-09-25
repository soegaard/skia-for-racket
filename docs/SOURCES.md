# Primary sources used

These are upstream references for the native interface and Racket FFI choices,
not evidence that this package's own tests have run. Checked on 2026-09-24.

## Pinned SkiaSharp interface

- [Generated C signatures, structs, and enumerations, v3.119.1](https://github.com/mono/SkiaSharp/blob/v3.119.1/binding/SkiaSharp/SkiaApi.generated.cs)
- [Native version checking, v3.119.1](https://github.com/mono/SkiaSharp/blob/v3.119.1/binding/SkiaSharp/SkiaSharpVersion.cs)
- [Canvas wrapper semantics, v3.119.1](https://github.com/mono/SkiaSharp/blob/v3.119.1/binding/SkiaSharp/SKCanvas.cs)
- [Font wrapper semantics, v3.119.1](https://github.com/mono/SkiaSharp/blob/v3.119.1/binding/SkiaSharp/SKFont.cs)
- [Typeface wrapper semantics, v3.119.1](https://github.com/mono/SkiaSharp/blob/v3.119.1/binding/SkiaSharp/SKTypeface.cs)
- [Image decode/shader/subset semantics, v3.119.1](https://github.com/mono/SkiaSharp/blob/v3.119.1/binding/SkiaSharp/SKImage.cs)
- [Codec metadata semantics, v3.119.1](https://github.com/mono/SkiaSharp/blob/v3.119.1/binding/SkiaSharp/SKCodec.cs)
- [Pixmap encoder semantics, v3.119.1](https://github.com/mono/SkiaSharp/blob/v3.119.1/binding/SkiaSharp/SKPixmap.cs)
- [Encoder option defaults, v3.119.1](https://github.com/mono/SkiaSharp/blob/v3.119.1/binding/SkiaSharp/Definitions.cs)
- [Shader/gradient wrapper semantics, v3.119.1](https://github.com/mono/SkiaSharp/blob/v3.119.1/binding/SkiaSharp/SKShader.cs)
- [Image-to-shader wrapper semantics, v3.119.1](https://github.com/mono/SkiaSharp/blob/v3.119.1/binding/SkiaSharp/SKImage.cs)
- [Paint/shader attachment semantics, v3.119.1](https://github.com/mono/SkiaSharp/blob/v3.119.1/binding/SkiaSharp/SKPaint.cs)
- [Path-effect wrapper semantics, v3.119.1](https://github.com/mono/SkiaSharp/blob/v3.119.1/binding/SkiaSharp/SKPathEffect.cs)
- [Path-measure wrapper semantics, v3.119.1](https://github.com/mono/SkiaSharp/blob/v3.119.1/binding/SkiaSharp/SKPathMeasure.cs)
- [PathOps wrapper semantics, v3.119.1](https://github.com/mono/SkiaSharp/blob/v3.119.1/binding/SkiaSharp/SKPath.cs)
- [Color-filter wrapper semantics, v3.119.1](https://github.com/mono/SkiaSharp/blob/v3.119.1/binding/SkiaSharp/SKColorFilter.cs)
- [Mask-filter wrapper semantics, v3.119.1](https://github.com/mono/SkiaSharp/blob/v3.119.1/binding/SkiaSharp/SKMaskFilter.cs)
- [Image-filter wrapper semantics, v3.119.1](https://github.com/mono/SkiaSharp/blob/v3.119.1/binding/SkiaSharp/SKImageFilter.cs)
- [macOS native-assets package, 3.119.1](https://www.nuget.org/packages/SkiaSharp.NativeAssets.macOS/3.119.1)
- [Linux NoDependencies native-assets package, 3.119.1](https://www.nuget.org/packages/SkiaSharp.NativeAssets.Linux.NoDependencies/3.119.1)

The NuGet package version is pinned intentionally. Later releases exist and
are not automatically substituted.

## Upstream background

- [SkiaSharp native C API development guide](https://github.com/mono/SkiaSharp/blob/main/documentation/dev/adding-apis.md)
- [SkiaSharp repository and license](https://github.com/mono/SkiaSharp)
- [Skia native C shim source](https://github.com/mono/skia/tree/xamarin-mobile-bindings/src/c)
- [Native codec shim](https://github.com/mono/skia/blob/xamarin-mobile-bindings/src/c/sk_codec.cpp)
- [Native image shim](https://github.com/mono/skia/blob/xamarin-mobile-bindings/src/c/sk_image.cpp)
- [Native ABI conversion helpers](https://github.com/mono/skia/blob/xamarin-mobile-bindings/src/c/sk_types_priv.h)
- [Native path/path-measure/PathOps shim](https://github.com/mono/skia/blob/xamarin-mobile-bindings/src/c/sk_path.cpp)
- [Native path-effect shim](https://github.com/mono/skia/blob/xamarin-mobile-bindings/src/c/sk_patheffect.cpp)
- [Native paint refcount attachment/getters](https://github.com/mono/skia/blob/xamarin-mobile-bindings/src/c/sk_paint.cpp)
- [Native color-filter shim](https://github.com/mono/skia/blob/xamarin-mobile-bindings/src/c/sk_colorfilter.cpp)
- [Native mask-filter shim](https://github.com/mono/skia/blob/xamarin-mobile-bindings/src/c/sk_maskfilter.cpp)
- [Native image-filter shim](https://github.com/mono/skia/blob/xamarin-mobile-bindings/src/c/sk_imagefilter.cpp)
- [Skia API documentation](https://api.skia.org/)

The moving-branch sources explain the design; the pinned generated declarations
are the compatibility reference for this implementation.

## Racket

- [Foreign interface introduction](https://docs.racket-lang.org/foreign/intro.html)
- [Allocation and finalization](https://docs.racket-lang.org/foreign/Allocation_and_Finalization.html)
- [Foreign pointers and memory functions](https://docs.racket-lang.org/foreign/foreign_pointer-funcs.html)
- [bitmap% and its ARGB pixel methods](https://docs.racket-lang.org/draw/bitmap_.html)

- Skia/SkiaSharp picture recorder and picture replay entry points (`sk_picture_recorder_*`, `sk_canvas_draw_picture`, `sk_picture_unref`) from the pinned m119 native ABI were used for the 0.7 recording layer.

- Expanded path/SVG geometry in 0.8 uses the pinned Skia path C ABI for relative commands, conics, path composition, point queries, and SVG path-data parsing/serialization.

- 0.8.1 audited legacy `sk_path_*` exports against the actual SkiaSharp 3.119.1 native library and the corresponding `include/c/sk_path.h` / `src/c/sk_path.cpp` C shim signatures.

- Font-manager/fallback work in 0.9 was checked against the pinned SkiaSharp `SKFontManager.cs`, generated `sk_typeface.h` bindings, and mono/skia `src/c/sk_typeface.cpp` / `include/c/sk_typeface.h`.
- Positioned text blobs in 0.9 were checked against `SKTextBlob.cs`, generated `sk_textblob.h` bindings and `SKRunBufferInternal`, plus mono/skia `src/c/sk_textblob.cpp` / `include/c/sk_textblob.h`.

- HarfBuzzSharp 8.3.1.2 / HarfBuzz 8.3.1 C APIs (`hb_blob_*`, `hb_face_*`,
  `hb_font_*`, `hb_buffer_*`, `hb_shape`, feature/script/language helpers) are
  the basis of the 0.10 shaping layer. The scale/position conversion follows
  SkiaSharp.HarfBuzz `SKShaper` from SkiaSharp v3.119.1.

- Version 0.11 paragraph layout is implemented in Racket above the existing HarfBuzz/Skia shaping substrate; no additional upstream native entry points are introduced.

- Unicode bidirectional data used by the 0.12 pure-Racket resolver is generated
  from Unicode 15.1 property data (matching the HarfBuzz 8.3-era Unicode data).
  Script classification is queried through HarfBuzz's default Unicode functions
  with `hb_unicode_funcs_get_default` / `hb_unicode_script`.
- The 0.12 resolver follows the relevant Unicode Bidirectional Algorithm (UAX #9)
  paragraph, weak, paired-bracket, neutral, implicit-level, and visual reordering
  rules for ordinary text; explicit embedding/override/isolate controls are a
  documented exclusion.
- Version 0.13 line breaking uses Unicode 15.1 `LineBreak.txt` property data,
  the Unicode 15.1 `emoji-data.txt` Extended_Pictographic reservation data used
  by LB30b, and Unicode Standard Annex #14 revision 51. The implementation uses
  UAX #14 Example 6's default-grapheme-cluster-preserving tailoring. Complex
  context dictionary segmentation and higher-level hyphenation are documented
  exclusions.

- Version 0.14 justification is implemented in pure Racket above the existing
  positioned HarfBuzz runs. It introduces no native entry points: the layout
  layer redistributes U+0020 inter-word slack by changing stored glyph x
  positions and per-run/line advances while preserving shaping clusters and
  visual bidi run order.
- Version 0.15 conformance tooling targets the normative Unicode 15.1
  `auxiliary/LineBreakTest.txt` and `BidiCharacterTest.txt` files. The upstream
  corpora are fetched only by the optional development script or supplied from
  an offline directory; they are not runtime/package data.
- Version 0.16 follows UAX #9 explicit rules X1–X10, isolating run sequences,
  FSI first-strong resolution, overflow counters, N0 bracket scoping, I1/I2,
  and line-specific L1. Explicit formatting controls are removed before shaping
  only after their paragraph-level directional effect has been resolved.
- Version 0.17 keeps higher-level segmentation and hyphenation policy outside
  the Unicode algorithms. Break providers contribute supplemental grapheme-safe
  boundaries after the conformant UAX #14 pass; optional display suffixes are
  layout metadata and do not mutate the logical paragraph used by UAX #9.
