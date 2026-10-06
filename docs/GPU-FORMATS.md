# GPU formats and surface properties — 0.73

Package version **0.73**. Source baseline: `bdb1aef4440cd31b2fdf4950069db29a2ed2b2c0`.
SkiaSharp 3.119.1 / Skia m119 (`40f75dc0051d141913c07c20d4c19590c7da0cb7`),
HarfBuzzSharp 8.3.1.2, Racket 8.18 and draw-lib 1.22 are unchanged.
This is a GPU-storage and configuration stage, not HDR window presentation.

## Detached surface properties

`surface-properties.rkt` contains immutable, transparent values, not native handles.
It can be required without loading Skia or constructing a GPU context. `main.rkt`
reexports its public operations and `surface-properties-of`.

```racket
(make-surface-properties
  #:pixel-geometry 'unknown
  #:device-independent-fonts? #f
  #:dynamic-msaa? #f
  #:always-dither? #f)

(surface-properties-of surface)
(surface-properties-pixel-geometry properties)
(surface-properties-flags properties)
(surface-properties-device-independent-fonts? properties)
(surface-properties-dynamic-msaa? properties)
(surface-properties-always-dither? properties)
(surface-properties->jsexpr properties)
```

Pixel geometry is one of `unknown`, `rgb-h`, `bgr-h`, `rgb-v`, `bgr-v`. Flags map to
the pinned native bits 1 (device-independent fonts), 2 (dynamic MSAA) and 4 (always
dither). Unknown bits reject. Their availability as settings does not guarantee
that every drawing operation uses the associated optimization.

The default remains **unknown geometry, no flags**. This preserves portable text
behavior instead of guessing the physical monitor's LCD arrangement. A geometry
request is not monitor detection or proof of visible subpixel text. No color-font
or variable-font configuration is added.

`surface-properties-of` works on a live owned CPU or GPU surface, enforces its
existing thread/context rules, and copies the borrowed native property fields.
The returned value outlives the surface. The borrowed native property pointer is
never exposed or deleted. CPU surface construction defaults remain unchanged;
this stage adds configurable properties to GPU construction, not every CPU factory.

## Typed GPU targets

```racket
(make-gpu-surface context width height
  #:background 'transparent
  #:color-space #f
  #:sample-count 0
  #:opaque? #f
  #:budgeted? #t
  #:color-type 'rgba-8888
  #:alpha-type #f
  #:surface-properties (make-surface-properties))
```

Existing arguments and defaults remain valid. `#:color-space` here continues to
accept an owned `color-space?` resource or `#f`, not a descriptor. The surface
retains independent native references, so closing the supplied wrapper is safe.

Nine formats are reviewed as requests: `rgba-8888`, `bgra-8888`, `rgb-888x`,
`alpha-8`, `gray-8`, `rgb-565`, `rgba-1010102`, `rgba-f16`, `rgba-f32`.
This is **not a universal support list**: capability depends on the active native
context/backend and the actual allocation must also succeed.

Alpha is `premul` or `opaque`. `unpremul` is rejected as a drawing target. An omitted
alpha type derives from the legacy `#:opaque?` flag; otherwise contradictory
requests reject. Opaque targets require an opaque background. RGBX, Gray8 and
RGB565 require explicitly opaque alpha. Alpha8 has no color-space interpretation.

Dimensions are nonempty exact integers up to 32768 and also bounded by the native
context. Allocation arithmetic uses the actual format's bytes per pixel, not a
four-byte assumption for float targets. Requested sample counts are exact integers
from 0 through 64 and must not exceed the native maximum for the selected color
format. A zero native maximum is an unsupported format, including for a zero-MSAA
request. No CPU surface or substitute color format is returned on failure.

Construction verifies its context, property roundtrip, and the initialized
snapshot's native color/alpha type before publishing the result. Snapshot metadata
requires no CPU readback, but taking a snapshot can involve native GPU work/storage;
it is not advertised as zero-cost. Byte limits bound wrapper-controlled storage,
not every Skia cache, multisample allocation or transient driver allocation.

