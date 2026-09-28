# Changelog

## 0.41.0 — offscreen Metal parity

- Added explicit owned Metal context construction without an OpenGL/GUI host,
  retaining the same surface, image, drawing and transfer interfaces.
- Reused the pinned device/queue reference contract, with failure cleanup and
  short native-call autorelease scopes captured by deferred destruction jobs.
- Made native target/backend checks and shared surface/image suites select the
  actual backend rather than assume OpenGL.
- Added 34 pure, 8 Metal-specific and 9 cross-backend source cases, three
  Metal rendering/teardown smoke cycles, and ten GL/Metal visual comparisons.
- Added raw-diagnostic/PNG parity inspection, run identity, required/optional
  orchestration checks, headless examples and API/validation documentation.
- Added patch-hunk count/context and ordinary Git application regression tests.
- Preserved CPU defaults, explicit transfers, retained affinity, GL window
  behavior and final source-sum sequencing. Metal presentation, external
  interop and performance conclusions remain outside this release.

## 0.40.0 — GPU images and transitive context affinity

- Added explicit texture uploads, GPU surface snapshots/subsets, ownership
  residency/context queries, texture validity diagnostics, and CPU detachment.
- Added retained graph affinity through shaders, filter graphs, runtime children,
  paint slots/copies/getters, recorders, nested pictures and picture shaders.
  Native reference ownership survives original-wrapper mutation/closure.
- Added owner-side queued destruction and public-context keepalive for retained
  parents. Clearing the last native GPU paint slot restores CPU independence;
  successful picture finish transfers affinity from the emptied recorder.
- Reject cross-context use, implicit CPU/PDF/SVG rendering, CPU image conversion
  and encoding, and GPU-dependent SKP serialization. Explicit image readback
  stages through a same-context GPU surface; no zero-copy promise is made.
- Added 33 pure + 42 live source cases, two retained-graph comparison workflows,
  a post-teardown detached image, PNG/ledger inspection and validator regressions.
- Preserved the 0.39 window-import and nested-activation fixes, CPU constructors,
  separate lazy GPU symbols and all preceding selected validation steps.
  Authoring checks do not establish a new Racket/native GPU pass.

## 0.39.0 — offscreen OpenGL surfaces and explicit transfers

- Added GPU-backed `surface?` values and ordinary `canvas?` drawing with
  activation-bound leases, creator/domain checks and deferred native release.
- Added explicit flush/submit/wait and synchronous RGBA, detached CPU-image and
  direct strided raster-buffer readback. CPU snapshot/encoding entry points
  reject GPU targets; no public GPU images are produced in this revision.
- Added surface/execution backend queries without changing CPU constructors,
  document representation policies or CPU-only import behavior.
- Added a diagnostic host-framebuffer renderer with actual pixel dimensions,
  format/origin/stencil/sample queries, GPU-only blit, asynchronous submission
  and swapping. The automatic report does not certify visible window pixels.
- Added 35 pure and 33 live-GPU source cases, eight direct CPU/GPU scene pairs,
  full PNG pixel inspection, explicit comparison bounds and transfer traces.
- Extended the selected-Racket validator; inspector reports publish on success
  and source sums update last. The 0.38 GC-test correction is preserved.
- This authoring delivery did not execute Racket or native GPU rendering.
  Hardware/platform support and performance remain established only by host runs.

## 0.38.0 — GPU foundation and explicit backend probes

- Added optional backend-neutral context/provider/domain APIs with serialized
  owner scopes, native identity checks, unique generations and deferred releases.
- Added GC/custodian shutdown requests with owner-side draining, explicit
  abandonment, live-child close guards and quarantined indeterminate releases.
- Added a Racket GL adapter, separate lazy GPU symbol group, and a private
  Ganesh target/draw/submit/readback probe with exact RGBA and context checks.
- Added early Metal device/queue/Ganesh construction and teardown diagnostics;
  audited the actual pinned retain behavior instead of relying on the legacy
  transfer comment. No Metal rendering or presentation claim is made.
