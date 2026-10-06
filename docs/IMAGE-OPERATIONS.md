# Direct image operations — 0.72

Package version **0.72**. Accepted source baseline:
`aa3dec2ba2fd461940757e5288ca81a3916a4282`.
SkiaSharp 3.119.1 / Skia m119 and HarfBuzzSharp 8.3.1.2 remain pinned.
Minimum Racket 8.18 and draw-lib 1.22 are unchanged.

`image-operations.rkt` is reexported by `main.rkt`. The explicit GPU filter
operation is reexported by `gpu.rkt`. Merely requiring these modules does not
construct a GPU context or initialize a window.

## Filtering: three results, two coordinate systems

```racket
(image-apply-filter image filter
                    #:subset [source-subset #f]
                    #:clip clip)
(gpu-image-apply-filter gpu-image filter
                        #:subset [source-subset #f]
                        #:clip clip)
; three values: owned-image, #(x y width height), #(offset-x offset-y)
```

A rectangle is a list or vector `(x y width height)` of exact integers, **not
LTRB**. Width and height must be positive and at most 32768; edges must fit
signed 32-bit coordinates. `source-subset` defaults to the whole image and
must be inside it. `clip` is **required**, in the original input image's
coordinate system, and may extend outside the source image. A blur or shadow
needs room beyond the original dimensions; no default silently removes its halo.

The returned image is an independently owned Skia image. Its storage can be
larger than the valid filtered content, particularly for GPU textures.
The second value identifies valid pixels **inside that returned image**.
The third value places the valid content **in the original input coordinate
system**. It is not the source subset origin or the returned texture origin.

To draw correctly, crop to the returned valid subset and draw the crop at the
returned offset. Adding an application placement `(x,y)` gives
`(x + offset-x, y + offset-y)`. Do not draw the entire backing image and do not
add the valid-subset origin to the geometric offset a second time.

```racket
(with-skia ([filter (make-drop-shadow-image-filter 8 6 2 2 'black)])
  (define-values (filtered valid offset)
    (image-apply-filter source filter #:clip '(-8 -8 64 48)))
  (with-skia ([result filtered]
              [visible (apply image-subset result (vector->list valid))])
    (draw-image canvas visible
                (+ x (vector-ref offset 0))
                (+ y (vector-ref offset 1))
                #:sampling 'nearest)))
```

For a GPU result use `gpu-image-subset`, inside its original active
`call-with-gpu-context` scope. The GPU filter entry point requires a GPU image,
uses its owning context, and rejects a foreign-context filter graph. Upload a
CPU image with `gpu-upload-image` explicitly before GPU filtering. CPU filtering
rejects both GPU images and GPU-dependent filters. A GPU request cannot silently
return a CPU image.

A native null result raises an exception. The pinned native interface does not
reliably distinguish an empty result, an unsupported filter path, and allocation
failure. No fabricated empty image or success receipt is returned, and undefined
output parameters are never read. All returned extents, valid-subset containment,
offset/clip containment and GPU texture limits are checked before publication.

A result retains its own native resources; closing the original image or filter
after the call does not invalidate it. The subset and offset are detached,
immutable vectors and remain inspectable after the result image closes.

An F32 source image cannot silently become F16 or an integer result. An F16 source image may remain F16 or
widen to F32. An unsupported native precision-preserving path raises; explicitly
convert the input first when reduced precision is intended. Native integer
format/order changes can occur; query the result rather than assuming identical
backing format.

## Format-aware reads, scaling and conversion

```racket
(image-read-pixmap! image destination
                   #:source-x [x 0] #:source-y [y 0]
                   #:cache? [cache? #f])
(image-scale-pixmap! image destination
                    #:sampling [mode 'linear]
                    #:cache? [cache? #f])
(image->raster-buffer image
                      #:info [destination-info #f]
                      #:row-bytes [row-bytes #f]
                      #:sampling [mode 'linear]
                      #:cache? [cache? #f])
```

