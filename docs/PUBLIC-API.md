# Public API baseline — 0.78c

<!-- Generated from checked-in public-api snapshots, not from source regexes. -->

Baseline: `cc6e63c3e14a9059b326f515ee01fd2b582c123f`. Package version: **0.78**.

This is an exact export/call-boundary baseline, **not a 1.0 release approval**, an overload-parity claim, or native/backend execution evidence.

See [ownership, errors and output contracts](API-CONTRACTS.md). Stable means a compatibility commitment for the reviewed API surface; experimental exports remain explicitly tracked, not silently omitted.

Nonzero phases and binding spaces are inventoried by name. Macro grammars, class constructor arguments/method arities, constant contents, defaults, return-value contracts and numerical/rendering semantics are not inferred by reflection. Existing class/consumer and native acceptance tests remain necessary.

Experimental names retain that label through convenience re-exports.

## Module policy

| Module | Default stability | Import group |
|---|---|---|
| `advanced-layers.rkt` | stable | headless |
| `annotations.rkt` | stable | headless |
| `bitmap.rkt` | stable | headless |
| `canvas-matrix.rkt` | stable | headless |
| `canvas-primitives.rkt` | stable | headless |
| `canvas.rkt` | experimental | gui |
| `codec-incremental.rkt` | stable | headless |
| `codec-queries.rkt` | stable | headless |
| `codec-scanlines.rkt` | stable | headless |
| `color-filters.rkt` | stable | headless |
| `color-space.rkt` | stable | headless |
| `color.rkt` | stable | headless |
| `color4f.rkt` | stable | headless |
| `dc-output.rkt` | experimental | headless |
| `dc.rkt` | experimental | headless |
| `drawables.rkt` | stable | headless |
| `effects.rkt` | stable | headless |
| `file-streams.rkt` | stable | headless |
| `float-colors.rkt` | stable | headless |
| `fonts.rkt` | stable | headless |
| `geometry-primitives.rkt` | stable | headless |
| `geometry.rkt` | stable | headless |
| `gpu-canvas.rkt` | experimental | gui |
| `gpu-context-options.rkt` | experimental | headless |
| `gpu-dc.rkt` | experimental | headless |
| `gpu-diagnostics.rkt` | experimental | headless |
| `gpu-egl.rkt` | experimental | headless |
| `gpu-gl-interop.rkt` | experimental | headless |
| `gpu-gui.rkt` | experimental | gui |
| `gpu-interop.rkt` | experimental | headless |
| `gpu-output.rkt` | experimental | headless |
| `gpu-racket-gl.rkt` | experimental | gui |
| `gpu.rkt` | experimental | headless |
| `graphics.rkt` | stable | headless |
| `image-info.rkt` | stable | headless |
| `image-operations.rkt` | stable | headless |
| `layer-options.rkt` | stable | headless |
| `live-streams.rkt` | stable | headless |
| `main.rkt` | stable | headless |
| `matrix.rkt` | stable | headless |
| `native-capabilities.rkt` | stable | headless |
| `output-audit.rkt` | stable | headless |
| `output-groups.rkt` | stable | headless |
| `output-policy.rkt` | stable | headless |
| `output.rkt` | stable | headless |
| `pictures.rkt` | stable | headless |
| `portable-drawing.rkt` | stable | headless |
| `projective-matrix.rkt` | stable | headless |
| `raster-buffers.rkt` | stable | headless |
| `render-canvas.rkt` | experimental | gui |
| `runtime-effects.rkt` | stable | headless |
| `specialized-canvases.rkt` | stable | headless |
| `stream-inputs.rkt` | stable | headless |
| `streams.rkt` | stable | headless |
| `surface-properties.rkt` | stable | headless |
| `text-blobs.rkt` | stable | headless |
| `typefaces.rkt` | stable | headless |
| `unsafe/gpu-d3d12.rkt` | experimental | headless |
| `unsafe/gpu-metal.rkt` | experimental | headless |

## Headless exports

### advanced-layers.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| call-with-canvas-layer-rec | stable | 0 | procedure | 2 | none | #:backdrop, #:clip, #:options, #:paint |
| canvas-discard! | stable | 0 | procedure | 1 | none | none |
| canvas-save-layer-rec! | stable | 0 | procedure | 1 | none | #:backdrop, #:options, #:paint |
### annotations.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| canvas-annotate-url! | stable | 0 | procedure | 6 | none | none |
| canvas-annotation-backend | stable | 0 | procedure | 1 | none | none |
| canvas-define-destination! | stable | 0 | procedure | 4 | none | none |
| canvas-link-destination! | stable | 0 | procedure | 6 | none | none |
| destination-id | stable | 0 | procedure | 1 | none | none |
| svg-destination-id | stable | 0 | procedure | 1 | none | #:id-prefix |
### bitmap.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| image->bitmap | stable | 0 | procedure | 1 | none | none |
| surface->bitmap | stable | 0 | procedure | 1 | none | none |
### canvas-matrix.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| call-with-canvas-matrix | stable | 0 | procedure | 3 | none | #:replace? |
| canvas-concat-matrix3! | stable | 0 | procedure | 2 | none | none |
| canvas-concat-matrix4! | stable | 0 | procedure | 2 | none | none |
| canvas-matrix4 | stable | 0 | procedure | 1 | none | none |
| canvas-set-matrix3! | stable | 0 | procedure | 2 | none | none |
| canvas-set-matrix4! | stable | 0 | procedure | 2 | none | none |
| with-canvas-matrix | stable | 0 | syntax | — | — | — |
### canvas-primitives.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| call-with-canvas-layer | stable | 0 | procedure | 2 | none | #:bounds, #:paint |
| canvas-clip-empty? | stable | 0 | procedure | 1 | none | none |
| canvas-clip-rect? | stable | 0 | procedure | 1 | none | none |
| canvas-clip-rounded-rect! | stable | 0 | procedure | 2 | none | #:antialias?, #:operation |
| canvas-device-clip-bounds | stable | 0 | procedure | 1 | none | none |
| canvas-local-clip-bounds | stable | 0 | procedure | 1 | none | none |
| canvas-quick-reject? | stable | 0 | procedure | 5 | none | none |
| canvas-save-layer! | stable | 0 | procedure | 1 | none | #:bounds, #:paint |
| draw-arc | stable | 0 | procedure | 8 | none | #:use-center? |
| draw-color | stable | 0 | procedure | 2 | none | #:blend-mode |
| draw-double-rounded-rect | stable | 0 | procedure | 4 | none | none |
| draw-point | stable | 0 | procedure | 4 | none | none |
| draw-points | stable | 0 | procedure | 3 | none | #:mode |
| draw-rrect | stable | 0 | procedure | 3 | none | none |
| make-rounded-rect | stable | 0 | procedure | 4 | none | #:radii |
| rounded-rect-bounds | stable | 0 | procedure | 1 | none | none |
| rounded-rect-radii | stable | 0 | procedure | 1 | none | none |
| rounded-rect? | stable | 0 | procedure | 1 | none | none |
| with-canvas-layer | stable | 0 | syntax | — | — | — |
### codec-incremental.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| codec-incremental-cancel! | stable | 0 | procedure | 1 | none | none |
| codec-incremental-feed! | stable | 0 | procedure | 2 | none | #:final? |
| codec-incremental-info | stable | 0 | procedure | 1 | none | none |
| codec-incremental-origin | stable | 0 | procedure | 1 | none | none |
| codec-incremental-session? | stable | 0 | procedure | 1 | none | none |
| codec-incremental-snapshot | stable | 0 | procedure | 1 | none | none |
| codec-incremental-state | stable | 0 | procedure | 1 | none | none |
| codec-incremental-statistics | stable | 0 | procedure | 1 | none | none |
| codec-incremental-step! | stable | 0 | procedure | 1 | none | #:cancel-evt |
| incremental-progress-initialized-rows | stable | 0 | procedure | 1 | none | none |
| incremental-progress-result | stable | 0 | procedure | 1 | none | none |
| incremental-progress-state | stable | 0 | procedure | 1 | none | none |
| incremental-progress? | stable | 0 | procedure | 1 | none | none |
| incremental-snapshot->raster-buffer | stable | 0 | procedure | 1 | none | none |
| incremental-snapshot-bytes | stable | 0 | procedure | 1 | none | none |
| incremental-snapshot-info | stable | 0 | procedure | 1 | none | none |
| incremental-snapshot-progress | stable | 0 | procedure | 1 | none | none |
| incremental-snapshot-row-bytes | stable | 0 | procedure | 1 | none | none |
| incremental-snapshot? | stable | 0 | procedure | 1 | none | none |
| make-codec-incremental | stable | 0 | procedure | 0 | none | #:alpha-type, #:color-space, #:color-type, #:limit, #:row-bytes |
### codec-queries.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| codec-scaled-dimensions | stable | 0 | procedure | 2 | none | none |
| codec-supported-subset | stable | 0 | procedure | 5 | none | none |
### codec-scanlines.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| codec-scanline-from-bytes | stable | 0 | procedure | 1 | none | #:alpha-type, #:color-space, #:color-type, #:scale |
| codec-scanline-from-port/buffered | stable | 0 | procedure | 1 | none | #:alpha-type, #:cancel-evt, #:close?, #:color-space, #:color-type, #:limit, #:scale |
| codec-scanline-from-stream | stable | 0 | procedure | 1 | none | #:alpha-type, #:color-space, #:color-type, #:scale |
| codec-scanline-info | stable | 0 | procedure | 1 | none | none |
| codec-scanline-next-row | stable | 0 | procedure | 1 | none | none |
| codec-scanline-order | stable | 0 | procedure | 1 | none | none |
| codec-scanline-output-row | stable | 0 | procedure | 2 | none | none |
| codec-scanline-position | stable | 0 | procedure | 1 | none | none |
| codec-scanline-read! | stable | 0 | procedure | 1, 2 | none | #:row-bytes |
| codec-scanline-session? | stable | 0 | procedure | 1 | none | none |
| codec-scanline-skip! | stable | 0 | procedure | 2 | none | none |
| codec-scanline-source-info | stable | 0 | procedure | 1 | none | none |
| codec-scanline-state | stable | 0 | procedure | 1 | none | none |
| exn:fail:codec-scanline-native-code | stable | 0 | procedure | 1 | none | none |
| exn:fail:codec-scanline-result | stable | 0 | procedure | 1 | none | none |
| exn:fail:codec-scanline? | stable | 0 | procedure | 1 | none | none |
| scanline-batch->raster-buffer | stable | 0 | procedure | 1 | none | none |
| scanline-batch-bytes | stable | 0 | procedure | 1 | none | none |
| scanline-batch-complete? | stable | 0 | procedure | 1 | none | none |
| scanline-batch-decoded-count | stable | 0 | procedure | 1 | none | none |
| scanline-batch-first-row | stable | 0 | procedure | 1 | none | none |
| scanline-batch-info | stable | 0 | procedure | 1 | none | none |
| scanline-batch-requested-count | stable | 0 | procedure | 1 | none | none |
| scanline-batch-row-bytes | stable | 0 | procedure | 1 | none | none |
| scanline-batch? | stable | 0 | procedure | 1 | none | none |
### color-filters.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| make-high-contrast-color-filter | stable | 0 | procedure | 0 | none | #:contrast, #:grayscale?, #:invert-style |
| make-hsla-matrix-filter | stable | 0 | procedure | 1 | none | none |
| make-lerp-color-filter | stable | 0 | procedure | 3 | none | none |
| make-lighting-color-filter | stable | 0 | procedure | 2 | none | none |
| make-linear-to-srgb-gamma-color-filter | stable | 0 | procedure | 0 | none | none |
| make-luma-color-filter | stable | 0 | procedure | 0 | none | none |
| make-srgb-to-linear-gamma-color-filter | stable | 0 | procedure | 0 | none | none |
| make-table-argb-color-filter | stable | 0 | procedure | 0 | none | #:alpha, #:blue, #:green, #:red |
| make-table-color-filter | stable | 0 | procedure | 1 | none | none |
### color-space.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| color-space-transfer-function | stable | 0 | procedure | 1 | none | none |
| color-space-xyz-d50 | stable | 0 | procedure | 1 | none | none |
| make-rgb-color-space | stable | 0 | procedure | 2 | none | none |
| make-transfer-function | stable | 0 | procedure | 7 | none | none |
| named-transfer-function | stable | 0 | procedure | 1 | none | none |
| named-xyz-d50 | stable | 0 | procedure | 1 | none | none |
| primaries->xyz-d50 | stable | 0 | procedure | 4 | none | none |
| transfer-function-coefficients | stable | 0 | procedure | 1 | none | none |
| transfer-function-evaluate | stable | 0 | procedure | 2 | none | none |
| transfer-function-invert | stable | 0 | procedure | 1 | none | none |
| transfer-function? | stable | 0 | procedure | 1 | none | none |
| xyz-d50-concat | stable | 0 | procedure | 2 | none | none |
| xyz-d50-invert | stable | 0 | procedure | 1 | none | none |
### color.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| color->argb | stable | 0 | procedure | 1 | none | none |
| color->rgba | stable | 0 | procedure | 1 | none | none |
| color? | stable | 0 | procedure | 1 | none | none |
| rgb | stable | 0 | procedure | 3 | none | none |
| rgba | stable | 0 | procedure | 4 | none | none |
| rgba-alpha | stable | 0 | procedure | 1 | none | none |
| rgba-blue | stable | 0 | procedure | 1 | none | none |
| rgba-green | stable | 0 | procedure | 1 | none | none |
| rgba-red | stable | 0 | procedure | 1 | none | none |
| rgba? | stable | 0 | procedure | 1 | none | none |
| struct:rgba | stable | 0 | value | — | — | — |
### color4f.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| color->color4f | stable | 0 | procedure | 1 | none | none |
| color4f->rgba | stable | 0 | procedure | 1 | none | #:out-of-range |
| color4f->vector | stable | 0 | procedure | 1 | none | none |
| color4f-alpha | stable | 0 | procedure | 1 | none | none |
| color4f-blue | stable | 0 | procedure | 1 | none | none |
| color4f-green | stable | 0 | procedure | 1 | none | none |
| color4f-red | stable | 0 | procedure | 1 | none | none |
| color4f? | stable | 0 | procedure | 1 | none | none |
| make-color4f | stable | 0 | procedure | 3, 4 | none | none |
### dc-output.rkt

Experimental optional execution/integration API; existing backend, owner-thread and document restrictions remain unchanged.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| call-with-output-dc | experimental | 0 | procedure | 4 | none | #:background, #:policy, #:raster-scale, #:smoothing, #:text-mode |
| current-output-dc-command-limit | experimental | 0 | parameter | 0, 1 | none | none |
| dc-annotate-url! | experimental | 0 | procedure | 6 | none | none |
| dc-define-destination! | experimental | 0 | procedure | 4 | none | none |
| dc-link-destination! | experimental | 0 | procedure | 6 | none | none |
| draw-dc-raster-group | experimental | 0 | procedure | 6 | none | #:label, #:scale |
| make-dc-output-page | experimental | 0 | procedure | 3 | none | #:background, #:margins, #:on-report, #:policy, #:smoothing, #:unit |
| output-dc-capabilities | experimental | 0 | procedure | 0 | none | none |
| skia-output-dc? | experimental | 0 | procedure | 1 | none | none |
### dc.rkt