- Added Windows x64 native selection, pinned archive/PE validation and explicit
  installer/validator PowerShell entry points, without changing CPU constructors.
- Added 64 pure source test cases, protected-flag-aware GPU ABI mirrors,
  diagnostic/PNG inspection, synthetic Python tests, docs and a selected-Racket
  runner that regenerates source sums only after selected validation succeeds.
- No public GPU surface/image API yet. Authoring checks did not execute Racket,
  live Skia/GL/Metal, Windows installation, or full-checkout native validation.

## 0.37.0 — owned raster buffers

- Added native-owned strided RGBA storage, exclusive pixmap/direct-canvas scopes
  and copied immutable image snapshots.

## 0.36.0 — CPU color filters

- Added HSLA, gamma, lookup-table, luma, contrast, lerp and lighting factories,
  including the explicit all-omitted ARGB identity-filter fix.

## 0.35.0 — portable drawing

- Added marker geometry, inspectable grid plans and cropped nine/lattice/atlas
  placements that lower before recording and avoid whole-panel fallback.

## 0.34.0 — bounded output groups

- Added capture-once backend-aware native/raster decisions with retained nested
  reports and explicit rejection of unknown or discarded semantics.

## 0.33.0 — persistent pictures and picture shaders

- Added copied native SKP bytes, explicitly trusted file/byte loading, and atomic
  file publication. Cheap bounded header checks do not validate native payloads.
- Added native cull-bound snapshots, process-local IDs, approximate operation
  counts (optionally nested), and native byte estimates. Loaders accept nominal extents.
- Added optional `#:spatial-index 'rtree` to both recording entry points. The
  temporary factory is released after synchronous creation of the hierarchy.
- Added retained picture shaders with tile modes, filtering, tile rectangles,
  and the existing affine local-matrix API.
- Preserved opaque-import provenance, including through shaders and recordings;
  rasterization does not certify unknown semantics. Sampled links are discarded.
- Added 31 pure and 40 native tests, doctor, combined document/reference probes,
  metadata and audit checks, and a fresh-process raw-pixel replay comparison.
- Native requirements are 377 Skia / 27 HarfBuzz symbols; no new layouts.

## 0.32.0 — perspective and general canvas matrices

- Added separate immutable row-major 3x3 and 4x4 matrix values, checked native
  float coefficients, composition, transpose, inversion, and explicit conversions.
- Added homogeneous mapping, projected points, and rectangle bounds that return
  false when W reaches or crosses zero rather than returning misleading bounds.
- Added retained-depth translation/scale/rotation and an explicit camera-distance
  projection convention; the six-coefficient affine API remains unchanged.
- Added full canvas matrix readback, replacement, concatenation, and scoped
  matrix application with protected restoration and multiple-value results.
- Reused the existing column-major SkM44 callouts; no symbols or layouts added.
- Audited general matrix operations and retained their provenance in pictures.
  Strict PDF/SVG output requires explicit raster groups around those transforms.
- Added 59 pure and 36 native cases, a doctor, an eighth C mirror, and one combined
  PDF/SVG/reference/audit/matrix-trace registry with a structural inspector.
- Preserved the 0.31 region-seam fix from the current repository baseline.
- Authoring validation did not execute Racket or native Skia.

## 0.31.0 — structured geometry and advanced image drawing

- Added owned integer regions, nonmutating Boolean operations, path conversion,
  copied rectangle sequences, drawing, and explicit device-coordinate clipping.
- Added immutable native triangle meshes with copied positions, texture
  coordinates, colors, optional uint16 indices, and detached inspection data.
- Added nine-patch/lattice images, anchored atlas sprites, and cubic Coons patches.
  Lattice cell-kind storage matches the C++ uint8 ABI despite the C enum pointer.
- Extended output policies and recording provenance; fixed PDF point-sprite
  explanatory text that had described SVG instead.
