# Development, validation, and documentation tools

This directory contains developer executables, evidence drivers, artifact
inspectors, and native ABI probes. It is not the public drawing API.
[tests](../tests/README.md) contains their shared assertions and scene inputs.

## Main workflows

| Entry points | Role |
| --- | --- |
| [doctor.rkt](doctor.rkt) | Human-facing installation and selected native feature diagnostics. |
| [ci.py](ci.py), [ci_matrix.py](ci_matrix.py), [ci-matrix.json](ci-matrix.json) | CI orchestration and the declared platform/runtime matrix. |
| [static-check.py](static-check.py) | Source-level checks complementing executable tests. |
| [api-inventory.py](api-inventory.py), [public_api.py](public_api.py) | API inventory validation, supported by isolated export reflection. |
| [check-reference.py](check-reference.py), [reference_review.py](reference_review.py) | Reference inventory and documentation acceptance checks. |
| [validate-release-candidate.py](validate-release-candidate.py), [release_candidate.py](release_candidate.py) | Assemble and validate release-candidate evidence. |
| [validate-release-scope.py](validate-release-scope.py), [release_scope.py](release_scope.py), [release_graph.py](release_graph.py) | Validate release scope and its dependency/evidence graph. |
| [install-native.sh](install-native.sh), [install-native-windows.py](install-native-windows.py), [install-native-windows.ps1](install-native-windows.ps1), [install-harfbuzz.sh](install-harfbuzz.sh) | Explicit native dependency installation, distinct from read-only checks. |

## File families

- `*-doctor.rkt` runs a focused native diagnostic or writes captures and a receipt.
  Some require a window, SDK fixture, or selected GPU backend.
- `validate-*.py`, `validate-*.sh`, and platform launchers coordinate acceptance
  runs. Consult their options before invoking them.
- `*_validation.py`, `*_cases.py`, and `reference_support.py` hold shared
  expectations, case data, and report logic.
- `inspect-*.py` checks produced images, documents, or receipts. Inspection alone
  is not evidence that the current host executed the workload.
- `test-*.py` and `test_*.py` test validators/inspectors, including rejection of
  incomplete or misleading evidence, rather than the rendering API itself.
- `check-*-abi.c`, [struct-layout.c](struct-layout.c), and
  [native_abi.py](native_abi.py) describe or check pinned native layouts.
- [audit-symbols.sh](audit-symbols.sh) and
  [audit-harfbuzz-symbols.sh](audit-harfbuzz-symbols.sh) inspect exported symbols.
- [run-unicode-conformance.sh](run-unicode-conformance.sh) drives the text
  conformance executable with external Unicode data.

GPU evidence distinguishes drawing, explicit readback, presentation requests,
and teardown. Receipts do not establish hardware, physical-display, or zero-copy
behavior unless those properties were actually measured. Many writers require
a fresh output directory and invocation token.

## Documentation

[reference-render.rkt](reference-render.rkt) builds linked manuals;
[reference-runtime.rkt](reference-runtime.rkt) checks binding shapes and resolved
cross-references. [reference-native-test.rkt](reference-native-test.rkt) runs
displayed examples with namespace/process isolation.

[render-reference-images.rkt](render-reference-images.rkt) generates examples and
conceptual figures; [validate-reference-images.py](validate-reference-images.py)
checks the set. [render-documentation-landing.rkt](render-documentation-landing.rkt)
builds shared landing navigation, checked by
[check-documentation-navigation.py](check-documentation-navigation.py) and
[test-documentation-navigation.py](test-documentation-navigation.py).
[copy-tutorial-examples.rkt](copy-tutorial-examples.rkt) exports complete cataloged
tutorial programs.

## Native helper projects