The first two operations write into a **live writable pixmap lease** and return
void. `image-read-pixmap!` reads exactly the destination extent from `(x,y)` in
the source; the entire rectangle must be in bounds. It does not accept native
partial-read clipping as a successful initialized destination. Scaling covers
the entire source image and the entire destination. For a cropped-and-scaled
operation, first take an explicit `image-subset`.

Destination format, alpha type and color-space descriptor control conversion.
The reviewed integer formats and RGBA F16/F32 are available subject to native
format-pair restrictions. Unsupported native conversion raises. Supplying a
narrower destination format is an **explicit quantization boundary**. Supplying
a float destination does not secretly insert an RGBA8888 staging buffer.

Tagged-to-tagged conversion uses the native color spaces. Tagged/untagged
mismatches reject rather than silently relabeling data or inventing sRGB.
Untagged-to-untagged conversion is supported. Existing resource-to-descriptor
rules in `INTEGER-PIXELS.md` remain in force.

Nearest and linear sampling are supported. `#:cache?` forwards a native caching
hint; it is neither an allocation guarantee nor a process-global cache change.
It defaults to false to avoid requesting additional native decode caching.

`image->raster-buffer` returns independent mutable storage. By default it uses
the source dimensions, native format and detached color-space description.
An explicit image-info selects the destination format and size: equal dimensions
use a read, differing dimensions use a scale. An unsupported source format that
cannot be described by the reviewed image-info set requires explicit compatible
destination metadata.

```racket
(with-skia ([pixels
             (image->raster-buffer image
               #:info (make-image-info 320 200
                        #:color-type 'rgba-f32
                        #:color-space 'linear-srgb))])
  (call-with-raster-buffer-pixmap pixels
    (lambda (view) (pixmap-sample view 10 10))))
```

Every write runs in immobile, zero-initialized temporary native storage first.
Only after the native call succeeds and all stored samples pass the existing
finite/alpha validation are tight rows copied into the destination. A failed
native call or invalid sample leaves destination bytes unchanged. Row padding
and pixels outside a destination subview are untouched. No application callback
or native address is exposed by the internal staging bridge.

Read-only, expired, foreign-thread or otherwise invalid destination leases
reject. Existing exclusive borrows and closure restrictions are unchanged.
The immutable source image never aliases the resulting mutable buffer.

These functions are CPU-only, even though the pinned C++ implementation might
infer a context internally. They reject GPU images **before readback**. Continue
using `gpu-image->raster-image`, `gpu-image->rgba-bytes` and the existing explicit
raster-buffer transfer APIs for GPU downloads. Generalized GPU formats remain
0.73; this stage does not broaden the existing RGBA GPU readback contract.

## Inspection and materialization

```racket
(image-unique-id image)             ; native nonzero identity
(image-alpha-only? image)           ; native channel format property
(image-lazy-generated? image)       ; native generator-backed classification
(image-texture-backed? image)       ; native texture-backed state
(image-valid? image)                ; native validity in the owning context
(image-pixels-available? image)     ; non-materializing native peek
(image->non-texture-image image)    ; independently owned CPU reference
(image->raster-image image)         ; independently owned materialized CPU image
```

These are not synonyms. Existing `image-residency` describes wrapper ownership;
a CPU-owned encoded image can still be lazy. A non-texture image can remain
lazy, and reading/scaling an image need not change that image object's native
class. `image-pixels-available?` asks whether pixels can be peeked immediately,
without decoding, copying or exporting a borrowed pixmap. It is not an
availability promise for arbitrary subsequent conversions.

`image-valid?` observes the native object using its owning GPU context when
needed. Scope/thread/lifetime violations still raise. It does not return false
as a substitute for reporting a closed or incorrectly used wrapper.

The two materialization functions require CPU input. Non-texture construction
can return an owned reference to the same immutable native image and preserve
laziness. Raster materialization requires non-lazy, directly available pixels.
Both results have independent wrapper lifetimes; already immutable native pixel
storage may be shared. Image identity is not a content checksum and can be
shared by separately owned aliases.

## Raw numeric image shaders

