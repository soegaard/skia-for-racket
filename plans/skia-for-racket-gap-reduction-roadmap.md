# Skia-for-Racket: gap-reduction roadmap

**Status:** proposal; no implementation changes are part of this roadmap.
**Baseline:** stage 0.64, commit `9d832d3ec9a8fe6b93298d6ac03783ee57ab7f36`.
**Primary comparison target:** SkiaSharp 3.119.1 and its pinned Skia C ABI at `40f75dc0051d141913c07c20d4c19590c7da0cb7`.
**Date:** October 4, 2026.

## Objective

Reduce meaningful capability gaps before freezing the public API. Prefer a safe, idiomatic Racket equivalent to duplicating every C# class, overload, mutable wrapper, or raw-pointer constructor.

Replace the previous single 0.65 stabilization milestone with stages 0.65–0.78 below. Keep major backend/native-version expansions as explicit subsequent workstreams, rather than silently removing them from the roadmap.

## Corrections to the preliminary inventory

- Structured raw and normal path iteration already exists through `path-segments`, `in-path-segments`, and `path-contours`. Extend it only where capabilities are genuinely missing. [S2]
- Variable-font/palette cloning is not exposed by the pinned SkiaSharp 3.119.1 `SKTypeface` class or pinned `sk_typeface.h`. Treat it as newer-ABI/custom-shim work, not an ordinary missing m119 binding. [S3, S4]
- Track managed API, C-shim API, actual native exports, public Racket equivalents, and executed tests separately. A header declaration or a missing symbol binding is not a reliable feature-parity score.
- Bytes and ports can replace .NET data/stream objects idiomatically, but whole-input buffering does not count as streaming support.

## Overview

| Stage | Main outcome |
|---|---|
| 0.65 | Authoritative gap inventory and API/ownership decisions |
| 0.66 | Missing effects and shader composition |
| 0.67 | Path, rounded-rectangle, region, and paint geometry completion |
| 0.68 | Typeface resources, style sets, font metadata, and glyph queries |
| 0.69 | Multi-run text blobs, transformed glyphs, and text-on-path |
| 0.70 | General image information and integer-format raster storage |
| 0.71 | Floating-point pixels, Color4f, and color-aware gradients |
| 0.72 | Direct image filtering, conversion, scaling, and inspection |
| 0.73 | Generalized GPU surface formats and surface properties |
| 0.74 | Advanced layers, drawables, and specialized canvases |
| 0.75 | Native stream and Racket port integration |
| 0.76 | Scaled/subset, scanline, and incremental decoding |
| 0.77 | Global caches, memory diagnostics, and GPU context options |
| 0.78 | Remaining-gap review, API stabilization, and release candidate |

Stages are accepted individually. Do not combine several unvalidated stages into one large patch.

## 0.65 — Authoritative inventory and contract decisions

**Goal:** make the remaining work measurable without counting equivalent implementations as missing.

Generate a checked-in capability inventory from the complete Racket checkout, all CPU and GPU binding registries, pinned SkiaSharp managed sources, pinned C headers, and actual shipped-library symbol inventories. Record upstream feature/source, native entry points, binding location, public equivalent, restrictions, tests, backend coverage, document behavior, and planned stage.

Use separate statuses: supported; supported with limits; equivalent Racket implementation; bound but not public; missing with available ABI; unavailable in the pinned ABI/build; intentionally excluded. Track execution evidence separately from declarations.

Make the design decisions needed later: a general image-info value, existing RGBA API compatibility, ownership of referenced color spaces, float-color representation, mutable pixel leases, and explicit CPU/GPU transfer names. Preserve the declared Racket/draw minimum unless a separately accepted migration changes it.

**Deliverables:** machine-readable inventory, generated human-readable report, drift checker, reviewed contract decisions, and a source manifest.

**Acceptance:** every audited feature has a disposition; known existing capabilities such as path iteration and GPU transfers are not falsely missing; no coverage percentage conflates overloads, C bindings, and public functionality.

## 0.66 — Effects and shader composition

**Goal:** add useful graphical capabilities with relatively limited architectural change.

Add 1D path stamping, 2D line/path effects, gamma/clip/table mask filters, Perlin fractal noise/turbulence, shader-with-color-filter, empty shaders, and supported shader/image-filter composition using custom blenders. Treat shader-mask filtering as a separately identified C-shim extension, not an assumed managed SkiaSharp factory. Keep floating-color variants for 0.71. [S5, S6]

