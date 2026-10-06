# General image information and integer raster storage — 0.70

Package version **0.70.0**. Baseline: `8130568dda31e43326884312113ffd5010e04a6d`.
The native pins remain SkiaSharp 3.119.1 / Skia m119 and HarfBuzzSharp 8.3.1.2.
Minimum Racket 8.18 and draw-lib 1.22 are unchanged. The APIs below are reexported
by `main.rkt`; metadata alone can be required from `image-info.rkt`.

## Compatibility and scope

Existing calls to `make-surface`, `make-raster-buffer`, `rgba-bytes->image`, bitmap
conversion, and RGBA byte accessors keep their existing meaning. In particular,
`make-raster-buffer` still creates RGBA8888 premultiplied storage, with the same
four-byte stride alignment and exact Racket premultiplication rule. Adding new
formats does not turn an RGBA accessor into an accessor for arbitrary raw bytes.

This stage adds seven selected integer formats, not every Skia enum. ARGB4444,
other packed/planar formats, float formats, allocation flags and externally owned
raw pointers are outside this implementation. F16/F32 and floating colors remain
0.71; configurable GPU surface formats remain 0.73. A metadata value describes a
layout; it does not certify support in an installed native library or GPU device.

## Detached image information

```racket
(make-image-info width height
                 #:color-type [color 'rgba-8888]
                 #:alpha-type [alpha 'premul]
                 #:color-space [descriptor #f])
(image-info? value)
(image-info-width info)
(image-info-height info)
(image-info-color-type info)
(image-info-alpha-type info)
(image-info-color-space info)
(image-info-bytes-per-pixel info)
(image-info-channel-bits info)
(image-info-byte-order info)
(image-info-min-row-bytes info)
(image-info-storage-layout info #:row-bytes [row-bytes #f]) ; three values
(image-info-with-dimensions info width height)
(image-info-supports? info operation)
```

Descriptions are immutable transparent Racket values: no pixels, live wrappers,
foreign addresses or close operation. They can be shared across Racket threads
and inspected after their source resources have closed. Extents are exact
integers in 0..32768. Zero width or height is permitted in a description, but
buffer/surface constructors reject zero-sized allocations.

`image-info-storage-layout` returns **row bytes, minimum accessible bytes, full
allocation bytes**. The default stride is tight. Each row must be aligned to the
format's bytes per pixel, and may include padding. For a nonempty image:

```text
minimum accessible = (height - 1) * row_bytes + width * bytes_per_pixel
full allocation    = height * row_bytes
```

Both final-row padding and intermediate padding count against the allocation.
Empty descriptions have minimum and allocation zero. Strides and allocation
sizes must fit m119's signed 31-bit raster limits and `current-skia-byte-limit`.
The byte limit applies to checked buffers/copies, not the sum of all temporary
allocations or the native/driver/process heap.

## Format and operation matrix

Logical raw sample channels below are listed in the order returned by
`pixmap-sample`, not necessarily the order of bytes in memory.

| Color type | Bytes/pixel | Logical sample | Permitted alpha types | Raster canvas |
|---|---:|---|---|---|
| `rgba-8888` | 4 | R8 G8 B8 A8 | premul, unpremul, opaque | premul / opaque |
| `bgra-8888` | 4 | R8 G8 B8 A8 | premul, unpremul, opaque | premul / opaque |
| `rgb-888x` | 4 | R8 G8 B8 | opaque | yes |
| `alpha-8` | 1 | A8 | premul, opaque | yes |
| `gray-8` | 1 | Gray8 | opaque | yes |
| `rgb-565` | 2 | R5 G6 B5 | opaque | yes |
| `rgba-1010102` | 4 | R10 G10 B10 A2 | premul, unpremul, opaque | premul / opaque |

All seven support checked storage allocation, exact sample reads/writes, explicit
RGBA conversion, independent raster-image copies, and native opacity inspection.
`image-info-supports?` accepts `storage`, `sample`, `rgba-read`, `rgba-write`,
`convert`, `image-copy`, `raster-canvas`, and `gpu-readback`. Its answer is the
wrapper's format/alpha contract, not a successful execution receipt. Pairwise
conversion also checks dimensions, exclusive leases and color interpretation.
`gpu-readback` is true **only for RGBA8888 premultiplied storage**. Unknown
operations raise an error rather than returning an ambiguous false value.

The default alpha type is always `premul`; callers choosing RGBX, Gray8 or RGB565
must explicitly supply `#:alpha-type 'opaque`. Alpha8 does not accept a color
space or an unpremultiplied declaration. Silent native canonicalization is not
exposed as a contradictory metadata value.

### Byte and sample packing

RGBA8888 bytes are R,G,B,A; BGRA8888 bytes are B,G,R,A; RGBX8888 bytes are R,G,B,X.
RGBX raw sample writes initialize X to 255; raw storage imports preserve X and
sample inspection ignores it. Alpha8 and Gray8 are one byte per pixel.

