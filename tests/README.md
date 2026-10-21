# Regression tests and shared fixtures

This directory protects public API behavior, native-resource lifetime rules,
and integration with Racket drawing consumers. Matching programs in
[tools](../tools/README.md) produce and inspect acceptance evidence; these modules
supply assertions and shared inputs.

## Choosing a test layer

- `*-pure-test.rkt` checks argument domains, detached values, and injected
  lifecycle models without requiring native Skia rendering.
- `*-native-test.rkt` checks actual native results and ownership. GPU-specific
  suite factories may require contexts supplied by a diagnostic host.
- `*-gpu-test.rkt` executables select a backend and emit tagged evidence. They
  are not software-raster substitutes for real GPU execution.
- `*-gui-test.rkt` requires real windows and an eventspace. A missing display or
  backend is not a successful run.
- `*-fixtures.rkt`, `*-scenes.rkt`, and support files share deterministic inputs.
  Generated fonts are original test fixtures, not copies of installed fonts.

Start with [run-tests.rkt](../run-tests.rkt), which selects the aggregate
[pure suite](pure-test.rkt) or [native suite](native-test.rkt). GUI and
platform-specific workflows are separate; use their validators in
[tools](../tools/README.md).

## Other fixtures

[convertible-scribble-png.scrbl](convertible-scribble-png.scrbl),
[convertible-scribble-svg.scrbl](convertible-scribble-svg.scrbl), and
[convertible-scribble-pdf.scrbl](convertible-scribble-pdf.scrbl) exercise
`file/convertible` inside rendered manuals.
[live-ffi-probe](live-ffi-probe/README.md) isolates live-port callbacks against
an independent native probe.

## Module map

### Core rendering and data