Experimental optional execution/integration API; existing backend, owner-thread and document restrictions remain unchanged.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| exn:fail:skia-dc:unsupported | experimental | 0 | procedure | 5 | none | none |
| exn:fail:skia-dc:unsupported-feature | experimental | 0 | procedure | 1 | none | none |
| exn:fail:skia-dc:unsupported-method | experimental | 0 | procedure | 1 | none | none |
| exn:fail:skia-dc:unsupported-stage | experimental | 0 | procedure | 1 | none | none |
| exn:fail:skia-dc:unsupported? | experimental | 0 | procedure | 1 | none | none |
| skia-dc% | experimental | 0 | class | — | — | — |
| skia-dc-capabilities | experimental | 0 | procedure | 0 | none | none |
| skia-dc-compatibility | experimental | 0 | procedure | 0, 1 | none | none |
| skia-dc? | experimental | 0 | procedure | 1 | none | none |
| struct:exn:fail:skia-dc:unsupported | experimental | 0 | value | — | — | — |
### drawables.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| call-with-drawable | stable | 0 | procedure | 3 | none | none |
| draw-drawable | stable | 0 | procedure | 2 | none | #:matrix, #:mode |
| drawable->picture | stable | 0 | procedure | 1 | none | none |
| drawable-approximate-bytes-used | stable | 0 | procedure | 1 | none | none |
| drawable-bounds | stable | 0 | procedure | 1 | none | none |
| drawable-generation-id | stable | 0 | procedure | 1 | none | none |
| drawable-notify-drawing-changed! | stable | 0 | procedure | 1 | none | none |
| drawable? | stable | 0 | procedure | 1 | none | none |
| picture->drawable | stable | 0 | procedure | 1 | none | none |
### effects.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| make-1d-path-effect | stable | 0 | procedure | 2, 3 | none | #:style |
| make-2d-line-path-effect | stable | 0 | procedure | 2 | none | none |
| make-2d-path-effect | stable | 0 | procedure | 2 | none | none |
| make-arithmetic-blender | stable | 0 | procedure | 4 | none | #:enforce-premul? |
| make-blender-image-filter | stable | 0 | procedure | 3 | none | #:crop |
| make-blender-shader | stable | 0 | procedure | 3 | none | none |
| make-clip-mask-filter | stable | 0 | procedure | 2 | none | none |
| make-empty-shader | stable | 0 | procedure | 0 | none | none |
| make-fractal-noise-shader | stable | 0 | procedure | 3, 4 | none | #:tile-size |
| make-gamma-mask-filter | stable | 0 | procedure | 1 | none | none |
| make-shader-mask-filter | stable | 0 | procedure | 1 | none | none |
| make-table-mask-filter | stable | 0 | procedure | 1 | none | none |
| make-turbulence-shader | stable | 0 | procedure | 3, 4 | none | #:tile-size |
| shader-with-color-filter | stable | 0 | procedure | 2 | none | none |
### file-streams.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| make-file-output-stream | stable | 0 | procedure | 1 | none | #:exists, #:limit |
| output-stream-flush! | stable | 0 | procedure | 1 | none | none |
### float-colors.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| canvas-clear-color4f! | stable | 0 | procedure | 2 | none | none |
| draw-color4f | stable | 0 | procedure | 2 | none | #:blend-mode |
| make-color4f-shader | stable | 0 | procedure | 1 | #:color-space | #:color-space |
| make-linear-gradient-color4f-shader | stable | 0 | procedure | 3 | #:color-space | #:color-space, #:matrix, #:stops, #:tile-mode |
| make-paint/color4f | stable | 0 | procedure | 1 | #:color-space | #:antialias?, #:color-space, #:stroke-width, #:style |
| make-radial-gradient-color4f-shader | stable | 0 | procedure | 3 | #:color-space | #:color-space, #:matrix, #:stops, #:tile-mode |
| make-sweep-gradient-color4f-shader | stable | 0 | procedure | 2 | #:color-space | #:color-space, #:end-angle, #:matrix, #:start-angle, #:stops, #:tile-mode |
| make-two-point-conical-gradient-color4f-shader | stable | 0 | procedure | 5 | #:color-space | #:color-space, #:matrix, #:stops, #:tile-mode |
| paint-color4f | stable | 0 | procedure | 1 | none | none |
| paint-set-color4f! | stable | 0 | procedure | 2 | #:color-space | #:color-space |
### fonts.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| font-baseline-snap? | stable | 0 | procedure | 1 | none | none |
| font-break-text | stable | 0 | procedure | 3 | none | #:paint |
| font-embedded-bitmaps? | stable | 0 | procedure | 1 | none | none |
| font-force-auto-hinting? | stable | 0 | procedure | 1 | none | none |
| font-glyph-bounds | stable | 0 | procedure | 2 | none | #:paint |
| font-glyph-paths | stable | 0 | procedure | 2 | none | none |
| font-glyph-positions | stable | 0 | procedure | 2 | none | #:origin |
| font-glyph-widths | stable | 0 | procedure | 2 | none | #:paint |
| font-glyph-widths+bounds | stable | 0 | procedure | 2 | none | #:paint |
| font-glyph-x-positions | stable | 0 | procedure | 2 | none | #:origin |
| font-set-baseline-snap! | stable | 0 | procedure | 2 | none | none |
| font-set-embedded-bitmaps! | stable | 0 | procedure | 2 | none | none |
| font-set-force-auto-hinting! | stable | 0 | procedure | 2 | none | none |
| font-set-typeface! | stable | 0 | procedure | 2 | none | none |
| font-typeface | stable | 0 | procedure | 1 | none | none |
### geometry-primitives.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| atlas-transform-coefficients | stable | 0 | procedure | 1 | none | none |
| atlas-transform? | stable | 0 | procedure | 1 | none | none |
| canvas-clip-region! | stable | 0 | procedure | 2 | none | #:operation |
| cubic-patch-colors | stable | 0 | procedure | 1 | none | none |
| cubic-patch-points | stable | 0 | procedure | 1 | none | none |
| cubic-patch-texture-coordinates | stable | 0 | procedure | 1 | none | none |
| cubic-patch? | stable | 0 | procedure | 1 | none | none |
| draw-atlas | stable | 0 | procedure | 4 | none | #:blend-mode, #:colors, #:cull, #:paint, #:sampling |
| draw-image-lattice | stable | 0 | procedure | 7 | none | #:paint, #:sampling |
| draw-image-nine | stable | 0 | procedure | 7 | none | #:paint, #:sampling |
| draw-patch | stable | 0 | procedure | 3 | none | #:blend-mode |
| draw-region | stable | 0 | procedure | 3 | none | none |
| draw-vertices | stable | 0 | procedure | 3 | none | #:blend-mode |
| image-lattice-bounds | stable | 0 | procedure | 1 | none | none |
| image-lattice-cell-types | stable | 0 | procedure | 1 | none | none |
| image-lattice-colors | stable | 0 | procedure | 1 | none | none |
| image-lattice-x-divisions | stable | 0 | procedure | 1 | none | none |
| image-lattice-y-divisions | stable | 0 | procedure | 1 | none | none |
| image-lattice? | stable | 0 | procedure | 1 | none | none |
| in-region-rectangles | stable | 0 | procedure | 1 | none | none |
| make-atlas-transform | stable | 0 | procedure | 2 | none | #:anchor, #:rotation, #:scale |
| make-cubic-patch | stable | 0 | procedure | 1 | none | #:colors, #:texture-coordinates |
| make-image-lattice | stable | 0 | procedure | 2 | none | #:bounds, #:cell-types, #:colors |
| make-region | stable | 0 | procedure | 0, 1 | none | none |
| make-vertices | stable | 0 | procedure | 2 | none | #:colors, #:indices, #:texture-coordinates |
| path->region | stable | 0 | procedure | 2 | none | none |
| region->path | stable | 0 | procedure | 1 | none | none |
| region-bounds | stable | 0 | procedure | 1 | none | none |
| region-complex? | stable | 0 | procedure | 1 | none | none |
| region-contains-point? | stable | 0 | procedure | 3 | none | none |
| region-contains-rect? | stable | 0 | procedure | 2 | none | none |
| region-contains-region? | stable | 0 | procedure | 2 | none | none |
| region-copy | stable | 0 | procedure | 1 | none | none |
| region-difference | stable | 0 | procedure | 2 | none | none |
| region-empty? | stable | 0 | procedure | 1 | none | none |
| region-intersect | stable | 0 | procedure | 2 | none | none |
| region-intersects? | stable | 0 | procedure | 2 | none | none |
| region-op | stable | 0 | procedure | 3 | none | none |
| region-rect? | stable | 0 | procedure | 1 | none | none |
| region-rectangles | stable | 0 | procedure | 1 | none | none |
| region-translate | stable | 0 | procedure | 3 | none | none |
| region-union | stable | 0 | procedure | 2 | none | none |
| region-xor | stable | 0 | procedure | 2 | none | none |
| region? | stable | 0 | procedure | 1 | none | none |
| vertices-colors | stable | 0 | procedure | 1 | none | none |
| vertices-count | stable | 0 | procedure | 1 | none | none |
| vertices-indices | stable | 0 | procedure | 1 | none | none |
| vertices-mode | stable | 0 | procedure | 1 | none | none |
| vertices-positions | stable | 0 | procedure | 1 | none | none |
| vertices-texture-coordinates | stable | 0 | procedure | 1 | none | none |
| vertices? | stable | 0 | procedure | 1 | none | none |
### geometry.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| conic->quadratics | stable | 0 | procedure | 4 | none | #:subdivisions |
| current-path-operation-limit | stable | 0 | parameter | 0, 1 | none | none |
| in-region-clipped-rectangles | stable | 0 | procedure | 2 | none | none |
| in-region-spans | stable | 0 | procedure | 4 | none | none |
| make-empty-rounded-rect | stable | 0 | procedure | 0 | none | none |
| make-nine-patch-rounded-rect | stable | 0 | procedure | 8 | none | none |
| paint->fill-path | stable | 0 | procedure | 2 | none | #:cull, #:matrix |
| paint-antialias? | stable | 0 | procedure | 1 | none | none |
| paint-blend-mode-or-src-over | stable | 0 | procedure | 1 | none | none |
| paint-cap | stable | 0 | procedure | 1 | none | none |
| paint-dither? | stable | 0 | procedure | 1 | none | none |
| paint-join | stable | 0 | procedure | 1 | none | none |
| paint-miter-limit | stable | 0 | procedure | 1 | none | none |
| paint-reset! | stable | 0 | procedure | 1 | none | none |
| paint-set-dither! | stable | 0 | procedure | 2 | none | none |
| paint-stroke-width | stable | 0 | procedure | 1 | none | none |
| paint-style | stable | 0 | procedure | 1 | none | none |
| path-add-arc! | stable | 0 | procedure | 7 | none | none |
| path-add-polygon! | stable | 0 | procedure | 2 | none | #:closed? |
| path-add-rect-start! | stable | 0 | procedure | 6 | none | #:direction |
| path-add-rrect! | stable | 0 | procedure | 2 | none | #:direction, #:start-index |
| path-add-transformed! | stable | 0 | procedure | 3 | none | #:mode |
| path-arc-to! | stable | 0 | procedure | 6 | none | #:direction, #:large? |
| path-arc-to-oval! | stable | 0 | procedure | 7 | none | #:force-move? |
| path-as-line | stable | 0 | procedure | 1 | none | none |
| path-as-oval | stable | 0 | procedure | 1 | none | none |
| path-as-rectangle | stable | 0 | procedure | 1 | none | none |
| path-as-rounded-rect | stable | 0 | procedure | 1 | none | none |
| path-combine | stable | 0 | procedure | 1 | none | none |
| path-fill-bounds | stable | 0 | procedure | 1 | none | none |
| path-rarc-to! | stable | 0 | procedure | 6 | none | #:direction, #:large? |
| path-rectangle-bounds | stable | 0 | procedure | 1 | none | none |
| path-rectangle-closed? | stable | 0 | procedure | 1 | none | none |
| path-rectangle-direction | stable | 0 | procedure | 1 | none | none |
| path-rectangle? | stable | 0 | procedure | 1 | none | none |
| path-rewind! | stable | 0 | procedure | 1 | none | none |
| path-segment-kinds | stable | 0 | procedure | 1 | none | none |
| path-tangent-arc-to! | stable | 0 | procedure | 6 | none | none |
| path-verbs | stable | 0 | procedure | 1 | none | none |
| region-clear! | stable | 0 | procedure | 1 | none | none |
| region-clipped-rectangles | stable | 0 | procedure | 2 | none | none |
| region-intersects-rect? | stable | 0 | procedure | 2 | none | none |
| region-op-rect | stable | 0 | procedure | 3 | none | none |
| region-quick-contains-rect? | stable | 0 | procedure | 2 | none | none |
| region-quick-reject-rect? | stable | 0 | procedure | 2 | none | none |
| region-quick-reject? | stable | 0 | procedure | 2 | none | none |
| region-set-rect! | stable | 0 | procedure | 2 | none | none |
| region-spans | stable | 0 | procedure | 4 | none | none |
| rounded-rect-inset | stable | 0 | procedure | 3 | none | none |
| rounded-rect-normalize | stable | 0 | procedure | 1 | none | none |
| rounded-rect-offset | stable | 0 | procedure | 3 | none | none |
| rounded-rect-outset | stable | 0 | procedure | 3 | none | none |
| rounded-rect-transform | stable | 0 | procedure | 2 | none | none |
| rounded-rect-type | stable | 0 | procedure | 1 | none | none |
### gpu-context-options.rkt

Experimental optional execution/integration API; existing backend, owner-thread and document restrictions remain unchanged.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| gpu-context-options->jsexpr | experimental | 0 | procedure | 1 | none | none |
| gpu-context-options-allow-path-mask-caching? | experimental | 0 | procedure | 1 | none | none |
| gpu-context-options-avoid-stencil-buffers? | experimental | 0 | procedure | 1 | none | none |
| gpu-context-options-buffer-map-threshold | experimental | 0 | procedure | 1 | none | none |
| gpu-context-options-glyph-cache-texture-maximum-bytes | experimental | 0 | procedure | 1 | none | none |
| gpu-context-options-manual-mipmapping? | experimental | 0 | procedure | 1 | none | none |
| gpu-context-options-runtime-program-cache-size | experimental | 0 | procedure | 1 | none | none |
| gpu-context-options? | experimental | 0 | procedure | 1 | none | none |
| make-gpu-context-options | experimental | 0 | procedure | 0 | none | #:allow-path-mask-caching?, #:avoid-stencil-buffers?, #:buffer-map-threshold, #:glyph-cache-texture-maximum-bytes, #:manual-mipmapping?, #:runtime-program-cache-size |
### gpu-dc.rkt

Experimental optional execution/integration API; existing backend, owner-thread and document restrictions remain unchanged.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| call-with-gpu-frame-dc | experimental | 0 | procedure | 2 | none | #:background, #:color-space, #:color-type, #:sample-count, #:smoothing, #:surface-properties |
| call-with-gpu-surface-dc | experimental | 0 | procedure | 2 | none | #:background, #:clear?, #:logical-height, #:logical-width, #:smoothing |
| skia-gpu-dc-capabilities | experimental | 0 | procedure | 0 | none | none |
| skia-gpu-dc? | experimental | 0 | procedure | 1 | none | none |
### gpu-diagnostics.rkt

Experimental optional execution/integration API; existing backend, owner-thread and document restrictions remain unchanged.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| gpu-gl-has-extension? | experimental | 0 | procedure | 2 | none | none |
| gpu-gl-interface-info | experimental | 0 | procedure | 1 | none | none |
| gpu-memory-statistics | experimental | 0 | procedure | 1 | none | #:byte-limit, #:detailed?, #:dump-wrapped?, #:max-entries, #:string-limit |
### gpu-egl.rkt

Experimental optional execution/integration API; existing backend, owner-thread and document restrictions remain unchanged.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| make-current-egl-gpu-provider | experimental | 0 | procedure | 0 | none | none |
| make-egl-gpu-context | experimental | 0 | procedure | 0 | none | #:device-index, #:gl-interface, #:options, #:platform, #:surface |
### gpu-gl-interop.rkt

Experimental optional execution/integration API; existing backend, owner-thread and document restrictions remain unchanged.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| call-with-gpu-external-gl | experimental | 0 | procedure | 2 | none | #:wait? |
| call-with-gpu-gl-framebuffer | experimental | 0 | procedure | 5 | none | #:color-space, #:origin, #:wait? |
| gpu-copy-gl-texture | experimental | 0 | procedure | 4 | none | #:color-space, #:origin, #:premultiplied?, #:wait? |
### gpu-interop.rkt

Experimental optional execution/integration API; existing backend, owner-thread and document restrictions remain unchanged.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| call-with-gpu-external-surface | experimental | 0 | procedure | 3 | none | none |
| gpu-external-texture-close! | experimental | 0 | procedure | 1 | none | none |
| gpu-external-texture-info | experimental | 0 | procedure | 1 | none | none |
| gpu-external-texture? | experimental | 0 | procedure | 1 | none | none |
| gpu-import-image | experimental | 0 | procedure | 2 | none | none |
### gpu-output.rkt

Experimental optional execution/integration API; existing backend, owner-thread and document restrictions remain unchanged.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| call-with-gpu-raster-executor | experimental | 0 | procedure | 2 | none | #:on-unavailable |
| make-gpu-raster-executor | experimental | 0 | procedure | 1 | none | none |
### gpu.rkt