Integrate factories with provenance, resource retention, byte limits, and document representation policies. Do not replace a native effect with an approximate hand-written substitute merely to mark it covered.

**Acceptance:** invalid arguments fail before native allocation; closing input wrappers does not invalidate retained effects; raster and supported GPU tests exercise actual pixels; PDF/SVG either preserves an effect correctly or reports/rejects an explicit bounded raster fallback. Fixed Perlin seeds do not imply universal cross-backend byte equality.

## 0.67 — Geometry completion

**Goal:** fill the remaining path-authoring and geometry-query holes.

Add endpoint/radius/tangent arc-to variants, relative arc-to, add-arc, line/rectangle/oval/rounded-rectangle recognition, missing verb/segment queries, conic-to-quadratic conversion, and a bounded path-operation builder. Review rounded-rectangle transforms/inset/outset, region rectangle/span/clip iteration, and public paint-to-fill-path access for genuine missing functionality.

Reuse existing immutable path snapshots and path-measure frames. Implement equivalent value-level convenience operations in Racket when that avoids unnecessary mutable native objects. [S2]

**Acceptance:** cover degenerate arcs, zero radii, sweep conventions, closed/open contours, singular transforms, boolean-operation failures, and immutable snapshots after source closure. Verify emitted PDF/SVG geometry, not only bitmap resemblance.

## 0.68 — Typeface resources and glyph queries

**Goal:** make the font-resource API match the sophistication of the existing shaping layer.

Add typeface construction from copied font bytes with collection index; style-set enumeration and matching; PostScript name, fixed-pitch flag, glyph count, units-per-em where not already exposed; bounded table tags/data; and public raw font-data extraction where the backend permits it. True live-stream input waits for 0.75. [S3, S4]

Add missing glyph widths, bounds, positions, kerning-pair inspection, and font controls such as embedded bitmaps, auto-hinting, and baseline snapping. Reuse existing equivalents where present. Low-level pair kerning must not be reapplied to HarfBuzz-shaped positions.

Raw OpenType table access is useful groundwork for mathematical typography, but is not itself a MATH-table layout implementation.

**Acceptance:** test known font fixtures, collection indices, missing tables, invalid ranges, unavailable metadata, and independent typeface lifetime after a style set or manager closes. Measurement and rendering must use the same font options.

## 0.69 — Text blobs and transformed text

**Goal:** support richer reusable text without bypassing shaping correctness.

Add a controlled multi-run builder, horizontal/XY/rotation-scale runs, optional original UTF-8 and cluster information, and intercept queries. Build shaped text-on-path from retained glyph positions and existing path-measure frames, not from an assumption that one character equals one glyph. The pinned C ABI includes these run-buffer families and intercept operations. [S7]

Retain each run's font configuration for both native drawing and later outline conversion. Keep `make-positioned-text-blob` as a convenience API.

**Acceptance:** exercise multiple fonts, ligatures, combining marks, RTL text, empty runs, independently closed builders/fonts, and glyph transforms. Check PDF text extraction for cases claiming preserved text, and verify outlines preserve placement. Bitmap/color-only glyph limitations must remain explicit.

## 0.70 — General image information and integer raster storage

**Goal:** remove the RGBA-only architectural restriction additively.

Introduce a checked image-info value carrying dimensions, color type, alpha type, and color-space semantics. Generalize raster-buffer/pixmap storage first for RGBA8888, BGRA8888, alpha-only, gray, and selected packed integer formats supported by the relevant operations.

Maintain an operation-by-format table: allocating storage, reading, converting, drawing into a surface, and uploading to a GPU are different capabilities. Do not assume a format is renderable because it is representable.

Preserve existing defaults, RGBA byte helpers, strides, ownership, and exclusive lease behavior. Existing RGBA-oriented accessors stay explicit conversions; add format-neutral storage/sample access rather than changing their return meaning.

**Acceptance:** validate row-byte arithmetic, overflow, initialized storage, padding canaries, subset bounds, invalid alpha/color combinations, and format conversion. Existing RGBA tests pass unchanged. Define whether color-space data is copied or retained so closing the original cannot corrupt a live buffer.

## 0.71 — Floating-point pixels and colors

**Goal:** provide real higher-precision rendering, not float arguments that immediately become 8-bit values.