RGB565 and RGBA1010102 use native-endian integer words. RGB565 has R in bits
11..15, G in bits 5..10, B in bits 0..4. RGBA1010102 has R in bits 0..9, G in
10..19, B in 20..29 and A in 30..31. `image-info-byte-order` reports
`little-endian` or `big-endian` for these formats, and `byte-channels` otherwise.
Raw packed bytes are not a machine-independent serialization format.

Sample values are exact unsigned integers at their declared precision. An
opaque alpha-bearing format requires maximum alpha. Premultiplied samples must
satisfy `color/color_max <= alpha/alpha_max` for each color channel; this also
handles the differing 10-bit color and 2-bit alpha precision correctly.
Unpremultiplied storage permits nonzero RGB at zero alpha. Neither raw samples
nor raw copies are converted through eight-bit RGBA values.

## Color-space descriptions and ownership

An image-info descriptor is `#f` (untagged), `srgb`, `linear-srgb`, or a copied,
immutable ICC byte string. The pure constructor checks the ICC header, declared
length and byte limit, not the complete ICC transform. Actual native parsing is
fallible and occurs only when constructing a native resource.

```racket
(color-space-descriptor? value)
(color-space->descriptor owned-color-space)
(descriptor->color-space descriptor) ; owned color-space, or #f
```

Passing a live `color-space?` object as an image-info descriptor is rejected.
Conversion from a native color space is explicit and fallible: named equivalent
spaces become named descriptors; otherwise bounded ICC export is attempted.
An unrepresentable space is not mislabeled sRGB. Each constructed buffer/image
retains its own native color-space reference. Closing the original wrapper does
not invalidate a dependent buffer, snapshot or descriptor.

`raster-buffer-image-info` returns detached information. For a legacy buffer,
exporting its native color space into a descriptor may fail even though ordinary
legacy drawing remains valid. New metadata operations do not alter legacy
construction or make old calls depend on an ICC round trip.

## Buffer and view APIs

```racket
(make-raster-buffer-from-info info #:row-bytes [row-bytes #f])
(raster-buffer-image-info buffer)
(pixmap-image-info view)
(raster-buffer-write-storage! buffer bytes)
(pixmap->storage-bytes view)
(pixmap-write-storage! view bytes #:row-bytes [row-bytes #f])
(pixmap-sample view x y)                 ; immutable vector of integer channels
(pixmap-set-sample! view x y channels)   ; list/vector of exact integer channels
(pixmap-opaque? view)
(raster-buffer-opaque? buffer)
```

Buffers use the ordinary `with-skia` / `skia-close!` lifecycle. Storage is
initialized: transparent black for nonopaque alpha formats, opaque black for
opaque formats. Padding starts zero. Opaque color fills preserve opaque alpha.

The existing `raster-buffer->storage-bytes` copies the **entire allocation**,
including padding after the last row. `raster-buffer-write-storage!` is its
symmetric exact-length import and preserves supplied padding. It snapshots and
validates every pixel before writing, so a bad late sample leaves the destination
unchanged. Caller mutation after the copy cannot change stored pixels.

A view's storage copy is **tight**: it omits row padding and neighboring pixels.
`pixmap-write-storage!` accepts source row bytes and requires at least the final
row's accessible pixels. It copies only view pixels and preserves destination
padding and pixels outside the view. It validates the detached input first.

Views retain the existing exclusive lease contract. They are valid only inside
`call-with-raster-buffer-pixmap`; subsets share the same lease. Read-only views
reject writes. Expired views, cross-thread access, nested borrows and buffer
mutation/copy/close during a borrow reject. Exceptions release the lease and
invalidate escaped views; pixel changes already made by arbitrary application
drawing are not rolled back.

### Precision example

```racket
(with-skia ([buffer
             (make-raster-buffer-from-info
              (make-image-info 2 1 #:color-type 'rgba-1010102))])
  (call-with-raster-buffer-pixmap buffer
    (lambda (view)
      (pixmap-set-sample! view 0 0 '#(1 2 3 3))
      (pixmap-set-sample! view 1 0 '#(2 3 4 3))
      (displayln (pixmap-sample view 0 0)) ; #(1 2 3 3), not eight-bit RGBA
      (displayln (pixmap-sample view 1 0)))
    #:writable? #t))
```

## Explicit conversion, alpha extraction and snapshots

```racket
(pixmap-convert! destination-view source-view)
(raster-buffer-convert source-buffer destination-info #:row-bytes [row-bytes #f])
(raster-buffer-extract-alpha source-buffer)
(raster-buffer->image source-buffer)
(image->image-info image)
```

Conversion requires matching dimensions and distinct allocations. Native
conversion writes a temporary tight result; only a successful result is copied
into the destination, preserving its padding. Same-allocation views reject even
when their rectangles do not overlap. `pixmap-scale!` remains the explicitly
named scaling operation, supports nearest/linear sampling, and also rejects
same-allocation aliases. Scaling is a native write and does not promise rollback.

