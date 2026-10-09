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

## 0.75b — Compiler-free live port operations and publication

**Implementation:** operation-scoped pure Racket FFI using call-in-os-thread,
async-apply and OS-asynchronous channels. The protected Racket service thread
performs port I/O outside atomic mode. Independent immutable native references
and exclusive mutable-output leases preserve ownership. No additional compiled
helper is required. Whole-input buffering is not used for live image/SKP input.

Image encoding, native picture output and audited PDF/SVG publication stream
native output as it is generated. Document authoring is recorded once before
preflight/publication. Native file output extends the 0.75a native stream API.

**Limits:** 64-bit Racket CS with OS threads; one live operation at a time per
process; one managed-callback provider/place. Cancellation is cooperative, and
partial publication is possible. Retained live-port codecs/typefaces remain out
of scope; use native streams or explicitly buffered adapters. Recording-canvas
annotation restrictions and existing document audit/GPU rules remain in force.

**Acceptance:** the unchanged-in-scope 25-case real native probe plus integrated
ownership/port/codec/picture/document tests. Retain required independent Linux
PDF/SVG rendering and full/none regression reporting without a new workflow.
The user's macOS probe pass is prior evidence, not a substitute for these new
integrated Linux/Windows/macOS runs.

## 0.76a — Scaled-dimension and subset negotiation

**Package version:** `0.76`. Query only: `codec-scaled-dimensions` returns two
native suggested encoded-pixel dimensions; `codec-supported-subset` returns an
immutable actual suggested rectangle or `#f`. Validate positive nonzero C-float
scales, integer bounds, closed/thread-affine resources, and native results.
No scaled/subset decoding, resampling, cropping, session or destination lease is
introduced here. Full-image/animation decoding remains unchanged.

**Acceptance:** PNG/JPEG/WebP native suggestions, WebP even-origin adjustment,
explicit unsupported results, EXIF-independent coordinates, detached metadata,
stream lifetime, unchanged full decoding, and independent evidence inspection.
No GPU or document-renderer requirement. Full/none regression scope is retained.

## 0.76b — Native scanline sessions

**Package version:** `0.76`. Owned private codecs accept copied bytes or an
independently duplicated native input stream; the explicitly buffered port
adapter does not install retained live-port callbacks. Native scanline start,
read, skip, order, next-row and output-row queries are exposed without using a
complete-decode/crop/resampling fallback. Optional native scale negotiation and
checked destination color/alpha/color-space descriptions are supported.

Batches are detached immutable bytes in increasing logical-Y order, with explicit
first-row and decoded/requested counts. On a short read, native default-fill rows
are discarded (including the leading fill of bottom-up batches). The session
becomes terminal incomplete; skip failure becomes terminal failed. EOF does not
call the out-of-range native nextScanline query. No native destination pointer is
retained between calls. Session close uses the ordinary resource lifecycle.

**Limits:** first frame, full-width encoded-pixel coordinates, native supported
scanline modes only; EXIF orientation is metadata, not a row reorder. Horizontal
native subset decoding is not exposed in this stage. Vertical selection uses
explicit skipping. Scaled bottom-up rows are rejected if their native coordinate
height differs. Incremental sessions and live-port-backed retained decoders remain
0.76c or future work, not a claim of this API.

**Acceptance:** real top/down and bottom/up BMPs, native JPEG scaling, padded
batches, truncation/empty partial batches, skip failure, independent row/byte
inspection, stream/source lifetime, thread rejection and explicit unsupported
PNG mode. The existing codec workflow runs focused scanline checks after its
query gate; global regressions are never repeated in the same job.

## 0.76c — Retained incremental decoding

**Package version:** `0.76`. Feed copied byte chunks into an owned session,
advance the native incremental decoder, and obtain detached snapshots with
explicit initialized-row and completion status. The decoder and its exclusive,
zero-initialized pixel allocation survive between incomplete native calls.
Cancellation/close destroy the codec before releasing retained pixels.