Experimental optional execution/integration API; existing backend, owner-thread and document restrictions remain unchanged.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| call-with-gpu-context | experimental | 0 | procedure | 2 | none | none |
| exn:fail:gpu:unavailable-step | experimental | 0 | procedure | 1 | none | none |
| exn:fail:gpu:unavailable? | experimental | 0 | procedure | 1 | none | none |
| gpu-backend-capabilities | experimental | 0 | procedure | 1 | none | none |
| gpu-backend? | experimental | 0 | procedure | 1 | none | none |
| gpu-backends | experimental | 0 | procedure | 0 | none | none |
| gpu-cache-info | experimental | 0 | procedure | 1 | none | none |
| gpu-context-abandon! | experimental | 0 | procedure | 1 | none | none |
| gpu-context-backend | experimental | 0 | procedure | 1 | none | none |
| gpu-context-close! | experimental | 0 | procedure | 1 | none | none |
| gpu-context-generation | experimental | 0 | procedure | 1 | none | none |
| gpu-context-info | experimental | 0 | procedure | 1 | none | none |
| gpu-context-options->jsexpr | experimental | 0 | procedure | 1 | none | none |
| gpu-context-options-allow-path-mask-caching? | experimental | 0 | procedure | 1 | none | none |
| gpu-context-options-avoid-stencil-buffers? | experimental | 0 | procedure | 1 | none | none |
| gpu-context-options-buffer-map-threshold | experimental | 0 | procedure | 1 | none | none |
| gpu-context-options-glyph-cache-texture-maximum-bytes | experimental | 0 | procedure | 1 | none | none |
| gpu-context-options-manual-mipmapping? | experimental | 0 | procedure | 1 | none | none |
| gpu-context-options-runtime-program-cache-size | experimental | 0 | procedure | 1 | none | none |
| gpu-context-options? | experimental | 0 | procedure | 1 | none | none |
| gpu-context-release-and-abandon! | experimental | 0 | procedure | 1 | none | none |
| gpu-context-request-shutdown! | experimental | 0 | procedure | 1 | none | none |
| gpu-context-state | experimental | 0 | procedure | 1 | none | none |
| gpu-context? | experimental | 0 | procedure | 1 | none | none |
| gpu-drain-pending-contexts! | experimental | 0 | procedure | 0 | none | #:abandon? |
| gpu-drain-pending-presenters! | experimental | 0 | procedure | 0 | none | none |
| gpu-drain-releases! | experimental | 0 | procedure | 1 | none | none |
| gpu-flush! | experimental | 0 | procedure | 1 | none | none |
| gpu-flush-and-submit! | experimental | 0 | procedure | 1 | none | #:wait? |
| gpu-flush-image! | experimental | 0 | procedure | 2 | none | none |
| gpu-flush-surface! | experimental | 0 | procedure | 2 | none | none |
| gpu-frame-canvas | experimental | 0 | procedure | 1 | none | none |
| gpu-frame-context | experimental | 0 | procedure | 1 | none | none |
| gpu-frame-expired? | experimental | 0 | procedure | 1 | none | none |
| gpu-frame-generation | experimental | 0 | procedure | 1 | none | none |
| gpu-frame-height | experimental | 0 | procedure | 1 | none | none |
| gpu-frame-index | experimental | 0 | procedure | 1 | none | none |
| gpu-frame-info | experimental | 0 | procedure | 1 | none | none |
| gpu-frame-logical-height | experimental | 0 | procedure | 1 | none | none |
| gpu-frame-logical-width | experimental | 0 | procedure | 1 | none | none |
| gpu-frame-scale-x | experimental | 0 | procedure | 1 | none | none |
| gpu-frame-scale-y | experimental | 0 | procedure | 1 | none | none |
| gpu-frame-width | experimental | 0 | procedure | 1 | none | none |
| gpu-frame? | experimental | 0 | procedure | 1 | none | none |
| gpu-free-resources! | experimental | 0 | procedure | 1 | none | none |
| gpu-gl-has-extension? | experimental | 0 | procedure | 2 | none | none |
| gpu-gl-interface-info | experimental | 0 | procedure | 1 | none | none |
| gpu-image->raster-buffer | experimental | 0 | procedure | 1 | none | #:info, #:row-bytes |
| gpu-image->raster-image | experimental | 0 | procedure | 1 | none | none |
| gpu-image->rgba-bytes | experimental | 0 | procedure | 1 | none | #:color-space, #:premultiplied? |
| gpu-image-apply-filter | experimental | 0 | procedure | 2 | #:clip | #:clip, #:subset |
| gpu-image-info | experimental | 0 | procedure | 1 | none | none |
| gpu-image-read-raster-buffer! | experimental | 0 | procedure | 2 | none | none |
| gpu-image-subset | experimental | 0 | procedure | 5 | none | none |
| gpu-image? | experimental | 0 | procedure | 1 | none | none |
| gpu-memory-statistics | experimental | 0 | procedure | 1 | none | #:byte-limit, #:detailed?, #:dump-wrapped?, #:max-entries, #:string-limit |
| gpu-perform-deferred-cleanup! | experimental | 0 | procedure | 2 | none | none |
| gpu-presenter-backend | experimental | 0 | procedure | 1 | none | none |
| gpu-presenter-close! | experimental | 0 | procedure | 1 | none | none |
| gpu-presenter-context | experimental | 0 | procedure | 1 | none | none |
| gpu-presenter-info | experimental | 0 | procedure | 1 | none | none |
| gpu-presenter-render! | experimental | 0 | procedure | 1 | none | none |
| gpu-presenter-request-render! | experimental | 0 | procedure | 1 | none | none |
| gpu-presenter-set-render! | experimental | 0 | procedure | 2 | none | none |
| gpu-presenter-state | experimental | 0 | procedure | 1 | none | none |
| gpu-presenter? | experimental | 0 | procedure | 1 | none | none |
| gpu-provider-backend | experimental | 0 | procedure | 1 | none | none |
| gpu-provider-name | experimental | 0 | procedure | 1 | none | none |
| gpu-provider? | experimental | 0 | procedure | 1 | none | none |
| gpu-purge-bytes! | experimental | 0 | procedure | 2 | none | #:prefer-scratch? |
| gpu-purge-unlocked! | experimental | 0 | procedure | 1 | none | #:scratch-only? |
| gpu-set-cache-limit! | experimental | 0 | procedure | 2 | none | none |
| gpu-smoke-test | experimental | 0 | procedure | 1 | none | none |
| gpu-submit! | experimental | 0 | procedure | 1 | none | #:wait? |
| gpu-surface->image-info | experimental | 0 | procedure | 1 | none | none |
| gpu-surface->raster-buffer | experimental | 0 | procedure | 1 | none | #:info, #:row-bytes |
| gpu-surface->raster-image | experimental | 0 | procedure | 1 | none | none |
| gpu-surface->rgba-bytes | experimental | 0 | procedure | 1 | none | #:color-space, #:premultiplied? |
| gpu-surface-format-info | experimental | 0 | procedure | 2 | none | none |
| gpu-surface-info | experimental | 0 | procedure | 1 | none | none |
| gpu-surface-read-pixmap! | experimental | 0 | procedure | 2 | none | none |
| gpu-surface-read-raster-buffer! | experimental | 0 | procedure | 2 | none | none |
| gpu-surface-snapshot | experimental | 0 | procedure | 1 | none | none |
| gpu-surface? | experimental | 0 | procedure | 1 | none | none |
| gpu-upload-image | experimental | 0 | procedure | 2 | none | #:budgeted?, #:mipmapped? |
| gpu-wait! | experimental | 0 | procedure | 1 | none | none |
| image-residency | experimental | 0 | procedure | 1 | none | none |
| make-gpu-context | experimental | 0 | procedure | 0, 1 | none | #:adapter, #:adapter-index, #:backend, #:gl-interface, #:options |
| make-gpu-context-options | experimental | 0 | procedure | 0 | none | #:allow-path-mask-caching?, #:avoid-stencil-buffers?, #:buffer-map-threshold, #:glyph-cache-texture-maximum-bytes, #:manual-mipmapping?, #:runtime-program-cache-size |
| make-gpu-provider | experimental | 0 | procedure | 0 | #:backend, #:call-as-current, #:current?, #:key, #:name | #:backend, #:call-as-current, #:current?, #:describe, #:get-proc-address, #:key, #:name |
| make-gpu-surface | experimental | 0 | procedure | 3 | none | #:alpha-type, #:background, #:budgeted?, #:color-space, #:color-type, #:opaque?, #:sample-count, #:surface-properties |
| skia-resource-gpu-context | experimental | 0 | procedure | 1 | none | none |
### graphics.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| memory-statistic-kind | stable | 0 | procedure | 1 | none | none |
| memory-statistic-name | stable | 0 | procedure | 1 | none | none |
| memory-statistic-units | stable | 0 | procedure | 1 | none | none |
| memory-statistic-value | stable | 0 | procedure | 1 | none | none |
| memory-statistic-value-name | stable | 0 | procedure | 1 | none | none |
| memory-statistic? | stable | 0 | procedure | 1 | none | none |
| memory-statistics->jsexpr | stable | 0 | procedure | 1 | none | none |
| memory-statistics-detailed? | stable | 0 | procedure | 1 | none | none |
| memory-statistics-dropped-count | stable | 0 | procedure | 1 | none | none |
| memory-statistics-dump-wrapped? | stable | 0 | procedure | 1 | none | none |
| memory-statistics-entries | stable | 0 | procedure | 1 | none | none |
| memory-statistics-scope | stable | 0 | procedure | 1 | none | none |
| memory-statistics-string-bytes | stable | 0 | procedure | 1 | none | none |
| memory-statistics-truncated? | stable | 0 | procedure | 1 | none | none |
| memory-statistics? | stable | 0 | procedure | 1 | none | none |
| skia-cache-statistics | stable | 0 | procedure | 0 | none | none |
| skia-font-cache-count-limit | stable | 0 | procedure | 0 | none | none |
| skia-font-cache-count-used | stable | 0 | procedure | 0 | none | none |
| skia-font-cache-limit | stable | 0 | procedure | 0 | none | none |
| skia-font-cache-used | stable | 0 | procedure | 0 | none | none |
| skia-initialize! | stable | 0 | procedure | 0 | none | none |
| skia-memory-statistics | stable | 0 | procedure | 0 | none | #:byte-limit, #:detailed?, #:dump-wrapped?, #:max-entries, #:string-limit |
| skia-purge-all-caches! | stable | 0 | procedure | 0 | none | none |
| skia-purge-font-cache! | stable | 0 | procedure | 0 | none | none |
| skia-purge-resource-cache! | stable | 0 | procedure | 0 | none | none |
| skia-resource-cache-limit | stable | 0 | procedure | 0 | none | none |
| skia-resource-cache-single-allocation-limit | stable | 0 | procedure | 0 | none | none |
| skia-resource-cache-used | stable | 0 | procedure | 0 | none | none |
| skia-set-font-cache-count-limit! | stable | 0 | procedure | 1 | none | none |
| skia-set-font-cache-limit! | stable | 0 | procedure | 1 | none | none |
| skia-set-resource-cache-limit! | stable | 0 | procedure | 1 | none | none |
| skia-set-resource-cache-single-allocation-limit! | stable | 0 | procedure | 1 | none | none |
### image-info.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| color-space-descriptor? | stable | 0 | procedure | 1 | none | none |
| float-pixel-formats | stable | 0 | value | — | — | — |
| image-info-alpha-type | stable | 0 | procedure | 1 | none | none |
| image-info-byte-order | stable | 0 | procedure | 1 | none | none |
| image-info-bytes-per-pixel | stable | 0 | procedure | 1 | none | none |
| image-info-channel-bits | stable | 0 | procedure | 1 | none | none |
| image-info-color-space | stable | 0 | procedure | 1 | none | none |
| image-info-color-type | stable | 0 | procedure | 1 | none | none |
| image-info-height | stable | 0 | procedure | 1 | none | none |
| image-info-min-row-bytes | stable | 0 | procedure | 1 | none | none |
| image-info-sample-type | stable | 0 | procedure | 1 | none | none |
| image-info-storage-layout | stable | 0 | procedure | 1 | none | #:row-bytes |
| image-info-supports? | stable | 0 | procedure | 2 | none | none |
| image-info-width | stable | 0 | procedure | 1 | none | none |
| image-info-with-dimensions | stable | 0 | procedure | 3 | none | none |
| image-info? | stable | 0 | procedure | 1 | none | none |
| integer-pixel-formats | stable | 0 | value | — | — | — |
| make-image-info | stable | 0 | procedure | 2 | none | #:alpha-type, #:color-space, #:color-type |
| pixel-formats | stable | 0 | value | — | — | — |
### image-operations.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| image->non-texture-image | stable | 0 | procedure | 1 | none | none |
| image->raster-buffer | stable | 0 | procedure | 1 | none | #:cache?, #:info, #:row-bytes, #:sampling |
| image->raster-image | stable | 0 | procedure | 1 | none | none |
| image-alpha-only? | stable | 0 | procedure | 1 | none | none |
| image-apply-filter | stable | 0 | procedure | 2 | #:clip | #:clip, #:subset |
| image-lazy-generated? | stable | 0 | procedure | 1 | none | none |
| image-pixels-available? | stable | 0 | procedure | 1 | none | none |
| image-read-pixmap! | stable | 0 | procedure | 2 | none | #:cache?, #:source-x, #:source-y |
| image-scale-pixmap! | stable | 0 | procedure | 2 | none | #:cache?, #:sampling |
| image-texture-backed? | stable | 0 | procedure | 1 | none | none |
| image-unique-id | stable | 0 | procedure | 1 | none | none |
| image-valid? | stable | 0 | procedure | 1 | none | none |
| make-raw-image-shader | stable | 0 | procedure | 1 | none | #:matrix, #:sampling, #:tile-x, #:tile-y |
### layer-options.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| layer-options-bounds | stable | 0 | procedure | 1 | none | none |
| layer-options-f16? | stable | 0 | procedure | 1 | none | none |
| layer-options-flags | stable | 0 | procedure | 1 | none | none |
| layer-options-initialize-with-previous? | stable | 0 | procedure | 1 | none | none |
| layer-options-preserve-lcd-text? | stable | 0 | procedure | 1 | none | none |
| layer-options? | stable | 0 | procedure | 1 | none | none |
| make-layer-options | stable | 0 | procedure | 0 | none | #:bounds, #:f16?, #:initialize-with-previous?, #:preserve-lcd-text? |
### live-streams.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| copy-port/streaming | stable | 0 | procedure | 2 | none | #:cancel-evt, #:close-input?, #:close-output?, #:limit |
| image->port | stable | 0 | procedure | 3 | none | #:cancel-evt, #:close?, #:jpeg-alpha, #:jpeg-downsample, #:limit, #:png-compression, #:quality, #:webp-lossless? |
| image-from-port | stable | 0 | procedure | 1 | none | #:cancel-evt, #:close?, #:length, #:limit, #:normalize-origin?, #:seekable? |
| image-write-stream! | stable | 0 | procedure | 3 | none | #:jpeg-alpha, #:jpeg-downsample, #:png-compression, #:quality, #:webp-lossless? |
| live-streams-available? | stable | 0 | procedure | 0 | none | none |
| live-streams-check! | stable | 0 | procedure | 0 | none | none |
| output->port | stable | 0 | procedure | 3 | none | #:cancel-evt, #:close?, #:limit, #:policy, #:raster-dpi, #:text-mode |
| output-write-stream! | stable | 0 | procedure | 2 | none | #:policy, #:raster-dpi, #:text-mode |
| picture->port | stable | 0 | procedure | 2 | none | #:cancel-evt, #:close?, #:limit |
| picture-from-port | stable | 0 | procedure | 1 | none | #:cancel-evt, #:close?, #:height, #:length, #:limit, #:seekable?, #:trusted?, #:width |
| picture-write-stream! | stable | 0 | procedure | 2 | none | none |
### main.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| analyze-output-page | stable | 0 | procedure | 2 | none | #:description, #:encoding-quality, #:id-prefix, #:pdfa?, #:raster-dpi, #:text-mode, #:title |
| atlas-transform-coefficients | stable | 0 | procedure | 1 | none | none |
| atlas-transform? | stable | 0 | procedure | 1 | none | none |
| blender? | stable | 0 | procedure | 1 | none | none |
| buffered-port->input-stream | stable | 0 | procedure | 1 | none | #:cancel-evt, #:close?, #:limit |
| call-with-canvas-layer | stable | 0 | procedure | 2 | none | #:bounds, #:paint |
| call-with-canvas-layer-rec | stable | 0 | procedure | 2 | none | #:backdrop, #:clip, #:options, #:paint |
| call-with-canvas-matrix | stable | 0 | procedure | 3 | none | #:replace? |
| call-with-canvas-state | stable | 0 | procedure | 2 | none | none |
| call-with-document-page | stable | 0 | procedure | 4 | none | none |
| call-with-drawable | stable | 0 | procedure | 3 | none | none |
| call-with-nodraw-canvas | stable | 0 | procedure | 3 | none | none |
| call-with-nway-canvas | stable | 0 | procedure | 2 | none | none |
| call-with-output-label | stable | 0 | procedure | 2 | none | none |
| call-with-overdraw-canvas | stable | 0 | procedure | 2 | none | none |
| call-with-pdf-bytes | stable | 0 | procedure | 1 | none | #:author, #:creation-date, #:creator, #:encoding-quality, #:keywords, #:modified-date, #:pdfa?, #:producer, #:raster-dpi, #:subject, #:title |
| call-with-pdf-file | stable | 0 | procedure | 2 | none | #:author, #:creation-date, #:creator, #:encoding-quality, #:exists, #:keywords, #:modified-date, #:pdfa?, #:producer, #:raster-dpi, #:subject, #:title |
| call-with-picture | stable | 0 | procedure | 3 | none | #:spatial-index |
| call-with-raster-buffer-canvas | stable | 0 | procedure | 2 | none | none |
| call-with-raster-buffer-pixmap | stable | 0 | procedure | 2 | none | #:writable? |
| call-with-skia-resource | stable | 0 | procedure | 2 | none | none |
| call-with-svg-bytes | stable | 0 | procedure | 3 | none | #:description, #:id-prefix, #:title |
| call-with-svg-file | stable | 0 | procedure | 4 | none | #:description, #:exists, #:id-prefix, #:title |
| call-with-svg-string | stable | 0 | procedure | 3 | none | #:description, #:id-prefix, #:title |
| canvas-annotate-url! | stable | 0 | procedure | 6 | none | none |
| canvas-annotation-backend | stable | 0 | procedure | 1 | none | none |
| canvas-clear! | stable | 0 | procedure | 2 | none | none |
| canvas-clear-color4f! | stable | 0 | procedure | 2 | none | none |
| canvas-clip-empty? | stable | 0 | procedure | 1 | none | none |
| canvas-clip-path! | stable | 0 | procedure | 2 | none | #:antialias?, #:operation |
| canvas-clip-rect! | stable | 0 | procedure | 5 | none | #:antialias?, #:operation |
| canvas-clip-rect? | stable | 0 | procedure | 1 | none | none |
| canvas-clip-region! | stable | 0 | procedure | 2 | none | #:operation |
| canvas-clip-rounded-rect! | stable | 0 | procedure | 2 | none | #:antialias?, #:operation |
| canvas-concat! | stable | 0 | procedure | 2 | none | none |
| canvas-concat-matrix3! | stable | 0 | procedure | 2 | none | none |
| canvas-concat-matrix4! | stable | 0 | procedure | 2 | none | none |
| canvas-define-destination! | stable | 0 | procedure | 4 | none | none |
| canvas-device-clip-bounds | stable | 0 | procedure | 1 | none | none |
| canvas-discard! | stable | 0 | procedure | 1 | none | none |
| canvas-execution-backend | stable | 0 | procedure | 1 | none | none |
| canvas-link-destination! | stable | 0 | procedure | 6 | none | none |
| canvas-local-clip-bounds | stable | 0 | procedure | 1 | none | none |
| canvas-matrix4 | stable | 0 | procedure | 1 | none | none |
| canvas-quick-reject? | stable | 0 | procedure | 5 | none | none |
| canvas-reset-transform! | stable | 0 | procedure | 1 | none | none |
| canvas-restore! | stable | 0 | procedure | 1 | none | none |
| canvas-restore-to-count! | stable | 0 | procedure | 2 | none | none |
| canvas-rotate! | stable | 0 | procedure | 2 | none | none |
| canvas-rotate-radians! | stable | 0 | procedure | 2 | none | none |
| canvas-save! | stable | 0 | procedure | 1 | none | none |
| canvas-save-count | stable | 0 | procedure | 1 | none | none |
| canvas-save-layer! | stable | 0 | procedure | 1 | none | #:bounds, #:paint |
| canvas-save-layer-rec! | stable | 0 | procedure | 1 | none | #:backdrop, #:options, #:paint |
| canvas-scale! | stable | 0 | procedure | 2, 3 | none | none |
| canvas-set-matrix3! | stable | 0 | procedure | 2 | none | none |
| canvas-set-matrix4! | stable | 0 | procedure | 2 | none | none |
| canvas-set-transform! | stable | 0 | procedure | 2 | none | none |
| canvas-skew! | stable | 0 | procedure | 3 | none | none |
| canvas-transform | stable | 0 | procedure | 1 | none | none |
| canvas-translate! | stable | 0 | procedure | 3 | none | none |
| canvas? | stable | 0 | procedure | 1 | none | none |
| codec->image | stable | 0 | procedure | 1 | none | #:color-space, #:frame-index, #:normalize-origin? |
| codec-color-space | stable | 0 | procedure | 1 | none | none |
| codec-frame-count | stable | 0 | procedure | 1 | none | none |
| codec-frame-info | stable | 0 | procedure | 2 | none | none |
| codec-frame-info-alpha-type | stable | 0 | procedure | 1 | none | none |
| codec-frame-info-blend | stable | 0 | procedure | 1 | none | none |
| codec-frame-info-disposal-method | stable | 0 | procedure | 1 | none | none |
| codec-frame-info-duration | stable | 0 | procedure | 1 | none | none |
| codec-frame-info-fully-received? | stable | 0 | procedure | 1 | none | none |
| codec-frame-info-has-alpha-within-bounds? | stable | 0 | procedure | 1 | none | none |
| codec-frame-info-index | stable | 0 | procedure | 1 | none | none |
| codec-frame-info-rect | stable | 0 | procedure | 1 | none | none |
| codec-frame-info-required-frame | stable | 0 | procedure | 1 | none | none |
| codec-frame-info? | stable | 0 | procedure | 1 | none | none |
| codec-from-bytes | stable | 0 | procedure | 1 | none | none |
| codec-from-file | stable | 0 | procedure | 1 | none | none |
| codec-from-port/buffered | stable | 0 | procedure | 1 | none | #:cancel-evt, #:close?, #:limit |
| codec-from-stream | stable | 0 | procedure | 1 | none | none |
| codec-incremental-cancel! | stable | 0 | procedure | 1 | none | none |
| codec-incremental-feed! | stable | 0 | procedure | 2 | none | #:final? |
| codec-incremental-info | stable | 0 | procedure | 1 | none | none |
| codec-incremental-origin | stable | 0 | procedure | 1 | none | none |
| codec-incremental-session? | stable | 0 | procedure | 1 | none | none |
| codec-incremental-snapshot | stable | 0 | procedure | 1 | none | none |
| codec-incremental-state | stable | 0 | procedure | 1 | none | none |
| codec-incremental-statistics | stable | 0 | procedure | 1 | none | none |
| codec-incremental-step! | stable | 0 | procedure | 1 | none | #:cancel-evt |
| codec-info | stable | 0 | procedure | 1 | none | none |
| codec-repetition-count | stable | 0 | procedure | 1 | none | none |
| codec-scaled-dimensions | stable | 0 | procedure | 2 | none | none |
| codec-scanline-from-bytes | stable | 0 | procedure | 1 | none | #:alpha-type, #:color-space, #:color-type, #:scale |
| codec-scanline-from-port/buffered | stable | 0 | procedure | 1 | none | #:alpha-type, #:cancel-evt, #:close?, #:color-space, #:color-type, #:limit, #:scale |
| codec-scanline-from-stream | stable | 0 | procedure | 1 | none | #:alpha-type, #:color-space, #:color-type, #:scale |
| codec-scanline-info | stable | 0 | procedure | 1 | none | none |
| codec-scanline-next-row | stable | 0 | procedure | 1 | none | none |
| codec-scanline-order | stable | 0 | procedure | 1 | none | none |
| codec-scanline-output-row | stable | 0 | procedure | 2 | none | none |
| codec-scanline-position | stable | 0 | procedure | 1 | none | none |
| codec-scanline-read! | stable | 0 | procedure | 1, 2 | none | #:row-bytes |
| codec-scanline-session? | stable | 0 | procedure | 1 | none | none |
| codec-scanline-skip! | stable | 0 | procedure | 2 | none | none |
| codec-scanline-source-info | stable | 0 | procedure | 1 | none | none |
| codec-scanline-state | stable | 0 | procedure | 1 | none | none |
| codec-supported-subset | stable | 0 | procedure | 5 | none | none |
| codec? | stable | 0 | procedure | 1 | none | none |
| color->argb | stable | 0 | procedure | 1 | none | none |
| color->color4f | stable | 0 | procedure | 1 | none | none |
| color->rgba | stable | 0 | procedure | 1 | none | none |
| color-filter? | stable | 0 | procedure | 1 | none | none |
| color-space->descriptor | stable | 0 | procedure | 1 | none | none |
| color-space->icc-bytes | stable | 0 | procedure | 1 | none | none |
| color-space->linear-gamma | stable | 0 | procedure | 1 | none | none |
| color-space->srgb-gamma | stable | 0 | procedure | 1 | none | none |
| color-space-descriptor? | stable | 0 | procedure | 1 | none | none |
| color-space-from-icc-bytes | stable | 0 | procedure | 1 | none | none |
| color-space-gamma-close-to-srgb? | stable | 0 | procedure | 1 | none | none |
| color-space-linear-gamma? | stable | 0 | procedure | 1 | none | none |
| color-space-srgb? | stable | 0 | procedure | 1 | none | none |
| color-space-transfer-function | stable | 0 | procedure | 1 | none | none |
| color-space-xyz-d50 | stable | 0 | procedure | 1 | none | none |
| color-space=? | stable | 0 | procedure | 2 | none | none |
| color-space? | stable | 0 | procedure | 1 | none | none |
| color4f->rgba | stable | 0 | procedure | 1 | none | #:out-of-range |
| color4f->vector | stable | 0 | procedure | 1 | none | none |
| color4f-alpha | stable | 0 | procedure | 1 | none | none |
| color4f-blue | stable | 0 | procedure | 1 | none | none |
| color4f-green | stable | 0 | procedure | 1 | none | none |
| color4f-red | stable | 0 | procedure | 1 | none | none |
| color4f? | stable | 0 | procedure | 1 | none | none |
| color? | stable | 0 | procedure | 1 | none | none |
| conic->quadratics | stable | 0 | procedure | 4 | none | #:subdivisions |
| copy-port/streaming | stable | 0 | procedure | 2 | none | #:cancel-evt, #:close-input?, #:close-output?, #:limit |
| cubic-patch-colors | stable | 0 | procedure | 1 | none | none |
| cubic-patch-points | stable | 0 | procedure | 1 | none | none |
| cubic-patch-texture-coordinates | stable | 0 | procedure | 1 | none | none |
| cubic-patch? | stable | 0 | procedure | 1 | none | none |
| current-output-audit-event-limit | stable | 0 | parameter | 0, 1 | none | none |
| current-path-operation-limit | stable | 0 | parameter | 0, 1 | none | none |
| current-raster-output-scale | stable | 0 | parameter | 0, 1 | none | none |
| current-skia-byte-limit | stable | 0 | parameter | 0, 1 | none | none |
| current-text-output-mode | stable | 0 | parameter | 0, 1 | none | none |
| default-font-manager | stable | 0 | procedure | 0 | none | none |
| descriptor->color-space | stable | 0 | procedure | 1 | none | none |
| destination-id | stable | 0 | procedure | 1 | none | none |
| document->pdf-bytes | stable | 0 | procedure | 1 | none | none |
| document-abort! | stable | 0 | procedure | 1 | none | none |
| document-begin-page! | stable | 0 | procedure | 3 | none | none |
| document-end-page! | stable | 0 | procedure | 1 | none | none |
| document-finish! | stable | 0 | procedure | 1 | none | none |
| document-page-count | stable | 0 | procedure | 1 | none | none |
| document-state | stable | 0 | procedure | 1 | none | none |
| document? | stable | 0 | procedure | 1 | none | none |
| draw-arc | stable | 0 | procedure | 8 | none | #:use-center? |
| draw-atlas | stable | 0 | procedure | 4 | none | #:blend-mode, #:colors, #:cull, #:paint, #:sampling |
| draw-atlas/portable | stable | 0 | procedure | 4 | none | #:alpha, #:sampling |
| draw-circle | stable | 0 | procedure | 5 | none | none |
| draw-color | stable | 0 | procedure | 2 | none | #:blend-mode |
| draw-color4f | stable | 0 | procedure | 2 | none | #:blend-mode |
| draw-double-rounded-rect | stable | 0 | procedure | 4 | none | none |
| draw-drawable | stable | 0 | procedure | 2 | none | #:matrix, #:mode |
| draw-image | stable | 0 | procedure | 4 | none | #:paint, #:sampling |
| draw-image-lattice | stable | 0 | procedure | 7 | none | #:paint, #:sampling |
| draw-image-lattice/portable | stable | 0 | procedure | 7 | none | #:alpha, #:sampling |
| draw-image-nine | stable | 0 | procedure | 7 | none | #:paint, #:sampling |
| draw-image-nine/portable | stable | 0 | procedure | 7 | none | #:alpha, #:sampling |
| draw-image-rect | stable | 0 | procedure | 6 | none | #:paint, #:sampling |
| draw-image-subrect | stable | 0 | procedure | 10 | none | #:paint, #:sampling |
| draw-line | stable | 0 | procedure | 6 | none | none |
| draw-markers | stable | 0 | procedure | 4 | none | #:shape |
| draw-mixed-text-layout | stable | 0 | procedure | 5 | none | none |
| draw-output-group | stable | 0 | procedure | 6 | none | #:color-space, #:label, #:padding, #:policy, #:raster-executor, #:scale |
| draw-output-page | stable | 0 | procedure | 2 | none | #:raster-dpi, #:text-mode |
| draw-oval | stable | 0 | procedure | 6 | none | none |
| draw-paint | stable | 0 | procedure | 2 | none | none |
| draw-patch | stable | 0 | procedure | 3 | none | #:blend-mode |
| draw-path | stable | 0 | procedure | 3 | none | none |
| draw-picture | stable | 0 | procedure | 2 | none | #:height, #:width, #:x, #:y |
| draw-point | stable | 0 | procedure | 4 | none | none |
| draw-points | stable | 0 | procedure | 3 | none | #:mode |
| draw-polygon | stable | 0 | procedure | 3 | none | #:closed? |
| draw-rasterized | stable | 0 | procedure | 6 | none | #:color-space, #:padding, #:scale |
| draw-rect | stable | 0 | procedure | 6 | none | none |
| draw-region | stable | 0 | procedure | 3 | none | none |
| draw-rounded-rect | stable | 0 | procedure | 8 | none | none |
| draw-rrect | stable | 0 | procedure | 3 | none | none |
| draw-shaped-run | stable | 0 | procedure | 6 | none | none |
| draw-shaped-run/on-path | stable | 0 | procedure | 5 | none | #:contour, #:force-closed?, #:normal-offset, #:start-offset |
| draw-shaped-text | stable | 0 | procedure | 6 | none | #:direction, #:features, #:language, #:script |
| draw-simple-text | stable | 0 | procedure | 6 | none | none |
| draw-text-blob | stable | 0 | procedure | 5 | none | none |
| draw-text-layout | stable | 0 | procedure | 5 | none | none |
| draw-vertices | stable | 0 | procedure | 3 | none | #:blend-mode |
| drawable->picture | stable | 0 | procedure | 1 | none | none |
| drawable-approximate-bytes-used | stable | 0 | procedure | 1 | none | none |
| drawable-bounds | stable | 0 | procedure | 1 | none | none |
| drawable-generation-id | stable | 0 | procedure | 1 | none | none |
| drawable-notify-drawing-changed! | stable | 0 | procedure | 1 | none | none |
| drawable? | stable | 0 | procedure | 1 | none | none |
| encoded-image-info-alpha-type | stable | 0 | procedure | 1 | none | none |
| encoded-image-info-color-type | stable | 0 | procedure | 1 | none | none |
| encoded-image-info-display-height | stable | 0 | procedure | 1 | none | none |
| encoded-image-info-display-width | stable | 0 | procedure | 1 | none | none |
| encoded-image-info-format | stable | 0 | procedure | 1 | none | none |
| encoded-image-info-frame-count | stable | 0 | procedure | 1 | none | none |
| encoded-image-info-from-bytes | stable | 0 | procedure | 1 | none | none |
| encoded-image-info-from-file | stable | 0 | procedure | 1 | none | none |
| encoded-image-info-height | stable | 0 | procedure | 1 | none | none |
| encoded-image-info-origin | stable | 0 | procedure | 1 | none | none |
| encoded-image-info-width | stable | 0 | procedure | 1 | none | none |
| encoded-image-info? | stable | 0 | procedure | 1 | none | none |
| exn:fail:codec-scanline-native-code | stable | 0 | procedure | 1 | none | none |
| exn:fail:codec-scanline-result | stable | 0 | procedure | 1 | none | none |
| exn:fail:codec-scanline? | stable | 0 | procedure | 1 | none | none |
| exn:fail:output-audit-event | stable | 0 | procedure | 1 | none | none |
| exn:fail:output-audit? | stable | 0 | procedure | 1 | none | none |
| exn:fail:output-group-report | stable | 0 | procedure | 1 | none | none |
| exn:fail:output-group? | stable | 0 | procedure | 1 | none | none |
| exn:fail:skia-sksl-diagnostics | stable | 0 | procedure | 1 | none | none |
| exn:fail:skia-sksl-kind | stable | 0 | procedure | 1 | none | none |
| exn:fail:skia-sksl-source | stable | 0 | procedure | 1 | none | none |
| exn:fail:skia-sksl? | stable | 0 | procedure | 1 | none | none |
| float-pixel-formats | stable | 0 | value | — | — | — |
| font-baseline-snap? | stable | 0 | procedure | 1 | none | none |
| font-break-text | stable | 0 | procedure | 3 | none | #:paint |
| font-char->glyph | stable | 0 | procedure | 2 | none | none |
| font-edging | stable | 0 | procedure | 1 | none | none |
| font-embedded-bitmaps? | stable | 0 | procedure | 1 | none | none |
| font-embolden? | stable | 0 | procedure | 1 | none | none |
| font-force-auto-hinting? | stable | 0 | procedure | 1 | none | none |
| font-get-metrics | stable | 0 | procedure | 1 | none | none |
| font-glyph-bounds | stable | 0 | procedure | 2 | none | #:paint |
| font-glyph-path | stable | 0 | procedure | 2 | none | none |
| font-glyph-paths | stable | 0 | procedure | 2 | none | none |
| font-glyph-positions | stable | 0 | procedure | 2 | none | #:origin |
| font-glyph-widths | stable | 0 | procedure | 2 | none | #:paint |
| font-glyph-widths+bounds | stable | 0 | procedure | 2 | none | #:paint |
| font-glyph-x-positions | stable | 0 | procedure | 2 | none | #:origin |
| font-hinting | stable | 0 | procedure | 1 | none | none |
| font-linear-metrics? | stable | 0 | procedure | 1 | none | none |
| font-manager-families | stable | 0 | procedure | 1 | none | none |
| font-manager-family-count | stable | 0 | procedure | 1 | none | none |
| font-manager-family-name | stable | 0 | procedure | 2 | none | none |
| font-manager-match-character | stable | 0 | procedure | 2 | none | #:family, #:languages, #:slant, #:weight, #:width |
| font-manager-match-family | stable | 0 | procedure | 2 | none | #:slant, #:weight, #:width |
| font-manager-style-set | stable | 0 | procedure | 2 | none | none |
| font-manager-style-set-ref | stable | 0 | procedure | 2 | none | none |
| font-manager-typeface-from-bytes | stable | 0 | procedure | 2 | none | #:index |
| font-manager? | stable | 0 | procedure | 1 | none | none |
| font-metrics-ascent | stable | 0 | procedure | 1 | none | none |
| font-metrics-average-character-width | stable | 0 | procedure | 1 | none | none |
| font-metrics-bottom | stable | 0 | procedure | 1 | none | none |
| font-metrics-cap-height | stable | 0 | procedure | 1 | none | none |
| font-metrics-descent | stable | 0 | procedure | 1 | none | none |
| font-metrics-leading | stable | 0 | procedure | 1 | none | none |
| font-metrics-max-character-width | stable | 0 | procedure | 1 | none | none |
| font-metrics-spacing | stable | 0 | procedure | 1 | none | none |
| font-metrics-strikeout-position | stable | 0 | procedure | 1 | none | none |
| font-metrics-strikeout-thickness | stable | 0 | procedure | 1 | none | none |
| font-metrics-top | stable | 0 | procedure | 1 | none | none |
| font-metrics-underline-position | stable | 0 | procedure | 1 | none | none |
| font-metrics-underline-thickness | stable | 0 | procedure | 1 | none | none |
| font-metrics-x-height | stable | 0 | procedure | 1 | none | none |
| font-metrics-x-max | stable | 0 | procedure | 1 | none | none |
| font-metrics-x-min | stable | 0 | procedure | 1 | none | none |
| font-metrics? | stable | 0 | procedure | 1 | none | none |
| font-scale-x | stable | 0 | procedure | 1 | none | none |
| font-set-baseline-snap! | stable | 0 | procedure | 2 | none | none |
| font-set-edging! | stable | 0 | procedure | 2 | none | none |
| font-set-embedded-bitmaps! | stable | 0 | procedure | 2 | none | none |
| font-set-embolden! | stable | 0 | procedure | 2 | none | none |
| font-set-force-auto-hinting! | stable | 0 | procedure | 2 | none | none |
| font-set-hinting! | stable | 0 | procedure | 2 | none | none |
| font-set-linear-metrics! | stable | 0 | procedure | 2 | none | none |
| font-set-scale-x! | stable | 0 | procedure | 2 | none | none |
| font-set-size! | stable | 0 | procedure | 2 | none | none |
| font-set-skew-x! | stable | 0 | procedure | 2 | none | none |
| font-set-subpixel! | stable | 0 | procedure | 2 | none | none |
| font-set-typeface! | stable | 0 | procedure | 2 | none | none |
| font-size | stable | 0 | procedure | 1 | none | none |
| font-skew-x | stable | 0 | procedure | 1 | none | none |
| font-style-entry-index | stable | 0 | procedure | 1 | none | none |
| font-style-entry-name | stable | 0 | procedure | 1 | none | none |
| font-style-entry-style | stable | 0 | procedure | 1 | none | none |
| font-style-entry? | stable | 0 | procedure | 1 | none | none |
| font-style-set-count | stable | 0 | procedure | 1 | none | none |
| font-style-set-match | stable | 0 | procedure | 1, 2 | none | none |
| font-style-set-ref | stable | 0 | procedure | 2 | none | none |
| font-style-set-styles | stable | 0 | procedure | 1 | none | none |
| font-style-set-typeface | stable | 0 | procedure | 2 | none | none |
| font-style-set? | stable | 0 | procedure | 1 | none | none |
| font-style-slant | stable | 0 | procedure | 1 | none | none |
| font-style-weight | stable | 0 | procedure | 1 | none | none |
| font-style-width | stable | 0 | procedure | 1 | none | none |
| font-style? | stable | 0 | procedure | 1 | none | none |
| font-subpixel? | stable | 0 | procedure | 1 | none | none |
| font-table-tag | stable | 0 | procedure | 1 | none | none |
| font-table-tag->bytes | stable | 0 | procedure | 1 | none | none |
| font-text->glyphs | stable | 0 | procedure | 2 | none | none |
| font-typeface | stable | 0 | procedure | 1 | none | none |
| font? | stable | 0 | procedure | 1 | none | none |
| harfbuzz-available? | stable | 0 | procedure | 0 | none | none |
| harfbuzz-check! | stable | 0 | procedure | 0 | none | none |
| harfbuzz-native-library-path | stable | 0 | procedure | 0 | none | none |
| harfbuzz-native-version | stable | 0 | procedure | 0 | none | none |
| harfbuzz-package-version | stable | 0 | value | — | — | — |
| image->encoded-bytes | stable | 0 | procedure | 2 | none | #:color-space, #:icc-description, #:icc-profile, #:jpeg-alpha, #:jpeg-downsample, #:png-compression, #:quality, #:webp-lossless? |
| image->image-info | stable | 0 | procedure | 1 | none | none |
| image->jpeg-bytes | stable | 0 | procedure | 1 | none | #:alpha, #:color-space, #:downsample, #:icc-description, #:icc-profile, #:quality |
| image->non-texture-image | stable | 0 | procedure | 1 | none | none |
| image->png-bytes | stable | 0 | procedure | 1 | none | #:color-space, #:compression, #:icc-description, #:icc-profile |
| image->port | stable | 0 | procedure | 3 | none | #:cancel-evt, #:close?, #:jpeg-alpha, #:jpeg-downsample, #:limit, #:png-compression, #:quality, #:webp-lossless? |
| image->raster-buffer | stable | 0 | procedure | 1 | none | #:cache?, #:info, #:row-bytes, #:sampling |
| image->raster-image | stable | 0 | procedure | 1 | none | none |
| image->rgba-bytes | stable | 0 | procedure | 1 | none | #:color-space, #:premultiplied? |
| image->webp-bytes | stable | 0 | procedure | 1 | none | #:color-space, #:icc-description, #:icc-profile, #:lossless?, #:quality |
| image-alpha-only? | stable | 0 | procedure | 1 | none | none |
| image-alpha-type | stable | 0 | procedure | 1 | none | none |
| image-apply-filter | stable | 0 | procedure | 2 | #:clip | #:clip, #:subset |
| image-color-space | stable | 0 | procedure | 1 | none | none |
| image-color-type | stable | 0 | procedure | 1 | none | none |
| image-convert-color-space | stable | 0 | procedure | 2 | none | #:source-color-space |
| image-filter? | stable | 0 | procedure | 1 | none | none |
| image-frame-from-bytes | stable | 0 | procedure | 1, 2 | none | #:color-space, #:normalize-origin? |
| image-frame-from-file | stable | 0 | procedure | 1, 2 | none | #:color-space, #:normalize-origin? |
| image-from-bytes | stable | 0 | procedure | 1 | none | none |
| image-from-file | stable | 0 | procedure | 1 | none | none |
| image-from-port | stable | 0 | procedure | 1 | none | #:cancel-evt, #:close?, #:length, #:limit, #:normalize-origin?, #:seekable? |
| image-from-port/buffered | stable | 0 | procedure | 1 | none | #:cancel-evt, #:close?, #:limit |
| image-grid-cell-color | stable | 0 | procedure | 1 | none | none |
| image-grid-cell-column | stable | 0 | procedure | 1 | none | none |
| image-grid-cell-destination | stable | 0 | procedure | 1 | none | none |
| image-grid-cell-kind | stable | 0 | procedure | 1 | none | none |
| image-grid-cell-row | stable | 0 | procedure | 1 | none | none |
| image-grid-cell-source | stable | 0 | procedure | 1 | none | none |
| image-grid-cell? | stable | 0 | procedure | 1 | none | none |
| image-grid-plan->jsexpr | stable | 0 | procedure | 1 | none | none |
| image-height | stable | 0 | procedure | 1 | none | none |
| image-info-alpha-type | stable | 0 | procedure | 1 | none | none |
| image-info-byte-order | stable | 0 | procedure | 1 | none | none |
| image-info-bytes-per-pixel | stable | 0 | procedure | 1 | none | none |
| image-info-channel-bits | stable | 0 | procedure | 1 | none | none |
| image-info-color-space | stable | 0 | procedure | 1 | none | none |
| image-info-color-type | stable | 0 | procedure | 1 | none | none |
| image-info-height | stable | 0 | procedure | 1 | none | none |
| image-info-min-row-bytes | stable | 0 | procedure | 1 | none | none |
| image-info-sample-type | stable | 0 | procedure | 1 | none | none |
| image-info-storage-layout | stable | 0 | procedure | 1 | none | #:row-bytes |
| image-info-supports? | stable | 0 | procedure | 2 | none | none |
| image-info-width | stable | 0 | procedure | 1 | none | none |
| image-info-with-dimensions | stable | 0 | procedure | 3 | none | none |
| image-info? | stable | 0 | procedure | 1 | none | none |
| image-lattice-bounds | stable | 0 | procedure | 1 | none | none |
| image-lattice-cell-types | stable | 0 | procedure | 1 | none | none |
| image-lattice-colors | stable | 0 | procedure | 1 | none | none |
| image-lattice-plan | stable | 0 | procedure | 7 | none | none |
| image-lattice-x-divisions | stable | 0 | procedure | 1 | none | none |
| image-lattice-y-divisions | stable | 0 | procedure | 1 | none | none |
| image-lattice? | stable | 0 | procedure | 1 | none | none |
| image-lazy-generated? | stable | 0 | procedure | 1 | none | none |
| image-nine-plan | stable | 0 | procedure | 7 | none | none |
| image-original-encoded-bytes | stable | 0 | procedure | 1 | none | none |
| image-pixels-available? | stable | 0 | procedure | 1 | none | none |
| image-read-pixmap! | stable | 0 | procedure | 2 | none | #:cache?, #:source-x, #:source-y |
| image-scale-pixmap! | stable | 0 | procedure | 2 | none | #:cache?, #:sampling |
| image-subset | stable | 0 | procedure | 5 | none | none |
| image-texture-backed? | stable | 0 | procedure | 1 | none | none |
| image-unique-id | stable | 0 | procedure | 1 | none | none |
| image-valid? | stable | 0 | procedure | 1 | none | none |
| image-width | stable | 0 | procedure | 1 | none | none |
| image-write-stream! | stable | 0 | procedure | 3 | none | #:jpeg-alpha, #:jpeg-downsample, #:png-compression, #:quality, #:webp-lossless? |
| image? | stable | 0 | procedure | 1 | none | none |
| in-path-segments | stable | 0 | procedure | 1 | none | #:force-closed?, #:mode |
| in-region-clipped-rectangles | stable | 0 | procedure | 2 | none | none |
| in-region-rectangles | stable | 0 | procedure | 1 | none | none |
| in-region-spans | stable | 0 | procedure | 4 | none | none |
| incremental-progress-initialized-rows | stable | 0 | procedure | 1 | none | none |
| incremental-progress-result | stable | 0 | procedure | 1 | none | none |
| incremental-progress-state | stable | 0 | procedure | 1 | none | none |
| incremental-progress? | stable | 0 | procedure | 1 | none | none |
| incremental-snapshot->raster-buffer | stable | 0 | procedure | 1 | none | none |
| incremental-snapshot-bytes | stable | 0 | procedure | 1 | none | none |
| incremental-snapshot-info | stable | 0 | procedure | 1 | none | none |
| incremental-snapshot-progress | stable | 0 | procedure | 1 | none | none |
| incremental-snapshot-row-bytes | stable | 0 | procedure | 1 | none | none |
| incremental-snapshot? | stable | 0 | procedure | 1 | none | none |
| input-stream->bytes | stable | 0 | procedure | 1 | none | none |
| input-stream-at-end? | stable | 0 | procedure | 1 | none | none |
| input-stream-duplicate | stable | 0 | procedure | 1 | none | none |
| input-stream-fork | stable | 0 | procedure | 1 | none | none |
| input-stream-length | stable | 0 | procedure | 1 | none | none |
| input-stream-move! | stable | 0 | procedure | 2 | none | none |
| input-stream-peek-bytes | stable | 0 | procedure | 2 | none | none |
| input-stream-position | stable | 0 | procedure | 1 | none | none |
| input-stream-read-bytes | stable | 0 | procedure | 2 | none | none |
| input-stream-rewind! | stable | 0 | procedure | 1 | none | none |
| input-stream-seek! | stable | 0 | procedure | 2 | none | none |
| input-stream-skip! | stable | 0 | procedure | 2 | none | none |
| integer-pixel-formats | stable | 0 | value | — | — | — |
| layer-options-bounds | stable | 0 | procedure | 1 | none | none |
| layer-options-f16? | stable | 0 | procedure | 1 | none | none |
| layer-options-flags | stable | 0 | procedure | 1 | none | none |
| layer-options-initialize-with-previous? | stable | 0 | procedure | 1 | none | none |
| layer-options-preserve-lcd-text? | stable | 0 | procedure | 1 | none | none |
| layer-options? | stable | 0 | procedure | 1 | none | none |
| layout-break-opportunity-index | stable | 0 | procedure | 1 | none | none |
| layout-break-opportunity-insert | stable | 0 | procedure | 1 | none | none |
| layout-break-opportunity? | stable | 0 | procedure | 1 | none | none |
| layout-mixed-text | stable | 0 | procedure | 3 | none | #:align, #:break-provider, #:direction, #:features, #:language, #:line-height, #:width |
| layout-text | stable | 0 | procedure | 2 | none | #:align, #:break-provider, #:direction, #:features, #:language, #:line-height, #:script, #:width |
| live-streams-available? | stable | 0 | procedure | 0 | none | none |
| live-streams-check! | stable | 0 | procedure | 0 | none | none |
| make-1d-path-effect | stable | 0 | procedure | 2, 3 | none | #:style |
| make-2d-line-path-effect | stable | 0 | procedure | 2 | none | none |
| make-2d-path-effect | stable | 0 | procedure | 2 | none | none |
| make-arithmetic-blender | stable | 0 | procedure | 4 | none | #:enforce-premul? |
| make-arithmetic-image-filter | stable | 0 | procedure | 6 | none | #:crop, #:enforce-premul? |
| make-atlas-transform | stable | 0 | procedure | 2 | none | #:anchor, #:rotation, #:scale |
| make-blend-color-filter | stable | 0 | procedure | 2 | none | none |
| make-blend-image-filter | stable | 0 | procedure | 3 | none | #:crop |
| make-blend-mode-blender | stable | 0 | procedure | 1 | none | none |
| make-blend-shader | stable | 0 | procedure | 3 | none | none |
| make-blender-image-filter | stable | 0 | procedure | 3 | none | #:crop |
| make-blender-shader | stable | 0 | procedure | 3 | none | none |
| make-blur-image-filter | stable | 0 | procedure | 2 | none | #:crop, #:input, #:tile-mode |
| make-blur-mask-filter | stable | 0 | procedure | 1 | none | #:respect-ctm?, #:style |
| make-clip-mask-filter | stable | 0 | procedure | 2 | none | none |
| make-codec-incremental | stable | 0 | procedure | 0 | none | #:alpha-type, #:color-space, #:color-type, #:limit, #:row-bytes |
| make-color-filter-image-filter | stable | 0 | procedure | 1 | none | #:crop, #:input |
| make-color-matrix-filter | stable | 0 | procedure | 1 | none | none |
| make-color-shader | stable | 0 | procedure | 1 | none | none |
| make-color4f | stable | 0 | procedure | 3, 4 | none | none |
| make-color4f-shader | stable | 0 | procedure | 1 | #:color-space | #:color-space |
| make-compose-color-filter | stable | 0 | procedure | 2 | none | none |
| make-compose-image-filter | stable | 0 | procedure | 2 | none | #:crop |
| make-compose-path-effect | stable | 0 | procedure | 2 | none | none |
| make-corner-path-effect | stable | 0 | procedure | 1 | none | none |
| make-crop-image-filter | stable | 0 | procedure | 1 | none | #:input |
| make-cubic-patch | stable | 0 | procedure | 1 | none | #:colors, #:texture-coordinates |
| make-dash-path-effect | stable | 0 | procedure | 1, 2 | none | none |
| make-dilate-image-filter | stable | 0 | procedure | 2 | none | #:crop, #:input |
| make-discrete-path-effect | stable | 0 | procedure | 2, 3 | none | none |
| make-displacement-map-image-filter | stable | 0 | procedure | 5 | none | #:crop |
| make-distant-lit-diffuse-image-filter | stable | 0 | procedure | 2 | none | #:coefficient, #:crop, #:input, #:surface-scale |
| make-distant-lit-specular-image-filter | stable | 0 | procedure | 2 | none | #:coefficient, #:crop, #:input, #:shininess, #:surface-scale |
| make-drop-shadow-image-filter | stable | 0 | procedure | 5 | none | #:crop, #:input |
| make-drop-shadow-only-image-filter | stable | 0 | procedure | 5 | none | #:crop, #:input |
| make-empty-font-style-set | stable | 0 | procedure | 0 | none | none |
| make-empty-rounded-rect | stable | 0 | procedure | 0 | none | none |
| make-empty-shader | stable | 0 | procedure | 0 | none | none |
| make-erode-image-filter | stable | 0 | procedure | 2 | none | #:crop, #:input |
| make-file-input-stream | stable | 0 | procedure | 1 | none | #:limit |
| make-file-output-stream | stable | 0 | procedure | 1 | none | #:exists, #:limit |
| make-font | stable | 0 | procedure | 0, 1 | none | #:baseline-snap?, #:edging, #:embedded-bitmaps?, #:embolden?, #:force-auto-hinting?, #:hinting, #:linear-metrics?, #:scale-x, #:size, #:skew-x, #:subpixel? |
| make-font-manager | stable | 0 | procedure | 0 | none | none |
| make-font-style | stable | 0 | procedure | 0 | none | #:slant, #:weight, #:width |
| make-fractal-noise-shader | stable | 0 | procedure | 3, 4 | none | #:tile-size |
| make-gamma-mask-filter | stable | 0 | procedure | 1 | none | none |
| make-high-contrast-color-filter | stable | 0 | procedure | 0 | none | #:contrast, #:grayscale?, #:invert-style |
| make-hsla-matrix-filter | stable | 0 | procedure | 1 | none | none |
| make-image-info | stable | 0 | procedure | 2 | none | #:alpha-type, #:color-space, #:color-type |
| make-image-lattice | stable | 0 | procedure | 2 | none | #:bounds, #:cell-types, #:colors |
| make-image-shader | stable | 0 | procedure | 1 | none | #:sampling, #:tile-x, #:tile-y |
| make-image-source-filter | stable | 0 | procedure | 1 | none | #:crop, #:destination, #:sampling, #:source |
| make-layer-options | stable | 0 | procedure | 0 | none | #:bounds, #:f16?, #:initialize-with-previous?, #:preserve-lcd-text? |
| make-layout-break-opportunity | stable | 0 | procedure | 1, 2 | none | none |
| make-lerp-color-filter | stable | 0 | procedure | 3 | none | none |
| make-lighting-color-filter | stable | 0 | procedure | 2 | none | none |
| make-linear-gradient-color4f-shader | stable | 0 | procedure | 3 | #:color-space | #:color-space, #:matrix, #:stops, #:tile-mode |
| make-linear-gradient-shader | stable | 0 | procedure | 5 | none | #:positions, #:tile-mode |
| make-linear-srgb-color-space | stable | 0 | procedure | 0 | none | none |
| make-linear-to-srgb-gamma-color-filter | stable | 0 | procedure | 0 | none | none |
| make-luma-color-filter | stable | 0 | procedure | 0 | none | none |
| make-magnifier-image-filter | stable | 0 | procedure | 2 | none | #:crop, #:input, #:inset, #:sampling |
| make-matrix | stable | 0 | procedure | 0, 1, 2, 3, 4, 5, 6 | none | none |
| make-matrix-convolution-image-filter | stable | 0 | procedure | 3 | none | #:bias, #:convolve-alpha?, #:crop, #:gain, #:input, #:offset, #:tile-mode |
| make-matrix-transform-image-filter | stable | 0 | procedure | 1 | none | #:crop, #:input, #:sampling |
| make-matrix3 | stable | 0 | procedure | 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 | none | none |
| make-matrix4 | stable | 0 | procedure | 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 | none | none |
| make-memory-input-stream | stable | 0 | procedure | 1 | none | #:limit |
| make-memory-output-stream | stable | 0 | procedure | 0 | none | #:limit |
| make-merge-image-filter | stable | 0 | procedure | 1 | none | #:crop |
| make-nine-patch-rounded-rect | stable | 0 | procedure | 8 | none | none |
| make-offset-image-filter | stable | 0 | procedure | 2 | none | #:crop, #:input |
| make-output-page | stable | 0 | procedure | 3 | none | #:background, #:clip?, #:margins, #:unit |
| make-paint | stable | 0 | procedure | 0 | none | #:antialias?, #:blend-mode, #:cap, #:color, #:color-filter, #:image-filter, #:join, #:mask-filter, #:miter-limit, #:path-effect, #:shader, #:stroke-width, #:style |
| make-paint/color4f | stable | 0 | procedure | 1 | #:color-space | #:antialias?, #:color-space, #:stroke-width, #:style |
| make-path | stable | 0 | procedure | 0, 1 | none | #:fill-rule |
| make-path-measure | stable | 0 | procedure | 1 | none | #:force-closed?, #:res-scale |
| make-pdf-document | stable | 0 | procedure | 0 | none | #:author, #:creation-date, #:creator, #:encoding-quality, #:keywords, #:modified-date, #:pdfa?, #:producer, #:raster-dpi, #:subject, #:title |
| make-picture-image-filter | stable | 0 | procedure | 1 | none | #:crop, #:target |
| make-picture-recorder | stable | 0 | procedure | 0 | none | none |
| make-picture-shader | stable | 0 | procedure | 1 | none | #:local-matrix, #:sampling, #:tile-rect, #:tile-x, #:tile-y |
| make-point-lit-diffuse-image-filter | stable | 0 | procedure | 2 | none | #:coefficient, #:crop, #:input, #:surface-scale |
| make-point-lit-specular-image-filter | stable | 0 | procedure | 2 | none | #:coefficient, #:crop, #:input, #:shininess, #:surface-scale |
| make-positioned-text-blob | stable | 0 | procedure | 3 | none | none |
| make-radial-gradient-color4f-shader | stable | 0 | procedure | 3 | #:color-space | #:color-space, #:matrix, #:stops, #:tile-mode |
| make-radial-gradient-shader | stable | 0 | procedure | 4 | none | #:positions, #:tile-mode |
| make-raster-buffer | stable | 0 | procedure | 2 | none | #:color-space, #:row-bytes |
| make-raster-buffer-from-info | stable | 0 | procedure | 1 | none | #:row-bytes |
| make-raw-image-shader | stable | 0 | procedure | 1 | none | #:matrix, #:sampling, #:tile-x, #:tile-y |
| make-region | stable | 0 | procedure | 0, 1 | none | none |
| make-rgb-color-space | stable | 0 | procedure | 2 | none | none |
| make-rounded-rect | stable | 0 | procedure | 4 | none | #:radii |
| make-runtime-effect | stable | 0 | procedure | 1 | none | #:kind |
| make-shader-image-filter | stable | 0 | procedure | 1 | none | #:crop, #:dither? |
| make-shader-mask-filter | stable | 0 | procedure | 1 | none | none |
| make-shaper | stable | 0 | procedure | 1 | none | none |
| make-spot-lit-diffuse-image-filter | stable | 0 | procedure | 3 | none | #:coefficient, #:crop, #:cutoff-angle, #:exponent, #:input, #:surface-scale |
| make-spot-lit-specular-image-filter | stable | 0 | procedure | 3 | none | #:coefficient, #:crop, #:cutoff-angle, #:exponent, #:input, #:shininess, #:surface-scale |
| make-srgb-color-space | stable | 0 | procedure | 0 | none | none |
| make-srgb-to-linear-gamma-color-filter | stable | 0 | procedure | 0 | none | none |
| make-sum-path-effect | stable | 0 | procedure | 2 | none | none |
| make-surface | stable | 0 | procedure | 2 | none | #:background, #:color-space |
| make-surface-from-info | stable | 0 | procedure | 1 | none | #:background, #:row-bytes |
| make-surface-properties | stable | 0 | procedure | 0 | none | #:always-dither?, #:device-independent-fonts?, #:dynamic-msaa?, #:pixel-geometry |
| make-svg-document | stable | 0 | procedure | 2 | none | #:description, #:id-prefix, #:title |
| make-sweep-gradient-color4f-shader | stable | 0 | procedure | 2 | #:color-space | #:color-space, #:end-angle, #:matrix, #:start-angle, #:stops, #:tile-mode |
| make-sweep-gradient-shader | stable | 0 | procedure | 3 | none | #:end-angle, #:positions, #:start-angle, #:tile-mode |
| make-table-argb-color-filter | stable | 0 | procedure | 0 | none | #:alpha, #:blue, #:green, #:red |
| make-table-color-filter | stable | 0 | procedure | 1 | none | none |
| make-table-mask-filter | stable | 0 | procedure | 1 | none | none |
| make-text-blob-builder | stable | 0 | procedure | 0 | none | none |
| make-tile-image-filter | stable | 0 | procedure | 2 | none | #:crop, #:input |
| make-transfer-function | stable | 0 | procedure | 7 | none | none |
| make-trim-path-effect | stable | 0 | procedure | 2 | none | #:mode |
| make-turbulence-shader | stable | 0 | procedure | 3, 4 | none | #:tile-size |
| make-two-point-conical-gradient-color4f-shader | stable | 0 | procedure | 5 | #:color-space | #:color-space, #:matrix, #:stops, #:tile-mode |
| make-two-point-conical-gradient-shader | stable | 0 | procedure | 7 | none | #:positions, #:tile-mode |
| make-typeface | stable | 0 | procedure | 0 | none | none |
| make-vertices | stable | 0 | procedure | 2 | none | #:colors, #:indices, #:texture-coordinates |
| mask-filter? | stable | 0 | procedure | 1 | none | none |
| matrix->matrix3 | stable | 0 | procedure | 1 | none | none |
| matrix->matrix4 | stable | 0 | procedure | 1 | none | none |
| matrix->vector | stable | 0 | procedure | 1 | none | none |
| matrix-compose | stable | 0 | procedure | 0+ | none | none |
| matrix-identity | stable | 0 | value | — | — | — |
| matrix-invert | stable | 0 | procedure | 1 | none | none |
| matrix-map-point | stable | 0 | procedure | 3 | none | none |
| matrix-map-rect | stable | 0 | procedure | 5 | none | none |
| matrix-map-vector | stable | 0 | procedure | 3 | none | none |
| matrix-rotate | stable | 0 | procedure | 1 | none | none |
| matrix-rotate-degrees | stable | 0 | procedure | 1 | none | none |
| matrix-scale | stable | 0 | procedure | 1, 2 | none | none |
| matrix-skew | stable | 0 | procedure | 2 | none | none |
| matrix-translate | stable | 0 | procedure | 2 | none | none |
| matrix-x0 | stable | 0 | procedure | 1 | none | none |
| matrix-xx | stable | 0 | procedure | 1 | none | none |
| matrix-xy | stable | 0 | procedure | 1 | none | none |
| matrix-y0 | stable | 0 | procedure | 1 | none | none |
| matrix-yx | stable | 0 | procedure | 1 | none | none |
| matrix-yy | stable | 0 | procedure | 1 | none | none |
| matrix3->matrix | stable | 0 | procedure | 1 | none | none |
| matrix3->matrix4 | stable | 0 | procedure | 1 | none | none |
| matrix3->vector | stable | 0 | procedure | 1 | none | none |
| matrix3-affine? | stable | 0 | procedure | 1 | none | none |
| matrix3-compose | stable | 0 | procedure | 0+ | none | none |
| matrix3-identity | stable | 0 | value | — | — | — |
| matrix3-invert | stable | 0 | procedure | 1 | none | none |
| matrix3-map-homogeneous | stable | 0 | procedure | 3, 4 | none | none |
| matrix3-map-point | stable | 0 | procedure | 3 | none | none |
| matrix3-map-rect | stable | 0 | procedure | 5 | none | none |
| matrix3-perspective | stable | 0 | procedure | 2 | none | none |
| matrix3-ref | stable | 0 | procedure | 3 | none | none |
| matrix3-transpose | stable | 0 | procedure | 1 | none | none |
| matrix3? | stable | 0 | procedure | 1 | none | none |
| matrix4->matrix | stable | 0 | procedure | 1 | none | none |
| matrix4->matrix3 | stable | 0 | procedure | 1 | none | none |
| matrix4->vector | stable | 0 | procedure | 1 | none | none |
| matrix4-affine-2d? | stable | 0 | procedure | 1 | none | none |
| matrix4-compose | stable | 0 | procedure | 0+ | none | none |
| matrix4-identity | stable | 0 | value | — | — | — |
| matrix4-invert | stable | 0 | procedure | 1 | none | none |
| matrix4-map-homogeneous | stable | 0 | procedure | 3, 4, 5 | none | none |
| matrix4-map-point | stable | 0 | procedure | 3, 4 | none | none |
| matrix4-map-rect | stable | 0 | procedure | 5 | none | none |
| matrix4-perspective | stable | 0 | procedure | 1 | none | none |
| matrix4-project-xy | stable | 0 | procedure | 1 | none | none |
| matrix4-ref | stable | 0 | procedure | 3 | none | none |
| matrix4-rotate-x-degrees | stable | 0 | procedure | 1 | none | none |
| matrix4-rotate-y-degrees | stable | 0 | procedure | 1 | none | none |
| matrix4-rotate-z-degrees | stable | 0 | procedure | 1 | none | none |
| matrix4-scale | stable | 0 | procedure | 1, 2, 3 | none | none |
| matrix4-translate | stable | 0 | procedure | 2, 3 | none | none |
| matrix4-transpose | stable | 0 | procedure | 1 | none | none |
| matrix4? | stable | 0 | procedure | 1 | none | none |
| matrix? | stable | 0 | procedure | 1 | none | none |
| measure-simple-text | stable | 0 | procedure | 2 | none | #:paint |
| memory-statistic-kind | stable | 0 | procedure | 1 | none | none |
| memory-statistic-name | stable | 0 | procedure | 1 | none | none |
| memory-statistic-units | stable | 0 | procedure | 1 | none | none |
| memory-statistic-value | stable | 0 | procedure | 1 | none | none |
| memory-statistic-value-name | stable | 0 | procedure | 1 | none | none |
| memory-statistic? | stable | 0 | procedure | 1 | none | none |
| memory-statistics->jsexpr | stable | 0 | procedure | 1 | none | none |
| memory-statistics-detailed? | stable | 0 | procedure | 1 | none | none |
| memory-statistics-dropped-count | stable | 0 | procedure | 1 | none | none |
| memory-statistics-dump-wrapped? | stable | 0 | procedure | 1 | none | none |
| memory-statistics-entries | stable | 0 | procedure | 1 | none | none |
| memory-statistics-scope | stable | 0 | procedure | 1 | none | none |
| memory-statistics-string-bytes | stable | 0 | procedure | 1 | none | none |
| memory-statistics-truncated? | stable | 0 | procedure | 1 | none | none |
| memory-statistics? | stable | 0 | procedure | 1 | none | none |
| mixed-text-layout-height | stable | 0 | procedure | 1 | none | none |
| mixed-text-layout-line-count | stable | 0 | procedure | 1 | none | none |
| mixed-text-layout-line-height | stable | 0 | procedure | 1 | none | none |
| mixed-text-layout-lines | stable | 0 | procedure | 1 | none | none |
| mixed-text-layout-width | stable | 0 | procedure | 1 | none | none |
| mixed-text-layout? | stable | 0 | procedure | 1 | none | none |
| mixed-text-line-baseline | stable | 0 | procedure | 1 | none | none |
| mixed-text-line-direction | stable | 0 | procedure | 1 | none | none |
| mixed-text-line-origin-x | stable | 0 | procedure | 1 | none | none |
| mixed-text-line-runs | stable | 0 | procedure | 1 | none | none |
| mixed-text-line-text | stable | 0 | procedure | 1 | none | none |
| mixed-text-line-width | stable | 0 | procedure | 1 | none | none |
| mixed-text-line? | stable | 0 | procedure | 1 | none | none |
| mixed-text-run-direction | stable | 0 | procedure | 1 | none | none |
| mixed-text-run-family | stable | 0 | procedure | 1 | none | none |
| mixed-text-run-level | stable | 0 | procedure | 1 | none | none |
| mixed-text-run-origin-x | stable | 0 | procedure | 1 | none | none |
| mixed-text-run-script | stable | 0 | procedure | 1 | none | none |
| mixed-text-run-shaped-run | stable | 0 | procedure | 1 | none | none |
| mixed-text-run-text | stable | 0 | procedure | 1 | none | none |
| mixed-text-run-width | stable | 0 | procedure | 1 | none | none |
| mixed-text-run? | stable | 0 | procedure | 1 | none | none |
| named-transfer-function | stable | 0 | procedure | 1 | none | none |
| named-xyz-d50 | stable | 0 | procedure | 1 | none | none |
| native-package-version | stable | 0 | value | — | — | — |
| output->bytes | stable | 0 | procedure | 2 | none | #:description, #:encoding-quality, #:id-prefix, #:pdfa?, #:raster-dpi, #:text-mode, #:title |
| output->bytes/audit | stable | 0 | procedure | 2 | none | #:description, #:encoding-quality, #:id-prefix, #:pdfa?, #:policy, #:raster-dpi, #:text-mode, #:title |
| output->port | stable | 0 | procedure | 3 | none | #:cancel-evt, #:close?, #:limit, #:policy, #:raster-dpi, #:text-mode |
| output-audit-event-details | stable | 0 | procedure | 1 | none | none |
| output-audit-event-feature | stable | 0 | procedure | 1 | none | none |
| output-audit-event-operation | stable | 0 | procedure | 1 | none | none |
| output-audit-event-page | stable | 0 | procedure | 1 | none | none |
| output-audit-event-reason | stable | 0 | procedure | 1 | none | none |
| output-audit-event-scope | stable | 0 | procedure | 1 | none | none |
| output-audit-event-status | stable | 0 | procedure | 1 | none | none |
| output-audit-event? | stable | 0 | procedure | 1 | none | none |
| output-audit-report->jsexpr | stable | 0 | procedure | 1 | none | none |
| output-audit-report-backend | stable | 0 | procedure | 1 | none | none |
| output-audit-report-blocking? | stable | 0 | procedure | 1 | none | none |
| output-audit-report-events | stable | 0 | procedure | 1 | none | none |
| output-audit-report-mode | stable | 0 | procedure | 1 | none | none |
| output-audit-report-pages | stable | 0 | procedure | 1 | none | none |
| output-audit-report-vector-only? | stable | 0 | procedure | 1 | none | none |
| output-audit-report? | stable | 0 | procedure | 1 | none | none |
| output-backends | stable | 0 | value | — | — | — |
| output-capability-backend | stable | 0 | procedure | 1 | none | none |
| output-capability-feature | stable | 0 | procedure | 1 | none | none |
| output-capability-for | stable | 0 | procedure | 2 | none | none |
| output-capability-reason | stable | 0 | procedure | 1 | none | none |
| output-capability-status | stable | 0 | procedure | 1 | none | none |
| output-capability? | stable | 0 | procedure | 1 | none | none |
| output-feature-names | stable | 0 | value | — | — | — |
| output-group-report->jsexpr | stable | 0 | procedure | 1 | none | none |
| output-group-report-backend | stable | 0 | procedure | 1 | none | none |
| output-group-report-bounds | stable | 0 | procedure | 1 | none | none |
| output-group-report-children | stable | 0 | procedure | 1 | none | none |
| output-group-report-execution | stable | 0 | procedure | 1 | none | none |
| output-group-report-features | stable | 0 | procedure | 1 | none | none |
| output-group-report-label | stable | 0 | procedure | 1 | none | none |
| output-group-report-padded-bounds | stable | 0 | procedure | 1 | none | none |
| output-group-report-pixel-size | stable | 0 | procedure | 1 | none | none |
| output-group-report-policy | stable | 0 | procedure | 1 | none | none |
| output-group-report-reason | stable | 0 | procedure | 1 | none | none |
| output-group-report-scale | stable | 0 | procedure | 1 | none | none |
| output-group-report-strategy | stable | 0 | procedure | 1 | none | none |
| output-group-report? | stable | 0 | procedure | 1 | none | none |
| output-page->image | stable | 0 | procedure | 1 | none | #:color-space, #:dpi, #:text-mode |
| output-page-background | stable | 0 | procedure | 1 | none | none |
| output-page-clip? | stable | 0 | procedure | 1 | none | none |
| output-page-content-size | stable | 0 | procedure | 1 | none | none |
| output-page-height | stable | 0 | procedure | 1 | none | none |
| output-page-margins | stable | 0 | procedure | 1 | none | none |
| output-page-size-in-points | stable | 0 | procedure | 1 | none | none |
| output-page-unit | stable | 0 | procedure | 1 | none | none |
| output-page-width | stable | 0 | procedure | 1 | none | none |
| output-page? | stable | 0 | procedure | 1 | none | none |
| output-raster-executor? | stable | 0 | procedure | 1 | none | none |
| output-stream->bytes | stable | 0 | procedure | 1 | none | none |
| output-stream-bytes-written | stable | 0 | procedure | 1 | none | none |
| output-stream-detach-input! | stable | 0 | procedure | 1 | none | none |
| output-stream-flush! | stable | 0 | procedure | 1 | none | none |
| output-stream-write-bytes! | stable | 0 | procedure | 2, 3, 4 | none | none |
| output-stream-write-port/buffered | stable | 0 | procedure | 2 | none | #:cancel-evt, #:close? |
| output-write-stream! | stable | 0 | procedure | 2 | none | #:policy, #:raster-dpi, #:text-mode |
| paint->fill-path | stable | 0 | procedure | 2 | none | #:cull, #:matrix |
| paint-antialias? | stable | 0 | procedure | 1 | none | none |
| paint-blend-mode-or-src-over | stable | 0 | procedure | 1 | none | none |
| paint-blender | stable | 0 | procedure | 1 | none | none |
| paint-cap | stable | 0 | procedure | 1 | none | none |
| paint-color | stable | 0 | procedure | 1 | none | none |
| paint-color-filter | stable | 0 | procedure | 1 | none | none |
| paint-color4f | stable | 0 | procedure | 1 | none | none |
| paint-copy | stable | 0 | procedure | 1 | none | none |
| paint-dither? | stable | 0 | procedure | 1 | none | none |
| paint-image-filter | stable | 0 | procedure | 1 | none | none |
| paint-join | stable | 0 | procedure | 1 | none | none |
| paint-mask-filter | stable | 0 | procedure | 1 | none | none |
| paint-miter-limit | stable | 0 | procedure | 1 | none | none |
| paint-path-effect | stable | 0 | procedure | 1 | none | none |
| paint-reset! | stable | 0 | procedure | 1 | none | none |
| paint-set-antialias! | stable | 0 | procedure | 2 | none | none |
| paint-set-blend-mode! | stable | 0 | procedure | 2 | none | none |
| paint-set-blender! | stable | 0 | procedure | 2 | none | none |
| paint-set-cap! | stable | 0 | procedure | 2 | none | none |
| paint-set-color! | stable | 0 | procedure | 2 | none | none |
| paint-set-color-filter! | stable | 0 | procedure | 2 | none | none |
| paint-set-color4f! | stable | 0 | procedure | 2 | #:color-space | #:color-space |
| paint-set-dither! | stable | 0 | procedure | 2 | none | none |
| paint-set-image-filter! | stable | 0 | procedure | 2 | none | none |
| paint-set-join! | stable | 0 | procedure | 2 | none | none |
| paint-set-mask-filter! | stable | 0 | procedure | 2 | none | none |
| paint-set-miter-limit! | stable | 0 | procedure | 2 | none | none |
| paint-set-path-effect! | stable | 0 | procedure | 2 | none | none |
| paint-set-shader! | stable | 0 | procedure | 2 | none | none |
| paint-set-stroke-width! | stable | 0 | procedure | 2 | none | none |
| paint-set-style! | stable | 0 | procedure | 2 | none | none |
| paint-shader | stable | 0 | procedure | 1 | none | none |
| paint-stroke-width | stable | 0 | procedure | 1 | none | none |
| paint-style | stable | 0 | procedure | 1 | none | none |
| paint? | stable | 0 | procedure | 1 | none | none |
| path->commands | stable | 0 | procedure | 1 | none | none |
| path->region | stable | 0 | procedure | 2 | none | none |
| path->svg-path | stable | 0 | procedure | 1 | none | none |
| path-add-arc! | stable | 0 | procedure | 7 | none | none |
| path-add-circle! | stable | 0 | procedure | 4 | none | #:direction |
| path-add-oval! | stable | 0 | procedure | 5 | none | #:direction |
| path-add-path! | stable | 0 | procedure | 2 | none | #:dx, #:dy, #:mode |
| path-add-polygon! | stable | 0 | procedure | 2 | none | #:closed? |
| path-add-rect! | stable | 0 | procedure | 5 | none | #:direction |
| path-add-rect-start! | stable | 0 | procedure | 6 | none | #:direction |
| path-add-reversed-path! | stable | 0 | procedure | 2 | none | none |
| path-add-rounded-rect! | stable | 0 | procedure | 7 | none | #:direction |
| path-add-rrect! | stable | 0 | procedure | 2 | none | #:direction, #:start-index |
| path-add-transformed! | stable | 0 | procedure | 3 | none | #:mode |
| path-arc-to! | stable | 0 | procedure | 6 | none | #:direction, #:large? |
| path-arc-to-oval! | stable | 0 | procedure | 7 | none | #:force-move? |
| path-as-line | stable | 0 | procedure | 1 | none | none |
| path-as-oval | stable | 0 | procedure | 1 | none | none |
| path-as-rectangle | stable | 0 | procedure | 1 | none | none |
| path-as-rounded-rect | stable | 0 | procedure | 1 | none | none |
| path-as-winding | stable | 0 | procedure | 1 | none | none |
| path-bounds | stable | 0 | procedure | 1 | none | none |
| path-close! | stable | 0 | procedure | 1 | none | none |
| path-combine | stable | 0 | procedure | 1 | none | none |
| path-conic-to! | stable | 0 | procedure | 6 | none | none |
| path-contains? | stable | 0 | procedure | 3 | none | none |
| path-contour-closed? | stable | 0 | procedure | 1 | none | none |
| path-contour-segments | stable | 0 | procedure | 1 | none | none |
| path-contour? | stable | 0 | procedure | 1 | none | none |
| path-contours | stable | 0 | procedure | 1 | none | #:force-closed?, #:mode |
| path-convex? | stable | 0 | procedure | 1 | none | none |
| path-copy | stable | 0 | procedure | 1 | none | none |
| path-cubic-to! | stable | 0 | procedure | 7 | none | none |
| path-difference | stable | 0 | procedure | 2 | none | none |
| path-effect? | stable | 0 | procedure | 1 | none | none |
| path-fill-bounds | stable | 0 | procedure | 1 | none | none |
| path-fill-rule | stable | 0 | procedure | 1 | none | none |
| path-intersect | stable | 0 | procedure | 2 | none | none |
| path-last-point | stable | 0 | procedure | 1 | none | none |
| path-line-to! | stable | 0 | procedure | 3 | none | none |
| path-measure-closed? | stable | 0 | procedure | 1 | none | none |
| path-measure-length | stable | 0 | procedure | 1 | none | none |
| path-measure-matrix | stable | 0 | procedure | 2 | none | #:mode |
| path-measure-next-contour! | stable | 0 | procedure | 1 | none | none |
| path-measure-position+tangent | stable | 0 | procedure | 2 | none | none |
| path-measure-segment | stable | 0 | procedure | 3 | none | #:start-with-move-to? |
| path-measure-set-path! | stable | 0 | procedure | 2 | none | #:force-closed? |
| path-measure? | stable | 0 | procedure | 1 | none | none |
| path-move-to! | stable | 0 | procedure | 3 | none | none |
| path-op | stable | 0 | procedure | 3 | none | none |
| path-point-count | stable | 0 | procedure | 1 | none | none |
| path-point-ref | stable | 0 | procedure | 2 | none | none |
| path-points | stable | 0 | procedure | 1 | none | none |
| path-quad-to! | stable | 0 | procedure | 5 | none | none |
| path-rarc-to! | stable | 0 | procedure | 6 | none | #:direction, #:large? |
| path-rconic-to! | stable | 0 | procedure | 6 | none | none |
| path-rcubic-to! | stable | 0 | procedure | 7 | none | none |
| path-rectangle-bounds | stable | 0 | procedure | 1 | none | none |
| path-rectangle-closed? | stable | 0 | procedure | 1 | none | none |
| path-rectangle-direction | stable | 0 | procedure | 1 | none | none |
| path-rectangle? | stable | 0 | procedure | 1 | none | none |
| path-reset! | stable | 0 | procedure | 1 | none | none |
| path-reverse-difference | stable | 0 | procedure | 2 | none | none |
| path-rewind! | stable | 0 | procedure | 1 | none | none |
| path-rline-to! | stable | 0 | procedure | 3 | none | none |
| path-rmove-to! | stable | 0 | procedure | 3 | none | none |
| path-rquad-to! | stable | 0 | procedure | 5 | none | none |
| path-segment-closing-line? | stable | 0 | procedure | 1 | none | none |
| path-segment-conic-weight | stable | 0 | procedure | 1 | none | none |
| path-segment-kinds | stable | 0 | procedure | 1 | none | none |
| path-segment-points | stable | 0 | procedure | 1 | none | none |
| path-segment-verb | stable | 0 | procedure | 1 | none | none |
| path-segment? | stable | 0 | procedure | 1 | none | none |
| path-segments | stable | 0 | procedure | 1 | none | #:force-closed?, #:mode |
| path-set-fill-rule! | stable | 0 | procedure | 2 | none | none |
| path-simplify | stable | 0 | procedure | 1 | none | none |
| path-tangent-arc-to! | stable | 0 | procedure | 6 | none | none |
| path-tight-bounds | stable | 0 | procedure | 1 | none | none |
| path-transform | stable | 0 | procedure | 2 | none | none |
| path-transform! | stable | 0 | procedure | 2 | none | none |
| path-union | stable | 0 | procedure | 2 | none | none |
| path-verbs | stable | 0 | procedure | 1 | none | none |
| path-xor | stable | 0 | procedure | 2 | none | none |
| picture->bytes | stable | 0 | procedure | 1 | none | none |
| picture->drawable | stable | 0 | procedure | 1 | none | none |
| picture->image | stable | 0 | procedure | 3 | none | #:background |
| picture->port | stable | 0 | procedure | 2 | none | #:cancel-evt, #:close?, #:limit |
| picture-approximate-bytes-used | stable | 0 | procedure | 1 | none | none |
| picture-approximate-op-count | stable | 0 | procedure | 1 | none | #:nested? |
| picture-cull-bounds | stable | 0 | procedure | 1 | none | none |
| picture-from-bytes | stable | 0 | procedure | 1 | none | #:height, #:trusted?, #:width |
| picture-from-file | stable | 0 | procedure | 1 | none | #:height, #:trusted?, #:width |
| picture-from-port | stable | 0 | procedure | 1 | none | #:cancel-evt, #:close?, #:height, #:length, #:limit, #:seekable?, #:trusted?, #:width |
| picture-from-port/buffered | stable | 0 | procedure | 1 | none | #:cancel-evt, #:close?, #:height, #:limit, #:trusted?, #:width |
| picture-from-stream | stable | 0 | procedure | 1 | none | #:height, #:trusted?, #:width |
| picture-height | stable | 0 | procedure | 1 | none | none |
| picture-recorder-begin-recording! | stable | 0 | procedure | 5 | none | #:spatial-index |
| picture-recorder-finish-recording! | stable | 0 | procedure | 1 | none | none |
| picture-recorder-recording? | stable | 0 | procedure | 1 | none | none |
| picture-recorder? | stable | 0 | procedure | 1 | none | none |
| picture-unique-id | stable | 0 | procedure | 1 | none | none |
| picture-width | stable | 0 | procedure | 1 | none | none |
| picture-write-stream! | stable | 0 | procedure | 2 | none | none |
| picture? | stable | 0 | procedure | 1 | none | none |
| pixel-formats | stable | 0 | value | — | — | — |
| pixmap->rgba-bytes | stable | 0 | procedure | 1 | none | #:premultiplied? |
| pixmap->storage-bytes | stable | 0 | procedure | 1 | none | none |
| pixmap-alphaf | stable | 0 | procedure | 3 | none | none |
| pixmap-color4f | stable | 0 | procedure | 3 | none | none |
| pixmap-convert! | stable | 0 | procedure | 2 | none | none |
| pixmap-fill! | stable | 0 | procedure | 2 | none | none |
| pixmap-fill-color4f! | stable | 0 | procedure | 2 | none | none |
| pixmap-height | stable | 0 | procedure | 1 | none | none |
| pixmap-image-info | stable | 0 | procedure | 1 | none | none |
| pixmap-opaque? | stable | 0 | procedure | 1 | none | none |
| pixmap-pixel | stable | 0 | procedure | 3 | none | none |
| pixmap-row-bytes | stable | 0 | procedure | 1 | none | none |
| pixmap-sample | stable | 0 | procedure | 3 | none | none |
| pixmap-scale! | stable | 0 | procedure | 2 | none | #:sampling |
| pixmap-set-color4f! | stable | 0 | procedure | 4 | none | none |
| pixmap-set-pixel! | stable | 0 | procedure | 4 | none | none |
| pixmap-set-sample! | stable | 0 | procedure | 4 | none | none |
| pixmap-subset | stable | 0 | procedure | 5 | none | none |
| pixmap-width | stable | 0 | procedure | 1 | none | none |
| pixmap-writable? | stable | 0 | procedure | 1 | none | none |
| pixmap-write-rgba! | stable | 0 | procedure | 2 | none | #:premultiplied?, #:row-bytes |
| pixmap-write-storage! | stable | 0 | procedure | 2 | none | #:row-bytes |
| pixmap? | stable | 0 | procedure | 1 | none | none |
| positioned-glyphs->path | stable | 0 | procedure | 3 | none | none |
| primaries->xyz-d50 | stable | 0 | procedure | 4 | none | none |
| raster-buffer->image | stable | 0 | procedure | 1 | none | none |
| raster-buffer->rgba-bytes | stable | 0 | procedure | 1 | none | #:premultiplied? |
| raster-buffer->storage-bytes | stable | 0 | procedure | 1 | none | none |
| raster-buffer-byte-size | stable | 0 | procedure | 1 | none | none |
| raster-buffer-convert | stable | 0 | procedure | 2 | none | #:row-bytes |
| raster-buffer-copy | stable | 0 | procedure | 1 | none | #:row-bytes |
| raster-buffer-extract-alpha | stable | 0 | procedure | 1 | none | none |
| raster-buffer-height | stable | 0 | procedure | 1 | none | none |
| raster-buffer-image-info | stable | 0 | procedure | 1 | none | none |
| raster-buffer-opaque? | stable | 0 | procedure | 1 | none | none |
| raster-buffer-row-bytes | stable | 0 | procedure | 1 | none | none |
| raster-buffer-width | stable | 0 | procedure | 1 | none | none |
| raster-buffer-write-rgba! | stable | 0 | procedure | 2 | none | #:premultiplied?, #:row-bytes |
| raster-buffer-write-storage! | stable | 0 | procedure | 2 | none | none |
| raster-buffer? | stable | 0 | procedure | 1 | none | none |
| region->path | stable | 0 | procedure | 1 | none | none |
| region-bounds | stable | 0 | procedure | 1 | none | none |
| region-clear! | stable | 0 | procedure | 1 | none | none |
| region-clipped-rectangles | stable | 0 | procedure | 2 | none | none |
| region-complex? | stable | 0 | procedure | 1 | none | none |
| region-contains-point? | stable | 0 | procedure | 3 | none | none |
| region-contains-rect? | stable | 0 | procedure | 2 | none | none |
| region-contains-region? | stable | 0 | procedure | 2 | none | none |
| region-copy | stable | 0 | procedure | 1 | none | none |
| region-difference | stable | 0 | procedure | 2 | none | none |
| region-empty? | stable | 0 | procedure | 1 | none | none |
| region-intersect | stable | 0 | procedure | 2 | none | none |
| region-intersects-rect? | stable | 0 | procedure | 2 | none | none |
| region-intersects? | stable | 0 | procedure | 2 | none | none |
| region-op | stable | 0 | procedure | 3 | none | none |
| region-op-rect | stable | 0 | procedure | 3 | none | none |
| region-quick-contains-rect? | stable | 0 | procedure | 2 | none | none |
| region-quick-reject-rect? | stable | 0 | procedure | 2 | none | none |
| region-quick-reject? | stable | 0 | procedure | 2 | none | none |
| region-rect? | stable | 0 | procedure | 1 | none | none |
| region-rectangles | stable | 0 | procedure | 1 | none | none |
| region-set-rect! | stable | 0 | procedure | 2 | none | none |
| region-spans | stable | 0 | procedure | 4 | none | none |
| region-translate | stable | 0 | procedure | 3 | none | none |
| region-union | stable | 0 | procedure | 2 | none | none |
| region-xor | stable | 0 | procedure | 2 | none | none |
| region? | stable | 0 | procedure | 1 | none | none |
| rgb | stable | 0 | procedure | 3 | none | none |
| rgba | stable | 0 | procedure | 4 | none | none |
| rgba-alpha | stable | 0 | procedure | 1 | none | none |
| rgba-blue | stable | 0 | procedure | 1 | none | none |
| rgba-bytes->image | stable | 0 | procedure | 3 | none | #:color-space, #:premultiplied? |
| rgba-green | stable | 0 | procedure | 1 | none | none |
| rgba-red | stable | 0 | procedure | 1 | none | none |
| rgba? | stable | 0 | procedure | 1 | none | none |
| rounded-rect-bounds | stable | 0 | procedure | 1 | none | none |
| rounded-rect-inset | stable | 0 | procedure | 3 | none | none |
| rounded-rect-normalize | stable | 0 | procedure | 1 | none | none |
| rounded-rect-offset | stable | 0 | procedure | 3 | none | none |
| rounded-rect-outset | stable | 0 | procedure | 3 | none | none |
| rounded-rect-radii | stable | 0 | procedure | 1 | none | none |
| rounded-rect-transform | stable | 0 | procedure | 2 | none | none |
| rounded-rect-type | stable | 0 | procedure | 1 | none | none |
| rounded-rect? | stable | 0 | procedure | 1 | none | none |
| runtime-child-index | stable | 0 | procedure | 1 | none | none |
| runtime-child-kind | stable | 0 | procedure | 1 | none | none |
| runtime-child-name | stable | 0 | procedure | 1 | none | none |
| runtime-child? | stable | 0 | procedure | 1 | none | none |
| runtime-effect->blender | stable | 0 | procedure | 1 | none | #:children, #:uniforms |
| runtime-effect->color-filter | stable | 0 | procedure | 1 | none | #:children, #:uniforms |
| runtime-effect->shader | stable | 0 | procedure | 1 | none | #:children, #:local-matrix, #:uniforms |
| runtime-effect-children | stable | 0 | procedure | 1 | none | none |
| runtime-effect-kind | stable | 0 | procedure | 1 | none | none |
| runtime-effect-source | stable | 0 | procedure | 1 | none | none |
| runtime-effect-uniform-byte-size | stable | 0 | procedure | 1 | none | none |
| runtime-effect-uniform-bytes | stable | 0 | procedure | 2 | none | none |
| runtime-effect-uniforms | stable | 0 | procedure | 1 | none | none |
| runtime-effect? | stable | 0 | procedure | 1 | none | none |
| runtime-uniform-array? | stable | 0 | procedure | 1 | none | none |
| runtime-uniform-byte-size | stable | 0 | procedure | 1 | none | none |
| runtime-uniform-color? | stable | 0 | procedure | 1 | none | none |
| runtime-uniform-count | stable | 0 | procedure | 1 | none | none |
| runtime-uniform-half-precision? | stable | 0 | procedure | 1 | none | none |
| runtime-uniform-name | stable | 0 | procedure | 1 | none | none |
| runtime-uniform-offset | stable | 0 | procedure | 1 | none | none |
| runtime-uniform-type | stable | 0 | procedure | 1 | none | none |
| runtime-uniform? | stable | 0 | procedure | 1 | none | none |
| save-image | stable | 0 | procedure | 3 | none | #:color-space, #:exists, #:icc-description, #:icc-profile, #:jpeg-alpha, #:jpeg-downsample, #:png-compression, #:quality, #:webp-lossless? |
| save-output | stable | 0 | procedure | 3 | none | #:description, #:encoding-quality, #:exists, #:id-prefix, #:pdfa?, #:raster-dpi, #:text-mode, #:title |
| save-output/audit | stable | 0 | procedure | 3 | none | #:description, #:encoding-quality, #:exists, #:id-prefix, #:pdfa?, #:policy, #:raster-dpi, #:text-mode, #:title |
| save-pdf | stable | 0 | procedure | 2 | none | #:exists |
| save-picture | stable | 0 | procedure | 2 | none | #:exists |
| save-png | stable | 0 | procedure | 2 | none | #:color-space, #:compression, #:exists, #:icc-description, #:icc-profile |
| save-svg | stable | 0 | procedure | 2 | none | #:exists |
| scanline-batch->raster-buffer | stable | 0 | procedure | 1 | none | none |
| scanline-batch-bytes | stable | 0 | procedure | 1 | none | none |
| scanline-batch-complete? | stable | 0 | procedure | 1 | none | none |
| scanline-batch-decoded-count | stable | 0 | procedure | 1 | none | none |
| scanline-batch-first-row | stable | 0 | procedure | 1 | none | none |
| scanline-batch-info | stable | 0 | procedure | 1 | none | none |
| scanline-batch-requested-count | stable | 0 | procedure | 1 | none | none |
| scanline-batch-row-bytes | stable | 0 | procedure | 1 | none | none |
| scanline-batch? | stable | 0 | procedure | 1 | none | none |
| shader-with-color-filter | stable | 0 | procedure | 2 | none | none |
| shader-with-local-matrix | stable | 0 | procedure | 2 | none | none |
| shader? | stable | 0 | procedure | 1 | none | none |
| shape-text | stable | 0 | procedure | 2 | none | #:direction, #:features, #:language, #:script |
| shaped-run->path | stable | 0 | procedure | 2 | none | none |
| shaped-run->text-blob | stable | 0 | procedure | 2 | none | none |
| shaped-run->text-blob/on-path | stable | 0 | procedure | 3 | none | #:contour, #:force-closed?, #:normal-offset, #:start-offset, #:text |
| shaped-run-advance-x | stable | 0 | procedure | 1 | none | none |
| shaped-run-advance-y | stable | 0 | procedure | 1 | none | none |
| shaped-run-clusters | stable | 0 | procedure | 1 | none | none |
| shaped-run-glyph-count | stable | 0 | procedure | 1 | none | none |
| shaped-run-glyphs | stable | 0 | procedure | 1 | none | none |
| shaped-run-positions | stable | 0 | procedure | 1 | none | none |
| shaped-run? | stable | 0 | procedure | 1 | none | none |
| shaper? | stable | 0 | procedure | 1 | none | none |
| simple-text-bounds | stable | 0 | procedure | 2 | none | #:paint |
| simple-text-path | stable | 0 | procedure | 2, 3, 4 | none | none |
| skia-available? | stable | 0 | procedure | 0 | none | none |
| skia-cache-statistics | stable | 0 | procedure | 0 | none | none |
| skia-check! | stable | 0 | procedure | 0 | none | none |
| skia-close! | stable | 0 | procedure | 1 | none | none |
| skia-closed? | stable | 0 | procedure | 1 | none | none |
| skia-font-cache-count-limit | stable | 0 | procedure | 0 | none | none |
| skia-font-cache-count-used | stable | 0 | procedure | 0 | none | none |
| skia-font-cache-limit | stable | 0 | procedure | 0 | none | none |
| skia-font-cache-used | stable | 0 | procedure | 0 | none | none |
| skia-initialize! | stable | 0 | procedure | 0 | none | none |
| skia-input-stream? | stable | 0 | procedure | 1 | none | none |
| skia-memory-statistics | stable | 0 | procedure | 0 | none | #:byte-limit, #:detailed?, #:dump-wrapped?, #:max-entries, #:string-limit |
| skia-native-library-path | stable | 0 | procedure | 0 | none | none |
| skia-native-version | stable | 0 | procedure | 0 | none | none |
| skia-output-stream? | stable | 0 | procedure | 1 | none | none |
| skia-path? | stable | 0 | procedure | 1 | none | none |
| skia-purge-all-caches! | stable | 0 | procedure | 0 | none | none |
| skia-purge-font-cache! | stable | 0 | procedure | 0 | none | none |
| skia-purge-resource-cache! | stable | 0 | procedure | 0 | none | none |
| skia-resource-cache-limit | stable | 0 | procedure | 0 | none | none |
| skia-resource-cache-single-allocation-limit | stable | 0 | procedure | 0 | none | none |
| skia-resource-cache-used | stable | 0 | procedure | 0 | none | none |
| skia-resource? | stable | 0 | procedure | 1 | none | none |
| skia-set-font-cache-count-limit! | stable | 0 | procedure | 1 | none | none |
| skia-set-font-cache-limit! | stable | 0 | procedure | 1 | none | none |
| skia-set-resource-cache-limit! | stable | 0 | procedure | 1 | none | none |
| skia-set-resource-cache-single-allocation-limit! | stable | 0 | procedure | 1 | none | none |
| struct:rgba | stable | 0 | value | — | — | — |
| surface->png-bytes | stable | 0 | procedure | 1 | none | #:color-space, #:compression, #:icc-description, #:icc-profile |
| surface->rgba-bytes | stable | 0 | procedure | 1 | none | #:color-space, #:premultiplied? |
| surface-backend | stable | 0 | procedure | 1 | none | none |
| surface-canvas | stable | 0 | procedure | 1 | none | none |
| surface-color-space | stable | 0 | procedure | 1 | none | none |
| surface-height | stable | 0 | procedure | 1 | none | none |
| surface-pixel | stable | 0 | procedure | 3 | none | none |
| surface-properties->jsexpr | stable | 0 | procedure | 1 | none | none |
| surface-properties-always-dither? | stable | 0 | procedure | 1 | none | none |
| surface-properties-device-independent-fonts? | stable | 0 | procedure | 1 | none | none |
| surface-properties-dynamic-msaa? | stable | 0 | procedure | 1 | none | none |
| surface-properties-flags | stable | 0 | procedure | 1 | none | none |
| surface-properties-of | stable | 0 | procedure | 1 | none | none |
| surface-properties-pixel-geometry | stable | 0 | procedure | 1 | none | none |
| surface-properties? | stable | 0 | procedure | 1 | none | none |
| surface-snapshot | stable | 0 | procedure | 1 | none | none |
| surface-width | stable | 0 | procedure | 1 | none | none |
| surface? | stable | 0 | procedure | 1 | none | none |
| svg-destination-id | stable | 0 | procedure | 1 | none | #:id-prefix |
| svg-document->bytes | stable | 0 | procedure | 1 | none | none |
| svg-document->string | stable | 0 | procedure | 1 | none | none |
| svg-document-abort! | stable | 0 | procedure | 1 | none | none |
| svg-document-canvas | stable | 0 | procedure | 1 | none | none |
| svg-document-finish! | stable | 0 | procedure | 1 | none | none |
| svg-document-height | stable | 0 | procedure | 1 | none | none |
| svg-document-state | stable | 0 | procedure | 1 | none | none |
| svg-document-width | stable | 0 | procedure | 1 | none | none |
| svg-document? | stable | 0 | procedure | 1 | none | none |
| svg-path->path | stable | 0 | procedure | 1 | none | #:fill-rule |
| text-blob->path | stable | 0 | procedure | 1 | none | none |
| text-blob-bounds | stable | 0 | procedure | 1 | none | none |
| text-blob-builder-add-horizontal-run! | stable | 0 | procedure | 4 | none | #:clusters, #:text, #:y |
| text-blob-builder-add-positioned-run! | stable | 0 | procedure | 4 | none | #:clusters, #:text |
| text-blob-builder-add-run! | stable | 0 | procedure | 3 | none | #:clusters, #:origin, #:text |
| text-blob-builder-add-shaped-run! | stable | 0 | procedure | 3 | none | #:origin, #:text |
| text-blob-builder-add-transformed-run! | stable | 0 | procedure | 4 | none | #:clusters, #:text |
| text-blob-builder-finish! | stable | 0 | procedure | 1 | none | none |
| text-blob-builder-run-count | stable | 0 | procedure | 1 | none | none |
| text-blob-builder? | stable | 0 | procedure | 1 | none | none |
| text-blob-intercepts | stable | 0 | procedure | 3 | none | #:paint |
| text-blob-run-count | stable | 0 | procedure | 1 | none | none |
| text-blob-run-font | stable | 0 | procedure | 2 | none | none |
| text-blob-runs | stable | 0 | procedure | 1 | none | none |
| text-blob-unique-id | stable | 0 | procedure | 1 | none | none |
| text-blob? | stable | 0 | procedure | 1 | none | none |
| text-layout-height | stable | 0 | procedure | 1 | none | none |
| text-layout-line-baseline | stable | 0 | procedure | 1 | none | none |
| text-layout-line-count | stable | 0 | procedure | 1 | none | none |
| text-layout-line-direction | stable | 0 | procedure | 1 | none | none |
| text-layout-line-height | stable | 0 | procedure | 1 | none | none |
| text-layout-line-origin-x | stable | 0 | procedure | 1 | none | none |
| text-layout-line-run | stable | 0 | procedure | 1 | none | none |
| text-layout-line-text | stable | 0 | procedure | 1 | none | none |
| text-layout-line-width | stable | 0 | procedure | 1 | none | none |
| text-layout-line? | stable | 0 | procedure | 1 | none | none |
| text-layout-lines | stable | 0 | procedure | 1 | none | none |
| text-layout-width | stable | 0 | procedure | 1 | none | none |
| text-layout? | stable | 0 | procedure | 1 | none | none |
| text-run-info-clusters | stable | 0 | procedure | 1 | none | none |
| text-run-info-glyphs | stable | 0 | procedure | 1 | none | none |
| text-run-info-positioning | stable | 0 | procedure | 1 | none | none |
| text-run-info-positions | stable | 0 | procedure | 1 | none | none |
| text-run-info-transforms | stable | 0 | procedure | 1 | none | none |
| text-run-info-utf8 | stable | 0 | procedure | 1 | none | none |
| text-run-info? | stable | 0 | procedure | 1 | none | none |
| transfer-function-coefficients | stable | 0 | procedure | 1 | none | none |
| transfer-function-evaluate | stable | 0 | procedure | 2 | none | none |
| transfer-function-invert | stable | 0 | procedure | 1 | none | none |
| transfer-function? | stable | 0 | procedure | 1 | none | none |
| typeface->font-bytes | stable | 0 | procedure | 1 | none | none |
| typeface-family-name | stable | 0 | procedure | 1 | none | none |
| typeface-fixed-pitch? | stable | 0 | procedure | 1 | none | none |
| typeface-from-bytes | stable | 0 | procedure | 1 | none | #:index |
| typeface-from-family | stable | 0 | procedure | 1 | none | #:slant, #:weight, #:width |
| typeface-from-file | stable | 0 | procedure | 1 | none | #:index |
| typeface-from-port/buffered | stable | 0 | procedure | 1 | none | #:cancel-evt, #:close?, #:index, #:limit |
| typeface-from-stream | stable | 0 | procedure | 1 | none | #:index |
| typeface-glyph-count | stable | 0 | procedure | 1 | none | none |
| typeface-kerning-pair-adjustments | stable | 0 | procedure | 2 | none | none |
| typeface-postscript-name | stable | 0 | procedure | 1 | none | none |
| typeface-slant | stable | 0 | procedure | 1 | none | none |
| typeface-style | stable | 0 | procedure | 1 | none | none |
| typeface-table-bytes | stable | 0 | procedure | 2 | none | #:end, #:start |
| typeface-table-size | stable | 0 | procedure | 2 | none | none |
| typeface-table-tags | stable | 0 | procedure | 1 | none | none |
| typeface-units-per-em | stable | 0 | procedure | 1 | none | none |
| typeface-weight | stable | 0 | procedure | 1 | none | none |
| typeface-width | stable | 0 | procedure | 1 | none | none |
| typeface? | stable | 0 | procedure | 1 | none | none |
| unit->points | stable | 0 | procedure | 1, 2 | none | none |
| vector->matrix | stable | 0 | procedure | 1 | none | none |
| vector->matrix3 | stable | 0 | procedure | 1 | none | none |
| vector->matrix4 | stable | 0 | procedure | 1 | none | none |
| vertices-colors | stable | 0 | procedure | 1 | none | none |
| vertices-count | stable | 0 | procedure | 1 | none | none |
| vertices-indices | stable | 0 | procedure | 1 | none | none |
| vertices-mode | stable | 0 | procedure | 1 | none | none |
| vertices-positions | stable | 0 | procedure | 1 | none | none |
| vertices-texture-coordinates | stable | 0 | procedure | 1 | none | none |
| vertices? | stable | 0 | procedure | 1 | none | none |
| with-canvas-layer | stable | 0 | syntax | — | — | — |
| with-canvas-matrix | stable | 0 | syntax | — | — | — |
| with-canvas-state | stable | 0 | syntax | — | — | — |
| with-document-page | stable | 0 | syntax | — | — | — |
| with-output-label | stable | 0 | syntax | — | — | — |
| with-skia | stable | 0 | syntax | — | — | — |
| xyz-d50-concat | stable | 0 | procedure | 2 | none | none |
| xyz-d50-invert | stable | 0 | procedure | 1 | none | none |
### matrix.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| make-matrix | stable | 0 | procedure | 0, 1, 2, 3, 4, 5, 6 | none | none |
| matrix->vector | stable | 0 | procedure | 1 | none | none |
| matrix-compose | stable | 0 | procedure | 0+ | none | none |
| matrix-identity | stable | 0 | value | — | — | — |
| matrix-invert | stable | 0 | procedure | 1 | none | none |
| matrix-map-point | stable | 0 | procedure | 3 | none | none |
| matrix-map-rect | stable | 0 | procedure | 5 | none | none |
| matrix-map-vector | stable | 0 | procedure | 3 | none | none |
| matrix-rotate | stable | 0 | procedure | 1 | none | none |
| matrix-rotate-degrees | stable | 0 | procedure | 1 | none | none |
| matrix-scale | stable | 0 | procedure | 1, 2 | none | none |
| matrix-skew | stable | 0 | procedure | 2 | none | none |
| matrix-translate | stable | 0 | procedure | 2 | none | none |
| matrix-x0 | stable | 0 | procedure | 1 | none | none |
| matrix-xx | stable | 0 | procedure | 1 | none | none |
| matrix-xy | stable | 0 | procedure | 1 | none | none |
| matrix-y0 | stable | 0 | procedure | 1 | none | none |
| matrix-yx | stable | 0 | procedure | 1 | none | none |
| matrix-yy | stable | 0 | procedure | 1 | none | none |
| matrix? | stable | 0 | procedure | 1 | none | none |
| vector->matrix | stable | 0 | procedure | 1 | none | none |
### native-capabilities.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| native-abi-catalog | stable | 0 | procedure | 0 | none | none |
| native-abi-profiles | stable | 0 | procedure | 0 | none | none |
| native-package-version | stable | 0 | value | — | — | — |
| skia-native-capabilities | stable | 0 | procedure | 0 | none | none |
| skia-native-symbol-inventory | stable | 0 | procedure | 1 | none | none |
### output-audit.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| analyze-output-page | stable | 0 | procedure | 2 | none | #:description, #:encoding-quality, #:id-prefix, #:pdfa?, #:raster-dpi, #:text-mode, #:title |
| call-with-output-label | stable | 0 | procedure | 2 | none | none |
| current-output-audit-event-limit | stable | 0 | parameter | 0, 1 | none | none |
| exn:fail:output-audit-event | stable | 0 | procedure | 1 | none | none |
| exn:fail:output-audit? | stable | 0 | procedure | 1 | none | none |
| output->bytes/audit | stable | 0 | procedure | 2 | none | #:description, #:encoding-quality, #:id-prefix, #:pdfa?, #:policy, #:raster-dpi, #:text-mode, #:title |
| output-audit-event-details | stable | 0 | procedure | 1 | none | none |
| output-audit-event-feature | stable | 0 | procedure | 1 | none | none |
| output-audit-event-operation | stable | 0 | procedure | 1 | none | none |
| output-audit-event-page | stable | 0 | procedure | 1 | none | none |
| output-audit-event-reason | stable | 0 | procedure | 1 | none | none |
| output-audit-event-scope | stable | 0 | procedure | 1 | none | none |
| output-audit-event-status | stable | 0 | procedure | 1 | none | none |
| output-audit-event? | stable | 0 | procedure | 1 | none | none |
| output-audit-report->jsexpr | stable | 0 | procedure | 1 | none | none |
| output-audit-report-backend | stable | 0 | procedure | 1 | none | none |
| output-audit-report-blocking? | stable | 0 | procedure | 1 | none | none |
| output-audit-report-events | stable | 0 | procedure | 1 | none | none |
| output-audit-report-mode | stable | 0 | procedure | 1 | none | none |
| output-audit-report-pages | stable | 0 | procedure | 1 | none | none |
| output-audit-report-vector-only? | stable | 0 | procedure | 1 | none | none |
| output-audit-report? | stable | 0 | procedure | 1 | none | none |
| output-backends | stable | 0 | value | — | — | — |
| output-capability-backend | stable | 0 | procedure | 1 | none | none |
| output-capability-feature | stable | 0 | procedure | 1 | none | none |
| output-capability-for | stable | 0 | procedure | 2 | none | none |
| output-capability-reason | stable | 0 | procedure | 1 | none | none |
| output-capability-status | stable | 0 | procedure | 1 | none | none |
| output-capability? | stable | 0 | procedure | 1 | none | none |
| output-feature-names | stable | 0 | value | — | — | — |
| save-output/audit | stable | 0 | procedure | 3 | none | #:description, #:encoding-quality, #:exists, #:id-prefix, #:pdfa?, #:policy, #:raster-dpi, #:text-mode, #:title |
| with-output-label | stable | 0 | syntax | — | — | — |
### output-groups.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| draw-output-group | stable | 0 | procedure | 6 | none | #:color-space, #:label, #:padding, #:policy, #:raster-executor, #:scale |
| exn:fail:output-group-report | stable | 0 | procedure | 1 | none | none |
| exn:fail:output-group? | stable | 0 | procedure | 1 | none | none |
| output-group-report->jsexpr | stable | 0 | procedure | 1 | none | none |
| output-group-report-backend | stable | 0 | procedure | 1 | none | none |
| output-group-report-bounds | stable | 0 | procedure | 1 | none | none |
| output-group-report-children | stable | 0 | procedure | 1 | none | none |
| output-group-report-execution | stable | 0 | procedure | 1 | none | none |
| output-group-report-features | stable | 0 | procedure | 1 | none | none |
| output-group-report-label | stable | 0 | procedure | 1 | none | none |
| output-group-report-padded-bounds | stable | 0 | procedure | 1 | none | none |
| output-group-report-pixel-size | stable | 0 | procedure | 1 | none | none |
| output-group-report-policy | stable | 0 | procedure | 1 | none | none |
| output-group-report-reason | stable | 0 | procedure | 1 | none | none |
| output-group-report-scale | stable | 0 | procedure | 1 | none | none |
| output-group-report-strategy | stable | 0 | procedure | 1 | none | none |
| output-group-report? | stable | 0 | procedure | 1 | none | none |
| output-raster-executor? | stable | 0 | procedure | 1 | none | none |
### output-policy.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| exn:fail:output-audit-event | stable | 0 | procedure | 1 | none | none |
| exn:fail:output-audit? | stable | 0 | procedure | 1 | none | none |
| output-audit-event-details | stable | 0 | procedure | 1 | none | none |
| output-audit-event-feature | stable | 0 | procedure | 1 | none | none |
| output-audit-event-operation | stable | 0 | procedure | 1 | none | none |
| output-audit-event-page | stable | 0 | procedure | 1 | none | none |
| output-audit-event-reason | stable | 0 | procedure | 1 | none | none |
| output-audit-event-scope | stable | 0 | procedure | 1 | none | none |
| output-audit-event-status | stable | 0 | procedure | 1 | none | none |
| output-audit-event? | stable | 0 | procedure | 1 | none | none |
| output-audit-report->jsexpr | stable | 0 | procedure | 1 | none | none |
| output-audit-report-backend | stable | 0 | procedure | 1 | none | none |
| output-audit-report-blocking? | stable | 0 | procedure | 1 | none | none |
| output-audit-report-events | stable | 0 | procedure | 1 | none | none |
| output-audit-report-mode | stable | 0 | procedure | 1 | none | none |
| output-audit-report-pages | stable | 0 | procedure | 1 | none | none |
| output-audit-report-vector-only? | stable | 0 | procedure | 1 | none | none |
| output-audit-report? | stable | 0 | procedure | 1 | none | none |
| output-backends | stable | 0 | value | — | — | — |
| output-capability-backend | stable | 0 | procedure | 1 | none | none |
| output-capability-feature | stable | 0 | procedure | 1 | none | none |
| output-capability-for | stable | 0 | procedure | 2 | none | none |
| output-capability-reason | stable | 0 | procedure | 1 | none | none |
| output-capability-status | stable | 0 | procedure | 1 | none | none |
| output-capability? | stable | 0 | procedure | 1 | none | none |
| output-feature-names | stable | 0 | value | — | — | — |
### output.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| draw-output-page | stable | 0 | procedure | 2 | none | #:raster-dpi, #:text-mode |
| make-output-page | stable | 0 | procedure | 3 | none | #:background, #:clip?, #:margins, #:unit |
| output->bytes | stable | 0 | procedure | 2 | none | #:description, #:encoding-quality, #:id-prefix, #:pdfa?, #:raster-dpi, #:text-mode, #:title |
| output-page->image | stable | 0 | procedure | 1 | none | #:color-space, #:dpi, #:text-mode |
| output-page-background | stable | 0 | procedure | 1 | none | none |
| output-page-clip? | stable | 0 | procedure | 1 | none | none |
| output-page-content-size | stable | 0 | procedure | 1 | none | none |
| output-page-height | stable | 0 | procedure | 1 | none | none |
| output-page-margins | stable | 0 | procedure | 1 | none | none |
| output-page-size-in-points | stable | 0 | procedure | 1 | none | none |
| output-page-unit | stable | 0 | procedure | 1 | none | none |
| output-page-width | stable | 0 | procedure | 1 | none | none |
| output-page? | stable | 0 | procedure | 1 | none | none |
| save-output | stable | 0 | procedure | 3 | none | #:description, #:encoding-quality, #:exists, #:id-prefix, #:pdfa?, #:raster-dpi, #:text-mode, #:title |
| unit->points | stable | 0 | procedure | 1, 2 | none | none |
### pictures.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| make-picture-shader | stable | 0 | procedure | 1 | none | #:local-matrix, #:sampling, #:tile-rect, #:tile-x, #:tile-y |
| picture->bytes | stable | 0 | procedure | 1 | none | none |
| picture-approximate-bytes-used | stable | 0 | procedure | 1 | none | none |
| picture-approximate-op-count | stable | 0 | procedure | 1 | none | #:nested? |
| picture-cull-bounds | stable | 0 | procedure | 1 | none | none |
| picture-from-bytes | stable | 0 | procedure | 1 | none | #:height, #:trusted?, #:width |
| picture-from-file | stable | 0 | procedure | 1 | none | #:height, #:trusted?, #:width |
| picture-unique-id | stable | 0 | procedure | 1 | none | none |
| save-picture | stable | 0 | procedure | 2 | none | #:exists |
### portable-drawing.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| draw-atlas/portable | stable | 0 | procedure | 4 | none | #:alpha, #:sampling |
| draw-image-lattice/portable | stable | 0 | procedure | 7 | none | #:alpha, #:sampling |
| draw-image-nine/portable | stable | 0 | procedure | 7 | none | #:alpha, #:sampling |
| draw-markers | stable | 0 | procedure | 4 | none | #:shape |
| image-grid-cell-color | stable | 0 | procedure | 1 | none | none |
| image-grid-cell-column | stable | 0 | procedure | 1 | none | none |
| image-grid-cell-destination | stable | 0 | procedure | 1 | none | none |
| image-grid-cell-kind | stable | 0 | procedure | 1 | none | none |
| image-grid-cell-row | stable | 0 | procedure | 1 | none | none |
| image-grid-cell-source | stable | 0 | procedure | 1 | none | none |
| image-grid-cell? | stable | 0 | procedure | 1 | none | none |
| image-grid-plan->jsexpr | stable | 0 | procedure | 1 | none | none |
| image-lattice-plan | stable | 0 | procedure | 7 | none | none |
| image-nine-plan | stable | 0 | procedure | 7 | none | none |
### projective-matrix.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| make-matrix3 | stable | 0 | procedure | 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 | none | none |
| make-matrix4 | stable | 0 | procedure | 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 | none | none |
| matrix->matrix3 | stable | 0 | procedure | 1 | none | none |
| matrix->matrix4 | stable | 0 | procedure | 1 | none | none |
| matrix3->matrix | stable | 0 | procedure | 1 | none | none |
| matrix3->matrix4 | stable | 0 | procedure | 1 | none | none |
| matrix3->vector | stable | 0 | procedure | 1 | none | none |
| matrix3-affine? | stable | 0 | procedure | 1 | none | none |
| matrix3-compose | stable | 0 | procedure | 0+ | none | none |
| matrix3-identity | stable | 0 | value | — | — | — |
| matrix3-invert | stable | 0 | procedure | 1 | none | none |
| matrix3-map-homogeneous | stable | 0 | procedure | 3, 4 | none | none |
| matrix3-map-point | stable | 0 | procedure | 3 | none | none |
| matrix3-map-rect | stable | 0 | procedure | 5 | none | none |
| matrix3-perspective | stable | 0 | procedure | 2 | none | none |
| matrix3-ref | stable | 0 | procedure | 3 | none | none |
| matrix3-transpose | stable | 0 | procedure | 1 | none | none |
| matrix3? | stable | 0 | procedure | 1 | none | none |
| matrix4->matrix | stable | 0 | procedure | 1 | none | none |
| matrix4->matrix3 | stable | 0 | procedure | 1 | none | none |
| matrix4->vector | stable | 0 | procedure | 1 | none | none |
| matrix4-affine-2d? | stable | 0 | procedure | 1 | none | none |
| matrix4-compose | stable | 0 | procedure | 0+ | none | none |
| matrix4-identity | stable | 0 | value | — | — | — |
| matrix4-invert | stable | 0 | procedure | 1 | none | none |
| matrix4-map-homogeneous | stable | 0 | procedure | 3, 4, 5 | none | none |
| matrix4-map-point | stable | 0 | procedure | 3, 4 | none | none |
| matrix4-map-rect | stable | 0 | procedure | 5 | none | none |
| matrix4-perspective | stable | 0 | procedure | 1 | none | none |
| matrix4-project-xy | stable | 0 | procedure | 1 | none | none |
| matrix4-ref | stable | 0 | procedure | 3 | none | none |
| matrix4-rotate-x-degrees | stable | 0 | procedure | 1 | none | none |
| matrix4-rotate-y-degrees | stable | 0 | procedure | 1 | none | none |
| matrix4-rotate-z-degrees | stable | 0 | procedure | 1 | none | none |
| matrix4-scale | stable | 0 | procedure | 1, 2, 3 | none | none |
| matrix4-translate | stable | 0 | procedure | 2, 3 | none | none |
| matrix4-transpose | stable | 0 | procedure | 1 | none | none |
| matrix4? | stable | 0 | procedure | 1 | none | none |
| vector->matrix3 | stable | 0 | procedure | 1 | none | none |
| vector->matrix4 | stable | 0 | procedure | 1 | none | none |
### raster-buffers.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| call-with-raster-buffer-canvas | stable | 0 | procedure | 2 | none | none |
| call-with-raster-buffer-pixmap | stable | 0 | procedure | 2 | none | #:writable? |
| color-space->descriptor | stable | 0 | procedure | 1 | none | none |
| descriptor->color-space | stable | 0 | procedure | 1 | none | none |
| image->image-info | stable | 0 | procedure | 1 | none | none |
| make-raster-buffer | stable | 0 | procedure | 2 | none | #:color-space, #:row-bytes |
| make-raster-buffer-from-info | stable | 0 | procedure | 1 | none | #:row-bytes |
| make-surface-from-info | stable | 0 | procedure | 1 | none | #:background, #:row-bytes |
| pixmap->rgba-bytes | stable | 0 | procedure | 1 | none | #:premultiplied? |
| pixmap->storage-bytes | stable | 0 | procedure | 1 | none | none |
| pixmap-alphaf | stable | 0 | procedure | 3 | none | none |
| pixmap-color4f | stable | 0 | procedure | 3 | none | none |
| pixmap-convert! | stable | 0 | procedure | 2 | none | none |
| pixmap-fill! | stable | 0 | procedure | 2 | none | none |
| pixmap-fill-color4f! | stable | 0 | procedure | 2 | none | none |
| pixmap-height | stable | 0 | procedure | 1 | none | none |
| pixmap-image-info | stable | 0 | procedure | 1 | none | none |
| pixmap-opaque? | stable | 0 | procedure | 1 | none | none |
| pixmap-pixel | stable | 0 | procedure | 3 | none | none |
| pixmap-row-bytes | stable | 0 | procedure | 1 | none | none |
| pixmap-sample | stable | 0 | procedure | 3 | none | none |
| pixmap-scale! | stable | 0 | procedure | 2 | none | #:sampling |
| pixmap-set-color4f! | stable | 0 | procedure | 4 | none | none |
| pixmap-set-pixel! | stable | 0 | procedure | 4 | none | none |
| pixmap-set-sample! | stable | 0 | procedure | 4 | none | none |
| pixmap-subset | stable | 0 | procedure | 5 | none | none |
| pixmap-width | stable | 0 | procedure | 1 | none | none |
| pixmap-writable? | stable | 0 | procedure | 1 | none | none |
| pixmap-write-rgba! | stable | 0 | procedure | 2 | none | #:premultiplied?, #:row-bytes |
| pixmap-write-storage! | stable | 0 | procedure | 2 | none | #:row-bytes |
| pixmap? | stable | 0 | procedure | 1 | none | none |
| raster-buffer->image | stable | 0 | procedure | 1 | none | none |
| raster-buffer->rgba-bytes | stable | 0 | procedure | 1 | none | #:premultiplied? |
| raster-buffer->storage-bytes | stable | 0 | procedure | 1 | none | none |
| raster-buffer-byte-size | stable | 0 | procedure | 1 | none | none |
| raster-buffer-convert | stable | 0 | procedure | 2 | none | #:row-bytes |
| raster-buffer-copy | stable | 0 | procedure | 1 | none | #:row-bytes |
| raster-buffer-extract-alpha | stable | 0 | procedure | 1 | none | none |
| raster-buffer-height | stable | 0 | procedure | 1 | none | none |
| raster-buffer-image-info | stable | 0 | procedure | 1 | none | none |
| raster-buffer-opaque? | stable | 0 | procedure | 1 | none | none |
| raster-buffer-row-bytes | stable | 0 | procedure | 1 | none | none |
| raster-buffer-width | stable | 0 | procedure | 1 | none | none |
| raster-buffer-write-rgba! | stable | 0 | procedure | 2 | none | #:premultiplied?, #:row-bytes |
| raster-buffer-write-storage! | stable | 0 | procedure | 2 | none | none |
| raster-buffer? | stable | 0 | procedure | 1 | none | none |
### runtime-effects.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| blender? | stable | 0 | procedure | 1 | none | none |
| exn:fail:skia-sksl-diagnostics | stable | 0 | procedure | 1 | none | none |
| exn:fail:skia-sksl-kind | stable | 0 | procedure | 1 | none | none |
| exn:fail:skia-sksl-source | stable | 0 | procedure | 1 | none | none |
| exn:fail:skia-sksl? | stable | 0 | procedure | 1 | none | none |
| make-blend-mode-blender | stable | 0 | procedure | 1 | none | none |
| make-runtime-effect | stable | 0 | procedure | 1 | none | #:kind |
| paint-blender | stable | 0 | procedure | 1 | none | none |
| paint-set-blender! | stable | 0 | procedure | 2 | none | none |
| runtime-child-index | stable | 0 | procedure | 1 | none | none |
| runtime-child-kind | stable | 0 | procedure | 1 | none | none |
| runtime-child-name | stable | 0 | procedure | 1 | none | none |
| runtime-child? | stable | 0 | procedure | 1 | none | none |
| runtime-effect->blender | stable | 0 | procedure | 1 | none | #:children, #:uniforms |
| runtime-effect->color-filter | stable | 0 | procedure | 1 | none | #:children, #:uniforms |
| runtime-effect->shader | stable | 0 | procedure | 1 | none | #:children, #:local-matrix, #:uniforms |
| runtime-effect-children | stable | 0 | procedure | 1 | none | none |
| runtime-effect-kind | stable | 0 | procedure | 1 | none | none |
| runtime-effect-source | stable | 0 | procedure | 1 | none | none |
| runtime-effect-uniform-byte-size | stable | 0 | procedure | 1 | none | none |
| runtime-effect-uniform-bytes | stable | 0 | procedure | 2 | none | none |
| runtime-effect-uniforms | stable | 0 | procedure | 1 | none | none |
| runtime-effect? | stable | 0 | procedure | 1 | none | none |
| runtime-uniform-array? | stable | 0 | procedure | 1 | none | none |
| runtime-uniform-byte-size | stable | 0 | procedure | 1 | none | none |
| runtime-uniform-color? | stable | 0 | procedure | 1 | none | none |
| runtime-uniform-count | stable | 0 | procedure | 1 | none | none |
| runtime-uniform-half-precision? | stable | 0 | procedure | 1 | none | none |
| runtime-uniform-name | stable | 0 | procedure | 1 | none | none |
| runtime-uniform-offset | stable | 0 | procedure | 1 | none | none |
| runtime-uniform-type | stable | 0 | procedure | 1 | none | none |
| runtime-uniform? | stable | 0 | procedure | 1 | none | none |
### specialized-canvases.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| call-with-nodraw-canvas | stable | 0 | procedure | 3 | none | none |
| call-with-nway-canvas | stable | 0 | procedure | 2 | none | none |
| call-with-overdraw-canvas | stable | 0 | procedure | 2 | none | none |
### stream-inputs.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| codec-from-port/buffered | stable | 0 | procedure | 1 | none | #:cancel-evt, #:close?, #:limit |
| codec-from-stream | stable | 0 | procedure | 1 | none | none |
| image-from-port/buffered | stable | 0 | procedure | 1 | none | #:cancel-evt, #:close?, #:limit |
| picture-from-port/buffered | stable | 0 | procedure | 1 | none | #:cancel-evt, #:close?, #:height, #:limit, #:trusted?, #:width |
| picture-from-stream | stable | 0 | procedure | 1 | none | #:height, #:trusted?, #:width |
| typeface-from-port/buffered | stable | 0 | procedure | 1 | none | #:cancel-evt, #:close?, #:index, #:limit |
| typeface-from-stream | stable | 0 | procedure | 1 | none | #:index |
### streams.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| buffered-port->input-stream | stable | 0 | procedure | 1 | none | #:cancel-evt, #:close?, #:limit |
| input-stream->bytes | stable | 0 | procedure | 1 | none | none |
| input-stream-at-end? | stable | 0 | procedure | 1 | none | none |
| input-stream-duplicate | stable | 0 | procedure | 1 | none | none |
| input-stream-fork | stable | 0 | procedure | 1 | none | none |
| input-stream-length | stable | 0 | procedure | 1 | none | none |
| input-stream-move! | stable | 0 | procedure | 2 | none | none |
| input-stream-peek-bytes | stable | 0 | procedure | 2 | none | none |
| input-stream-position | stable | 0 | procedure | 1 | none | none |
| input-stream-read-bytes | stable | 0 | procedure | 2 | none | none |
| input-stream-rewind! | stable | 0 | procedure | 1 | none | none |
| input-stream-seek! | stable | 0 | procedure | 2 | none | none |
| input-stream-skip! | stable | 0 | procedure | 2 | none | none |
| make-file-input-stream | stable | 0 | procedure | 1 | none | #:limit |
| make-memory-input-stream | stable | 0 | procedure | 1 | none | #:limit |
| make-memory-output-stream | stable | 0 | procedure | 0 | none | #:limit |
| output-stream->bytes | stable | 0 | procedure | 1 | none | none |
| output-stream-bytes-written | stable | 0 | procedure | 1 | none | none |
| output-stream-detach-input! | stable | 0 | procedure | 1 | none | none |
| output-stream-write-bytes! | stable | 0 | procedure | 2, 3, 4 | none | none |
| output-stream-write-port/buffered | stable | 0 | procedure | 2 | none | #:cancel-evt, #:close? |
| skia-input-stream? | stable | 0 | procedure | 1 | none | none |
| skia-output-stream? | stable | 0 | procedure | 1 | none | none |
### surface-properties.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| make-surface-properties | stable | 0 | procedure | 0 | none | #:always-dither?, #:device-independent-fonts?, #:dynamic-msaa?, #:pixel-geometry |
| surface-properties->jsexpr | stable | 0 | procedure | 1 | none | none |
| surface-properties-always-dither? | stable | 0 | procedure | 1 | none | none |
| surface-properties-device-independent-fonts? | stable | 0 | procedure | 1 | none | none |
| surface-properties-dynamic-msaa? | stable | 0 | procedure | 1 | none | none |
| surface-properties-flags | stable | 0 | procedure | 1 | none | none |
| surface-properties-pixel-geometry | stable | 0 | procedure | 1 | none | none |
| surface-properties? | stable | 0 | procedure | 1 | none | none |
### text-blobs.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| draw-shaped-run/on-path | stable | 0 | procedure | 5 | none | #:contour, #:force-closed?, #:normal-offset, #:start-offset |
| make-text-blob-builder | stable | 0 | procedure | 0 | none | none |
| positioned-glyphs->path | stable | 0 | procedure | 3 | none | none |
| shaped-run->text-blob/on-path | stable | 0 | procedure | 3 | none | #:contour, #:force-closed?, #:normal-offset, #:start-offset, #:text |
| text-blob-builder-add-horizontal-run! | stable | 0 | procedure | 4 | none | #:clusters, #:text, #:y |
| text-blob-builder-add-positioned-run! | stable | 0 | procedure | 4 | none | #:clusters, #:text |
| text-blob-builder-add-run! | stable | 0 | procedure | 3 | none | #:clusters, #:origin, #:text |
| text-blob-builder-add-shaped-run! | stable | 0 | procedure | 3 | none | #:origin, #:text |
| text-blob-builder-add-transformed-run! | stable | 0 | procedure | 4 | none | #:clusters, #:text |
| text-blob-builder-finish! | stable | 0 | procedure | 1 | none | none |
| text-blob-builder-run-count | stable | 0 | procedure | 1 | none | none |
| text-blob-builder? | stable | 0 | procedure | 1 | none | none |
| text-blob-intercepts | stable | 0 | procedure | 3 | none | #:paint |
| text-blob-run-count | stable | 0 | procedure | 1 | none | none |
| text-blob-run-font | stable | 0 | procedure | 2 | none | none |
| text-blob-runs | stable | 0 | procedure | 1 | none | none |
| text-run-info-clusters | stable | 0 | procedure | 1 | none | none |
| text-run-info-glyphs | stable | 0 | procedure | 1 | none | none |
| text-run-info-positioning | stable | 0 | procedure | 1 | none | none |
| text-run-info-positions | stable | 0 | procedure | 1 | none | none |
| text-run-info-transforms | stable | 0 | procedure | 1 | none | none |
| text-run-info-utf8 | stable | 0 | procedure | 1 | none | none |
| text-run-info? | stable | 0 | procedure | 1 | none | none |
### typefaces.rkt