Conversion between tagged and untagged buffers rejects: choosing a destination
tag is not evidence of the source interpretation. Both-untagged conversion
preserves numeric interpretation; both-tagged conversion uses native color-space
conversion. Construct/import a buffer with the correct source descriptor before
requesting a color-space transform. No metadata-relabeling setter is introduced.

RGBA write APIs interpret input RGBA under the destination buffer's color-space
interpretation, as the legacy API did; they do not silently tag input sRGB.
`#:premultiplied?` explicitly selects input alpha semantics. RGBA reads are
explicit eight-bit conversions and may quantize packed higher-precision samples.

Alpha extraction returns independent, untagged Alpha8 storage with the same
extent. Eight-bit alpha is copied exactly; two-bit alpha expands by 85; formats
without alpha produce 255. This is **plain channel extraction**, not the upstream
paint/mask-filter overload: no filter expansion, reconstructed coverage, or
nonzero placement offset is implied.

`raster-buffer->image` makes an independent native raster copy, preserving the
selected color/alpha format and its own color-space ownership. It does not alias
later buffer mutations. `image->image-info` queries a native image and returns a
detached descriptor when its type is in this stage's selected format set.
Unsupported native image types reject rather than being silently converted.

## Raster and GPU drawing

```racket
(make-surface-from-info info
                        #:row-bytes [row-bytes #f]
                        #:background [background #f])
(call-with-raster-buffer-canvas buffer draw-procedure)
```

The first creates an ordinary owned raster surface; the second creates an
ordinary borrowed canvas with the existing protected state/expiry semantics.
Both reject unpremultiplied raster targets. New surfaces are cleared to black
(opaque targets) or transparent black, unless an explicit background is supplied.
Opaque-only formats necessarily discard transparency when drawing.

This stage does not change GPU surface/presenter formats. Existing
`gpu-surface-read-raster-buffer!` and the image readback route write RGBA8888
premultiplied pixels. The private transfer lease now rejects incompatible
formats/alpha types **before exposing the buffer address**. Read back into a
compatible RGBA buffer, then explicitly convert. Existing `gpu-upload-image`
remains the upload vocabulary; there is no new implicit transfer operation.

The acceptance program explicitly converts and nearest-scales each integer
fixture into a 64x32 RGBA image, uploads that image, draws it into an existing
RGBA GPU target and performs one deliberate readback. Its seven captures prove
that particular consumer route only, not native generalized GPU formats, HDR,
physical monitor output or every encoder's support for every integer format.

## Documents and acceptance

The 14 documents (seven formats, each as PDF and SVG) use the same explicit RGBA
conversion, a vector background/marker and a hyperlink. Images are drawn 1:1.
The export audit uses policy `error`: the intentional image is recorded as
`embedded-raster`, while blocking fallbacks remain errors and all surrounding
document content must remain vector.
The inspector checks actual image extents, surrounding vector content, links,
opaque backgrounds and independent known-color probes. It rejects full-page
rasterization or unreported conversion. This is ordinary explicitly authored
image content, not a claim that raster samples become vector geometry.

```bash
python -m pip install -r tools/dc-output-requirements.txt
python tools/update-source-sums.py --check
python tools/api-inventory.py --check
python tools/test-integer-pixels.py
RACKET="/Applications/Racket v9.3.0.2/bin/racket"
python tools/validate-integer-pixels.py \
  --racket "$RACKET" --require-gpu --backend metal --require-renderers
```

`--require-renderers` requires `pdftoppm` and `rsvg-convert`; absence is failure,
not a skipped pass. Linux acceptance uses EGL/Mesa; Windows uses
`--backend direct3d --adapter warp`. Omit `--require-gpu` only for an intentionally
CPU-only run, which is recorded as such. Each run creates a fresh evidence
directory, checks source hashes before/after, runs all regressions, and records
actual attempted/executed gates. Failed command log tails are printed directly.

The Python inspector's synthetic fixtures test rejection/inspection behavior.
They are not native Skia rendering evidence. Native bindings, full Racket tests,
GPU pixels and independently rendered Skia documents must pass on the selected
hosts before accepting 0.70 as the next baseline.

## Reviewed source basis

Pinned m119 C headers: `include/c/sk_pixmap.h`, `sk_surface.h`, `sk_image.h`;
packing definitions: `include/core/SkColorType.h`, `src/core/SkImageInfoPriv.h`;
row-byte/raster validation: `src/core/SkBitmap.cpp`, `src/image/SkSurface_Raster.cpp`.
All refer to `mono/skia` commit `40f75dc0051d141913c07c20d4c19590c7da0cb7`.
The repository's `docs/API-DESIGN-DECISIONS.md` remains the additive design basis.
