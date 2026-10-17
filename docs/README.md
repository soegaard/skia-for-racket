# Maintainer documentation

This directory explains implementation boundaries, design decisions, ABI/ownership
requirements, and how to validate features. It complements the user-facing
[Reference](../scribblings/reference/reference.scrbl) and
[Tutorials](../scribblings/tutorials/index.scrbl); it is not a second source of
public API signatures.

Start with [PUBLIC-API.md](PUBLIC-API.md), [API-CONTRACTS.md](API-CONTRACTS.md),
[RESOURCE-LIFETIMES.md](RESOURCE-LIFETIMES.md), and [CI.md](CI.md) when changing
library code. For documentation work, start with
[REFERENCE-DEVELOPMENT.md](REFERENCE-DEVELOPMENT.md) and
[TUTORIAL-GUIDELINES.md](TUTORIAL-GUIDELINES.md).

Version/stage labels record the context in which a feature or validation gate
was introduced. A source inventory, an available test, and a successful native
execution are distinct kinds of evidence. Files ending in `-TESTING.md` describe
checks and prerequisites; do not interpret their presence as a current pass.

## Project contracts and maintenance

These files define compatibility boundaries, inventory evidence, release scope, and repository validation policy.

- [API-CONTRACTS.md](API-CONTRACTS.md): Public API contracts — 0.78c.
- [API-DESIGN-DECISIONS.md](API-DESIGN-DECISIONS.md): Additive API decisions for gap reduction — 0.65.
- [API.md](API.md): API reference.
- [CI-REGRESSION-SCOPE.md](CI-REGRESSION-SCOPE.md): Global regression scope and feature acceptance.
- [CI.md](CI.md): GitHub Actions CI.
- [GLOBAL-CACHES.md](GLOBAL-CACHES.md): Global caches and memory statistics — 0.77a.
- [PORTABILITY.md](PORTABILITY.md): Portability and evidence.
- [PUBLIC-API.md](PUBLIC-API.md): Public API baseline — 0.78c.
- [RELEASE-CANDIDATE-MATRIX.md](RELEASE-CANDIDATE-MATRIX.md): Release candidate matrix — 0.78d.
- [RELEASE-CANDIDATE.md](RELEASE-CANDIDATE.md): Release candidate validation — 0.78d.
- [RELEASE-SCOPE-REVIEW.md](RELEASE-SCOPE-REVIEW.md): 0.78b — Review rationale and maintenance.
- [RELEASE-SCOPE.md](RELEASE-SCOPE.md): Release-scope reconciliation — 0.78b.
- [RESOURCE-LIFETIMES.md](RESOURCE-LIFETIMES.md): Resource lifetimes.
- [SKIASHARP-GAPS.md](SKIASHARP-GAPS.md): SkiaSharp capability inventory — 0.78b.
- [SMALL-GAPS.md](SMALL-GAPS.md): Small remaining gaps — 0.78b.
- [SOURCES.md](SOURCES.md): Primary sources used.

## Native ABI and backend investigations

Pinned ABI notes and investigations explain which native layouts, symbols, and backends are supported. Historical investigations are not new execution receipts.

- [ABI.md](ABI.md): Native ABI and ownership notes.
- [GANESH-CLOSEOUT.md](GANESH-CLOSEOUT.md): Ganesh closeout and Racket drawing compatibility.
- [GPU-ABI.md](GPU-ABI.md): Pinned GPU ABI and source audit.
- [GRAPHITE-FEASIBILITY.md](GRAPHITE-FEASIBILITY.md): Graphite feasibility investigation — 0.47.
- [NATIVE-ABI.md](NATIVE-ABI.md): Native ABI policy and diagnostics — 0.47.
- [NATIVE-MIGRATION-0.47.md](NATIVE-MIGRATION-0.47.md): Native compatibility and migration report — 0.47.
- [PATH-MATRIX-ABI.md](PATH-MATRIX-ABI.md): Pinned path/matrix ABI audit.
- [RUNTIME-ABI.md](RUNTIME-ABI.md): Runtime-effect ABI and ownership.

## Manual and tutorial maintenance

Editorial conventions, manual build procedures, navigation behavior, and tutorial acceptance instructions.

- [DOCUMENTATION-NAVIGATION.md](DOCUMENTATION-NAVIGATION.md): Documentation navigation.
- [REFERENCE-DEVELOPMENT.md](REFERENCE-DEVELOPMENT.md): Skia Reference development: R4g.
- [TUTORIAL-GUIDELINES.md](TUTORIAL-GUIDELINES.md): Tutorial Guidelines.
- [TUTORIALS-16-20-TESTING.md](TUTORIALS-16-20-TESTING.md): Tutorials 16–20: maintainer checks.
- [TUTORIALS-21-22-TESTING.md](TUTORIALS-21-22-TESTING.md): Tutorials 21–22: maintainer checks.

## GPU rendering and interoperability

Backend, ownership, synchronization, presentation, cache, and transfer contracts. Testing companions describe explicitly selected platform acceptance.