- Reused existing rounded-rectangle values; no competing native public type.
- Added 38 pure and 42 native tests, a doctor probe, a seventh C layout mirror,
  and a combined PDF/SVG/reference/audit registry with a structural inspector.
- This authoring run did not execute Racket or native Skia tests.


## 0.30.0 — canvas primitives and scoped layers

- Added point sets, arcs, pure immutable four-corner rounded-rectangle
  specifications, rounded frames and clips, and clip-aware draw-color.
- Normalized rounded clips are rebuilt as ordinary paths so unequal corners
  survive SVG serialization and recorded-picture replay.
- Added detached local/device clip bounds, empty/rect predicates, and
  conservative quick rejection; no automatic culling is installed.
- Added native low-level and scoped save layers with paint snapshots, protected
  save-stack floors, multiple-value preservation, and exception cleanup.
- Documented the pinned m119 content-bounds restriction rather than promising
  that native layer bounds are merely an ignorable allocation hint.
- Device-clip color fills reset/restore the local matrix to avoid SVG's transformed
  drawPaint rectangle. Unbounded recorded color fills are conservatively audited.
- Extended output auditing and recorded-picture provenance for points and layers;
  corrected PDF native-text explanations that previously described SVG behavior.
- Added a picture-recorder finish guard for protected state/layer scopes.
- Added 28 pure and 40 native cases, doctor, a combined three-page registry,
  SVG/report/query inspector, and single-interpreter host validation.
- Adds 17 Skia symbols (336 total); no new structs. HarfBuzz remains 27.

## 0.29.0 — output capability and fallback auditing

- Added pure, conservative PDF/SVG/raster capability queries and immutable
  operation reports, named scopes, and JSON conversion.
- Added dynamic preflight and single-execution audited byte/file exporters with
  report, error, and vector-only publication policies.
- Resource provenance follows paint attachments/copies/getters, shader/filter
  children, path fill types, and recorded pictures, including recorder reuse.
- Explicit raster groups record padded bounds and actual pixel dimensions;
  known rendering features are resolved inside the group while lost document
  annotations remain a blocking semantic-loss event.
- Added 30 pure and 28 native tests, doctor, a three-page probe/report registry,
  structural inspector, and single-interpreter validation script.
- No new native symbols/layouts. Existing ICC/PNG fixes and annotations remain.

## 0.28.0 — runtime effects / SkSL

- Added owned compiled runtime effects and ordinary shader, color-filter, and
  blender instances with immutable uniform/child snapshots.
- Copied reflection exposes names, types, counts, offsets, precision/color flags,
  and child kinds without retaining borrowed C++ string views.
- Added checked, tightly packed float/int/vector/matrix/array uniforms, structured
  compilation errors, affine shader local matrices, and typed child binding.
- Added preset blender objects, paint setter/getter integration, and common
  lifetime/thread validation for runtime-effect and blender resources.
- Added 38 pure and 39 native cases, a doctor, reflection ABI mirror, and one
  twelve-panel PDF/SVG/reference runner with explicit bounded raster fallback.
- Adds 18 Skia symbols (319 total); HarfBuzz remains 27. Expected suite: 670 cases.
  Native/Racket execution is not claimed by the authoring checks.

## 0.27.0 — PDF/SVG links and document annotations

- Added canvas URL rectangles, named destinations, internal links, backend
  queries, and deterministic PDF/SVG destination-ID helpers.
- PDF references resolve across pages. SVG references resolve to predefined
  views; duplicate or missing names cannot silently enter completed exports.
- Native URL annotations retain copied data through picture recording/replay.
  Named annotations on recorders reject; raster annotations are validated no-ops.
- SVG finalization relocates native annotation rectangles to a root overlay to
  avoid stale graphics clips, preserves URI text, and emits href plus xlink:href.
- Added 25 pure and 27 native cases, doctor, a single three-page PDF/SVG registry,
  interactive object-based review HTML, and a structural inspector.
- Three additional native symbols (301 total); no new structs or encoder changes.