| Directory | Independent evidence |
| --- | --- |
| [ci-abi](ci-abi/README.md) | Portable C mirrors of binding ABI declarations. |
| [d3d12-abi](d3d12-abi/README.md) | SDK layouts, GUIDs, and by-value structure passing. |
| [dxgi-abi](dxgi-abi/README.md) | DXGI SDK declarations and explicitly limited host mirrors. |
| [d3d12-interop-fixture](d3d12-interop-fixture/README.md) | Independent Direct3D producer/consumer and synchronization cases. |
| [metal-interop-fixture](metal-interop-fixture/README.md) | Independent Metal producer/consumer and Apple SDK checks. |

## Racket module map

### Diagnostics and evidence generation

| Module | Responsibility |
| --- | --- |
| [advanced-canvas-doctor.rkt](advanced-canvas-doctor.rkt) | Exercises save layers, native drawables, and specialized canvases and reports native diagnostic evidence. |
| [annotation-doctor.rkt](annotation-doctor.rkt) | Exercises document links, named destinations, and SVG annotation finishing and reports native diagnostic evidence. |
| [canvas-doctor.rkt](canvas-doctor.rkt) | Exercises canvas state, geometric queries, clipping, and drawing and reports native diagnostic evidence. |
| [codec-doctor.rkt](codec-doctor.rkt) | Exercises animation decoding, frame disposal, and encoded image orientation and reports native diagnostic evidence. |
| [codec-incremental-doctor.rkt](codec-incremental-doctor.rkt) | Exercises incremental PNG feeding, decode progress, and detached snapshots and reports native diagnostic evidence. |
| [codec-query-doctor.rkt](codec-query-doctor.rkt) | Exercises native codec scaling and subset negotiation and reports native diagnostic evidence. |
| [codec-scanline-doctor.rkt](codec-scanline-doctor.rkt) | Exercises scanline decoding, encoded row order, and cursor ownership and reports native diagnostic evidence. |
| [color-filter-doctor.rkt](color-filter-doctor.rkt) | Exercises HSLA, gamma, lookup-table, and composed color filters and reports native diagnostic evidence. |
| [color-output-doctor.rkt](color-output-doctor.rkt) | Exercises ICC profiles, transfer functions, and color-preserving image output and reports native diagnostic evidence. |
| [dc-consumer-doctor.rkt](dc-consumer-doctor.rkt) | Exercises pict, plot/no-gui, and recorded drawing consumers and reports native diagnostic evidence. |
| [dc-doctor.rkt](dc-doctor.rkt) | Exercises the persistent Skia implementation of Racket's drawing-context interface and reports native diagnostic evidence. |
| [dc-output-doctor.rkt](dc-output-doctor.rkt) | Exercises shared DC authoring on raster, PDF, and SVG output canvases and reports native diagnostic evidence. |
| [dc-style-doctor.rkt](dc-style-doctor.rkt) | Exercises DC brush styles, gradients, stipples, and compatibility queries and reports native diagnostic evidence. |
| [doctor.rkt](doctor.rkt) | Runs installation diagnostics and feature-specific native rendering probes selected by command-line options. |
| [effects-doctor.rkt](effects-doctor.rkt) | Exercises path effects, mask filters, noise, and programmable blending and reports native diagnostic evidence. |
| [filter-graph-doctor.rkt](filter-graph-doctor.rkt) | Exercises image-filter graph geometry, retained inputs, and output policy and reports native diagnostic evidence. |
| [float-pixel-doctor.rkt](float-pixel-doctor.rkt) | Exercises floating-point pixel storage, colors, and conversion and reports native diagnostic evidence. |
| [font-query-doctor.rkt](font-query-doctor.rkt) | Exercises font mutation, glyph metrics, and detached outline queries and reports native diagnostic evidence. |
| [geometry-completion-doctor.rkt](geometry-completion-doctor.rkt) | Exercises arc construction, path operations, rounded rectangles, and regions and reports native diagnostic evidence. |
| [geometry-doctor.rkt](geometry-doctor.rkt) | Exercises structured geometry, vertices, patches, and advanced image drawing and reports native diagnostic evidence. |
| [global-cache-doctor.rkt](global-cache-doctor.rkt) | Exercises global font/resource cache controls and bounded memory statistics and reports native diagnostic evidence. |
| [gpu-backend-doctor.rkt](gpu-backend-doctor.rkt) | Runs the backend-specific diagnostic chosen by command-line arguments. |
| [gpu-cross-backend-doctor.rkt](gpu-cross-backend-doctor.rkt) | Exercises OpenGL/Metal separation and explicit cross-backend transfers and reports native diagnostic evidence. |
| [gpu-d3d12-doctor.rkt](gpu-d3d12-doctor.rkt) | Exercises Direct3D 12 adapter selection, COM ownership, and ABI contracts and reports native diagnostic evidence. |
| [gpu-d3d12-interop-doctor.rkt](gpu-d3d12-interop-doctor.rkt) | Exercises gpu d3d12 interop and reports native diagnostic evidence. |
| [gpu-doctor.rkt](gpu-doctor.rkt) | Exercises GPU domains, thread affinity, deferred release, and abandonment and reports native diagnostic evidence. |
| [gpu-dxgi-doctor.rkt](gpu-dxgi-doctor.rkt) | Exercises DXGI presentation policy and swap-chain ownership and reports native diagnostic evidence. |
| [gpu-egl-doctor.rkt](gpu-egl-doctor.rkt) | Exercises EGL activation, surface selection, and resource ownership and reports native diagnostic evidence. |
| [gpu-image-doctor.rkt](gpu-image-doctor.rkt) | Exercises GPU image residency, ownership, and explicit pixel transfer and reports native diagnostic evidence. |
| [gpu-interop-doctor.rkt](gpu-interop-doctor.rkt) | Exercises external Direct3D textures, state handoff, and synchronization and reports native diagnostic evidence. |
| [gpu-metal-doctor.rkt](gpu-metal-doctor.rkt) | Exercises Metal device/queue ownership, activation scopes, and abandonment and reports native diagnostic evidence. |
| [gpu-metal-interop-doctor.rkt](gpu-metal-interop-doctor.rkt) | Exercises Metal texture handoff, producer completion, and retained ownership and reports native diagnostic evidence. |
| [gpu-offscreen-doctor.rkt](gpu-offscreen-doctor.rkt) | Exercises gpu offscreen and reports native diagnostic evidence. |
| [gpu-output-doctor.rkt](gpu-output-doctor.rkt) | Exercises bounded GPU raster fallbacks within vector documents and reports native diagnostic evidence. |
| [gpu-performance-doctor.rkt](gpu-performance-doctor.rkt) | Exercises GPU timing, frame reuse, and deferred-release measurements and reports native diagnostic evidence. |
| [gpu-presenter-doctor.rkt](gpu-presenter-doctor.rkt) | Exercises frame acquisition, presentation, redraw scheduling, and closure and reports native diagnostic evidence. |
| [gpu-redraw-doctor.rkt](gpu-redraw-doctor.rkt) | Exercises gpu redraw and reports native diagnostic evidence. |
| [gpu-render-doctor.rkt](gpu-render-doctor.rkt) | Runs the native one-shot rendering suite and writes a result receipt. |
| [gpu-window-doctor.rkt](gpu-window-doctor.rkt) | Exercises gpu window and reports native diagnostic evidence. |
| [image-operation-doctor.rkt](image-operation-doctor.rkt) | Exercises image filtering, subsets, placement offsets, and raw pixel access and reports native diagnostic evidence. |
| [integer-pixel-doctor.rkt](integer-pixel-doctor.rkt) | Exercises integer pixel formats, channel packing, and padded row storage and reports native diagnostic evidence. |
| [live-stream-doctor.rkt](live-stream-doctor.rkt) | Exercises synchronous native callbacks over live Racket input and output ports and reports native diagnostic evidence. |
| [native-abi-doctor.rkt](native-abi-doctor.rkt) | Prints the active native ABI profile and resolved library information. |
| [output-audit-doctor.rkt](output-audit-doctor.rkt) | Exercises vector-output capability tracking and fallback policy and reports native diagnostic evidence. |
| [output-doctor.rkt](output-doctor.rkt) | Exercises reusable output pages and PDF, SVG, and raster destinations and reports native diagnostic evidence. |
| [path-matrix-doctor.rkt](path-matrix-doctor.rkt) | Exercises path geometry, affine matrices, and detached query results and reports native diagnostic evidence. |
| [pdf-doctor.rkt](pdf-doctor.rkt) | Exercises PDF documents, page scopes, metadata, and finish-time output and reports native diagnostic evidence. |
| [picture-doctor.rkt](picture-doctor.rkt) | Exercises persistent recorded pictures, serialization, and replay ownership and reports native diagnostic evidence. |
| [portable-drawing-doctor.rkt](portable-drawing-doctor.rkt) | Exercises portable drawing and reports native diagnostic evidence. |
| [projective-doctor.rkt](projective-doctor.rkt) | Exercises projective transforms and output-audit classification and reports native diagnostic evidence. |
| [raster-buffer-doctor.rkt](raster-buffer-doctor.rkt) | Exercises raster buffer layouts, writable pixmaps, and storage ownership and reports native diagnostic evidence. |
| [runtime-doctor.rkt](runtime-doctor.rkt) | Exercises SkSL runtime effects, uniform packing, and retained child effects and reports native diagnostic evidence. |
| [stream-doctor.rkt](stream-doctor.rkt) | Exercises bounded port I/O, cancellation, and stream ownership and reports native diagnostic evidence. |
| [svg-doctor.rkt](svg-doctor.rkt) | Exercises SVG document finishing, XML metadata, and output lifetime and reports native diagnostic evidence. |
| [text-blob-doctor.rkt](text-blob-doctor.rkt) | Exercises retained text runs, glyph positions, clusters, and serialization and reports native diagnostic evidence. |
| [typeface-doctor.rkt](typeface-doctor.rkt) | Exercises deterministic font fixtures, font tables, and typeface ownership and reports native diagnostic evidence. |

