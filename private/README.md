# Private implementation modules

This folder implements the public Racket modules in the repository root. Its modules are
internal building blocks, not a second public API: application code should normally require
`skia` or the documented public submodule instead of importing these files directly.

## Where to start

- [core.rkt](core.rkt) connects checked Racket values to native resources, drawing, documents,
  codecs, and text layout. Smaller helpers isolate validation and additional API families.
- [lifetime.rkt](lifetime.rkt) owns ordinary native references and propagated GPU affinity;
  [gpu-domain.rkt](gpu-domain.rkt) owns GPU activation, deferred release, and shutdown.
- [native.rkt](native.rkt) declares the core lazy FFI bindings. Files ending in `-native.rkt`
  usually contain additional native bridges; `-types.rkt` files document ABI layouts.
- The `dc-` modules implement the `racket/draw` adapter. The `gpu-presenter` family
  supplies backend-independent frame lifetimes; GL, Metal, and Direct3D files implement
  their platform-specific operations.
- [bidi.rkt](bidi.rkt), [line-break.rkt](line-break.rkt), and [joining.rkt](joining.rkt)
  are the pure text algorithms used by layout, not native rendering entry points.

Resource wrappers, borrowed pointers, and detached snapshots have different lifetimes.
Consult [Resource Lifetimes](../docs/RESOURCE-LIFETIMES.md) and the field comments beside
each structure before changing ownership or caching. FFI layouts and native field order
must remain compatible with the pinned ABI. Tests live in [tests/](../tests/).

## Module directory

Each module below has a responsibility description and a sentence explaining its role
in the wider project. The groups are a browsing aid; they do not introduce new layers
or change module dependencies.

### Core API and native ownership

| Module | Contents |
| --- | --- |
| [advanced-canvas-types.rkt](advanced-canvas-types.rkt) | Defines the native save-layer record passed to the pinned Skia ABI. |
| [check.rkt](check.rkt) | Checks dimensions, scalars, strings, glyphs, and symbolic options; reports argument names, positions, and calling forms for drawing primitives. |
| [core.rkt](core.rkt) | Implements owned resources, canvas operations, image codecs, documents, and text layout. |
| [shader-util.rkt](shader-util.rkt) | Converts optional affine transforms shared by shader constructors. |
| [lifetime.rkt](lifetime.rkt) | Owns native references, scoped borrows, and propagated GPU affinity. |
| [native.rkt](native.rkt) | Declares lazy Skia FFI entry points and checks native readiness. |
| [native-abi.rkt](native-abi.rkt) | Checks Skia versions and native layout sizes before using the FFI. |
| [native-layouts.rkt](native-layouts.rkt) | Collects the C layout types checked during native initialization. |
| [native-loader.rkt](native-loader.rkt) | Resolves platform libraries and validates the selected Skia build. |
| [native-platform.rkt](native-platform.rkt) | Maps the host platform to the expected native library package and filename. |
| [types.rkt](types.rkt) | Defines the pinned C records and constants used by the Skia FFI. |

### Text, fonts, and Unicode

| Module | Contents |
| --- | --- |
| [bidi.rkt](bidi.rkt) | Classifies Unicode characters and resolves embedding levels and visual order. |
| [font-query-util.rkt](font-query-util.rkt) | Checks glyph requests, text slices, origins, and query allocation budgets. |
| [harfbuzz-native.rkt](harfbuzz-native.rkt) | Loads shaping and Unicode-query entry points lazily. |
| [harfbuzz-types.rkt](harfbuzz-types.rkt) | Defines glyph-info, glyph-position, and feature records. |
| [joining.rkt](joining.rkt) | Classifies joining characters and identifies connected text clusters. |
| [line-break.rkt](line-break.rkt) | Classifies characters and resolves line-break opportunities at text boundaries. |
| [text-run-data.rkt](text-run-data.rkt) | Defines glyph-run snapshots and the font references retained with them. |
| [text-run-util.rkt](text-run-util.rkt) | Checks glyph arrays, positions, transforms, UTF-8 metadata, and run budgets. |
| [typeface-util.rkt](typeface-util.rkt) | Validates font styles, collection indices, table tags, and font data slices. |
| [unicode-conformance.rkt](unicode-conformance.rkt) | Parses Unicode line-break and bidi test cases and compares resolved results. |