Stable export/call-boundary target for the 0.78 API. Feature-specific ownership, failure and backend limits still apply.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| font-manager-style-set | stable | 0 | procedure | 2 | none | none |
| font-manager-style-set-ref | stable | 0 | procedure | 2 | none | none |
| font-manager-typeface-from-bytes | stable | 0 | procedure | 2 | none | #:index |
| font-style-entry-index | stable | 0 | procedure | 1 | none | none |
| font-style-entry-name | stable | 0 | procedure | 1 | none | none |
| font-style-entry-style | stable | 0 | procedure | 1 | none | none |
| font-style-entry? | stable | 0 | procedure | 1 | none | none |
| font-style-set-count | stable | 0 | procedure | 1 | none | none |
| font-style-set-match | stable | 0 | procedure | 1, 2 | none | none |
| font-style-set-ref | stable | 0 | procedure | 2 | none | none |
| font-style-set-styles | stable | 0 | procedure | 1 | none | none |
| font-style-set-typeface | stable | 0 | procedure | 2 | none | none |
| font-style-set? | stable | 0 | procedure | 1 | none | none |
| font-style-slant | stable | 0 | procedure | 1 | none | none |
| font-style-weight | stable | 0 | procedure | 1 | none | none |
| font-style-width | stable | 0 | procedure | 1 | none | none |
| font-style? | stable | 0 | procedure | 1 | none | none |
| font-table-tag | stable | 0 | procedure | 1 | none | none |
| font-table-tag->bytes | stable | 0 | procedure | 1 | none | none |
| make-empty-font-style-set | stable | 0 | procedure | 0 | none | none |
| make-font-style | stable | 0 | procedure | 0 | none | #:slant, #:weight, #:width |
| typeface->font-bytes | stable | 0 | procedure | 1 | none | none |
| typeface-fixed-pitch? | stable | 0 | procedure | 1 | none | none |
| typeface-from-bytes | stable | 0 | procedure | 1 | none | #:index |
| typeface-glyph-count | stable | 0 | procedure | 1 | none | none |
| typeface-kerning-pair-adjustments | stable | 0 | procedure | 2 | none | none |
| typeface-postscript-name | stable | 0 | procedure | 1 | none | none |
| typeface-style | stable | 0 | procedure | 1 | none | none |
| typeface-table-bytes | stable | 0 | procedure | 2 | none | #:end, #:start |
| typeface-table-size | stable | 0 | procedure | 2 | none | none |
| typeface-table-tags | stable | 0 | procedure | 1 | none | none |
| typeface-units-per-em | stable | 0 | procedure | 1 | none | none |
### unsafe/gpu-d3d12.rkt