## Capability versus actual surface metadata

```racket
(gpu-surface-format-info context 'rgba-f16)
(gpu-surface-info surface)
(gpu-surface->image-info surface)
```

The first query requires the live context and reports `renderable`,
`max_sample_count`, `max_render_target_size`, backend and context generation.
`renderable` means a positive native format/sample capability, not successful
allocation, transfer, drawing or device-wide certification.

`gpu-surface->image-info` returns detached metadata checked against an initialized
native texture snapshot. It preserves actual color/alpha interpretation and the
existing named/copied-ICC descriptor rules. Describing an unusual color space can
fail rather than silently relabel it.

`gpu-surface-info` retains existing fields and adds canonical color/alpha names,
selected format maximum, and detached `surface_properties`. **Requested and actual
sample count are distinct**. Pinned Skia may round a request to a supported count;
its C wrapper does not expose the actual count of a Skia-owned target. Therefore
`actual_sample_count` stays `#f`, rather than pretending the request was observed.
Native sample-count getters for external GL descriptors do not solve this owned-
surface limitation.

## Explicit typed transfers

```racket
(gpu-surface-read-pixmap! surface destination)
(gpu-surface->raster-buffer surface #:info #f #:row-bytes #f)
(gpu-image->raster-buffer image #:info #f #:row-bytes #f)
```

The pixmap destination must be a live, writable lease of exactly the source's
extent. A matching subview is allowed; outside pixels and row padding are preserved.
The call is an explicit synchronous GPU-to-CPU transfer and is recorded as such.
Native readback runs into immobile scratch memory with a separate immobile image
info. Only a successful read with valid finite/alpha samples is copied into the
destination. Native failure or invalid samples leave destination bytes unchanged.
The pre-read GPU flush/wait is not undone by a failed conversion.

The buffer helpers default to the actual source image-info and return independently
owned CPU storage. An explicit `#:info` authorizes a destination format/alpha/color-
space conversion; dimensions must match (these are transfers, not scalers). Tagged
and untagged interpretations cannot be mixed implicitly. Tagged-to-tagged conversion
is native and can fail for an unsupported pair. Raw stored samples remain available
through the existing `pixmap-sample`/`raster-buffer->storage-bytes` APIs.

`gpu-surface->raster-image` and `gpu-image->raster-image` now preserve target format
through the typed buffer path. F16/F32 storage is not secretly routed through an
eight-bit RGBA buffer. Image staging uses the original image color format and color
space. GPU upload checks and rejects a native reduction of float storage precision.
This does not promise infinite precision inside every native shader/filter; native
arithmetic and supported format pairs still constrain results.

The existing `gpu-surface->rgba-bytes` and `gpu-image->rgba-bytes` remain explicit
eight-bit conversions. Legacy `gpu-surface-read-raster-buffer!` and
`gpu-image-read-raster-buffer!` retain their RGBA8888-premultiplied destination
restriction. Use the new pixmap/buffer entry points for generalized transfers.

Float precision provenance is retained on targets, snapshots and typed detached
images. Strict PDF/SVG publication requires an explicit integer conversion or the
existing declared rasterization boundary. Merely downloading to CPU does not
turn a float image into a vector/ordinary eight-bit publication result.

## Presenter staging configuration

`call-with-gpu-frame-dc` gains optional keywords:

```racket
(call-with-gpu-frame-dc frame draw
  #:color-type 'rgba-f16
  #:color-space 'linear-srgb
  #:sample-count 0
  #:surface-properties (make-surface-properties))
```