### Images, pixels, and color

| Module | Contents |
| --- | --- |
| [bitmap-transfer.rkt](bitmap-transfer.rkt) | Converts premultiplied RGBA storage to and from racket/draw ARGB byte order. |
| [color-filter-types.rkt](color-filter-types.rkt) | Defines the high-contrast configuration record required by Skia. |
| [color-filter-util.rkt](color-filter-util.rkt) | Validates color matrices, lookup tables, interpolation weights, and contrast options. |
| [color-output-util.rkt](color-output-util.rkt) | Validates color-space matrices, chromaticities, and encoder ICC metadata. |
| [float-color-native.rkt](float-color-native.rkt) | Converts detached floating-point colors to native RGBA records and back. |
| [float-pixel-util.rkt](float-pixel-util.rkt) | Encodes and decodes half- and single-precision pixel samples. |
| [icc-encoding.rkt](icc-encoding.rkt) | Prepares ICC profile and description values for native image encoders. |
| [image-info-native.rkt](image-info-native.rkt) | Converts between detached image descriptions and native image-info records. |
| [image-operation-util.rkt](image-operation-util.rkt) | Checks subset, scaling, sampling, and filter requests. |
| [integer-pixel-util.rkt](integer-pixel-util.rkt) | Packs and unpacks supported integer pixel formats and alpha modes. |
| [pixel-sample-util.rkt](pixel-sample-util.rkt) | Dispatches sample encoding and decoding to integer or floating-point formats. |
| [raster-buffer-util.rkt](raster-buffer-util.rkt) | Checks byte layouts, pixel coordinates, subsets, and raster callbacks. |
| [surface-property-native.rkt](surface-property-native.rkt) | Converts surface-property descriptions and scopes temporary native records. |

### Codecs and incremental decoding

| Module | Contents |
| --- | --- |
| [codec-incremental-input.rkt](codec-incremental-input.rkt) | Accumulates encoded bytes while tracking the prefix currently visible to a decoder. |
| [codec-incremental-source.rkt](codec-incremental-source.rkt) | Registers incremental inputs and services native read and seek requests. |
| [codec-incremental-state.rkt](codec-incremental-state.rkt) | Defines mutable cells and owned session records for an incremental decode. |
| [codec-incremental-util.rkt](codec-incremental-util.rkt) | Defines detached progress and snapshot records and validates incremental options. |
| [codec-query-util.rkt](codec-query-util.rkt) | Validates scaled dimensions, source sizes, and subset rectangles. |
| [codec-scanline-state.rkt](codec-scanline-state.rkt) | Defines the owned session record used while decoding image rows. |
| [codec-scanline-util.rkt](codec-scanline-util.rkt) | Validates row requests and packages decoded scanline batches and failures. |
| [codec-util.rkt](codec-util.rkt) | Maps codec result codes and applies encoded-image orientation to RGBA pixels. |

### Geometry, effects, and recorded pictures

| Module | Contents |
| --- | --- |
| [effects-util.rkt](effects-util.rkt) | Checks effect matrices, tables, clipping values, noise parameters, and path budgets. |
| [filter-graph.rkt](filter-graph.rkt) | Builds owned filter graphs for compositing, transforms, morphology, and lighting. |
| [filter-util.rkt](filter-util.rkt) | Validates filter crops, kernels, channels, tile modes, and lighting parameters. |
| [geometry-completion-util.rkt](geometry-completion-util.rkt) | Checks geometry matrices, conic subdivision, path-operation lists, and span bounds. |
| [geometry-util.rkt](geometry-util.rkt) | Checks points, colors, rectangles, vertex arrays, and lattice divisions. |
| [path-matrix.rkt](path-matrix.rkt) | Converts matrix layouts, transforms resources, and snapshots path commands. |
| [pict-util.rkt](pict-util.rkt) | Checks image and picture dimensions, backing scales, and scratch budgets. |
| [picture-util.rkt](picture-util.rkt) | Checks trust, byte budgets, bounds, and paths for recorded pictures. |
| [portable-util.rkt](portable-util.rkt) | Builds detached nine-patch and lattice cell plans with explicit source geometry. |
| [racket-draw-bitmap.rkt](racket-draw-bitmap.rkt) | Copies bitmap pixels, alpha, masks, and backing-scale information. |
| [racket-draw-path.rkt](racket-draw-path.rkt) | Converts between dc-path% commands and detached Skia path contours. |
| [runtime-util.rkt](runtime-util.rkt) | Validates SkSL source, uniform layouts, child bindings, and packed uniform values. |

