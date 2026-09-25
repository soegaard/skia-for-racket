# Changelog

## 0.23.0 — vector-output refinement

- Added reusable output-page specifications and shared PDF/SVG byte/file exports,
  explicit physical units, margins, content clipping, and page backgrounds.
  PDF accepts multiple pages; SVG rejects extra pages instead of dropping them.
- Shared SVG exports now use physical pt root dimensions matching PDF media boxes;
  the low-level SVG interface retains its existing user-unit sizing.
- Added scoped native/outline text policy across simple, shaped, paragraph,
  mixed-run, and prebuilt-blob drawing. Auto export chooses native PDF / outlined
  SVG. Already-recorded native pictures are intentionally not rewritten.
- Added independent text-blob outline conversion using private font snapshots
  and copied glyph/position metadata, including source-mutation/closure tests.
- Extended explicit raster groups with density inheritance, four-sided padding,
  and optional color-space tags, while preserving their local content origin.
- Added 20 pure and 29 native cases (344 expected total), doctor coverage, one
  PDF/SVG/raster visual registry, and a structural inspector with eight synthetic
  tests plus optional pypdf-backed size/text/font inspection.
- Adds no native bindings or layouts: 249 Skia and 27 HarfBuzz remain required.
  Based on `fa7d04e881df9f80a99e62e5f51aaa5ec30b02dc`. Authoring validation is
  source/context-patch and synthetic-parser validation, not a Racket/native run.

## 0.22.0 — SVG document output

- Added owned single-viewport SVG documents with borrowed canvases, explicit
  finish/abort, copied bytes/strings, and safe file publication. Canvas deletion
  completes the XML before stream detachment; closed canvas aliases stay invalid.
- Added fractional dimensions/viewBox, escaped UTF-8 title/description, and
  deterministic resource-ID canonicalization with a caller-selected prefix.
- Added backend-independent `shaped-run->path` and `draw-rasterized` helpers:
  explicit glyph geometry or local pixel groups, not hidden whole-page fallback.
- Documented the pinned C shim's missing SVG flags, native glyph/text mapping,
  unsupported shader/filter/clip/blend cases, and lack of font embedding.
- Added 16 pure and 27 native cases (295 expected total), a doctor probe, three
  SVG examples with raster references/browser comparison, and a standard-library
  Python structural inspector with six synthetic self-tests.
- Adds two Skia symbols (249 total), no HarfBuzz symbols (27 total), and no
  native struct layouts. Existing PDF, ICC/color, and codec code is retained.
- Based on pushed PDF commit `246f70cd80e26bc5d8da126e86ff7e520225a5f7` after
  the maintainer reported its tests passing. New Racket/native SVG execution
  awaits host validation; see `docs/SVG-TESTING.md` for the verification boundary.

## 0.21.0 — PDF document output

- Added owned PDF documents and per-page borrowed canvases using the existing
  drawing API. Ended page canvases stay invalid when later pages begin.
- Added explicit begin/end/finish/abort operations, copied PDF bytes, safe file
  publication, scoped page helpers, and multi-page convenience functions.
- Added UTF-8 metadata, optional explicit dates, raster-fallback DPI, and native
  lossless/JPEG image-quality policy. Page dimensions are fractional PDF points.
- Document/stream/data lifetimes are released in order; unfinished documents are
  aborted. Exceptions, breaks, and continuation escapes cannot publish partial
  file output. PDF does not introduce native-to-Racket callbacks.
- Added 12 pure and 21 native cases (252 total source cases), doctor coverage,
  a C ABI mirror, a three-page visual probe with raster reference PNGs, and an
  optional parser-based PDF inspector. Adds seven Skia symbols (247 total),
  no HarfBuzz symbols (27 total), and two C layouts (metadata/timestamp).
- Based on pushed 0.20 commit `ccabb4741edc227a1dbeba91a47adf5082d7417f`.
  The user's 0.20 native suite and visual probe are green. This stage has source
  and host-C checks only in the authoring environment; Racket/native/PDF visual
  validation is still required. See `docs/PDF-TESTING.md`.

## 0.20.0 — advanced codecs

- Added owned, thread-confined codecs with copied byte/file inputs, native
  metadata snapshots, owned color-space queries, frame counts, and repeat counts.
- Added eager, independently decoded full-canvas frames. Skia reconstructs
  dependencies and applies animation disposal/blending; no previous-output
  buffer is assumed. GIF and animated WebP have deterministic pixel fixtures.
- Added exact normalization for all eight encoded origins, with an explicit
  opt-out, display-dimension queries, and one-shot byte/file frame constructors.
- Exposed frame duration, required frame, completeness, alpha, disposal, blend,
  and encoded-coordinate frame rectangles. Preserved the legacy zero-count
  still-image metadata convention while exposing one selectable still frame.
