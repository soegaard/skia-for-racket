# Floating-point pixels and colors — 0.71

This stage adds real RGBA F16/F32 CPU storage, separate unpremultiplied Color4f
values, source-space paints and shaders, native float reads/fills, and explicit
precision boundaries for document output. It does not change the existing
seven integer formats or the default RGBA8888 APIs. Native pins remain
SkiaSharp 3.119.1 / m119 and HarfBuzzSharp 8.3.1.2; Racket 8.18 and draw-lib 1.22
remain the minimums. Nothing loads a renderer just to construct a description.

## Values, storage, and color interpretation

`color4f.rkt` is a pure module. A `color4f?` value contains finite,
**unpremultiplied** red, green, blue, and alpha components. RGB is not clamped
to [0,1]: negative and extended-range values are retained. Alpha must be in
[0,1]. Values must be representable in the finite binary32 range. This is a
separate type; `rgba`, `color?`, byte color arguments and their accessors do
not silently acquire float semantics.

```racket
(make-color4f red green blue [alpha 1])
(color4f? value)
(color4f-red color)
(color4f-green color)
(color4f-blue color)
(color4f-alpha color)
(color4f->vector color)                     ; immutable #(r g b a)
(color->color4f byte-color)                 ; explicit channels / 255
(color4f->rgba color #:out-of-range 'error)  ; numerical quantization
(color4f->rgba color #:out-of-range 'clip)   ; explicit RGB clipping
```

`color4f->rgba` rounds to nearest eight-bit channels. It is not tone mapping
or color-space conversion. By default, extended RGB is an error; `clip` is
an explicit lossy choice. No font file, color profile, GPU context, or monitor
is implied by these values.

### Image descriptions

`float-pixel-formats` is the immutable vector `#(rgba-f16 rgba-f32)`.
`integer-pixel-formats` remains unchanged. `pixel-formats` contains both sets.
The existing `make-image-info` accepts the two new formats:

```racket
(make-image-info 64 32 #:color-type 'rgba-f16
                #:alpha-type 'premul #:color-space 'linear-srgb)
(image-info-sample-type info)      ; 'float or 'unsigned-integer
(image-info-bytes-per-pixel info)  ; 8 for F16; 16 for F32
(image-info-channel-bits info)     ; #(16 16 16 16) or #(32 32 32 32)
(image-info-byte-order info)       ; native 'little-endian or 'big-endian
```

Each pixel consists of four native-endian IEEE binary16 or binary32 samples
in RGBA order. The stored bit depth is not a claim that every operation has
that many bits of numerical accuracy. F16Norm, alpha-only float, and two-channel
float formats are not added here. Descriptions can have zero extents, but actual
buffer/surface allocation still requires nonempty dimensions.

Descriptors remain detached immutable values: `#f` (untagged), `'srgb`,
`'linear-srgb`, or copied ICC bytes. Existing live `color-space?` wrappers are
not interchangeable with descriptors. `color-space->descriptor` is the explicit,
fallible bridge. Buffers and surfaces retain their own native color-space
references; a saved description outlives every resource involved in creating it.

### Stored samples are not Color4f values

`pixmap-sample` and `pixmap-set-sample!` operate on the **stored** channels,
without color-space conversion, premultiplication, or unpremultiplication.
A premultiplied sample therefore differs from the unpremultiplied Color4f used
for painting. Extended premultiplied RGB may be negative or exceed alpha;
the eight-bit rule `RGB <= alpha` does not apply to this extended float space.
At zero premultiplied alpha, RGB must be zero. Opaque storage requires alpha 1.
Unpremultiplied storage can retain RGB behind zero alpha.

All channels supplied through raw storage/sample ingress must be finite. F16
channels are restricted to [-65504,65504]; F32 uses the finite binary32 range.
Input is checked again after storage rounding, so tiny alpha cannot round to
zero while leaving nonzero premultiplied RGB. Invalid input is rejected before
any destination bytes change. Full raw writes validate every pixel before
mutation, including a bad final pixel; padding bytes are not pixel samples.

The F16 encoder rounds directly to binary16 with ties to even, without an
intermediate binary32 rounding. Raw storage preserves signed zero and finite
subnormal bit patterns. **Native Skia arithmetic and F16 color queries may
flush subnormals**; raw bit preservation is not a promise about the native
raster pipeline. The acceptance tests separate these two claims.

## Operation-by-format contract

These are supported wrapper routes, not per-device execution receipts.