| Module | Coverage or shared inputs |
| --- | --- |
| [advanced-canvas-gpu-test.rkt](advanced-canvas-gpu-test.rkt) | Checks save layers, native drawables, and specialized canvases. |
| [advanced-canvas-native-test.rkt](advanced-canvas-native-test.rkt) | advanced layers, native drawables and specialized canvases. |
| [advanced-canvas-pure-test.rkt](advanced-canvas-pure-test.rkt) | advanced canvases: pure argument, ABI and policy contracts. |
| [annotation-native-test.rkt](annotation-native-test.rkt) | document links and destinations: native backends. |
| [annotation-pure-test.rkt](annotation-pure-test.rkt) | document annotations: pure contracts and SVG finishing. |
| [canvas-native-test.rkt](canvas-native-test.rkt) | canvas primitives: native geometry, queries, and layers. |
| [canvas-pure-test.rkt](canvas-pure-test.rkt) | Canvas primitives: validation and argument-error messages without native loading. |
| [canvas-text-load-order.rkt](canvas-text-load-order.rkt) | Checks Skia and Pango text rendering under different library load orders. |
| [codec-incremental-native-test.rkt](codec-incremental-native-test.rkt) | retained incremental codec, feed framing and pixel ownership. |
| [codec-incremental-pure-test.rkt](codec-incremental-pure-test.rkt) | incremental input framing and detached progress. |
| [codec-native-test.rkt](codec-native-test.rkt) | advanced codecs: native checks. |
| [codec-pure-test.rkt](codec-pure-test.rkt) | advanced codecs: pure checks. |
| [codec-query-native-test.rkt](codec-query-native-test.rkt) | native codec size and subset negotiation. |
| [codec-query-pure-test.rkt](codec-query-pure-test.rkt) | codec query arguments and detached results. |
| [codec-scanline-native-test.rkt](codec-scanline-native-test.rkt) | native scanline decoding and cursor ownership. |
| [codec-scanline-pure-test.rkt](codec-scanline-pure-test.rkt) | pure scanline contracts. |
| [color-filter-native-test.rkt](color-filter-native-test.rkt) | cPU color filters: native results, ownership, and output policy. |
| [color-filter-pure-test.rkt](color-filter-pure-test.rkt) | cPU color filters: validation without native loading. |
| [color-output-native-test.rkt](color-output-native-test.rkt) | color output native regression. |
| [color-output-pure-test.rkt](color-output-pure-test.rkt) | color output: pure values and validation. |
| [convertible-native-test.rkt](convertible-native-test.rkt) | file/convertible live Skia interoperability. |
| [convertible-pure-test.rkt](convertible-pure-test.rkt) | file/convertible dispatch without native loading. |
| [effects-gpu-test.rkt](effects-gpu-test.rkt) | shader masks retain GPU affinity through paint and getters. |
| [effects-native-test.rkt](effects-native-test.rkt) | actual effect pixels and retained inputs. |
| [effects-pure-test.rkt](effects-pure-test.rkt) | effect validation without loading Skia. |
| [filter-graph-native-test.rkt](filter-graph-native-test.rkt) | advanced filter graphs: native pixels, retention, output. |
| [filter-graph-pure-test.rkt](filter-graph-pure-test.rkt) | filter graphs: validation without native loading. |
| [float-pixel-gpu-test.rkt](float-pixel-gpu-test.rkt) | float colors on existing RGBA GPU targets. |
| [float-pixel-native-test.rkt](float-pixel-native-test.rkt) | floating pixels and colors (native). |
| [float-pixel-pure-test.rkt](float-pixel-pure-test.rkt) | floating colors and storage (pure). |
| [font-query-gpu-test.rkt](font-query-gpu-test.rkt) | gPU font mutation, snapshots and batch outlines. |
| [font-query-native-test.rkt](font-query-native-test.rkt) | font options and glyph queries (native). |
| [font-query-pure-test.rkt](font-query-pure-test.rkt) | font queries (pure). |
| [geometry-completion-gpu-test.rkt](geometry-completion-gpu-test.rkt) | gPU geometry and retained paint reset. |
| [geometry-completion-native-test.rkt](geometry-completion-native-test.rkt) | native path, region, rounded-rectangle and paint geometry. |
| [geometry-completion-pure-test.rkt](geometry-completion-pure-test.rkt) | pure geometry domains and paint provenance. |
| [geometry-native-test.rkt](geometry-native-test.rkt) | structured geometry and advanced image drawing: native backends. |
| [geometry-pure-test.rkt](geometry-pure-test.rkt) | structured geometry: pure contracts and immutable specifications. |
| [global-cache-native-test.rkt](global-cache-native-test.rkt) | native global caches and memory statistics. |
| [global-cache-pure-test.rkt](global-cache-pure-test.rkt) | global cache values and bounded memory collector. |
| [image-operation-gpu-test.rkt](image-operation-gpu-test.rkt) | direct GPU image operations. |
| [image-operation-native-test.rkt](image-operation-native-test.rkt) | direct image operations (native). |
| [image-operation-pure-test.rkt](image-operation-pure-test.rkt) | direct image operations (pure). |
| [integer-pixel-gpu-test.rkt](integer-pixel-gpu-test.rkt) | integer storage -> explicit RGBA upload -> GPU draw/readback. |
| [integer-pixel-native-test.rkt](integer-pixel-native-test.rkt) | general integer pixel storage (native). |
| [integer-pixel-pure-test.rkt](integer-pixel-pure-test.rkt) | image information and integer samples (pure). |
| [lifetime-test.rkt](lifetime-test.rkt) | ownership and scoped cleanup (no native library). |
| [live-stream-native-test.rkt](live-stream-native-test.rkt) | live ports and native consumers; real Skia required. |
| [live-stream-pure-test.rkt](live-stream-pure-test.rkt) | live port utilities; no native execution. |
| [native-test.rkt](native-test.rkt) | Checks actual rendering, fonts, image encoding, resource lifetime, and the integrated native API. |
| [output-audit-native-test.rkt](output-audit-native-test.rkt) | output capability audit: actual drawing wrappers. |
| [output-audit-pure-test.rkt](output-audit-pure-test.rkt) | output audit: pure policies and provenance. |
| [output-group-native-test.rkt](output-group-native-test.rkt) | bounded output groups: native backends. |
| [output-group-pure-test.rkt](output-group-pure-test.rkt) | bounded output groups: pure decisions. |
| [output-native-test.rkt](output-native-test.rkt) | shared vector output: live rendering and lifetime. |
| [output-pure-test.rkt](output-pure-test.rkt) | shared vector output: pure contracts. |
| [path-matrix-native-test.rkt](path-matrix-native-test.rkt) | path inspection and affine native boundaries. |
| [path-matrix-pure-test.rkt](path-matrix-pure-test.rkt) | affine matrix values and path/matrix validation. |
| [pdf-native-test.rkt](pdf-native-test.rkt) | pDF documents and borrowed page canvases. |
| [pdf-pure-test.rkt](pdf-pure-test.rkt) | pDF pure validation and ABI. |
| [pict-native-test.rkt](pict-native-test.rkt) | skia/pict eager CPU snapshots. |
| [pict-pure-test.rkt](pict-pure-test.rkt) | skia/pict pure validation and explicit-transfer boundaries. |
| [picture-native-test.rkt](picture-native-test.rkt) | persistent pictures: native streams, retained resources, spatial indexing, and audit. |
| [picture-pure-test.rkt](picture-pure-test.rkt) | persistent pictures: bounded framing, file publication, and conservative policy. |
| [portable-native-test.rkt](portable-native-test.rkt) | portable drawing: native resources and vector backends. |
| [portable-pure-test.rkt](portable-pure-test.rkt) | portable drawing: plans and validation. |
| [projective-native-test.rkt](projective-native-test.rkt) | general canvas matrices: native storage, lifetime, and document policies. |
| [projective-pure-test.rkt](projective-pure-test.rkt) | perspective and general matrices: pure values and audit policy. |
| [pure-test.rkt](pure-test.rkt) | Combines source-only validation suites across the public API and implementation helpers. |
| [racket-draw-native-test.rkt](racket-draw-native-test.rkt) | skia/racket-draw owned raster and vector conversions. |
| [racket-draw-pure-test.rkt](racket-draw-pure-test.rkt) | skia/racket-draw pure boundary and detached conversions. |
| [raster-buffer-native-test.rkt](raster-buffer-native-test.rkt) | raster buffers: native storage, scoped borrowing, and snapshots. |
| [raster-buffer-pure-test.rkt](raster-buffer-pure-test.rkt) | raster storage: checked layout and detached input. |
| [runtime-native-test.rkt](runtime-native-test.rkt) | runtime effects: native compilation, rendering, and ownership. |
| [runtime-pure-test.rkt](runtime-pure-test.rkt) | runtime effects: pure validation and uniform packing. |
| [small-gap-native-test.rkt](small-gap-native-test.rkt) | small-gap native acceptance. |
| [small-gap-pure-test.rkt](small-gap-pure-test.rkt) | small-gap pure contracts. |
| [stream-native-test.rkt](stream-native-test.rkt) | native streams and buffered port consumers. |
| [stream-pure-test.rkt](stream-pure-test.rkt) | stream buffers (pure Racket; no native callbacks). |
| [svg-native-test.rkt](svg-native-test.rkt) | sVG native document output. |
| [svg-pure-test.rkt](svg-pure-test.rkt) | sVG pure validation and serialization. |
| [text-blob-gpu-test.rkt](text-blob-gpu-test.rkt) | retained multi-run text on the selected GPU backend. |
| [text-blob-native-test.rkt](text-blob-native-test.rkt) | multi-run text blobs (native). |
| [text-blob-pure-test.rkt](text-blob-pure-test.rkt) | multi-run text blobs (pure). |
| [typeface-native-test.rkt](typeface-native-test.rkt) | native typeface resources, metadata and detached data. |
| [typeface-pure-test.rkt](typeface-pure-test.rkt) | pure typeface values, ranges and original generated fixtures. |

