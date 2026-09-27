# CPU color filters

Require `skia/color-filters` for the additional factories, or `skia` for the full
public API. Every factory returns the existing owned `color-filter?` type. Use
`with-skia`, `skia-close!`, `make-paint #:color-filter`, and
`paint-set-color-filter!` as usual. These are native Skia effects, not a new
pixel loop or an SVG filter emitter.

## Factory reference

### `make-hsla-matrix-filter`

```racket
(make-hsla-matrix-filter matrix) ; -> color-filter?
```

`matrix` is a list or vector of exactly 20 finite C-float-representable numbers,
in row-major 4-by-5 order. It transforms `(H S L A 1)` after conversion from
unpremultiplied RGB to HSL, then converts back to RGB. Channels and offsets are
normalized numbers, **not bytes**; hue uses turns, **not degrees**. The existing
RGBA-domain `make-color-matrix-filter` is unchanged. Neither is a canvas matrix.

```racket
(define hue-third
  '(1 0 0 0 1/3
    0 1 0 0 0
    0 0 1 0 0
    0 0 0 1 0))
(with-skia ([cf (make-hsla-matrix-filter hue-third)]
            [paint (make-paint #:color 'red #:color-filter cf)])
  (draw-rect canvas 10 10 80 40 paint))
```

This shifts opaque red to green in the ordinary raster test. Input vectors are
copied. Skia stores its own float matrix; mutating the caller's vector afterward
does not change the filter. General HSL/alpha matrices are not promised to
preserve source alpha; the last matrix row controls it.

### Gamma filters

```racket
(make-linear-to-srgb-gamma-color-filter) ; -> color-filter?
(make-srgb-to-linear-gamma-color-filter) ; -> color-filter?
```

These apply transfer functions to color samples and preserve alpha. On the
untagged RGBA8 test surface, stored gray 128 becomes approximately 188 in the
first direction and 55 in the second. Composition in inverse order restores
the input within numerical/quantization tolerance.

**These filters do not assign a color-space tag, attach ICC data, perform a
gamut conversion, or replace `image-convert-color-space`.** Keep the destination
color space and the rest of the drawing pipeline in mind when composing them.
The native gamma filter unpremultiplies/re-premultiplies as needed; there is no
manual alpha division in this wrapper.

### Lookup tables

```racket
(make-table-color-filter table) ; -> color-filter?
(make-table-argb-color-filter #:alpha [alpha #f]
                             #:red   [red #f]
                             #:green [green #f]
                             #:blue  [blue #f]) ; -> color-filter?
```

A table is bytes, a list, or a vector containing exactly 256 exact bytes in
`0..255`. Normalized floats and inexact integer-looking values are rejected.
All provided tables are copied. A `#f` channel in the ARGB factory means the
native documented identity mapping. All four channels may be `#f`, producing
an identity filter; the pinned native table factory optimizes that all-null case
to a null pointer, so the wrapper materializes an equivalent owned identity
RGBA-matrix filter instead. A `#f` single table is invalid.

Tables operate on **unpremultiplied** byte channels, before re-premultiplication.
The one-table factory maps **all four components, including alpha**. For example,
`255-x` applied as a single table makes an opaque input transparent. To invert
RGB without changing alpha, use the three RGB keywords:

```racket
(define inverse (apply bytes (build-list 256 (lambda (x) (- 255 x)))))
(define invert-rgb
  (make-table-argb-color-filter #:red inverse #:green inverse #:blue inverse))
```

These are per-channel one-dimensional tables, not a 3-D color lookup table.
Byte indexing is quantized; this API makes no HDR preservation promise.

### `make-luma-color-filter`

```racket
(make-luma-color-filter) ; -> color-filter?
```

Produces black RGB with `output-alpha = input-alpha * luma(input-RGB)`.
White preserves input alpha; black becomes transparent. This is **not a grayscale
RGB conversion**. It also differs from ignoring input alpha and merely writing
luma into alpha. Use the high-contrast grayscale option or an appropriate matrix
when the desired output is opaque gray.

### `make-high-contrast-color-filter`

```racket
(make-high-contrast-color-filter #:grayscale? [grayscale? #f]
                                 #:invert-style [invert-style 'none]
                                 #:contrast [contrast 0]) ; -> color-filter?
```

`grayscale?` is a boolean. Inversion is `'none`, `'brightness`, or `'lightness`.
Contrast is a finite real in the closed interval `[-1,1]`; zero means no contrast
adjustment. The native order is grayscale, inversion, then contrast. The two
inversion modes are not equivalent: brightness inverts RGB, while lightness
inverts the HSL lightness component.