```racket
(make-raw-image-shader image
                       #:tile-x [tile-x 'clamp]
                       #:tile-y [tile-y 'clamp]
                       #:sampling [mode 'nearest]
                       #:matrix [local-matrix #f])
```

This calls the native **raw** shader factory, not `make-image-shader` with a
renamed wrapper. Numeric samples bypass ordinary source-to-destination color
conversion and unpremultiplication. This is useful for data textures and shader
inputs, not a replacement for ordinary color-managed image drawing. Alpha and
sample interpretation follow the native raw shader contract.

Tile choices are clamp, repeat, mirror and decal. Sampling is nearest or linear;
cubic is rejected. A supplied matrix is a checked invertible affine `matrix?`
value copied into the existing nine-float native matrix layout. The shader
retains the source image independently, including GPU context affinity. A paint
that retains that shader remains valid after both caller-owned wrappers close.

## Document policy and precision

CPU filter evaluation and explicit pixel conversion produce raster images, not
vector geometry. Export an integer result using `#:policy 'error`, not
`'vector-only`. The document inspector requires exactly one intentional
`image / embedded-raster` event and vector background/marker/link operations.
Surrounding vector content is not silently rasterized.

Raw image shader interpretation has no promised direct PDF/SVG equivalent.
It is classified separately as `raw-image-shader / needs-raster` for both
backends. Render it into an explicitly chosen bounded raster image or use the
existing explicit bounded raster-group mechanism before document publication.
The acceptance example uses upfront rasterization into a 16×12 image.

Float precision provenance survives aliases, filtered images, native image
subsets, image shaders and retained filter inputs. Strict document export must
not erase this requirement merely because a filter has been evaluated. Explicit
conversion to reviewed integer storage followed by an image snapshot ends the
requirement. Existing packed-color/RGBA conveniences keep their original
contracts. In particular the earlier eight-bit `image-convert-color-space`
helper remains unchanged; use the new format-aware buffer path for float images.

## Bounds and memory limits

Input extents and the required clip are conservatively charged at up to 16 bytes
per pixel, even for an integer input. Staging and returned-image dimensions are
checked against the configured per-buffer cap and native signed arithmetic.
This can intentionally reject a large integer image that would fit a looser
four-byte calculation. The API never claims that a wrapper cap bounds the whole
native filter graph, transient cache, GPU allocation or process heap.

## Acceptance

```bash
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
python tools/validate-image-operations.py \
  --racket "$RACKET" \
  --require-gpu \
  --backend metal \
  --require-renderers
```

Use the existing `tools/dc-output-requirements.txt` environment. Required viewers
are `pdftoppm` and `rsvg-convert`; a missing required viewer is a failure.
Linux CI uses Mesa/EGL on Racket 8.18 and 9.3. Windows uses D3D12/WARP on 9.3.
Native setup, source manifest and full regression checks precede acceptance.
The canonical Racket package version is checked early using `version/utils`.

The fixture matrix covers offset, nonzero subset/clip, blur halo, offset shadow,
float-preserving scaling with explicit quantization, and raw shader drawing.
There are 12 native documents and six GPU captures. Scale evidence retains F32
samples before quantization; the independent inspector detects an eight-bit
intermediate. GPU receipts require four filter executions, four rejected CPU
operations, cross-context exclusion, retained-result lifetime, and zero drawing
readbacks with one explicit inspection readback per capture. Counts come from
the current tests and are not a coverage percentage.

Delivery-time synthetic inspector tests are labeled synthetic. They cannot
establish that Skia, a GPU backend, or platform CI executed successfully.

## Pinned source basis

- `mono/skia` at `40f75dc0051d141913c07c20d4c19590c7da0cb7`:
  `include/c/sk_image.h`, `src/c/sk_image.cpp`, `src/image/SkImage.cpp`,
  `src/core/SkImageFilter.cpp`.
- Existing wrapper contracts: `private/lifetime.rkt`, `private/gpu-images.rkt`,
  `raster-buffers.rkt`, `private/audit-trace.rkt`, `output-policy.rkt`.
- The existing `picture->image` convenience and GPU upload/download vocabulary
  are reused, not duplicated just to mirror C# overloads.