PNG prefixes are exposed at complete chunk boundaries, as required by the pinned
libpng-backed Skia decoder's resumption loop. Arbitrary feed sizes are accepted,
but a PNG with one large IDAT cannot show intermediate pixels before that chunk
arrives. Header construction may retry; after successful incremental start the
same codec and destination are retained. No one-shot decode, resampling or
reconstruction fallback is used. Sealed inputs in other formats still require
native incremental support; unsupported native modes are explicit failures.

**Limits:** first frame, full-size encoded coordinates, RGBA8888/BGRA8888,
explicit premul/unpremul and detached color-space descriptors. Input and pixel
storage are bounded separately, not constant-memory. Native initialized-row
counts do not certify completed rows in interlaced images. Pixel completion is
not whole-container/trailing-data validation. Cancellation is observed between
synchronous memory-only native calls, not inside native computation. No retained
user port callback, new callback table, compiler or native helper is added.

**Acceptance:** staged normal/interlaced PNGs with partial snapshots before
completion, stable decoder/allocation counts, arbitrary fragment boundaries,
padding, final truncation, corrupt data, unsupported modes, GC, thread affinity,
independent snapshots, cancellation and coexistence with the live-port provider.
The existing codec workflow retains full/none scope and adds a focused gate.

## 0.77a — Global caches and bounded memory statistics

**Package version:** `0.77`. Expose native font/resource cache byte limits,
font entry limits, usage and purge operations; setters return the prior setting.
Initialization is explicit and import never changes native cache policy. These
are global Skia caches, not GPU context caches or process/driver memory budgets.
A zero single-allocation limit means no separate per-entry ceiling.

Return detached, bounded numeric/string statistics from the native global dump.
The synchronous private callbacks only copy memory: no user callbacks, ports,
blocking I/O, nested Skia calls, or exception unwinding across native frames.
Whole records omitted by count/string/byte limits are disclosed as truncated.
The trace adapter is independently inventoried under the pinned Xamarin header;
one provider/module/place may claim its global table. It does not replace the
existing managed stream callback tables. No new compiler/native helper is needed.

**Acceptance:** prior-value setter/getter round trips, restoration of all changed
limits even on failure, unchanged known pixels under reduced limits and purges,
named native glyph-cache measurements matched against scalar getters, bounded
snapshot output, GC, thread use, deferred callback errors, and coexistence with
live ports and incremental decoders. Focused Acceptance and global CI remain
separate. Native dump output is not a total-allocation or heap-ownership graph.

## 0.77b — GPU context options and targeted resource operations

**Package version:** `0.77`. Six immutable m119 options feed GL, Metal and
Direct3D context construction; EGL forwards the same options. Omitted options
keep existing native-default factories. Metadata records requests, not effective
settings: the pinned ABI supplies no option readback.

Targeted surface/image flush requires a matching active context and live GPU
resource; surfaces also require a balanced save/layer stack. It requests neither
submission nor CPU completion and performs no hidden upload/readback. Flush may
include dependent work; existing submit/wait APIs retain their separate roles.

Healthy-host release-and-abandon runs outside user GPU scopes on the owner,
activates the provider, drains pending releases, then invalidates native children
for use. Their wrappers still require retirement before final context close.
Indeterminate native teardown is quarantined and never retried. Existing
lost-context abandonment remains nonactivating. 0.77a user changes are preserved.

**Acceptance:** option values and exact ABI, old versus with-options factories,
selected-backend pixels, targeted I/O ledgers, affinity/stack rejection, and
healthy versus lost-host lifecycle tests. Linux 8.18/9.3 and Windows WARP run
under Acceptance; local Metal is explicitly selected. No new compiler or native
helper. GPU diagnostics and interface helpers remain 0.77c.

## 0.77c — GPU memory diagnostics and retained GL interfaces

**Package version:** `0.77`. `gpu-memory-statistics` reuses 0.77a's bounded,
synchronous native-only collector and returns detached reports with a distinct
GPU-context scope. No cache limit changes, flush, submit, wait, upload or readback
are introduced by diagnostics. Owner/current/ready/native-abandoned checks run
before capture; callback errors are raised only after native object cleanup.