| Operation | F16 | F32 | Meaning |
|---|---|---|---|
| Owned initialized buffer | Yes | Yes | Full padded allocation; opaque alpha initialized to float 1 |
| Raw storage/sample access | Yes | Yes | Native-endian stored channels, no eight-bit intermediate |
| Independent image snapshot | Yes | Yes | Retains format and its own color-space ownership |
| Conversion to/from reviewed formats | Yes | Yes | Explicit native conversion, staged and validated |
| CPU canvas, premul/opaque | Yes | Yes | Real float target; no implicit RGBA8888 staging |
| CPU canvas, unpremul | No | No | Rejected explicitly |
| `pixmap-color4f` / `pixmap-alphaf` | Yes | Yes | Native float query; color is unpremultiplied |
| `pixmap-fill-color4f!` | Yes | Yes | Input is sRGB, converted to target; one checked native sample staged first |
| Existing RGBA byte accessors | Yes | Yes | Explicit eight-bit read/quantization, not raw float bytes |
| Existing GPU buffer readback | No | No | Rejected before any raw destination address is handed out |
| Direct strict PDF/SVG float image | No | No | Explicit integer conversion or declared raster group required |

Row bytes are aligned to the entire pixel size (8 or 16), not merely one
component. The existing checked layout arithmetic charges all allocated rows,
including final-row padding, and enforces native signed-31-bit storage and
`current-skia-byte-limit`. This is a bound on wrapper-managed buffers and staging,
not on the whole process, Skia caches, or driver memory.

The existing exclusive owner-thread leases, read-only views, subset bounds,
expired-view rejection and canvas-state cleanup are retained. Padding is left
unchanged by pixel fills and subset writes. User code can still leave pixels
partially drawn when a canvas callback raises; drawing does not promise rollback.
Native arithmetic can overflow even with finite input; raw/sample inspection
rejects nonfinite stored values rather than disguising them as ordinary colors.

## Native float pixel operations

These additions are exported by `raster-buffers.rkt` and `main.rkt`:

```racket
(pixmap-color4f pixmap x y)                 ; color4f?, unpremultiplied
(pixmap-alphaf pixmap x y)                  ; finite alpha in [0,1]
(pixmap-fill-color4f! pixmap color)
(pixmap-set-color4f! pixmap x y color)
```

`pixmap-color4f` returns the native unpremultiplied color **in the pixmap's
own color interpretation**; it does not transform to sRGB. By contrast, pinned
`SkPixmap::erase(Color4f)` treats its input as unpremultiplied **sRGB**, then
converts into the destination. Thus `pixmap-fill-color4f!` is not the inverse
of a local-space raw sample read. Use `pixmap-set-sample!` for exact local-space
storage, or `raster-buffer-convert` for a declared source/destination conversion.

Fills stage one native converted pixel in separate scratch storage, validate it,
and only then copy it into the destination rows. Unsupported/nonfinite/overflowing
converted samples cannot leave a partially filled destination. Opaque targets
require opaque fill input. For integer targets the float fill is an explicit
quantization operation. `raster-buffer-extract-alpha` still returns **Alpha8**;
float alpha is explicitly rounded to eight bits, not returned as a new float type.

`raster-buffer->image` preserves F16/F32. The older `image-convert-color-space`
route stages eight-bit RGBA and now explicitly rejects float snapshots; use
`raster-buffer-convert` before taking the immutable image snapshot instead.
This also means encoding paths that request that legacy image-level conversion
must receive an explicitly converted integer image. `raster-buffer-copy` copies stored data.
`raster-buffer-convert` transforms samples; it does not merely relabel metadata.
A conversion between tagged and untagged data still rejects ambiguity. The
legacy RGBA constructor and its exact premultiplication behavior remain unchanged.

## Paints, clears, and shaders

`float-colors.rkt` and `main.rkt` provide:

```racket
(make-paint/color4f color #:color-space descriptor
                   #:style 'fill #:stroke-width 1 #:antialias? #t)
(paint-color4f paint)
(paint-set-color4f! paint color #:color-space descriptor)
(canvas-clear-color4f! canvas color)
(draw-color4f canvas color #:blend-mode 'src-over)
```

Paint setters take an explicit, non-null source-space descriptor. SkPaint stores
an extended sRGB color internally, so `paint-color4f` reports extended sRGB,
not the original descriptor's numerical tuple. Paint construction, copying,
mutation and normal resource closure follow the existing ownership rules.
The convenience constructor exposes basic paint options; apply the existing
paint setters for other effects and stroke properties.

Canvas clear/draw Color4f values use Skia's sRGB interpretation. They do not take
a source color space in the pinned ABI. For another source space use a float
paint or shader with its explicit descriptor. Canvas arguments are **16-byte
structs by value**; paint and shader Color4f arguments are pointers. The binding
uses separate signatures and native tests with distinct RGBA values to detect
calling-convention mistakes, rather than trusting a matching symbol name.