Extend the format table with RGBA F16/F32 where supported. Add float color values, Color4f paint/clear operations, float gradient factories with explicit source color spaces, and float pixmap inspection/conversion. The pinned shader ABI already has Color4f gradient entry points. [S5]

Make metadata relabeling distinct from conversion of sample values. Define finite-value and alpha policies; preserve extended-range RGB where the selected native operation supports it. Do not funnel float data through existing 8-bit helpers implicitly.

**Acceptance:** tests retain distinctions below 1/255, verify premultiplication and color-space conversion, and document quantization on export. Float-capable CPU rendering is not a claim of HDR window presentation. PQ/HLG work must not be forced into an incompatible SDR transfer-function representation.

## 0.72 — Direct image operations

**Goal:** make the existing filter graph and broader pixel storage directly useful to image clients.

Add image-filter application returning its image, valid subset, and placement offset; explicit scaling and conversion into compatible pixmaps; missing unique-id/lazy/alpha-only/residency queries; raw image shaders; and equivalent picture-to-image conveniences where not already available. The pinned C ABI has both raster and context-aware filter application plus pixel scaling operations. [S8]

Reuse existing upload, download, GPU subset, and raster-image operations. Avoid introducing synonymous transfer APIs merely to mirror C# naming.

**Acceptance:** blur/shadow halos and offsets remain correct; subsets and clips are tested; detached results retain dependencies safely; wrong-context operations reject; CPU transfers are explicit and recorded. Do not promise that wrapper buffer bounds limit every internal native filter allocation.

## 0.73 — GPU formats and surface properties

**Goal:** carry the new pixel model into supported OpenGL, Metal, and Direct3D surfaces.

Add surface-property values, supported pixel-geometry/font flags, requested color/alpha types, and per-backend format/sample-count validation. Keep the current format and grayscale text defaults unless explicitly changed by the caller. Backend-resource ingress remains scoped and checked.

Update presenter staging compatibility whenever target format, color-space interpretation, sample count, or properties become variable. A width/height-only reuse policy is insufficient for newly variable configurations.

**Acceptance:** test supported formats on each backend, explicit rejection of unsupported combinations, cross-context exclusion, uploads/readbacks, resize, and staging retirement. Do not silently turn an unsupported GPU format into CPU rendering. Physical monitor color/HDR claims remain outside this stage.

## 0.74 — Advanced layers and specialized canvases

**Goal:** support richer compositing and retained/diagnostic drawing objects.

Add a checked SaveLayerRec equivalent for fields available in the pinned ABI, including supported backdrop/initialization behavior. Layer bounds are allocation hints, not a clipping substitute; install a real clip when bounded output is required. [S9]

Then add retained drawables and NoDraw/NWay/Overdraw canvas equivalents. Prefer immutable snapshots where appropriate, but do not mislabel a static picture as a mutable drawable. Restrict cross-context target combinations; define exception and ownership behavior before exposing user callback-backed drawables.

**Acceptance:** nested restore and exceptional exits preserve state; retained children live long enough; closed targets reject; fan-out does not rerun application authoring unexpectedly. Keep diagnostic counters distinct from evidence of visible rendering. Document export follows the existing audit policy, including rejection where a backdrop cannot be represented faithfully.

## 0.75a — Native streams and explicitly buffered ports

**Package version:** `0.75` (the stage suffix is not a Racket package version).

Provide owned native memory/file input streams and dynamic-memory output with
length, position, bounded reads/peek/skip/seek, duplicate/fork, copied SkData and
output detachment. Integrate streams with the existing thread-affine `with-skia`
lifecycle. Codec and typeface constructors consume a private native duplicate,
never the caller's stream; trusted picture input borrows a private duplicate and
preserves opaque imported-picture audit provenance.

Provide explicitly named `/buffered` Racket-port adapters. They finish bounded
port I/O outside native calls, handle short reads/writes, EOF and cancellation,
and state borrowing/closing and partial-output rules. Native file input is live
file I/O, not an immutable file snapshot; callers keep the backing file stable.
A read-all-bytes adapter is not counted as a live Racket-port bridge.

**Acceptance:** native stream lifecycle and cursor tests, constructor failure and
retained-input lifetime, file/memory input, independent codec pixels and font
metadata, pure seekable/nonseekable buffered port tests and cancellation/error
propagation. Full regressions remain the standalone default; feature-only CI
always runs focused pure/native stream tests and inspected native evidence.