- [GPU-BACKENDS.md](GPU-BACKENDS.md): GPU backends and shared validation — 0.52.
- [GPU-CACHE.md](GPU-CACHE.md): GPU cache management — 0.45.
- [GPU-CONTEXT-CONTROLS.md](GPU-CONTEXT-CONTROLS.md): GPU context options and targeted resource operations — 0.77b.
- [GPU-D3D12-INTEROP.md](GPU-D3D12-INTEROP.md): Direct3D external-resource interop — 0.51.
- [GPU-D3D12.md](GPU-D3D12.md): Direct3D 12 offscreen rendering — 0.48.
- [GPU-DC-CONSUMERS.md](GPU-DC-CONSUMERS.md): GPU DC consumer acceptance (0.60).
- [GPU-DC.md](GPU-DC.md): GPU drawing contexts and GUI facade — 0.59.
- [GPU-DIAGNOSTICS.md](GPU-DIAGNOSTICS.md): GPU diagnostics and GL interface selection — 0.77c.
- [GPU-DXGI.md](GPU-DXGI.md): DXGI / D3D12 window presentation — 0.49.
- [GPU-EGL.md](GPU-EGL.md): EGL contexts without a window system.
- [GPU-FORMATS.md](GPU-FORMATS.md): GPU formats and surface properties — 0.73.
- [GPU-FOUNDATION.md](GPU-FOUNDATION.md): GPU contexts and diagnostic rendering.
- [GPU-FRAME-REUSE.md](GPU-FRAME-REUSE.md): GPU frame staging reuse — 0.62.
- [GPU-HEADLESS-TESTING.md](GPU-HEADLESS-TESTING.md): EGL and external GL validation.
- [GPU-IMAGE-TESTING.md](GPU-IMAGE-TESTING.md): GPU image validation.
- [GPU-IMAGES.md](GPU-IMAGES.md): GPU images and retained resource ownership.
- [GPU-INTEROP.md](GPU-INTEROP.md): Borrowing external OpenGL storage.
- [GPU-METAL-INTEROP.md](GPU-METAL-INTEROP.md): Metal external-resource interop — 0.52.
- [GPU-METAL-TESTING.md](GPU-METAL-TESTING.md): Offscreen Metal validation.
- [GPU-METAL.md](GPU-METAL.md): Offscreen Metal rendering.
- [GPU-OFFSCREEN-TESTING.md](GPU-OFFSCREEN-TESTING.md): Offscreen OpenGL validation.
- [GPU-OFFSCREEN.md](GPU-OFFSCREEN.md): Offscreen GPU surfaces.
- [GPU-OUTPUT-TESTING.md](GPU-OUTPUT-TESTING.md): GPU document-output validation.
- [GPU-OUTPUT.md](GPU-OUTPUT.md): GPU execution for bounded output groups.
- [GPU-PERFORMANCE-TESTING.md](GPU-PERFORMANCE-TESTING.md): GPU 0.45 validation and measurement.
- [GPU-PERFORMANCE.md](GPU-PERFORMANCE.md): GPU measurements and release stress — 0.45.
- [GPU-PRESENTATION-TESTING.md](GPU-PRESENTATION-TESTING.md): Unified presentation validation.
- [GPU-PRESENTATION.md](GPU-PRESENTATION.md): GPU window presentation.
- [GPU-RENDER.md](GPU-RENDER.md): Render one image on the GPU.
- [GPU-TESTING.md](GPU-TESTING.md): GPU foundation validation.

## Racket drawing and GUI consumers

Drawing-context compatibility, raster/GPU consumers, GUI canvas lifetimes, and explicit value-conversion bridges.

- [DC-COMPATIBILITY.md](DC-COMPATIBILITY.md): DC compatibility boundary — 0.64.
- [DC-CONSUMERS.md](DC-CONSUMERS.md): Real drawing consumers — 0.56.
- [DC-OUTPUT.md](DC-OUTPUT.md): Shared DC authoring for PDF and SVG — 0.63.
- [DC-STYLES.md](DC-STYLES.md): DC styles and compatibility — 0.57.
- [PICT-BRIDGE.md](PICT-BRIDGE.md): skia/pict — eager pict snapshots.
- [RACKET-DRAW.md](RACKET-DRAW.md): skia/racket-draw — explicit Racket Draw interoperability.
- [RENDER-CANVAS.md](RENDER-CANVAS.md): 0.61 — Unified callback-oriented render canvases.
- [SKIA-CANVAS.md](SKIA-CANVAS.md): Persistent raster GUI canvas — 0.58.
- [SKIA-DC.md](SKIA-DC.md): Skia drawing contexts — 0.57 drawing contract.

## Images, text, geometry, and document output

Feature contracts and their validation companions for the drawing API, codecs, pixels, fonts, streams, and PDF/SVG output.