```racket
(make-color4f-shader color #:color-space descriptor)
(make-linear-gradient-color4f-shader start end colors #:color-space descriptor
                                    #:stops #f #:tile-mode 'clamp #:matrix #f)
(make-radial-gradient-color4f-shader center radius colors #:color-space descriptor
                                    #:stops #f #:tile-mode 'clamp #:matrix #f)
(make-sweep-gradient-color4f-shader center colors #:color-space descriptor
                                   #:start-angle 0 #:end-angle 360
                                   #:stops #f #:tile-mode 'clamp #:matrix #f)
(make-two-point-conical-gradient-color4f-shader start start-radius end end-radius colors
                                              #:color-space descriptor
                                              #:stops #f #:tile-mode 'clamp #:matrix #f)
```

Points are `(list x y)` or `#(x y)`. Colors/stops are lists or vectors. At least
two Color4f stops are required. Explicit stop positions must be in [0,1] and
strictly increasing **after binary32 conversion**; duplicate hard stops are
not exposed by this wrapper. Tile modes use the existing clamp/repeat/mirror/decal
table; local matrices are the existing affine `matrix?` values. Shaders retain
independent native inputs. Closing temporary color-space wrappers does not
invalidate a shader. No array pointer or native callback is public.

F16/F32 precision depends on the actual drawing target. Drawing these shaders
onto an existing eight-bit GPU surface is still eight-bit output. This stage
adds no configurable float GPU targets, HDR surface formats, tone mapping,
PQ/HLG transfer model, display negotiation or physical-monitor claim.

## Document output and explicit precision loss

The auditor classifies `float-color` and `float-pixels` as `needs-raster` for
PDF/SVG. This is intentionally conservative: even float colors in [0,1] may
contain precision or source-space information not preserved by the serializer.
Strict output does not silently call such content ordinary vector geometry.
Paint copies, image snapshots/subsets, image shaders and recorded pictures
retain the relevant provenance. Setting a paint back to an integer color or
resetting it clears that float-color requirement.

Choose an explicit boundary:

```racket
(with-skia ([source (make-raster-buffer-from-info
                    (make-image-info 64 32 #:color-type 'rgba-f16 #:color-space 'srgb))]
            [converted (raster-buffer-convert source
                        (make-image-info 64 32 #:color-space 'srgb))]
            [image (raster-buffer->image converted)])
  ;; 'image' is now an intentionally quantized RGBA8888 snapshot.
  ;; Export a page containing it with #:policy 'error, not 'vector-only.
  (void))
```

Alternatively author a declared `draw-rasterized` group, or explicitly convert
an individual color with `color4f->rgba` and the appropriate clipping choice.
A declared raster group is an intentional representation/precision compromise;
its existing RGBA target does not preserve F16/F32 precision. `#:policy 'report`
still reports risks without enforcing them; it is not a precision guarantee.
PNG/JPEG/WebP and existing RGBA read APIs are explicit integer export boundaries.
Their existing ICC metadata policies remain unchanged; clipping is not HDR tone
mapping. A buffer snapshot itself is never such a hidden conversion boundary.

## Verification and acceptance

```bash
python tools/update-source-sums.py --check
python tools/api-inventory.py --check
python tools/test-float-pixels.py
python tools/test-float-pixel-documents.py
python tools/validate-float-pixels.py --racket "$RACKET" \
  --require-gpu --backend metal --require-renderers
```

The validator compiles the full regression graph and runs `run-tests.rkt`.
It generates eight PDF/SVG documents, retains their raw pre-quantization float
samples, checks known values (including extended RGB and sub-byte differences),
and independently inspects page structure, embedded image dimensions, surrounding
vector geometry and hyperlinks. Required Poppler/librsvg rendering checks
known semantic pixels rather than merely comparing two outputs from the same
implementation. Six GPU captures exercise float clear/solid/gradient operations
on the existing RGBA8888 targets, with separate explicit-readback counts and
rejection of float readback buffers.

Python inspector tests use explicitly synthetic files and do not execute Skia.
A source signature/layout check is not native ABI execution. The stage's source
inventory records implemented routes, not unearned platform passes. Native,
GPU and viewer flags in acceptance reports reflect the gates actually selected
and completed. Missing required dependencies fail; there is no synthetic
fallback. The bundle's delivery report states which checks ran before delivery.

### Pinned implementation sources

The source basis is `mono/skia` commit
`40f75dc0051d141913c07c20d4c19590c7da0cb7`:
`include/c/sk_canvas.h`, `sk_paint.h`, `sk_shader.h`, `sk_pixmap.h`, `sk_types.h`,
`src/core/SkPixmap.cpp`, `SkColorSpaceXformSteps.cpp`, and `SkConvertPixels.cpp`.
The existing API decisions are in [API-DESIGN-DECISIONS.md](API-DESIGN-DECISIONS.md).