### Drawing contexts and GUI integration

| Module | Coverage or shared inputs |
| --- | --- |
| [canvas-dc-native-test.rkt](canvas-dc-native-test.rkt) | canvas backing storage and native Skia-to-bitmap transfer (no GUI). |
| [canvas-dc-pure-test.rkt](canvas-dc-pure-test.rkt) | canvas DC ownership, resizing, paint recovery and direct pixel bridge (headless). |
| [canvas-gui-test.rkt](canvas-gui-test.rkt) | required real-window Skia canvas eventspace, exposure and lifecycle tests. |
| [dc-alpha-test.rkt](dc-alpha-test.rkt) | Checks isolated alpha groups and renderer failure cleanup. |
| [dc-closure-native-test.rkt](dc-closure-native-test.rkt) | native font-description and DC compatibility acceptance. |
| [dc-closure-pure-test.rkt](dc-closure-pure-test.rkt) | declared DC contract, font translation and single-line boundaries. |
| [dc-compat-native-test.rkt](dc-compat-native-test.rkt) | skia DC text, bitmap and region native execution. |
| [dc-compat-pure-test.rkt](dc-compat-pure-test.rkt) | dC compatibility contracts; recording renderer, no Skia pixels. |
| [dc-consumer-native-test.rkt](dc-consumer-native-test.rkt) | direct pict and plot/no-gui consumers on the existing Skia DC subset. |
| [dc-native-test.rkt](dc-native-test.rkt) | skia-dc persistent CPU raster native tests. |
| [dc-output-native-test.rkt](dc-output-native-test.rkt) | shared authoring on actual PDF, SVG and raster output canvases. |
| [dc-output-pure-test.rkt](dc-output-pure-test.rkt) | document DC capture, lifetime and explicit pixel boundary. |
| [dc-pure-test.rkt](dc-pure-test.rkt) | skia-dc foundation (recording renderer; no Skia pixels). |
| [dc-replay-native-test.rkt](dc-replay-native-test.rkt) | dC recorded replay and isolated raster alpha groups (native Skia pixels). |
| [dc-replay-pure-test.rkt](dc-replay-pure-test.rkt) | dC replay, locking and alpha protocol (recording renderer; no Skia pixels). |
| [dc-style-math-test.rkt](dc-style-math-test.rkt) | Checks gradient, stipple, and hatch coordinate calculations. |
| [dc-style-native-test.rkt](dc-style-native-test.rkt) | dC native styles and compatibility queries. |
| [dc-style-pure-test.rkt](dc-style-pure-test.rkt) | dC style preparation without Skia. |
| [racket-draw-consumer-test.rkt](racket-draw-consumer-test.rkt) | skia/racket-draw ordinary consumer integration. |
| [render-canvas-gui-test.rkt](render-canvas-gui-test.rkt) | unified callback API on real raster and GPU canvas% objects. |
| [render-canvas-pure-test.rkt](render-canvas-pure-test.rkt) | unified canvas declarative selection and callback scope; no GUI or native code. |

