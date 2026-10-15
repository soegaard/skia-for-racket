# `skia/pict` — eager `pict` snapshots

`skia/pict` is an explicit, headless bridge from CPU Skia values to ordinary
Racket `pict`s. It is not re-exported by `skia`; require it only where a pict
consumer is needed:

```racket
(require skia skia/pict)

(image->pict image #:backing-scale 1)
(surface->pict surface #:backing-scale 1)
(picture->pict picture #:bounds #f #:raster-scale 1)
```

Every call snapshots eagerly into an independent Racket `bitmap%`. The returned
value is an ordinary `pict?`, including the upstream `pict/convert` protocol.
It may be given to `bitmap-dc%`, `skia-dc%`, record/replay contexts, or document
DC consumers. Closing or subsequently drawing into the Skia source cannot
change the returned pict.

## Pixel and size rules

`image->pict` and `surface->pict` preserve the source's physical pixels. A
`#:backing-scale` changes only the pict's logical size: a 101×51 pixel source
at scale 2 becomes a pict measuring 101/2 by 51/2. No display DPI is inferred.
The pict ascent is its logical height and its descent is zero.

`picture->pict` renders once to a transparent CPU surface. With no `#:bounds`,
it uses the picture's nominal `(0 0 picture-width picture-height)` extent; a
zero nominal extent requires an explicit positive bounds vector. An explicit
bounds value must be `#(x y width height)` with finite coordinates and positive
extents. Its vector is copied immediately. `#:raster-scale` controls only
sampling density: physical dimensions are `ceiling(width * scale)` and
`ceiling(height * scale)`, while the resulting pict still measures exactly the
requested logical width and height. The viewport is clipped to those bounds.

The bridge reads premultiplied RGBA, rearranges it to the premultiplied ARGB
expected by `bitmap%`, and does not encode/decode PNG. Alpha is preserved;
hidden RGB under fully transparent premultiplied pixels is not promised. Tagged
images are read into owned sRGB; untagged channels are copied as sRGB numerical
values. This is intentionally an 8-bit display bridge, so float/HDR sources
are converted through RGBA8888 samples.

## Limits and backend boundary

Each axis remains limited to 32768 pixels. In addition to Skia's normal RGBA
readback limit, this bridge preflights both simultaneous Racket byte buffers
(RGBA and ARGB), charging twice the pixel byte count against
`current-skia-byte-limit`.

The bridge is CPU-only. It never creates a GPU context or performs implicit
readback; detach GPU images through the existing explicit GPU APIs first.
Likewise, ordinary closed-resource, wrong-thread, and active-borrow errors are
preserved. Requiring `skia/pict` by itself neither loads Skia's native library
nor initializes a GUI.

See [`examples/pict-bridge.rkt`](../examples/pict-bridge.rkt) for a complete
small program.