### Reference acceptance suites

| Module | Responsibility |
| --- | --- |
| [reference-blob-values-test.rkt](reference-blob-values-test.rkt) | Checks copied atlas transforms, anchor placement, rotation direction, and zero-scale geometry. |
| [reference-blobs-test.rkt](reference-blobs-test.rkt) | Checks text-blob builder consumption, copied metadata, retained fonts, intercepts, and text-on-path placement. |
| [reference-color-management-pure-test.rkt](reference-color-management-pure-test.rkt) | Checks floating color ranges, transfer descriptors, byte conversion, and ICC headers without native parsing. |
| [reference-color-management-test.rkt](reference-color-management-test.rkt) | Checks retained color spaces, gamut transforms, ICC round trips, floating paints, and sample conversion. |
| [reference-color-test.rkt](reference-color-test.rkt) | Checks byte-color construction, channel access, named colors, and packed ARGB conversion. |
| [reference-core-test.rkt](reference-core-test.rkt) | Checks canvas restoration, clipping, retained paint/path/image values, path measurement, and encoder options. |
| [reference-dc-integration-pure-test.rkt](reference-dc-integration-pure-test.rkt) | Checks detached DC capability reports, callback lifetimes, and validation before native drawing. |
| [reference-effects-pure-test.rkt](reference-effects-pure-test.rkt) | Checks effect argument ranges, runtime-source validation, and graph options before native allocation. |
| [reference-effects-test.rkt](reference-effects-test.rkt) | Checks retained effect inputs, filter composition, runtime uniform packing, and programmable blending. |
| [reference-geometry-pure-test.rkt](reference-geometry-pure-test.rkt) | Checks matrix values, geometry copying, grid planning, and scoped macro grammar without native drawing. |
| [reference-geometry-test.rkt](reference-geometry-test.rkt) | Checks native path/region operations, copied geometry, canvas restoration, drawables, and atlas cropping. |
| [reference-gpu-context-pure-test.rkt](reference-gpu-context-pure-test.rkt) | Checks activation, thread affinity, child leases, shutdown, and release quarantine using fake drivers. |
| [reference-gpu-context-test.rkt](reference-gpu-context-test.rkt) | Checks real backend contexts, options, nesting, canvas expiry, child cleanup, and abandonment. |
| [reference-gpu-interop-pure-test.rkt](reference-gpu-interop-pure-test.rkt) | Checks token consumption and Direct3D, Metal, OpenGL, and EGL handoff policies without native contexts. |
| [reference-gpu-presentation-pure-test.rkt](reference-gpu-presentation-pure-test.rkt) | Checks frame acquisition, generation tracking, redraw coalescing, and expiration using a fake adapter. |
| [reference-gpu-surface-pure-test.rkt](reference-gpu-surface-pure-test.rkt) | Checks format budgets and one-shot cleanup with fake resources, and compiles displayed GPU helpers. |
| [reference-gpu-surface-test.rkt](reference-gpu-surface-test.rkt) | Checks native image ownership, exact pixels, transfers, targeted flushes, caches, and displayed GPU helpers. |
| [reference-io-pure-test.rkt](reference-io-pure-test.rkt) | Checks storage sizing, bounded buffering, codec negotiation, scanline placement, and incremental states. |
| [reference-io-test.rkt](reference-io-test.rkt) | Checks native stream ownership, codec snapshots, bottom-up rows, incremental completion, and live ports. |
| [reference-matrix-test.rkt](reference-matrix-test.rkt) | Checks affine coefficient order, rounding, composition, point/vector differences, bounds, and inversion. |
| [reference-native-test.rkt](reference-native-test.rkt) | Extracts displayed Reference examples and runs them in fresh namespaces or isolated processes. |
| [reference-output-pure-test.rkt](reference-output-pure-test.rkt) | Checks page units, margins, output policies, explicit picture trust, and protected page syntax. |
| [reference-output-test.rkt](reference-output-test.rkt) | Checks picture retention, document lifetimes, annotation resolution, pages, and transactional publication. |
| [reference-raster-pure-test.rkt](reference-raster-pure-test.rkt) | Checks format inventories, surface properties, output policies, and layer syntax without native loading. |
| [reference-raster-test.rkt](reference-raster-test.rkt) | Checks raster stride and borrowing, pixel conversion, image independence, output groups, and caches. |
| [reference-text-pure-test.rkt](reference-text-pure-test.rkt) | Checks font-style normalization, OpenType tag conversion, and deferred break-position validation. |
| [reference-text-test.rkt](reference-text-test.rkt) | Checks font/shaper retention, glyph metrics, UTF-8 offsets, blob copying, wrapping, and mixed-layout lifetime. |