### Document output and auditing

| Module | Contents |
| --- | --- |
| [annotation-util.rkt](annotation-util.rkt) | Validates annotation names, destinations, and links, and resolves SVG annotation output. |
| [audit-trace.rkt](audit-trace.rkt) | Tracks resource provenance and drawing events without exposing native handles. |
| [output-executor.rkt](output-executor.rkt) | Defines deferred raster plans and validates their execution owner. |
| [output-group-util.rkt](output-group-util.rkt) | Checks output-group labels, policies, geometry, and execution strategies. |
| [output-util.rkt](output-util.rkt) | Normalizes page units, insets, text modes, labels, and raster fallback dimensions. |
| [output-file.rkt](output-file.rkt) | Validates destinations and writes completed image, PDF, SVG, and picture bytes through same-directory temporary files. |
| [pdf-util.rkt](pdf-util.rkt) | Checks page sizes, metadata, dates, encoding settings, and output paths. |
| [svg-util.rkt](svg-util.rkt) | Checks dimensions and metadata and canonicalizes generated SVG identifiers. |

### Streams and live port I/O

| Module | Contents |
| --- | --- |
| [live-native-lease.rkt](live-native-lease.rkt) | Retains native references and pins resource owners during callback-based I/O. |
| [live-port-native.rkt](live-port-native.rkt) | Binds callback streams and drives native image and document operations over ports. |
| [live-port-runtime.rkt](live-port-runtime.rkt) | Tracks cancellation, byte limits, positions, and callback failures for live I/O. |
| [live-port-util.rkt](live-port-util.rkt) | Checks port capabilities, cancellation, limits, and execution ownership. |
| [stream-buffer.rkt](stream-buffer.rkt) | Reads and writes bounded byte sequences with cancellation support. |
| [stream-resource.rkt](stream-resource.rkt) | Defines the owned native stream wrapper and its retained storage. |

### Racket drawing-context adapters

| Module | Contents |
| --- | --- |
| [dc-alpha.rkt](dc-alpha.rkt) | Tracks nested transparency layers and their temporary render targets. |
| [dc-bitmap.rkt](dc-bitmap.rkt) | Copies Racket bitmap pixels and resolves logical versus physical bitmap geometry. |
| [dc-class.rkt](dc-class.rkt) | Builds the dc<%>-compatible class and maintains its selected drawing state. |
| [dc-compatibility.rkt](dc-compatibility.rkt) | Records the supported dc<%> method surface and compatibility classifications. |
| [dc-font-name.rkt](dc-font-name.rkt) | Normalizes font names, weights, and style requests into detached face descriptions. |
| [dc-font-name-native.rkt](dc-font-name-native.rkt) | Loads platform font-description support lazily and copies parsed font attributes. |
| [dc-geometry.rkt](dc-geometry.rkt) | Builds detached path commands for shapes and clipping geometry. |
| [dc-native-util.rkt](dc-native-util.rkt) | Installs matrices and clips and scopes temporary native paths. |
| [dc-output-capture.rkt](dc-output-capture.rkt) | Records bounded drawing-context commands for later replay. |
| [dc-output-native.rkt](dc-output-native.rkt) | Replays captured drawing-context commands with relative transforms and state. |
| [dc-path-bounds.rkt](dc-path-bounds.rkt) | Computes filled and stroked path bounds while accounting for degenerate contours. |
| [dc-region-adapter.rkt](dc-region-adapter.rkt) | Maintains selected clipping regions and snapshots their path representation. |
| [dc-region-query.rkt](dc-region-query.rkt) | Scopes native region queries and validates the associated drawing context. |
| [dc-render.rkt](dc-render.rkt) | Draws paths, bitmaps, copies, and alpha composites on Skia surfaces. |
| [dc-replay-adapter.rkt](dc-replay-adapter.rkt) | Tracks selected pen and brush styles through replayable leases. |
| [dc-style-math.rkt](dc-style-math.rkt) | Computes dash patterns, hatch lines, alignment, and local style transforms. |
| [dc-style-render.rkt](dc-style-render.rkt) | Creates temporary paint and shader resources from detached style descriptions. |
| [dc-styles.rkt](dc-styles.rkt) | Validates pens, brushes, stipples, gradients, and style transforms. |
| [dc-support.rkt](dc-support.rkt) | Defines renderer protocols, detached drawing records, and matrix helpers. |
| [dc-text.rkt](dc-text.rkt) | Measures and draws text using the adapter's normalized font requests. |
| [dc-text-spec.rkt](dc-text-spec.rkt) | Copies font and text settings into detached request records. |

