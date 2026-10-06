# Additive API decisions for gap reduction — 0.65

**Decision status:** accepted direction for implementing stages 0.66–0.77, subject
to the native and cross-platform acceptance specified below. **Implementation
status:** this document does not add image-info, color4f, generalized pixel formats,
new streams, or new rendering operations. Names in sketches are provisional;
existing public identifiers and behavior are unchanged in 0.65.

The comparison target is SkiaSharp 3.119.1 at
`cc78b5933d23e6383db5d246e70db915770d55d6`, with the C shim at
`40f75dc0051d141913c07c20d4c19590c7da0cb7`. Keep the Racket 8.18,
`draw-lib` 1.22, SkiaSharp 3.119.1 and HarfBuzzSharp 8.3.1.2 minimum/pin decisions.
The Pango module compatibility bridge from 0.64 remains required.

## D1. Image information is an immutable value, not a pixel owner

A future image-info value describes dimensions, color type, alpha type and a
color-space descriptor. It contains neither pixels nor a raw/native owner pointer.
It is safe to share between Racket threads, store in an inventory, and inspect
after closing a source surface. It has no `close` operation.

A description is not an availability promise: allocating byte storage, reading a
sample, converting samples, rendering into a surface, uploading to a backend and
encoding are distinct operations. Stage 0.70 must publish an operation-by-format
matrix. A known enum value does not make a format renderable. Unknown formats and
unsupported alpha/color combinations reject before native allocation.

**Construction sketch, not a current export:**

```racket
(make-image-info width height
                 #:color-type 'rgba-8888
                 #:alpha-type 'premul
                 #:color-space descriptor)
```

Logical GUI size is not image pixel extent. Image-info dimensions and strides are
physical pixel storage; existing independent X/Y device-scale semantics remain.

**Acceptance:** immutable/detached metadata; zero-sized description rules separate
from allocatable-surface rules; checked byte arithmetic; no accidental GUI/native
initialization merely to inspect metadata.

## D2. Color-space values and resource retention have distinct roles

Existing `color-space?` objects remain owned native resources. Do not silently
change their type or close behavior. A future image-info value carries a detached
immutable descriptor: untagged, a reviewed named space, copied ICC bytes, or a
reviewed parametric RGB description. Converting an existing native resource to a
descriptor is explicit and fallible; an unrepresentable native space is rejected,
not relabeled sRGB. Querying/copying its description can require native code.

Constructing an image/surface from a descriptor creates or retains its own native
color-space reference. Closing the caller's temporary native color space cannot
invalidate live pixel storage, a retained image, or a recorded command. Metadata
returned from a live resource is detached, or is documented as a separately owned
color-space resource. Never return a borrowed pointer with hidden expiry.

Do not key a staging cache solely by the address of a temporary color-space
wrapper. Use an owned stable identity or canonical descriptor with explicitly
reviewed equality semantics. ICC byte equality is a valid conservative cache key,
not a proof that unequal profiles represent different transforms.

**Acceptance:** close original resource before using its dependent buffer/image;
inspect saved metadata after all native resources close; verify failure paths and
non-ICC-representable spaces without destroying the original object.

## D3. Preserve the current RGBA convenience contract

Keep `make-surface`, `make-raster-buffer`, `rgba-bytes->image`, RGBA byte accessors,
`surface-pixel`, and existing bitmap conversions unchanged for existing calls.
Their defaults, channel order, alpha semantics, stride interpretation and return
values do not change because more formats become representable.

Add generalized constructors/keywords and explicit storage/sample operations.
Existing RGBA accessors remain **conversions to RGBA**, not a newly format-dependent
interpretation of the same bytes. Raw storage access reports color/alpha type,
row bytes and endianness/packing. A metadata relabeling operation is not sample
conversion; these need different names and tests. No inferred source space for
untagged samples, beyond any precisely preserved legacy contract.

Stages 0.70 and 0.71 should first support a bounded set of integer and floating
formats, not every upstream enum on every backend. Existing geometry, pictures,
DCs and canvases are unaffected by merely adding storage descriptions.