## 0.26.0 — color-managed encoded and document output

- Added immutable SDR transfer values, named transfer/gamut queries, custom RGB
  construction, chromaticity-to-XYZ-D50 conversion, and detached inspection.
- Added explicit image sample conversion. Untagged input requires a source
  declaration; tagged input cannot have its source silently overridden.
- Extended PNG/JPEG/WebP and surface PNG encoders with destination conversion,
  matrix/TRC ICC overrides and descriptions. Native profile buffers remain live
  throughout encoding; metadata overrides alone never convert pixel samples.
- Exposed the existing Skia PDF/A metadata flag through low-level and shared
  PDF exports. It requests XMP/UUID/sRGB output intent, not certified conformance.
- Added a unified PDF/SVG/encoded-image color probe and semantic ICC inspector.
  The guide documents 8-bit SDR limitations, profile regeneration, and the
  pinned PDF image-color limitation requiring explicit sRGB normalization.
- Added 34 pure and 35 native tests (541 total), doctor coverage, color ABI
  mirror and a one-interpreter validation script compiling every test module.
- Based on 0.25 commit `7372d061ff2e1cf0c85c44a48d8ce5b994538027` after the
  maintainer reported its successful run. New native validation awaits the host.

## 0.25.0 — advanced filter graphs and crop semantics

- Added merge, blend/arithmetic, offset, morphology, displacement, convolution,
  affine image transforms, tile, magnifier, image/picture/shader source nodes,
  and six diffuse/specular lighting constructors: 21 new public constructors.
- Added #:crop to blur, both shadow constructors, color-filter image nodes, and
  composition, plus an explicit standalone output-crop node. Rectangles use xywh.
- Preserved dynamic-source semantics for #f; private identity nodes keep valid
  native Src/Dst and identity optimizations owned instead of treating them as
  allocation failures. Parent graphs and paints retain their inputs natively.
- Copied input arrays and kernels with byte limits, strict geometry/enum checks,
  and explicit convolution pixel-unit and crop/tile semantics. No claimed
  blanket SVG filter support: the new SVG probes rasterize panels explicitly.
- Added 30 pure + 44 native tests (472 total), doctor coverage, three C structure
  mirrors (8/8/12 bytes), ten Python inspector tests, and one 18-panel registry
  for native PDF, SVG raster groups, and independent native raster references.
- Added 20 native symbols: 285 Skia / 27 HarfBuzz. The single-interpreter
  validation script continues to compile all tests/*.rkt before running them.
- Based on cd046ac6eb92d7c0534b70900a341b1014cd6fbe. Authoring checks are not
  Racket compilation or native execution; see docs/FILTER-TESTING.md.

## 0.24.0 — path inspection and affine matrices

- Added immutable six-coefficient affine matrix values, composition/inversion,
  point/vector/bounds mapping, and canvas transform get/set/concat operations.
- Added eager detached raw/normal path snapshots, reusable sequences, conic
  weights, generated closing-line flags, contour groups and raw reconstruction.
- Added copied/in-place path transforms, path-measure placement matrices, and
  independently owned shader-local-matrix wrappers.
- Audited the distinct m119 matrix boundaries: 36-byte M33 for paths/shaders,
  64-byte column-major SkM44 storage for canvas functions. Added an independent
  native-translate/readback test, not just a self-consistent get/set round trip.
- Added 24 pure and 30 native tests: 398 total cases (136 pure, 6 lifetime,
  256 native). Adds 16 Skia symbols (265 total); HarfBuzz remains 27.
- Added one PDF/SVG/raster-reference probe runner and an eight-test structural
  inspector. Local shader examples explicitly rasterize only the shader panel.
- Validation now compiles all tests/*.rkt through the selected Racket's raco
  module, avoiding stale dynamically loaded test bytecode from another version.
- Starts from 36b4b44dae46e30bb07dcdb569a254c8fdd4d982. Source/context-patch,
  host-C and synthetic inspector checks are not Racket/native execution.

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