- [ADVANCED-CANVASES.md](ADVANCED-CANVASES.md): Advanced layers, drawables and specialized canvases — 0.74.
- [ANNOTATION-TESTING.md](ANNOTATION-TESTING.md): Document-link validation — 0.27.
- [ANNOTATIONS.md](ANNOTATIONS.md): Links and document annotations.
- [CANVAS-PRIMITIVES.md](CANVAS-PRIMITIVES.md): Canvas primitives and scoped compositing layers.
- [CANVAS-TESTING.md](CANVAS-TESTING.md): Canvas primitive validation.
- [CODEC-INCREMENTAL.md](CODEC-INCREMENTAL.md): Retained incremental decoding — 0.76c.
- [CODEC-QUERIES.md](CODEC-QUERIES.md): Codec size and subset negotiation — 0.76a.
- [CODEC-SCANLINES.md](CODEC-SCANLINES.md): Native scanline decoding — 0.76b.
- [CODEC-TESTING.md](CODEC-TESTING.md): Advanced codecs: validation and ABI notes.
- [COLOR-OUTPUT-TESTING.md](COLOR-OUTPUT-TESTING.md): Color-output validation — 0.26.0.
- [COLOR-OUTPUT.md](COLOR-OUTPUT.md): Color-managed output.
- [CPU-COLOR-FILTER-TESTING.md](CPU-COLOR-FILTER-TESTING.md): CPU color-filter validation.
- [CPU-COLOR-FILTERS.md](CPU-COLOR-FILTERS.md): CPU color filters.
- [EFFECTS.md](EFFECTS.md): Additional effects and composition — 0.66.
- [FILTER-GRAPHS.md](FILTER-GRAPHS.md): Image-filter graphs.
- [FILTER-TESTING.md](FILTER-TESTING.md): Applying and validating the advanced-filter stage.
- [FLOAT-PIXELS.md](FLOAT-PIXELS.md): Floating-point pixels and colors — 0.71.
- [FONT-QUERIES.md](FONT-QUERIES.md): 0.68b — Font options and glyph queries.
- [GEOMETRY-COMPLETION.md](GEOMETRY-COMPLETION.md): Geometry completion — 0.67.
- [GEOMETRY-PRIMITIVES.md](GEOMETRY-PRIMITIVES.md): Structured geometry and advanced image drawing.
- [GEOMETRY-TESTING.md](GEOMETRY-TESTING.md): Structured geometry validation (0.31).
- [IMAGE-OPERATIONS.md](IMAGE-OPERATIONS.md): Direct image operations — 0.72.
- [INTEGER-PIXELS.md](INTEGER-PIXELS.md): General image information and integer raster storage — 0.70.
- [LIVE-STREAMS.md](LIVE-STREAMS.md): Compiler-free live ports and native publication — 0.75b.
- [OUTPUT-AUDIT-TESTING.md](OUTPUT-AUDIT-TESTING.md): Validating output capabilities and fallback auditing.
- [OUTPUT-AUDIT.md](OUTPUT-AUDIT.md): Output capabilities and fallback auditing.
- [OUTPUT-GUIDE.md](OUTPUT-GUIDE.md): Shared PDF/SVG output — 0.23.0.
- [OUTPUT-TESTING.md](OUTPUT-TESTING.md): Vector-output refinement — application and validation.
- [PATH-MATRIX-TESTING.md](PATH-MATRIX-TESTING.md): Applying and validating 0.24.
- [PATH-MATRIX.md](PATH-MATRIX.md): Path inspection and affine matrices.
- [PDF-OUTPUT.md](PDF-OUTPUT.md): PDF output.
- [PDF-TESTING.md](PDF-TESTING.md): PDF stage: validation and application.
- [PERSISTENT-PICTURES.md](PERSISTENT-PICTURES.md): Persistent pictures and picture shaders.
- [PICTURE-TESTING.md](PICTURE-TESTING.md): Persistent-picture validation.
- [PORTABLE-DRAWING-TESTING.md](PORTABLE-DRAWING-TESTING.md): Portable drawing validation.
- [PORTABLE-DRAWING.md](PORTABLE-DRAWING.md): Portable drawing.
- [PROJECTIVE-MATRICES.md](PROJECTIVE-MATRICES.md): Perspective and general canvas matrices.
- [PROJECTIVE-TESTING.md](PROJECTIVE-TESTING.md): Validating perspective and general matrices.
- [RASTER-BUFFER-TESTING.md](RASTER-BUFFER-TESTING.md): Raster-buffer validation.
- [RASTER-BUFFERS.md](RASTER-BUFFERS.md): Owned raster buffers and scoped pixmaps.
- [RUNTIME-EFFECTS.md](RUNTIME-EFFECTS.md): Runtime effects / SkSL.
- [RUNTIME-TESTING.md](RUNTIME-TESTING.md): Runtime effects: application and validation.
- [STREAMS.md](STREAMS.md): Streams and buffered ports — 0.75a.
- [SVG-OUTPUT.md](SVG-OUTPUT.md): SVG document output.
- [SVG-TESTING.md](SVG-TESTING.md): SVG output: application and validation.
- [TEXT-BLOBS.md](TEXT-BLOBS.md): Multi-run text blobs and shaped text-on-path — 0.69.
- [TYPEFACES.md](TYPEFACES.md): Typeface resources — 0.68a.
