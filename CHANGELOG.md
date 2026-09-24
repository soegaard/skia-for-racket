# Changelog

## 0.14.0 — paragraph justification

- Added `#:align 'justify` and `#:align 'justify-all` to `layout-text` and `layout-mixed-text`.
- `justify` expands wrapped non-final lines and leaves each paragraph's final line at logical start; `justify-all` also expands final/single lines.
- Justification adjusts positioned HarfBuzz glyph origins without reshaping, preserving glyph IDs, clusters, bidi run order, script segmentation, and font fallback.
- Expansion is deliberately inter-word only: U+0020 SPACE absorbs the extra width; NBSP/NNBSP, CJK inter-character spacing, letter spacing, and Arabic kashida are unchanged.
- Added LTR/RTL/mixed-bidi tests, doctor coverage, and `examples/justification.rkt`.
- No new Skia or HarfBuzz native symbols or ABI structs are required.

## 0.13.0 — Unicode line breaking

- Added a private Unicode 15.1 `Line_Break` property table and UAX #14 revision 51 resolver.
- `layout-text` and `layout-mixed-text` now fit lines greedily at Unicode line-break opportunities instead of whitespace runs only, including unspaced CJK and punctuation-aware breaks.
- Preserved default grapheme clusters as an explicit UAX #14 tailoring and retained non-tailorable ZWJ behavior at grapheme boundaries.
- Added Unicode hard-break handling for BK/CR/LF/NL separators, while retaining blank and trailing lines.
- Added line-break property/opportunity tests, native CJK/punctuation layout tests, doctor coverage, and `examples/line-breaking.rkt`.
- Southeast Asian dictionary segmentation, language-specific hyphenation/emergency breaking, and explicit UAX #9 embedding/override/isolate controls remain outside this stage; basic inter-word justification arrives in 0.14.
- No new Skia or HarfBuzz native symbols or ABI structs are required.

## 0.12.0 — mixed-script and bidirectional text layout

- Added `layout-mixed-text` / `draw-mixed-text-layout` with multiple shaped runs per visual line.
- Added ordinary Unicode bidi resolution for paragraph direction, weak/neutral types, paired brackets, implicit levels, and visual run reordering.
- Added HarfBuzz Unicode-script classification and script-aware run segmentation.
- Added grapheme-preserving font fallback through `font-manager-match-character`, with fallback family/style metadata retained in pure layout runs.
- Added mixed-run wrapping/alignment, run inspection APIs, doctor coverage, tests, and `examples/mixed-text.rkt`.
- Explicit Unicode embedding/override/isolate controls are intentionally not interpreted in this stage; they are omitted from shaping. Full explicit-control UAX #9 support remains future work; UAX #14 line breaking arrives in 0.13 and inter-word justification in 0.14.

## 0.11.0 — paragraph text layout

- Added pure `text-layout?` and `text-layout-line?` values above shaped runs.
- Added `layout-text` with explicit newlines, greedy Unicode-whitespace wrapping, start/center/end/left/right alignment, horizontal LTR/RTL direction, and configurable line height.
- Added `draw-text-layout` using font-metric-derived baselines.
- Added `examples/layout.rkt`, doctor coverage, and layout tests.
- No new native symbols or ABI structs are required by this stage.

## 0.10.1 — HarfBuzz feature-struct compile fix

- Renamed the Racket-side `hb_feature_t.tag` field binding to `feature-tag` to avoid colliding with the `hb-feature-tag` identifier that `define-cstruct` generates for the cstruct pointer tag. The native ABI layout is unchanged.

## 0.10.0 — HarfBuzz shaping

- Added lazy loading of pinned HarfBuzzSharp 8.3.1.2 / HarfBuzz 8.3.1.
- Added owned `shaper?` resources that snapshot an Skia font/typeface for deterministic shaping and later TextBlob rendering.
- Added immutable `shaped-run?` values with glyph IDs, UTF-8 clusters, explicit glyph positions, and x/y advances.
- Added `shape-text`, OpenType feature strings, direction/script/language overrides, `shaped-run->text-blob`, `draw-shaped-run`, and `draw-shaped-text`.
- Added `tools/install-harfbuzz.sh` and `tools/audit-harfbuzz-symbols.sh`.
- Added `examples/shaping.rkt`, doctor coverage, ABI checks, and shaping tests.

## 0.9.0 — font managers and positioned text blobs

- Added owned `font-manager?` resources, default/fresh manager constructors, family enumeration, family-style matching, and character fallback with BCP-47 language hints.
- Added immutable `text-blob?` resources built from explicit glyph IDs and positions, blob bounds/unique IDs, and `draw-text-blob`.
- Added the native `sk_textblob_builder_runbuffer_t` layout mirror and host-C layout assertions.
- Added `examples/text-blobs.rkt`, doctor coverage, and font-manager/text-blob tests.


## 0.8.1 — path ABI symbol hotfix

- Corrected `sk_path_add_round_rect` to the actual m119 export `sk_path_add_rounded_rect`.
- Corrected translated path composition to call `sk_path_add_path_offset`; `sk_path_add_path` has only `(path, other, mode)`.
- Corrected `sk_path_reverse_add_path` to the actual export `sk_path_add_path_reverse`.
- Added `tools/audit-symbols.sh` to compare every `define-native` declaration with the selected native library in one pass.

## 0.8.0 — expanded paths and SVG geometry

- Added relative path commands, conic segments, rounded-rect insertion, path composition, point queries, and SVG path-data conversion.
- Added `examples/svg-paths.rkt`, doctor coverage, and native tests for path/SVG geometry.


## 0.7.1 — picture recorder symbol hotfix

- Corrected the pinned m119 FFI symbol for finishing picture recording from the nonexistent `sk_picture_recorder_finish_recording_as_picture` to the exported `sk_picture_recorder_end_recording`.

## 0.7.0 — pictures and recording

- Added immutable `picture?` resources with `picture-width` and `picture-height`.
- Added `picture-recorder?` resources plus `make-picture-recorder`, `picture-recorder-begin-recording!`, and `picture-recorder-finish-recording!`.
- Added `call-with-picture` convenience recording.
- Added `draw-picture` replay and `picture->image` rasterization.
- Added `examples/pictures.rkt`, doctor coverage, and picture tests.

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