### GPU lifecycle, rendering, and presentation

| Module | Coverage or shared inputs |
| --- | --- |
| [gpu-backends-pure-test.rkt](gpu-backends-pure-test.rkt) | source-only backend policy and production output/metadata boundaries. |
| [gpu-cache-native-test.rkt](gpu-cache-native-test.rkt) | live GPU cache control. |
| [gpu-cache-pure-test.rkt](gpu-cache-pure-test.rkt) | Checks context-local GPU cache limits and resource accounting. |
| [gpu-context-control-gpu-test.rkt](gpu-context-control-gpu-test.rkt) | Checks GPU context options, flush controls, and context lifecycle. |
| [gpu-context-control-native-test.rkt](gpu-context-control-native-test.rkt) | gPU context control ABI and symbol resolution (no GPU execution). |
| [gpu-context-control-pure-test.rkt](gpu-context-control-pure-test.rkt) | gPU context options and pure lifecycle. |
| [gpu-cross-backend-native-test.rkt](gpu-cross-backend-native-test.rkt) | actual OpenGL/Metal separation and explicit two-way transfer. |
| [gpu-d3d12-pure-test.rkt](gpu-d3d12-pure-test.rkt) | d3D12 ownership and ABI without native libraries. |
| [gpu-dc-gui-test.rkt](gpu-dc-gui-test.rkt) | real-window GPU DC facade and eventspace lifetime. |
| [gpu-dc-native-test.rkt](gpu-dc-native-test.rkt) | native Ganesh GPU DC: coordinates, residency, transfer and frame lifetime. |
| [gpu-dc-pure-test.rkt](gpu-dc-pure-test.rkt) | frame-scoped GPU DC state, scaling and lifetime (no native renderer). |
| [gpu-diagnostics-gpu-test.rkt](gpu-diagnostics-gpu-test.rkt) | Checks GPU capabilities, GL interfaces, and bounded memory diagnostics. |
| [gpu-diagnostics-native-test.rkt](gpu-diagnostics-native-test.rkt) | gPU diagnostic ABI and shared collector (GPU execution separate). |
| [gpu-diagnostics-pure-test.rkt](gpu-diagnostics-pure-test.rkt) | gPU diagnostics: native-free contracts and ownership doubles. |
| [gpu-dxgi-pure-test.rkt](gpu-dxgi-pure-test.rkt) | dXGI policy and shared presenter semantics; no Windows/Skia calls. |
| [gpu-egl-native-test.rkt](gpu-egl-native-test.rkt) | eGL native ownership and true headless contexts. |
| [gpu-egl-pure-test.rkt](gpu-egl-pure-test.rkt) | eGL ownership, callback scopes and GL interop contracts. |
| [gpu-format-gpu-test.rkt](gpu-format-gpu-test.rkt) | Checks GPU surface formats, surface properties, and explicit readback. |
| [gpu-format-native-test.rkt](gpu-format-native-test.rkt) | surface properties (native; no GPU required). |
| [gpu-format-pure-test.rkt](gpu-format-pure-test.rkt) | gPU format and surface property contracts (pure). |
| [gpu-frame-target-native-test.rkt](gpu-frame-target-native-test.rkt) | cached GPU frame staging: constructor reduction, pixels and retirement. |
| [gpu-frame-target-pure-test.rkt](gpu-frame-target-pure-test.rkt) | presenter staging target cache: bounded ownership and single-use scopes. |
| [gpu-gl-interop-native-test.rkt](gpu-gl-interop-native-test.rkt) | external GL: borrowed framebuffer, owned texture copy and state handoff. |
| [gpu-image-native-test.rkt](gpu-image-native-test.rkt) | gPU images: live uploads, snapshots, transitive graphs, and explicit transfers. |
| [gpu-image-pure-test.rkt](gpu-image-pure-test.rkt) | gPU images: pure transitive affinity, setters, recording and deferred ownership. |
| [gpu-interop-native-test.rkt](gpu-interop-native-test.rkt) | real D3D12 producer, Skia handoff, independent consumer. |
| [gpu-interop-pure-test.rkt](gpu-interop-pure-test.rkt) | external resource handoff contracts; no Windows/native loading. |
| [gpu-metal-interop-native-test.rkt](gpu-metal-interop-native-test.rkt) | independent Metal producer, Skia handoff and consumer. |
| [gpu-metal-interop-pure-test.rkt](gpu-metal-interop-pure-test.rkt) | metal external-resource contracts without native/GUI loading. |
| [gpu-metal-native-test.rkt](gpu-metal-native-test.rkt) | metal-specific owned queue, scope, GC, and abandonment. |
| [gpu-metal-pure-test.rkt](gpu-metal-pure-test.rkt) | metal ownership and native-call scopes: pure mocked operations. |
| [gpu-output-native-test.rkt](gpu-output-native-test.rkt) | bounded GPU document fallbacks with unchanged representation policies. |
| [gpu-output-pure-test.rkt](gpu-output-pure-test.rkt) | gPU document execution: pure protocol, lazy ownership and scoped audit. |
| [gpu-performance-pure-test.rkt](gpu-performance-pure-test.rkt) | Checks GPU timing, frame reuse, and deferred-release measurements. |
| [gpu-presenter-native-test.rkt](gpu-presenter-native-test.rkt) | live shared presenter/frame API (submission, not visible-pixel certification). |
| [gpu-presenter-pure-test.rkt](gpu-presenter-pure-test.rkt) | presentation lifecycle and scheduling with synthetic adapters. |
| [gpu-pure-test.rkt](gpu-pure-test.rkt) | gPU foundation: pure mock-provider, ownership, lifecycle, and ABI tests. |
| [gpu-render-native-test.rkt](gpu-render-native-test.rkt) | one-shot GPU render on the explicitly selected backend. |
| [gpu-render-pure-test.rkt](gpu-render-pure-test.rkt) | one-shot GPU render: arguments and lifetime worker. |
| [gpu-surface-native-test.rkt](gpu-surface-native-test.rkt) | gPU surfaces: live Ganesh drawing, leases, submission, and transfers. |
| [gpu-surface-pure-test.rkt](gpu-surface-pure-test.rkt) | gPU surfaces: pure options, generic handles, and activation leases. |