Unlike the long-standing surface constructor, this new `#:color-space` accepts a
**detached descriptor**: `#f`, `srgb`, `linear-srgb`, or complete ICC bytes. ICC bytes
are copied before forming the key; no temporary native pointer or closeable wrapper
identity is used. Staging alpha is premultiplied, allowing transparent clears and
nested alpha groups. Supported DC staging requests are RGBA8888, BGRA8888, F16, F32;
packed/gray/alpha-only targets are explicitly outside this full-color compositor.

A reuse hit requires physical width/height plus color type, alpha type, copied color
space, sample request and property flags/geometry. Context and backend remain
implicit in the owning presenter, never a shared global pool. A changed same-size
configuration retires the old wrapper before replacement. Returning to an earlier
configuration allocates again. A hit rechecks the format-aware byte budget.

Every callback still receives fresh DC state. Failed/escaped callbacks retire their
staging target. The commit remains a GPU snapshot and GPU-to-GPU copy into the
existing presenter target; snapshots and alpha intermediates are not pooled away.
Borrowed `call-with-gpu-surface-dc` inherits the actual root color/space/properties for
its full-color alpha intermediates. Ordinary DC colors keep their existing meaning.

Selecting float staging **does not change the window/swapchain format**, negotiate
HDR or certify a physical display. Final presentation to the existing SDR target
can quantize the explicitly selected staging. High-precision offscreen output is
separate from display output. The current canvas factory defaults remain unchanged.

## Scoped backend descriptor verification

Existing GL/Metal/D3D texture descriptor constructors now cross-check native width,
height, backend, validity and (where supplied) mipmap state. GL texture and framebuffer
information are copied into bounded temporary storage and compared by scalar fields.
External GL target getters also verify dimensions, samples and stencil fields.
Checks occur while the existing checked host/resource scope is active; a failed
validation releases the new descriptor before it can be wrapped or published.

These are additional checks behind existing resource ingress, not a public arbitrary
pointer API. There is no Vulkan extension or adoption of untracked user memory.
New descriptor symbols have a separate diagnostic group so the older surface/window
inspectors still validate their exact original inventories.

## Acceptance

From a complete applied checkout with the existing Python environment:

```bash
source "$HOME/.venvs/skia-for-racket/bin/activate"
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
python tools/validate-gpu-formats.py \
  --racket "$RACKET" \
  --require-gpu \
  --backend metal \
  --require-renderers
```

This runs source checks, the package-version check, compilation and full regressions,
then selected native GPU tests and four GPU-derived PDF/SVG documents. Raw captures
retain padding and float samples including negative RGB, values above one and a
nonuniform difference smaller than 1/255. Independent inspection checks the actual
stored data, not merely a success flag or native reference image. Required formats
are RGBA8888, BGRA8888 and F16; others are accepted as unsupported only when the
native capability is zero and the constructor explicitly rejects them.

Poppler (`pdftoppm`) and librsvg (`rsvg-convert`) independently render the documents
when required. Their raster image is an explicit RGBA conversion; marker geometry
and hyperlinks remain vector/annotation content. Missing viewers are failures.
Without `--require-gpu`, the validator reports only the executed source/native CPU
property regressions, not GPU or document success.

The new workflow is reusable and called by `Acceptance`; it does not add a fourth
automatic top-level run. Linux requires Mesa/EGL on Racket 8.18 and 9.3; Windows
requires D3D12/WARP on 9.3. Existing full CI/interop/presenter gates remain in place.
Manual Metal validation uses the same driver. Only actual selected runs establish
backend execution; delivery-time Python tests are not native/GPU execution evidence.

## Primary source basis

Pinned `mono/skia` revision `40f75dc0051d141913c07c20d4c19590c7da0cb7`:
`include/core/SkSurfaceProps.h`, `include/c/sk_surface.h`, `include/c/gr_context.h`,
`include/c/sk_pixmap.h`. Integration follows existing `private/gpu-surfaces.rkt`,
`private/gpu-frame-target-cache.rkt`, `private/gpu-images.rkt`, the scoped interop
wrappers and the 0.72 transactional pixmap writer.