`#:gl-interface` selects preserved defaults, auto-detected assembly, desktop GL,
GLES or WebGL on an explicit OpenGL provider. Owned EGL remains desktop and
accepts default/auto/desktop only. Each GL context retains its actual selected
interface for validated `gpu-gl-interface-info` and `gpu-gl-has-extension?`
queries, releasing it at context teardown, including constructor failure.
Explicit factory failure never falls back to another standard. Interface mode is
not a request to create a host context or a guarantee of extension usability.

**Limits:** memory dumps are Skia's reported context resources, not driver/process
memory and not an additive global total. Native adapter backing/ownership hooks
not exported by m119 are not invented. Existing single-provider/place and
live-operation restrictions apply to the shared collector. Matching GLES/WebGL
hosts must be supplied externally; required CI exercises desktop default/auto/GL
routes, resolver/mismatch failures and Direct3D dumps. Metal uses a separate
selected-backend local gate. Browser or GLES presentation is not certified. No compiler/native helper is introduced.

**Acceptance:** focused native-free ownership/argument tests, real callback/ABI
tests, selected GPU allocation/dump/pixel evidence, bounded/truncated reports,
no hidden transfers, and constructor/abandon/close cleanup. Existing GPU control
jobs run diagnostics feature-only; central CI owns full regressions.

## 0.78a — Source inventory and release-scope reconciliation

**Library package version:** `0.77` remains unchanged: this audit introduces no
public rendering API. The inventory/review milestone is `0.78a`.

Freeze a decision for every capability family against the actual GitHub
baseline and the pinned SkiaSharp 3.119.1 / m119 scope. Reconcile the existing
Color4f/packed-color Racket equivalent without inventing native bindings.
Keep null-surface and XYZ helper decisions open for 0.78b. The selected
baseline contains 0.77c; preserve its GPU diagnostics and retained GL interface
implementation, bindings, tests, and documented backend restrictions. These two
families are supported-with-limits, not pending and not unrestricted support.

**Acceptance:** complete existing declaration/anchor checks; exact review/source
fingerprints; deterministic reports; no unknown/duplicate/unclassified family;
explicit excluded/deferred rationale and closure gates; pure color conversion
tests. A green audit certifies classification, not feature completion or release
readiness. `--require-no-open-gaps` fails until the in-scope backlog is closed.

## 0.78b — Close or explicitly justify the small remaining gaps

Implementation: native XYZ-D50 helpers plus a reviewed null-surface exclusion;
see `docs/SMALL-GAPS.md`. Acceptance still requires the new native suites.

Review the current open ledger before implementation. Resolve null-surface
semantics and XYZ-D50 convenience operations with real native/pure evidence,
or an explicit justified exclusion. Do not add pointer-level convenience APIs
solely to increase a binding count. Refresh reviewed decisions deliberately.

## 0.78c — Public API and documentation stabilization

Implementation: explicit stable/experimental module policy, frozen runtime-reflected
exports/arities/keywords, headless and GUI checks, consolidated contracts and
public examples. See `docs/API-CONTRACTS.md` and `docs/PUBLIC-API.md`.
The current API gate and cross-platform CI must pass before acceptance.

Snapshot supported public exports/signatures; distinguish stable, experimental
and private interfaces; unify documented ownership, errors and output rules.
Examples must use public APIs. Source availability is not runtime evidence.

## 0.78d — Release candidate validation

Implementation: the manual Release candidate coordinator calls the same-commit CI,
full Acceptance and API inventory workflows. A frozen expanded job/step/artifact
policy rejects incomplete or mixed-attempt evidence. Verified evidence and a
deterministic source ZIP are retained. See `docs/RELEASE-CANDIDATE.md`.
Implementation is not acceptance: require a successful fresh candidate run.

Require current isolated installation, minimum Racket/platform support,
CPU/GPU/document and real-consumer acceptance, plus the authoritative release
gate. No mandatory lane may be skipped or left outside that decision. Zero
unclassified families is necessary, not sufficient for a 1.0 release candidate.

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

Run and accept the implemented 0.78d release-candidate gate before claiming
candidate readiness. Review the exact source archive and execution evidence;
publishing or changing the package version is a separate decision. Then select
a named extended workstream (G1/G2, U1/U2/U3, H1 or X1) according to priorities,
without silently broadening the accepted m119/PDF/SVG-focused scope.

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