### Build, host, reflection, and shared support

| Module | Responsibility |
| --- | --- |
| [check-d3d12-call.rkt](check-d3d12-call.rkt) | Compares a native fixture call with Racket's Direct3D structure-passing layout. |
| [check-dxgi-layouts.rkt](check-dxgi-layouts.rkt) | Prints the Racket FFI sizes used by the DXGI layout checks. The Windows validation tools compare these values with structures compiled against the SDK. |
| [check-package-version.rkt](check-package-version.rkt) | Reads package metadata and prints the version expected by validation and release tooling. |
| [ci-identity.rkt](ci-identity.rkt) | Prints the Racket version, VM, operating system, and architecture as structured evidence. The CI runner uses this receipt to identify the runtime that performed its checks. |
| [ci-import-smoke.rkt](ci-import-smoke.rkt) | Loads the package's supported module entry points in a controlled smoke-test process. CI uses this probe to catch missing installed files and accidental eager native or GUI imports. |
| [ci-package-smoke.rkt](ci-package-smoke.rkt) | Checks the installed package's rendering path and native-library identity. |
| [copy-tutorial-examples.rkt](copy-tutorial-examples.rkt) | Copies cataloged complete tutorial programs into a selected destination or lists the planned files. |
| [gpu-dc-consumer-common.rkt](gpu-dc-consumer-common.rkt) | Records consumer I/O, writes captures, and assembles common JSON report fields. Native and GUI consumer probes share these checks to enforce explicit readback and presentation. |
| [gpu-dc-consumer-gui.rkt](gpu-dc-consumer-gui.rkt) | Runs pict, plot, and recorded workloads through real window paint callbacks. |
| [gpu-dc-consumer-native.rkt](gpu-dc-consumer-native.rkt) | Runs consumer workloads on GPU surfaces and presenter frames, saving comparison captures. |
| [gpu-gui-host.rkt](gpu-gui-host.rkt) | Creates a GUI OpenGL host and scopes callbacks to its current context. GPU tests use this host adapter when they require a real window-system GL context. |
| [gpu-performance-options.rkt](gpu-performance-options.rkt) | Validates benchmark options, clears targeted prior evidence, and fingerprints relevant Racket sources. Performance diagnostics share this configuration layer to make captures comparable and attributable. |
| [gpu-performance-work.rkt](gpu-performance-work.rkt) | Defines rendering scenes and deferred-release stress workloads with completion-aware timing. The performance diagnostics use these shared workloads for CPU/GPU comparison and lifetime evidence. |
| [gpu-presentation-host.rkt](gpu-presentation-host.rkt) | Loads presentation widgets and dispatches work on their GUI handler thread. Presentation diagnostics use this boundary to preserve eventspace ownership while testing windows. |
| [gpu-report.rkt](gpu-report.rkt) | Writes GPU JSON receipts and checks that context teardown leaves no owned resources behind. GPU diagnostics share this layer so evidence is published only with verified cleanup. |
| [gpu-test-host.rkt](gpu-test-host.rkt) | Selects GUI OpenGL, EGL, Metal, or Direct3D activation for a diagnostic callback. |
| [live-stream-identity.rkt](live-stream-identity.rkt) | Prints the runtime and native-library identity needed for live-stream validation receipts. The callback validation workflow uses this probe to attribute evidence to the loaded binaries. |
| [native-abi-reject.rkt](native-abi-reject.rkt) | Exercises rejection of an unsupported or mismatched native ABI in an isolated process. |
| [public-api-probe.rkt](public-api-probe.rkt) | Reflects requested public modules in an isolated process and emits their export shapes. The API inventory workflow uses this process boundary to observe loading and GUI side effects. |
| [public-api-reflect.rkt](public-api-reflect.rkt) | Describes exported values, procedure arities, keywords, and GUI-loading state. |
| [reference-render.rkt](reference-render.rkt) | Builds the Reference and related manuals with stable cross-manual tag prefixes. |
| [reference-runtime.rkt](reference-runtime.rkt) | Checks live public binding shapes and cross-reference targets against the documentation inventory. |
| [render-documentation-landing.rkt](render-documentation-landing.rkt) | Expands the landing-page template with shared collection links and categorized tutorial navigation. |
| [render-reference-images.rkt](render-reference-images.rkt) | Renders API examples and conceptual diagrams into the Reference image directory. |
| [replay-picture-probe.rkt](replay-picture-probe.rkt) | Loads a serialized picture and exercises replay in an isolated process. Picture validation uses this probe to detect unsafe serialized-input failures without losing the driver. |
| [unicode-conformance.rkt](unicode-conformance.rkt) | Runs line-break and bidirectional conformance checks against supplied Unicode test data. |