### GUI rendering and presentation

| Module | Contents |
| --- | --- |
| [canvas-backing.rkt](canvas-backing.rkt) | Manages bitmap backing stores and presents rendered pixels in a GUI canvas. |
| [gpu-dc-native.rkt](gpu-dc-native.rkt) | Renders drawing-context commands on a scoped GPU canvas. |
| [gpu-dc-scope.rkt](gpu-dc-scope.rkt) | Validates frame dimensions and scopes a drawing context to a GPU frame. |
| [gpu-frame-target-cache.rkt](gpu-frame-target-cache.rkt) | Caches presentation targets by size and configuration and disposes replacements. |
| [gpu-presentation-cleanup.rkt](gpu-presentation-cleanup.rkt) | Runs presentation cleanup steps without losing earlier failures. |
| [gpu-presentation-native.rkt](gpu-presentation-native.rkt) | Binds native flush and presentation-related operations lazily. |
| [gpu-presenter.rkt](gpu-presenter.rkt) | Scopes frame canvases and coordinates presentation, resize, and shutdown. |
| [gpu-presenter-d3d12.rkt](gpu-presenter-d3d12.rkt) | Builds the presentation adapter around DXGI swap-chain targets. |
| [gpu-presenter-gl.rkt](gpu-presenter-gl.rkt) | Builds a presentation adapter for GL-backed window contexts. |
| [gpu-presenter-metal.rkt](gpu-presenter-metal.rkt) | Builds the presentation adapter around CAMetalLayer drawable leases. |
| [gpu-window.rkt](gpu-window.rkt) | Creates window-backed GPU presenters and coordinates GUI cleanup. |
| [render-canvas-policy.rkt](render-canvas-policy.rkt) | Resolves requested rendering backends and reports supported capabilities. |
| [render-canvas-state.rkt](render-canvas-state.rkt) | Tracks callback delivery, active drawing contexts, and session ownership. |

### GPU domains and shared resources