## 0.75b — Live port bridge and streamed publication

Complete native output consumers and file output: image encoding, picture output,
and PDF/SVG document publication through supported native stream paths. Implement
the managed live Racket-port bridge without arbitrary exceptions unwinding across
native frames. Define callback thread/reentry rules, retained bridge lifetime,
short I/O, cancellation, allocation limits, and deferred error transport before
exposing live callback-backed resources.

**Acceptance:** use real retained consumers, nonseekable/chunked ports and partial
writes; test callbacks during normal document drawing, cleanup, cancellation and
failure. Preserve GPU affinity and output auditing. Streamed publication may leave
partial output; buffered/temporary-file atomic publication remains a separate
policy. Do not count 0.75a's complete-input buffering as live streaming. Together
0.75a and 0.75b replace the original 0.75 streams/ports milestone.

## 0.76 — Advanced codecs

**Goal:** reduce the remaining codec capability gap using the new storage and input foundations.

Add scaled-dimension queries, supported subset negotiation, scanline sessions with ordering/skipping, and incremental decode sessions with progress and cancellation. These operations are explicitly present in the pinned codec header. [S10]

Separate session state from immutable decoded images. Keep destination storage alive and exclusively leased while native decoding retains its address. Preserve current one-shot and animation APIs. A sequential animation cache is an optional follow-on, not required to expose scanline/incremental decoding.

**Acceptance:** use real supported-format fixtures; test chunked/truncated/corrupt input, unsupported decoder modes, top/bottom scanline order, partial completion, cancellation, and origin normalization. Do not manufacture incremental success by secretly falling back to a complete decode.

## 0.77 — Caches, diagnostics, and context options

**Goal:** expose useful runtime controls without confusing them with memory guarantees.

Add missing process-global Skia font/resource cache queries and controls; bounded detached memory-statistics snapshots; and supported immutable GPU context options passed at construction. Keep process-global controls separate from existing context-local GPU cache APIs.

No cache policy changes occur simply by requiring a module. Tests must restore global settings where possible and avoid contaminating concurrent rendering tests. Validate callback-based tracing before offering user callbacks directly.

**Acceptance:** test getter/setter roundtrips, process versus context scope, closed-context rejection, supported option fields, and rendering under changed limits. Distinguish requested cache limits, reported Skia cache usage, total native memory, driver allocations, and process memory.

## 0.78 — Reconcile remaining gaps and stabilize

**Goal:** reach a defensible API-freeze checkpoint after the capability work.

Regenerate the complete inventory and resolve residual getters, conversions, and convenience operations. Require each remaining gap to be implemented, documented as a supported equivalent, assigned an explicit restriction, or linked to the extended roadmap.

Consolidate canonical API/lifetime/output documentation; snapshot exports; unify errors; verify isolated installation and minimum-version support; and run end-to-end raster, GPU, PDF/SVG, and real-consumer acceptance. All added required lanes must feed an authoritative release gate rather than leaving critical tests outside the release decision.

**Acceptance:** no unclassified item in the frozen upstream scope; all in-scope missing supported-ABI features closed or explicitly justified; executable examples use public APIs only; no silent regression of ownership, transfers, or document policies. This is the proposed 1.0 readiness checkpoint—not a claim of complete Skia/Cairo equivalence.

## Dependency order

Default delivery order is numeric. Important dependencies are:

- 0.68 font resources precedes 0.69 richer text runs.
- 0.70 general storage precedes 0.71 float colors and 0.72 image operations.
- 0.70/0.71 precede 0.73 generalized GPU surfaces.
- 0.70 plus 0.75 precede 0.76 incremental/scanline decoding.
- Every feature stage supplies its own document and lifetime evidence; 0.78 consolidates rather than first testing the pieces together.

Independent workstreams can be developed separately, but baseline acceptance remains incremental.

## Extended gap-reduction workstreams

These remain explicit roadmap items. They need not block a release covering the m119 core feature set.

### G1 — Vulkan offscreen

Build on the pinned Ganesh Vulkan ABI where available: extension/device/queue ownership, context creation, compatible images/surfaces, submission/completion, explicit readback, cache behavior, and domain teardown. Verify binary build support separately from device availability. A new ABI is not inherently a prerequisite for Ganesh Vulkan.

**Gate:** known-pixel offscreen rendering, failure/teardown tests, and software Vulkan CI where feasible. Keep platform support claims limited to exercised paths.