**Acceptance:** old RGBA tests unchanged; exact integer reference patterns;
channel/alpha conversion once; padding canaries; rejected invalid combinations;
explicitly recorded quantization where float output becomes eight-bit output.

## D4. Floating color is not an eight-bit color in disguise

Introduce a separate immutable float-color value rather than broadening existing
packed/byte color accessors incompatibly. RGB components are finite; values below
zero or above one are retained when the specific native operation supports them.
Alpha remains finite in [0,1]. Do not clip or round components globally just to
fit an existing eight-bit conversion helper.

Specify whether source colors are premultiplied at each boundary. Associate an
explicit source color space with a color conversion or gradient operation, not
with a hidden global default. F16 and F32 storage can have backend-specific
restrictions. Integer encoders are allowed to quantize only at an explicit,
documented export/conversion boundary.

PQ/HLG are not forced into the existing SDR piecewise-parametric constructor.
Their representation and tone policy are separate H1 decisions. Float-capable
raster rendering does not establish HDR window or physical-display support.

**Acceptance:** preserve test differences below 1/255; test negative/extended RGB
when allowed; reject NaN/infinity and invalid alpha; inspect actual float samples
rather than only PNG previews.

## D5. Pixel ownership stays explicit and mutable views stay scoped

Generalized storage remains an initialized, owned allocation with deterministic
close and GC fallback. A pixmap is a non-owning description/view obtained through
an exclusive checked lease. Mutable and read-only views retain the existing
owner-thread, active-scope and expiry checks. Subsets cannot escape the lease's
lifetime or expand its bounds. No raw address or callback-controlled allocation
ownership enters the safe API solely to match a SkiaSharp constructor.

For a layout, compute both the minimum accessible storage
`(height - 1) * row_bytes + width * bytes_per_pixel` and the actual allocation
extent. Check overflow and the configured bound before allocation or borrowing.
Document whether the final row includes padding. Never read uninitialized padding
or equate a per-buffer cap with a bound on the entire native/driver heap.

Snapshots are explicit independent results, not silent aliases to a mutable
buffer. A decoder retaining a destination address owns a live exclusive lease
until completion/cancellation; it must not continue after that lease expires.

**Acceptance:** mutation/closure during a borrow, exceptions and continuation
escapes, nested views, canaries and stride bounds, retained decoder buffers and
snapshot independence across source mutation/closure.

## D6. Retain one coherent transfer vocabulary

Use the existing operations wherever they already express the operation:
`gpu-upload-image`, `gpu-surface-snapshot`, `gpu-image-subset`,
`gpu-image->raster-image`, `gpu-image->rgba-bytes`, and the explicit
raster-buffer transfer operations. `image-residency` classifies wrapper ownership;
native texture-backed state can be a different property and must be labeled as
such. Do not add synonyms just to duplicate `ToTextureImage`/`ToRasterImage`.

A normal GPU frame must not implicitly read back to the CPU. New filtering,
conversion and scaling operations state source/destination residency, owning
context, and whether they can submit, wait, allocate or transfer. Cross-context
inputs reject unless an explicitly implemented interop/copy operation handles
that exact case. A non-texture image can still be lazy; do not describe it as
completed pixel materialization.

For stage 0.72, filtering returns a result with **image, valid subset and placement
offset**, with coordinate conventions stated. A shadow/blur halo cannot be
represented faithfully by dropping the offset or cropping to input dimensions.

**Acceptance:** positive-control readbacks plus no-readback normal scopes, wrong
context/expired resource rejection, retained results after original wrappers
close, and comparison at the final target rather than staging alone.

## D7. Format/configuration changes must invalidate incompatible staging

The current presenter retains compatible staging by physical extent within one
fixed presenter/context. When 0.73 adds configurable formats/properties, extend
the reuse key to every allocation-affecting property: physical dimensions,
color/alpha type, owned color-space identity/descriptor, sample count and reviewed
surface properties. Context/backend identity remains part of the owner's domain.
Changing format or color interpretation must not accidentally reuse old storage.

Keep current grayscale text/pixel-geometry defaults until the caller deliberately
selects other behavior. LCD/subpixel text has target-opacity and pixel-geometry
requirements; support for an enum does not certify those requirements.