The pinned m119 implementation evaluates this effect in **linear,
unpremultiplied working values using the destination gamut**, then converts
back. Do not predict its gray/inversion results by subtracting encoded sRGB
bytes from 255. Alpha is preserved. Native code clamps contrast endpoints
slightly inward to avoid division by zero. This is a configurable visual
transformation, not an accessibility or contrast-ratio conformance checker.

The 12-byte native configuration is `(bool, enum, float)` at offsets 0, 4, and 8.
It is created only for the synchronous factory call; no borrowed configuration
pointer survives construction.

### `make-lerp-color-filter`

```racket
(make-lerp-color-filter weight filter0 filter1) ; -> color-filter?
```

`weight` is in `[0,1]`. Both filters receive the same source color; their results
are interpolated as `(1-weight)*filter0(source) + weight*filter1(source)`. Weight
zero selects the first result and weight one the second. This is **parallel
interpolation**, unlike `make-compose-color-filter outer inner`, which evaluates
`outer(inner(source))`.

Both inputs must be live `color-filter?` values on the calling Racket thread,
even at the endpoints. `#f` is not accepted; use an explicit identity matrix or
table filter. Native code retains the child references. Once construction
succeeds, the caller may close both original wrappers.

The audit conservatively preserves both child feature summaries even when the
native factory optimizes an endpoint. In particular, interpolation does not
remove the provenance of a runtime filter child.

### `make-lighting-color-filter`

```racket
(make-lighting-color-filter multiply add) ; -> color-filter?
```

Both arguments use the existing `color?` conventions. The native operation
multiplies RGB by the multiply color, adds the add color, and clamps. **Alpha
components of both argument colors are ignored; source alpha is preserved.**
This is the legacy per-channel color adjustment, not a light source, normal
map, or one of the alpha-height-field image filters.

## Ownership and composition

Factories return ordinary owned color-filter resources. Paints, composed/lerped
filters, color-filter image nodes, and recorded pictures retain their native
inputs. `paint-color-filter` returns an independently owned reference. Explicit
closure invalidates that wrapper, not already constructed native parents.
No raw pointer is exposed. Existing thread-affinity and exception cleanup rules
apply; native Skia's internal sharing does not relax Racket wrapper rules.

The table payload limit is aggregate (up to 4*256 bytes). HSLA matrix payloads
are 80 bytes and high-contrast configurations 12 bytes. These payloads respect
`current-skia-byte-limit`, but the limit is not a quota on all native/Racket heap
allocation or native shader compilation.

## PDF and SVG output

All additions retain the existing `color-filter` classification: native
expansion in PDF and explicit-fallback requirement in SVG. This pass does not
claim exact native vector serialization for any filter, including identity
settings. `draw-output-group` with `'prefer-vector` selects a bounded raster
representation for these effects on both document formats.

```racket
(draw-output-group
 canvas 20 30 240 100
 (lambda (local)
   (with-skia ([cf (make-high-contrast-color-filter #:contrast 0.25)]
               [p (make-paint #:color 'blue #:color-filter cf)])
     (draw-rounded-rect local 0 0 240 100 12 12 p)))
 #:scale 2
 #:label "contrast panel")
```

Keep semantic text and document annotations outside an effect group unless an
explicit outline or semantic-loss choice is appropriate. The output-group
implementation still rejects unknown imported content and discarded semantics.
Color effects alone do not expand geometry, so the probes use zero padding;
image filters added later can require their own padding.

## Implementation sources

The native ABI remains pinned to SkiaSharp 3.119.1, mono/skia commit
`40f75dc0051d141913c07c20d4c19590c7da0cb7`. Relevant primary sources:

- `include/c/sk_colorfilter.h`, `src/c/sk_colorfilter.cpp` — nine C factories,
  retained interpolation inputs, synchronous parameters.
- `include/c/sk_types.h`, `include/effects/SkHighContrastFilter.h`,
  `src/effects/SkHighContrastFilter.cpp` — configuration, operation order,
  linear working values, and contrast endpoint handling.
- `include/core/SkColorFilter.h`,
  `src/effects/colorfilters/SkMatrixColorFilter.cpp`,
  `src/effects/colorfilters/SkTableColorFilter.cpp` — matrix/table semantics,
  copying, and unpremultiplication.
- `include/effects/SkLumaColorFilter.h` — luma-times-alpha rather than grayscale.
- `src/effects/SkColorMatrixFilter.cpp` — lighting parameters and ignored alpha.