### API and release boundaries

| Module | Coverage or shared inputs |
| --- | --- |
| [native-abi-native-test.rkt](native-abi-native-test.rkt) | native ABI diagnostics on the accepted library. |
| [native-abi-pure-test.rkt](native-abi-pure-test.rkt) | native ABI policy (no native library). |
| [public-api-pure-test.rkt](public-api-pure-test.rkt) | public API reflection. |
| [release-scope-pure-test.rkt](release-scope-pure-test.rkt) | release-scope Color4f equivalent (pure Racket). |

### Shared fixtures and support

| Module | Coverage or shared inputs |
| --- | --- |
| [advanced-canvas-fixtures.rkt](advanced-canvas-fixtures.rkt) | Shared fixtures for save layers, native drawables, and specialized canvases. |
| [codec-fixtures.rkt](codec-fixtures.rkt) | Shared fixtures for animation decoding, frame disposal, and encoded image orientation. |
| [codec-incremental-fixtures.rkt](codec-incremental-fixtures.rkt) | Shared fixtures for incremental PNG feeding, decode progress, and detached snapshots. |
| [codec-query-fixtures.rkt](codec-query-fixtures.rkt) | Shared fixtures for native codec scaling and subset negotiation. |
| [codec-scanline-fixtures.rkt](codec-scanline-fixtures.rkt) | Shared fixtures for scanline decoding, encoded row order, and cursor ownership. |
| [color-filter-fixtures.rkt](color-filter-fixtures.rkt) | Shared fixtures for HSLA, gamma, lookup-table, and composed color filters. |
| [color-output-fixtures.rkt](color-output-fixtures.rkt) | Shared fixtures for ICC profiles, transfer functions, and color-preserving image output. |
| [d3d12-interop-fixture.rkt](d3d12-interop-fixture.rkt) | Loads the independent Windows texture producer and exposes its checked C entry points. |
| [dc-consumer-fixtures.rkt](dc-consumer-fixtures.rkt) | Shared fixtures for pict, plot/no-gui, and recorded drawing consumers. |
| [dc-output-fixtures.rkt](dc-output-fixtures.rkt) | Shared fixtures for shared DC authoring on raster, PDF, and SVG output canvases. |
| [dc-style-fixtures.rkt](dc-style-fixtures.rkt) | Shared fixtures for DC brush styles, gradients, stipples, and compatibility queries. |
| [effects-fixtures.rkt](effects-fixtures.rkt) | Shared fixtures for path effects, mask filters, noise, and programmable blending. |
| [float-pixel-fixtures.rkt](float-pixel-fixtures.rkt) | Shared fixtures for floating-point pixel storage, colors, and conversion. |
| [font-query-fixtures.rkt](font-query-fixtures.rkt) | Shared fixtures for font mutation, glyph metrics, and detached outline queries. |
| [geometry-completion-fixtures.rkt](geometry-completion-fixtures.rkt) | Shared fixtures for arc construction, path operations, rounded rectangles, and regions. |
| [global-cache-support.rkt](global-cache-support.rkt) | Shared fixtures for global font/resource cache controls and bounded memory statistics. |
| [gpu-dc-consumer-fixtures.rkt](gpu-dc-consumer-fixtures.rkt) | Shared fixtures for pict, plot, and recorded drawing on frame-scoped GPU DCs. |
| [gpu-fixtures.rkt](gpu-fixtures.rkt) | Shared fixtures for GPU domains, thread affinity, deferred release, and abandonment. |
| [gpu-gl-fixtures.rkt](gpu-gl-fixtures.rkt) | Shared fixtures for independently owned OpenGL textures and framebuffer fixtures. |
| [gpu-metal-fixtures.rkt](gpu-metal-fixtures.rkt) | Shared fixtures for Metal device/queue ownership, activation scopes, and abandonment. |
| [gpu-output-fixtures.rkt](gpu-output-fixtures.rkt) | Shared fixtures for bounded GPU raster fallbacks within vector documents. |
| [image-operation-fixtures.rkt](image-operation-fixtures.rkt) | Shared fixtures for image filtering, subsets, placement offsets, and raw pixel access. |
| [integer-pixel-fixtures.rkt](integer-pixel-fixtures.rkt) | Shared fixtures for integer pixel formats, channel packing, and padded row storage. |
| [metal-interop-fixture.rkt](metal-interop-fixture.rkt) | Wraps the independent Objective-C texture producer, including readback and explicit closure. |
| [portable-fixtures.rkt](portable-fixtures.rkt) | Shared fixtures for portable image drawing and bounded vector-output alternatives. |
| [public-api-fixture.rkt](public-api-fixture.rkt) | Shared fixtures for export reflection, arities, keywords, and public API inventory. |
| [runtime-fixtures.rkt](runtime-fixtures.rkt) | Shared fixtures for SkSL runtime effects, uniform packing, and retained child effects. |
| [text-blob-fixtures.rkt](text-blob-fixtures.rkt) | Shared fixtures for retained text runs, glyph positions, clusters, and serialization. |
| [text-blob-scenes.rkt](text-blob-scenes.rkt) | Shared fixtures for retained text runs, glyph positions, clusters, and serialization. |
| [typeface-fixtures.rkt](typeface-fixtures.rkt) | Shared fixtures for deterministic font fixtures, font tables, and typeface ownership. |
