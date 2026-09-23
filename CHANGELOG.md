# Changelog

## 0.6.0 — 2026-09-23

Adds the first standalone filter/effects layer: owned color, mask, and image
filter resources; 4×5 color-matrix, blend, and composed color filters; Gaussian
mask blur; image blur; drop-shadow and shadow-only filters; color-filter image
nodes; composed image-filter graphs; and paint constructor/getter/setter support
for all three filter families. Paints and filter graphs retain their inputs with
native reference counting, while getters expose independently owned wrappers.

The pinned m119 C shim and Skia implementations were audited for constructor,
attachment, getter, and release ownership. The m119 image-blur documentation
marks mirror tiling unsupported, so the Racket constructor rejects that mode.
The 0.6 source contains 105 test cases (23 pure, 6 lifetime, 76 native) plus a
six-panel `examples/filters.rkt` visual probe. These new filter paths were
source/ABI checked in the authoring environment but still require the included
local doctor, suite, and visual probe for live validation.

## 0.5.0 — 2026-09-23

Adds the first path-effects and path-measurement layer: dash, corner, discrete,
trim, compose, and sum path effects; paint attachment/getters; snapshot-safe
path measurement with contour traversal, position/tangent sampling, and segment
extraction; and boolean path operations including union, intersection,
difference, xor, reverse difference, simplify, and conversion to winding fill.

This version also corrects `paint-shader` ownership. The pinned m119 C shim's
`sk_paint_get_shader` already returns an owned reference via
`refShader().release()`. Versions 0.3/0.4 added another `sk_shader_ref`, which
kept rendering correct but leaked one native shader reference per getter call.
0.5 wraps the returned owned reference directly and documents the actual shim
semantics.

The completed 0.5 tree was subsequently live-validated on macOS/aarch64 with
Racket 9.3.0.2 and SkiaSharp 3.119.1: doctor passed, all 95 test cases passed
(21 pure, 6 lifetime, 68 native), and the path-effects visual probe rendered
correctly. See `TESTING.md`.

## 0.4.0 — 2026-09-23

Adds high-level encoded image support through the pinned SkiaSharp codec and
encoder C ABI: decode from byte strings or files; metadata probing without a
public image object; PNG/JPEG/WebP encoding; access to retained original encoded
data; image color/alpha metadata; raster subsets; and source-rectangle image
drawing. JPEG exposes quality, 4:2:0/4:2:2/4:4:4 downsampling, and alpha
handling; WebP exposes quality and lossy/lossless mode.

The ABI layer adds integer rectangles plus the JPEG and WebP encoder option
layouts, temporary codec/data/raster-image ownership, and explicit release of
the color-space reference returned through codec image info. A new
`examples/codecs.rkt` performs an in-memory render/encode/decode/crop round
trip. The 0.4 source contains 85 test cases (19 pure, 6 lifetime, 60 native).
The completed 0.4 tree was subsequently live-validated on macOS/aarch64 with
Racket 9.3.0.2 and the pinned native asset: doctor passed, all 85 test cases
passed (19 pure, 6 lifetime, 60 native), and the codec visual probe rendered
correctly.

## 0.3.0 — 2026-09-23

Adds the first standalone shader layer: owned `shader?` resources, color
shaders, linear/radial/sweep/two-point-conical gradients, tiled image shaders,
blend shaders, and shader attachment/querying on paints. Gradient stops accept
lists or vectors with optional explicit positions and all four Skia tile modes.
The implementation keeps the unsafe C ABI private and exposes paint shaders as
owned Racket wrappers. Version 0.5 corrects the exact native getter refcount
handling after auditing the m119 C shim.

The doctor, ABI checks, native regression suite, API reference, and a new
`examples/gradients.rkt` visual smoke test are extended for the feature. The
completed 0.3 tree was subsequently live-validated on macOS/aarch64 with Racket
9.3.0.2 and the pinned native asset: doctor passed, all 77 test cases passed
(17 pure, 6 lifetime, 54 native), and the gradients visual probe rendered
correctly.

## 0.2.0 — 2026-09-23

Adds the first standalone font and text layer: default, family, and file-backed
`typeface?` resources; configurable `font?` resources; font metrics; UTF-8
simple-text drawing and measurement; character/text-to-glyph mapping; and glyph
or simple-text outline paths. The ABI layer now includes the pinned SkiaSharp
font/typeface/string calls and the 64-byte `SKFontMetrics` layout. The doctor,
tests, example set, API reference, and ABI notes are extended accordingly.

The 0.2.0 source changes were initially checked statically in the authoring
environment. Its font/text paths were later exercised successfully as part of
the user's subsequent 0.3 doctor and complete 77-case regression run on
macOS/aarch64.

## 0.1.0 — 2026-09-23

Initial standalone CPU Skia binding using the SkiaSharp 3.119.1 native C ABI.
Adds resource ownership, drawing primitives, paths, clipping/transforms, image
snapshots and copied pixel input, native PNG output, a bitmap bridge, a native
installer/doctor, documentation, and tests.

The 0.1.0 baseline was subsequently validated on macOS/aarch64 with Racket
9.3.0.2 and the pinned native asset: doctor passed, all 57 source test cases
passed, and the circle, gallery, and bitmap-bridge examples rendered correctly.