### G2 — Vulkan presentation and interop

Add swap-chain presentation, resize/out-of-date handling, queue-family/layout transitions, synchronization, external-image handoff, and bounded document execution. Require the shared consumer and no-hidden-readback suites before advertising parity with the other presenters.

### U1 — Native-version migration

Select an exact newer SkiaSharp/native pin using an isolated candidate matrix. Diff symbols, ABI structures, enum values, ownership contracts, required platforms, and changed raster/document semantics. Migrate separately from adding a new backend; do not combine both sources of failure in one stage.

### U2 — Variable/color-font configuration

After U1 supplies the necessary API—or a separately maintained C shim is approved—add variation-axis discovery and selection, palette selection/overrides, clone ownership, and consistent shaping/outline export. Use fonts with known axis/palette behavior. This is not available as a simple missing binding in the 3.119.1 comparison baseline. [S3, S4]

### U3 — Graphite

Treat Graphite as a new execution model. Separate gates for native ABI/build support, recorder/context ownership, recording insertion/submission, readback completion, retained image lifetime, and finally presentation/shared API integration. Reuse drawing/validation components only where their contracts actually match.

### H1 — HDR/wide-gamut presentation

Build on float storage and generalized surfaces, not on an assumption that Graphite is required. Specify transfer functions, tone mapping, display color-space negotiation, presentation formats, and SDR fallback policy. Separate numeric/metadata tests from physical HDR-display verification.

### X1 — Optional XPS exporter

Audit the pinned factory and actual Windows native build first. Add an exporter with page lifecycle, stream ownership, and independent document inspection only if there is a concrete use for XPS. Otherwise record it as an intentional format omission rather than pretending PDF is an XPS equivalent.

## Common definition of done

Every implementation stage includes real binding/layout checks, a reviewed public ownership contract, pure argument/state tests, relevant native regression tests, documentation/examples, and updated source checksums.

Drawing/effect stages also require actual raster pixels and the supported GPU paths; document-facing stages require native PDF/SVG inspection and independent rendering where applicable. Unsupported backend/format combinations are reported as such, never as successful coverage. GPU normal-frame I/O ledgers must not acquire hidden CPU readbacks.

Do not hard-code speculative future test totals. Test counts and evidence come from the implemented suites. A new stage becomes the baseline only after local checks and the selected cross-platform CI gates pass.

## Measures of progress

Publish separate counts for available-ABI functionality implemented, idiomatic equivalents, native bindings lacking public APIs, supported public features lacking execution evidence, intentionally excluded features, and features requiring a newer ABI or backend. Use stable capability families as the primary denominator; count symbols and overloads only as secondary diagnostics.

Success means that users can perform the important missing tasks, not that every native pointer constructor or C# overload has a Racket spelling.

## Recommended next implementation

Start with **0.65: a reconciled, machine-checked gap inventory and the additive pixel/ownership design decisions**. Then implement **0.66 effects**. Keep the format, stream, GPU, and document contracts explicit throughout so feature additions do not require an incompatible redesign immediately after 1.0.

## Sources

[S1] Current Racket repository baseline: https://github.com/soegaard/skia-for-racket/tree/9d832d3ec9a8fe6b93298d6ac03783ee57ab7f36

[S2] Existing path snapshots and iteration: https://github.com/soegaard/skia-for-racket/blob/9d832d3ec9a8fe6b93298d6ac03783ee57ab7f36/docs/PATH-MATRIX.md

[S3] Pinned managed typeface API: https://github.com/mono/SkiaSharp/blob/v3.119.1/binding/SkiaSharp/SKTypeface.cs

[S4] Pinned C typeface API: https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/c/sk_typeface.h

[S5] Pinned shader API: https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/c/sk_shader.h

[S6] Pinned managed mask-filter API: https://github.com/mono/SkiaSharp/blob/v3.119.1/binding/SkiaSharp/SKMaskFilter.cs

[S7] Pinned text-blob API: https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/c/sk_textblob.h

[S8] Pinned image API: https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/c/sk_image.h

[S9] SaveLayer API and bounds semantics: https://learn.microsoft.com/en-us/dotnet/api/skiasharp.skcanvas.savelayer?view=skiasharp-3.119 and https://api.skia.org/classSkCanvas.html

[S10] Pinned codec API: https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/c/sk_codec.h