Unsafe external-resource entry point: caller-supplied native object validity and lifetime remain caller obligations.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| call-with-gpu-d3d12-device | experimental | 0 | procedure | 2 | none | none |
| make-d3d12-external-texture | experimental | 0 | procedure | 2 | #:incoming-state, #:outgoing-state, #:producer-fence, #:producer-value | #:color-space, #:incoming-state, #:outgoing-state, #:premultiplied?, #:producer-fence, #:producer-value, #:timeout-ms |
### unsafe/gpu-metal.rkt

Unsafe external-resource entry point: caller-supplied native object validity and lifetime remain caller obligations.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| call-with-gpu-metal-device | experimental | 0 | procedure | 2 | none | none |
| make-metal-external-texture | experimental | 0 | procedure | 2 | #:producer-command-buffer | #:color-space, #:premultiplied?, #:producer-command-buffer, #:timeout-ms |

## Gui exports

### canvas.rkt

Experimental GUI integration: owner/eventspace and callback-scoped lifetimes remain mandatory; import requires a graphical session.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| skia-canvas% | experimental | 0 | class | — | — | — |
| skia-canvas? | experimental | 0 | procedure | 1 | none | none |
### gpu-canvas.rkt

Experimental GUI integration: owner/eventspace and callback-scoped lifetimes remain mandatory; import requires a graphical session.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| skia-gpu-canvas% | experimental | 0 | class | — | — | — |
| skia-gpu-canvas? | experimental | 0 | procedure | 1 | none | none |
| skia-gpu-window% | experimental | 0 | class | — | — | — |
### gpu-gui.rkt