- Added strict decode-result handling, 10 pure and 17 native test cases,
  doctor coverage, a host-C ABI mirror, and a self-contained visual example.
- Adds three Skia C-ABI symbols (240 total), no HarfBuzz symbols (27 total),
  and two complete native struct layouts. Expected suite: 219 source cases.
- Based on `257517a5c9f561b075c2fff23dd3ccad3be39d9a`; the corrected 0.19 ICC
  implementation and the previous image-decoding entry points are unchanged.
- Source/fixture/C-layout checks were performed. Racket compilation, the new
  native suite, native symbol audits, doctor, and visual rendering await the
  host run described in `docs/CODEC-TESTING.md`.

## 0.19.0 — color spaces and ICC color management

- Added owned `color-space?` wrappers with sRGB and linear-sRGB constructors, gamma queries, equality, and transfer-function conversion helpers.
- Added ICC profile import/export through byte strings, with native profile lifetime retained safely by ICC-created color spaces.
- `make-surface` and `rgba-bytes->image` now accept `#:color-space`; snapshots preserve the tag and `surface-color-space` / `image-color-space` expose owned references.
- `surface->rgba-bytes` and `image->rgba-bytes` accept a destination `#:color-space`, allowing Skia to perform CPU color conversion during readback.
- Added doctor/native coverage and `examples/color-spaces.rkt`. Encoded-output ICC injection and custom RGB transfer/matrix constructors remain future work.
- Adds 16 Skia C-ABI symbols and no HarfBuzz symbols or new native struct layouts.

## 0.18.0 — script-aware justification

- Extended `justify` / `justify-all` from U+0020-only expansion to automatic script-aware opportunities.
- Added CJK inter-character expansion for Han, Hiragana, Katakana, and Hangul, including compatible boundaries between separately shaped visual runs while excluding common punctuation.
- Added Unicode 15.1 Joining_Type data and Arabic kashida shaping: eligible cursive connections receive display-only U+0640 TATWEEL material, are reshaped by HarfBuzz, and preserve logical line/run text.
- Mixed lines distribute slack across inter-word, CJK, and Arabic opportunities; paragraph bidi resolution, fallback selection, break-provider indices, and Unicode conformance behavior remain unchanged.
- Added joining-data pure tests, CJK/Arabic/mixed native tests, doctor coverage, and `examples/script-justification.rkt`.
- No new Skia or HarfBuzz native symbols or ABI structs are required.

## 0.17.0 — external segmentation and hyphenation hooks

- Added public `layout-break-opportunity?` values and `make-layout-break-opportunity` for discretionary breaks with optional display-only suffix text such as `"-"`.
- Added `#:break-provider` to `layout-text` and `layout-mixed-text`. Providers receive each hard-break-delimited paragraph and normalized language hint and return supplemental string-index break boundaries.
- Provider boundaries supplement rather than replace Unicode 15.1 UAX #14 opportunities, allowing application-supplied Thai/Lao/Khmer dictionary segmentation or language-specific hyphenation without embedding a dictionary in the core package.
- Provider indices must be interior Racket default-grapheme boundaries. A suffix is shaped only when its boundary is selected; mixed layout preserves paragraph-wide UAX #9 resolution and gives the suffix the resolved level immediately preceding the break.
- Added pure/native tests, doctor coverage, and `examples/break-providers.rkt`.
- No new Skia or HarfBuzz native symbols or ABI structs are required.

## 0.16.0 — explicit Unicode bidi controls

- `layout-mixed-text` now interprets UAX #9 explicit embeddings, overrides, and isolates: `LRE/RLE/LRO/RLO/PDF/LRI/RLI/FSI/PDI`.
- Added the directional-status-stack rules, overflow handling through level 125, matching isolates, FSI direction selection, isolating run sequences, scoped bracket resolution, and line-specific L1 resets.
- Explicit formatting controls remain zero-width and are removed before HarfBuzz shaping; their resolved paragraph levels are retained across UAX #14 wrapping so a directional scope may span visual lines.
- Added pure resolver tests, native wrapped-scope/isolate tests, doctor coverage, and `examples/bidi-controls.rkt`.
- No new Skia or HarfBuzz native symbols or ABI structs are required.

## 0.15.0 — Unicode conformance hardening

- Added a pure-Racket conformance harness for Unicode 15.1 `LineBreakTest.txt` and `BidiCharacterTest.txt`, including the library's documented default-grapheme-cluster line-break tailoring.
- Added `tools/unicode-conformance.rkt` plus `tools/run-unicode-conformance.sh`, which can use an offline Unicode-data directory or fetch the pinned 15.1 test files from unicode.org.
- Added parser/smoke-vector regression tests and a reproducible source-checksum updater.
- The multi-megabyte Unicode test corpora are development inputs and are not vendored in the package.
- No new native symbols or ABI structs are required.

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
