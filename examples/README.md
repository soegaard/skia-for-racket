# Examples

These programs show the public drawing APIs in use and supply shared scenes for
visual comparison. They are clients of the library, not its implementation.
Start with [circle.rkt](circle.rkt) for a minimal raster program or
[gallery.rkt](gallery.rkt) for a broader drawing sample. For a guided sequence,
see the [tutorial sources](../scribblings/tutorials/README.md).

Many programs write files when run; GUI and GPU examples may open windows or
require a particular platform. Read the entry point and command-line options
before running an unfamiliar example. Some reusable scene modules are intended
to be imported by comparison tools instead of run alone.

## Files

- [advanced-canvases.rkt](advanced-canvases.rkt) — Demonstrates native recorded drawables, canvas stacks, and compositing layers.
- [advanced-codecs.rkt](advanced-codecs.rkt) — Renders a contact sheet of animation disposal and EXIF orientation cases.
- [bidi-controls.rkt](bidi-controls.rkt) — Compares explicit Unicode embedding, override, and isolate controls in shaped text.
- [bitmap-bridge.rkt](bitmap-bridge.rkt) — Copies a Skia drawing into a Racket bitmap and saves the detached result.
- [break-providers.rkt](break-providers.rkt) — Demonstrates application-supplied word breaks and visible hyphen opportunities.
- [canvas-primitives.rkt](canvas-primitives.rkt) — Builds drawing pages for points, arcs, clip queries, and compositing layers.
- [circle.rkt](circle.rkt) — Renders a red circle to PNG using a surface, its borrowed canvas, and a paint.
- [codec-incremental.rkt](codec-incremental.rkt) — Feeds PNG chunks to the incremental decoder and reports progress.
- [codec-queries.rkt](codec-queries.rkt) — Inspects codec scaling suggestions without treating them as decoded images.
- [codec-scanlines.rkt](codec-scanlines.rkt) — Reads a native JPEG decoder in bounded batches of scanlines.
- [codecs.rkt](codecs.rkt) — Renders an image-codec gallery from in-memory encoding and decoding round trips.
- [color-filters.rkt](color-filters.rkt) — Compares channel matrices, transfer curves, and composed color filters.
- [color-output.rkt](color-output.rkt) — Compares color-space tagging, conversion, and profile-aware document output.
- [dc-closure.rkt](dc-closure.rkt) — Exports a described-font drawing callback through audited document output.
- [dc-compatibility.rkt](dc-compatibility.rkt) — Defines independent racket/draw scenes for bitmap and text compatibility checks.
- [dc-consumers.rkt](dc-consumers.rkt) — Runs existing drawing consumers directly against the public Skia drawing context.
- [dc-output.rkt](dc-output.rkt) — Exports shared drawing-context callbacks to PDF, SVG, and raster previews.
- [dc-primitives.rkt](dc-primitives.rkt) — Defines drawing-context geometry scenes and an independent raster oracle.
- [dc-replay.rkt](dc-replay.rkt) — Compares recorded drawing procedures with directly authored drawing-context scenes.
- [dc-styles.rkt](dc-styles.rkt) — Writes the shared drawing-context style corpus to a PNG.
- [document-links.rkt](document-links.rkt) — Builds document pages with hyperlinks, destinations, and linkable regions.
- [effects.rkt](effects.rkt) — Exports a drawing with explicit bounded raster fallback for a visual effect.
- [filter-graphs.rkt](filter-graphs.rkt) — Compares native filter graphs with bounded SVG raster groups and raster references.
- [filters.rkt](filters.rkt) — Renders examples of color filters, blur masks, shadows, and filter composition.
- [float-pixels.rkt](float-pixels.rkt) — Draws into a floating-point pixel buffer and explicitly quantizes PNG output.
- [font-queries.rkt](font-queries.rkt) — Inspects glyph metrics and font options without assuming a particular system font.
- [gallery.rkt](gallery.rkt) — Renders a font-independent gallery of curves, clips, transforms, and compositing.
- [geometry-primitives.rkt](geometry-primitives.rkt) — Builds pages comparing regions, image lattices, sprite atlases, and meshes.
- [geometry.rkt](geometry.rkt) — Runs the geometry document generator with an explicitly chosen output directory.
- [global-caches.rkt](global-caches.rkt) — Reports native cache and memory statistics without changing cache policy.
- [gpu-breakout.rkt](gpu-breakout.rkt) — Runs an interactive Breakout game with offscreen rendering and a shader post-pass.
- [gpu-context-options.rkt](gpu-context-options.rkt) — Builds GPU context options without opening a native GPU context.
- [gpu-d3d12.rkt](gpu-d3d12.rkt) — Renders through an explicitly selected Direct3D adapter and records its metadata.
- [gpu-dc-consumers.rkt](gpu-dc-consumers.rkt) — Opens an interactive GPU review window for drawing-context consumers.
- [gpu-diagnostics.rkt](gpu-diagnostics.rkt) — Reports context, cache, and memory diagnostics for an explicitly selected GPU.
- [gpu-dxgi.rkt](gpu-dxgi.rkt) — Opens a Windows DXGI presenter on a selected software or hardware adapter.
- [gpu-formats.rkt](gpu-formats.rkt) — Returns a detached half-float CPU image rendered in a caller-selected GPU context.
- [gpu-game-demo.rkt](gpu-game-demo.rkt) — Combines runtime shaders, recorded backgrounds, uploaded textures, and sprite batches.
- [gpu-headless.rkt](gpu-headless.rkt) — Renders a headless OpenGL image through an explicitly configured EGL binding.
- [gpu-images.rkt](gpu-images.rkt) — Defines shared image-workflow scenes for CPU and GPU comparison.
- [gpu-metal.rkt](gpu-metal.rkt) — Renders a selected shared scene with Metal and saves a CPU-readable result.
- [gpu-output.rkt](gpu-output.rkt) — Generates output documents using an explicitly selected GPU rendering backend.
- [gpu-presentation-scene.rkt](gpu-presentation-scene.rkt) — Draws a shared frame callback for comparing native GPU presenters.
- [gpu-presenters.rkt](gpu-presenters.rkt) — Opens GPU presenter windows that share the same drawing callback.
- [gpu-scenes.rkt](gpu-scenes.rkt) — Defines the common scene registry used for direct CPU and GPU rendering comparisons.
- [gradients.rkt](gradients.rkt) — Renders a gallery of gradient, tiled-image, and blended shaders.
- [image-operations.rkt](image-operations.rkt) — Demonstrates filtered-image subsets and the placement of their valid pixels.
- [integer-pixels.rkt](integer-pixels.rkt) — Preserves exact high-bit-depth channel samples until explicit 8-bit conversion.
- [justification.rkt](justification.rkt) — Compares text alignment and justification using visible layout guides.
- [layout.rkt](layout.rkt) — Renders paragraph layout examples with explicit alignment and language settings.
- [line-breaking.rkt](line-breaking.rkt) — Illustrates how line breaking changes the measured and displayed text lines.
- [live-streams.rkt](live-streams.rkt) — Copies between native streams and Racket ports while respecting borrowed ownership.
- [mixed-text.rkt](mixed-text.rkt) — Renders mixed-script text and summarizes its visual runs.
- [output-audit.rkt](output-audit.rkt) — Builds output pages that expose document capability and fallback decisions.
- [output-groups.rkt](output-groups.rkt) — Compares vector output, raster groups, isolation, and nested output decisions.
- [path-effects.rkt](path-effects.rkt) — Renders path effects, measurements, segments, and Boolean path operations.
- [path-matrix.rkt](path-matrix.rkt) — Compares path geometry, frame transforms, and shader-coordinate transforms.
- [pdf-documents.rkt](pdf-documents.rkt) — Uses shared drawing callbacks to produce PDF pages and separate raster references.
- [persistent-pictures.rkt](persistent-pictures.rkt) — Compares recorded pictures before and after serialization and indexed replay.
- [pict-bridge.rkt](pict-bridge.rkt) — Converts a Skia surface through the pict bridge and saves a Racket bitmap.
- [pictures.rkt](pictures.rkt) — Builds and replays reusable recorded pictures in a comparison gallery.
- [portable-drawing.rkt](portable-drawing.rkt) — Exports point markers, image lattices, and atlas sprites with explicit output decisions.
- [projective-matrices.rkt](projective-matrices.rkt) — Compares affine and projective transforms, clipping, and saved canvas state.
- [raster-buffers.rkt](raster-buffers.rkt) — Illustrates row stride, borrowed pixel views, drawing, and detached snapshots.
- [render-canvas.rkt](render-canvas.rkt) — Opens a review window that runs the same consumer on selected rendering backends.
- [runtime-effects.rkt](runtime-effects.rkt) — Builds pages demonstrating runtime shader uniforms, children, and reflection.
- [script-justification.rkt](script-justification.rkt) — Compares script-aware justification and paragraph layout behavior.
- [shaping.rkt](shaping.rkt) — Renders shaped text examples that expose glyph placement and language behavior.
- [skia-canvas.rkt](skia-canvas.rkt) — Opens raster-backed Skia drawing-context windows for interactive lifecycle review.
- [skia-canvas-on-gpu.rkt](skia-canvas-on-gpu.rkt) — Opens a GPU-backed drawing-context window without retaining frame-local resources.
- [small-gaps.rkt](small-gaps.rkt) — Demonstrates linear RGB basis conversion using XYZ-D50 matrices.
- [streams.rkt](streams.rkt) — Demonstrates native memory-stream ownership transfer, duplication, and reading.
- [svg-documents.rkt](svg-documents.rkt) — Exports SVG probe pages and separate raster references from shared drawing callbacks.
- [svg-paths.rkt](svg-paths.rkt) — Compares SVG path parsing and rendering in a visual gallery.
- [text-blobs-advanced.rkt](text-blobs-advanced.rkt) — Builds retained shaped text and places it along a path.
- [text-blobs.rkt](text-blobs.rkt) — Compares retained text blobs with their glyph data and placements.
- [text.rkt](text.rkt) — Renders a basic text specimen using fonts, paints, metrics, and outline drawing.
- [typefaces.rkt](typefaces.rkt) — Inspects a supplied font file without replacing it with a default family.
- [vector-output.rkt](vector-output.rkt) — Compares units, text, and effects across shared PDF, SVG, and raster output pages.
- [public/](public/README.md) — Focused examples using only public package modules.