Experimental GUI integration: owner/eventspace and callback-scoped lifetimes remain mandatory; import requires a graphical session.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| gpu-canvas% | experimental | 0 | class | — | — | — |
| gpu-window% | experimental | 0 | class | — | — | — |
### gpu-racket-gl.rkt

Experimental GUI integration: owner/eventspace and callback-scoped lifetimes remain mandatory; import requires a graphical session.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| make-racket-gl-provider | experimental | 0 | procedure | 1 | none | none |
### render-canvas.rkt

Experimental GUI integration: owner/eventspace and callback-scoped lifetimes remain mandatory; import requires a graphical session.

| Export | Stability | Phase / space | Kind | Positional arguments | Required keywords | Accepted keywords |
|---|---|---|---|---|---|---|
| make-skia-render-canvas | experimental | 0 | procedure | 1 | none | #:adapter, #:adapter-index, #:backend, #:background, #:min-height, #:min-width, #:on-error, #:paint-callback, #:renderer, #:smoothing, #:sync-interval |
| skia-render-canvas<%> | experimental | 0 | interface | — | — | — |
| skia-render-canvas? | experimental | 0 | procedure | 1 | none | none |
| skia-render-window% | experimental | 0 | class | — | — | — |

## Updating the baseline

The validator and probe never rewrite expected snapshots. An intentional API change requires a separately reviewed baseline update, a generated-document diff, a release-review update, source checksums, and fresh runtime checks. Exact comparison flags additions as well as removals and changed arities/keywords.

### Reference

Racket reflection: `module->exports`, `dynamic-require`, `procedure-arity-mask`, and `procedure-keywords`. This baseline uses the actual expanded and instantiated modules, including aliases and syntax-backed constructors, rather than parsing a procedure definition to guess its signature.