| Module | Contents |
| --- | --- |
| [gpu-backends.rkt](gpu-backends.rkt) | Loads immutable backend capabilities and validates backend identifiers. |
| [gpu-cache.rkt](gpu-cache.rkt) | Runs cache queries and cleanup inside the owning GPU domain. |
| [gpu-cache-native.rkt](gpu-cache-native.rkt) | Loads cache-management entry points lazily and dispatches checked native requests. |
| [gpu-cache-util.rkt](gpu-cache-util.rkt) | Validates GPU cache limits, purge sizes, and age thresholds. |
| [gpu-context.rkt](gpu-context.rkt) | Wraps GPU domains and arranges owner-thread context cleanup. |
| [gpu-context-control.rkt](gpu-context-control.rkt) | Validates and executes context reset, flush, and lifecycle operations. |
| [gpu-context-control-native.rkt](gpu-context-control-native.rkt) | Dispatches reset and resource-management operations to native Ganesh contexts. |
| [gpu-context-options-native.rkt](gpu-context-options-native.rkt) | Builds the pinned native options record for Ganesh context creation. |
| [gpu-diagnostic-util.rkt](gpu-diagnostic-util.rkt) | Checks diagnostic values and converts native reports to detached Racket data. |
| [gpu-diagnostics.rkt](gpu-diagnostics.rkt) | Classifies detached driver strings and checks smoke-test RGBA pixels without native initialization. |
| [gpu-diagnostics-native.rkt](gpu-diagnostics-native.rkt) | Copies native context diagnostics through lazy bindings. |
| [gpu-domain.rkt](gpu-domain.rkt) | Owns context activation, resource affinity, deferred release, and shutdown state. |
| [gpu-external.rkt](gpu-external.rkt) | Wraps externally supplied GPU texture identities and tracks their lifetime. |
| [gpu-format-util.rkt](gpu-format-util.rkt) | Checks GPU color formats, alpha modes, and texture compatibility. |
| [gpu-image-native.rkt](gpu-image-native.rkt) | Binds image upload, texture conversion, and readback operations lazily. |
| [gpu-image-operations.rkt](gpu-image-operations.rkt) | Performs GPU-aware image validity and conversion operations. |
| [gpu-images.rkt](gpu-images.rkt) | Uploads images, snapshots surfaces, and explicitly detaches GPU pixels. |
| [gpu-interop-cleanup.rkt](gpu-interop-cleanup.rkt) | Runs cleanup actions while preserving the operation's original exception. |
| [gpu-interop-guard.rkt](gpu-interop-guard.rkt) | Tracks scopes in which reentrant Skia GPU access is forbidden. |
| [gpu-io-trace.rkt](gpu-io-trace.rkt) | Provides the shared hook for recording GPU transfer events. |
| [gpu-native.rkt](gpu-native.rkt) | Loads Ganesh context and interface entry points lazily. |
| [gpu-native-scope.rkt](gpu-native-scope.rkt) | Scopes per-call native thread-local setup and cleanup, including Metal autorelease pools. |
| [gpu-performance-util.rkt](gpu-performance-util.rkt) | Validates benchmark settings, measures completed work, and checks resource-use envelopes. |
| [gpu-provider.rkt](gpu-provider.rkt) | Defines provider identity, activation, capability descriptions, and unavailability errors. |
| [gpu-raw.rkt](gpu-raw.rkt) | Checks and exposes native resource pointers within valid internal scopes. |
| [gpu-render.rkt](gpu-render.rkt) | Validates context-bound drawing procedures and executes GPU rendering scopes. |
| [gpu-smoke.rkt](gpu-smoke.rkt) | Renders and checks a small scene through a selected GPU context. |
| [gpu-surface-identity.rkt](gpu-surface-identity.rkt) | Associates surface wrappers with immutable native identity descriptions. |
| [gpu-surface-native.rkt](gpu-surface-native.rkt) | Binds render-target creation, wrapping, and surface queries lazily. |
| [gpu-surface-util.rkt](gpu-surface-util.rkt) | Checks dimensions, sampling, origins, and surface configuration. |
| [gpu-surfaces.rkt](gpu-surfaces.rkt) | Creates and wraps GPU surfaces and validates their context-affine canvases. |
| [gpu-types.rkt](gpu-types.rkt) | Defines GL framebuffer, GL texture, and Metal texture information records. |

### OpenGL and EGL

| Module | Contents |
| --- | --- |
| [gpu-driver-egl.rkt](gpu-driver-egl.rkt) | Constructs the GL driver through an EGL context provider. |
| [gpu-driver-gl.rkt](gpu-driver-gl.rkt) | Creates and describes Ganesh GL contexts using a provider-resolved interface. |
| [gpu-egl-system.rkt](gpu-egl-system.rkt) | Loads EGL, retains displays, and manages current-context scopes. |
| [gpu-egl-util.rkt](gpu-egl-util.rkt) | Defines injectable EGL operations and validates provider options. |
| [gpu-gl-interface.rkt](gpu-gl-interface.rkt) | Constructs Skia GL interfaces from provider-resolved entry points. |
| [gpu-gl-interop.rkt](gpu-gl-interop.rkt) | Scopes application-owned textures and framebuffers under their GPU context. |
| [gpu-gl-interop-native.rkt](gpu-gl-interop-native.rkt) | Binds backend texture and render-target operations lazily. |
| [gpu-gl-interop-util.rkt](gpu-gl-interop-util.rkt) | Checks external GL identifiers and texture target options. |
| [gpu-gl-queries.rkt](gpu-gl-queries.rkt) | Queries texture and framebuffer descriptions while restoring GL bindings. |
| [gpu-gl-system.rkt](gpu-gl-system.rkt) | Loads platform GL libraries and resolves native entry points. |

