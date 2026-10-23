# `skia/racket-draw` — explicit Racket Draw interoperability

`skia/racket-draw` is an opt-in, eager-copy bridge between ordinary
`racket/draw` values and Skia. It is not re-exported from `skia`, adds no
implicit conversions, and does not initialize Skia, HarfBuzz, a GUI, or a GPU
just by being required.

```racket
(require skia/racket-draw)
```

It exports exactly these operations:

- `bitmap->image`
- the unchanged `image->bitmap` and `surface->bitmap` bindings from
  `skia/bitmap`
- `color%->rgba` and `rgba->color%`
- `dc-path->skia-path` and `skia-path->dc-path`

All successful conversions are detached copies. They do not share mutable
pixel storage, native handles, or ownership with their source.

## Bitmap import

`bitmap->image` copies a Draw `bitmap%` to an owned CPU Skia image:

```racket
(bitmap->image bitmap
               #:resolution 'physical ; default; or 'logical
               #:mask 'loaded)       ; default; or #f / replacement bitmap
```

Physical mode reads the public unscaled rectangle with dimensions
`ceil(logical-width * backing-scale)` by
`ceil(logical-height * backing-scale)`. Logical mode reads at the bitmap's
logical dimensions and lets Racket Draw perform its normal resampling. The
result retains pixels only—never backing scale, DPI, source format, palette,
color profile, HDR precision, or a loaded-mask object.

The default uses the bitmap's loaded mask as alpha coverage. Use `#:mask #f`
to ignore it, or pass another same-logical-size bitmap as a replacement. In
physical mode, a differently scaled mask is sampled at source-pixel centers.
Mask coverage multiplies all premultiplied RGBA components. Monochrome source
pixels are copied as literal black and white; this is not the colorized stencil
semantics of `draw-bitmap`.

The bridge uses direct public ARGB readback and an in-memory channel reorder;
it never encodes PNG. It checks dimensions, scales, and conservative temporary
buffers against `current-skia-byte-limit` before allocating bridge buffers.

For reverse bitmap exports, `image->bitmap` and `surface->bitmap` convert
tagged sources to sRGB, matching the pict bridge. Untagged numerical samples
are copied unchanged. The result has eight-bit components and no original ICC
profile; use the raw pixel readers when destination conversion is unwanted.
GPU readback remains explicit.

## Colors

`color%->rgba` copies byte RGB values and converts alpha with
`(inexact->exact (round (* 255 alpha)))`. `rgba->color%` returns a fresh
mutable `color%` with alpha `A/255.0`. Neither operation premultiplies,
performs profile conversion, or looks up names.

## Paths

`dc-path->skia-path` copies Draw moves, lines, cubics, closures, and an
explicit `#:fill-style` (default `'odd-even`) to a fresh Skia path. It copies
geometry only, not DC state such as transforms, pens, brushes, or clips.

`skia-path->dc-path` returns two values: a fresh `dc-path%` and its Draw fill
style. A Draw path can contain closed contours and only one final open contour,
so an open Skia contour followed by another contour is rejected rather than
silently closed or reordered. Lines/cubics copy directly and quadratics are
elevated to cubics. Non-unit rational conics are rejected by default; request
a bounded vector approximation with `#:conic-subdivisions` from 0 through 5.
The power is not a geometric-error tolerance.

See the reference chapter and
[`examples/public/racket-draw.rkt`](../examples/public/racket-draw.rkt) for
runnable public-API examples.