**Acceptance:** configuration toggles create/retire the correct targets; no stale
pixels or state; unchanged expired-DC semantics; no implicit fallback to another
backend or to CPU rendering.

## D8. Document policy accompanies each new drawing feature

Every effect, image, blob, geometry and layer addition must update resource
provenance and document auditing before its capability is called integrated.
Classify native vector/text output, explicit bounded raster output, and rejection
per backend. Do not silently rasterize surrounding vector content or discard
links/original text. SaveLayer bounds are hints unless a separate clip is installed.

Recorded fonts/glyph placements retain the state used by drawing and outline
conversion. Supplying UTF-8/cluster data to a blob does not by itself prove correct
PDF extraction; acceptance must inspect generated content and rendered pixels.
Full SVG document parsing, PDF/A, tagging, universal font metrics and physical
screen validation are not implied by the existing output layer.

**Acceptance:** actual PDF streams/SVG elements and independent rendering when
applicable; strict rejection tests; exact output placement and image dimensions;
no source-only assertion used as a rendering pass.

## D9. Stream callbacks and publication are separate contracts

Bytes snapshots remain useful and must be labeled as buffered input. Stage 0.75
adds actual stream/port ownership and I/O behavior; whole-input buffering is not
counted as streaming. State whether a port is borrowed or closed by the wrapper,
what seeking is required, and how short reads/writes, EOF and cancellation work.
No Racket exception may unwind unsafely through an FFI callback.

Direct output streaming can leave partial bytes when authoring or encoding fails.
Atomic publication remains an explicit buffered or temporary-file policy. Do not
promise rollback for arbitrary ports. Native callbacks invoked from an unexpected
thread require an explicit marshal/reject protocol, not unconstrained user calls.

## D10. Scope and release decisions remain data, not marketing metrics

`api/capabilities.json` is the disposition ledger. Keep source declaration,
export/resolution observations and executed tests as distinct evidence. Report
both existing equivalents and limitations. A header entry point with a NULL
platform implementation is not a supported renderer. A successful CI workflow is
not automatically evidence for every newly added inventory row.

0.65 exports no speculative image-info/color4f/stream APIs. Detailed stage APIs
can refine provisional names while preserving these additive ownership decisions.
General signature/export freeze and clean-package stabilization remain 0.78;
Vulkan, native migration, variable fonts, Graphite and HDR remain explicit tracks.

## Source basis

- Pinned C image, pixmap, surface, shader and codec interfaces:
  https://github.com/mono/skia/tree/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/c
- Pinned managed source families:
  https://github.com/mono/SkiaSharp/tree/cc78b5933d23e6383db5d246e70db915770d55d6/binding/SkiaSharp
- Existing ownership: `private/lifetime.rkt`, `raster-buffers.rkt`,
  `private/gpu-domain.rkt`, `private/gpu-images.rkt`, `private/gpu-frame-target-cache.rkt`.
- Existing document policy: `output-policy.rkt`, `output-audit.rkt`,
  `docs/DC-OUTPUT.md`, `docs/DC-COMPATIBILITY.md`.

## 0.70 implementation checkpoint

D1–D3 and D5 now have the additive implementation described in
[INTEGER-PIXELS.md](INTEGER-PIXELS.md). Floating formats and generalized GPU
targets remain separate stages; this note does not assert native execution.

## 0.71 implementation checkpoint

F16/F32 storage and Color4f values now implement D4 together with the existing D1–D3/D5 foundations. See [FLOAT-PIXELS.md](FLOAT-PIXELS.md) for precision, color interpretation, lease, and quantization contracts. HDR and generalized GPU formats remain separate work.

## 0.72 implementation checkpoint

Direct image operations implement D6 with explicit CPU/GPU entry points, and retain D3–D5 precision and exclusive leases. Filter results preserve image, valid subset and world placement offset. Reads/scales stage and validate before destination mutation. Raw numeric image shaders require an explicit document rasterization boundary. See [IMAGE-OPERATIONS.md](IMAGE-OPERATIONS.md).