### Metal

| Module | Contents |
| --- | --- |
| [gpu-driver-metal.rkt](gpu-driver-metal.rkt) | Builds a Ganesh driver around retained Metal devices and queues. |
| [gpu-metal-handles.rkt](gpu-metal-handles.rkt) | Owns retained Metal devices and queues on their creator thread. |
| [gpu-metal-interop.rkt](gpu-metal-interop.rkt) | Scopes external Metal textures as Skia images and surfaces. |
| [gpu-metal-interop-native.rkt](gpu-metal-interop-native.rkt) | Binds Skia Metal texture wrapping and flush operations lazily. |
| [gpu-metal-interop-policy.rkt](gpu-metal-interop-policy.rkt) | Validates supported texture shapes, formats, and synchronization outcomes. |
| [gpu-metal-interop-session.rkt](gpu-metal-interop-session.rkt) | Retains shared textures and coordinates producer completion with Skia work. |
| [gpu-metal-interop-system.rkt](gpu-metal-interop-system.rkt) | Queries Metal texture properties and command-buffer status through Objective-C. |
| [gpu-metal-layer.rkt](gpu-metal-layer.rkt) | Manages CAMetalLayer hosts, drawable leases, and presentation. |
| [gpu-metal-probe.rkt](gpu-metal-probe.rkt) | Checks whether native Metal support can be loaded. |
| [gpu-metal-system.rkt](gpu-metal-system.rkt) | Loads Objective-C Metal services and retains device and queue handles. |
| [gpu-metal-util.rkt](gpu-metal-util.rkt) | Defines injectable Metal platform and context operations and validates options. |

### Direct3D and DXGI

| Module | Contents |
| --- | --- |
| [gpu-d3d12-handles.rkt](gpu-d3d12-handles.rkt) | Owns retained adapter, device, and queue handles for one Racket thread. |
| [gpu-d3d12-interop.rkt](gpu-d3d12-interop.rkt) | Scopes external Direct3D textures and validates their context affinity. |
| [gpu-d3d12-interop-native.rkt](gpu-d3d12-interop-native.rkt) | Binds native texture wrapping and synchronization entry points lazily. |
| [gpu-d3d12-interop-policy.rkt](gpu-d3d12-interop-policy.rkt) | Checks texture descriptions and supported Direct3D sharing constraints. |
| [gpu-d3d12-interop-system.rkt](gpu-d3d12-interop-system.rkt) | Coordinates Direct3D resource states, fences, and interoperation sessions. |
| [gpu-d3d12-system.rkt](gpu-d3d12-system.rkt) | Loads Windows device functions and manages adapter, device, and queue creation. |
| [gpu-d3d12-types.rkt](gpu-d3d12-types.rkt) | Defines the backend-context, command-queue, and adapter-description C layouts. |
| [gpu-d3d12-util.rkt](gpu-d3d12-util.rkt) | Defines injectable platform and context operations and validates device requests. |
| [gpu-driver-d3d12.rkt](gpu-driver-d3d12.rkt) | Builds a Ganesh driver from Direct3D platform and context operations. |
| [gpu-dxgi-system.rkt](gpu-dxgi-system.rkt) | Manages swap chains, frame tokens, back buffers, and presentation synchronization. |
| [gpu-dxgi-types.rkt](gpu-dxgi-types.rkt) | Defines swap-chain, resource, transition, copy, and range records. |
| [gpu-dxgi-util.rkt](gpu-dxgi-util.rkt) | Checks presentation sizes, options, and native integer ranges. |

### Graphics diagnostics

| Module | Contents |
| --- | --- |
| [graphics-data.rkt](graphics-data.rkt) | Collects bounded, detached memory-statistics records and scope metadata. |
| [graphics-trace-native.rkt](graphics-trace-native.rkt) | Installs native memory-dump callbacks and copies their bounded results. |
