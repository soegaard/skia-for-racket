# Path inspection and affine matrices

Import `(require skia)`, or `"main.rkt"` from a source checkout. The pure matrix
values are also available separately from `(require skia/matrix)`.

## Matrices are values

```racket
(define m
  (matrix-compose (matrix-translate 100 60)
                  (matrix-rotate-degrees 30)
                  (matrix-scale 2 1)))
(define-values (x y) (matrix-map-point m 10 0))
```

`matrix-compose` multiplies left to right: `A * B` applies **B first, then A**.
The example scales, rotates, then translates. `canvas-concat!` changes the current
transform `C` to `C * m`. Use it inside `with-canvas-state` to preserve the caller's
transform and clip. In a shared output-page callback, this also preserves the
page-unit scale and margins. `canvas-set-transform!` deliberately replaces the
entire current transform; it is not relative to page content.

```racket
(with-canvas-state canvas
  (canvas-concat! canvas m)
  (draw-path canvas path paint))
```

`make-matrix` takes six optional positional coefficients in this order:

```text
xx yx xy yy x0 y0       (defaults: 1 0 0 1 0 0)

[ xx  xy  x0 ] [ x ]   [ xx*x + xy*y + x0 ]
[ yx  yy  y0 ] [ y ] = [ yx*x + yy*y + y0 ]
[  0   0   1 ] [ 1 ]   [         1        ]
```

The public abstraction is **2D affine**, not a projective or 3D matrix. Each
coefficient is checked and rounded to its single-precision native value.
`matrix->vector` returns an immutable vector in the six-coefficient order;
`vector->matrix` copies and validates its input. Values may be freely shared
between Racket threads. They have no native lifetime and are not `skia-resource?`.

`matrix-translate`, `matrix-scale`, `matrix-skew`, `matrix-rotate` (radians), and
`matrix-rotate-degrees` are convenience constructors. Positive rotation maps
positive x toward positive y, appearing clockwise in the default y-down canvas.
Skew arguments are shear factors, not angles. Negative and zero scales are allowed.

`matrix-invert` returns a new matrix or `#f` for a singular matrix or an inverse
outside the supported coefficient range. It does not use an arbitrary determinant
epsilon. Near-singular transforms remain numerically sensitive. Pure calculations
round results to single precision; this does not promise bit-for-bit equality
with every native SIMD arithmetic path.

`matrix-map-point` and `matrix-map-vector` return two values. The latter ignores
translation. `matrix-map-rect` returns `(values x y width height)` for the
axis-aligned bounds of all four transformed corners. It does not preserve an
oriented rectangle as an oriented shape. Non-finite/unrepresentable results raise.

## Inspecting a path

```racket
(with-skia ([p (make-path '((move 0 0)
                           (line 80 0)
                           (conic 100 40 80 80 0.5)
                           (close)))])
  (for ([segment (in-path-segments p #:mode 'raw)])
    (printf "~a: ~s; weight ~s\n"
            (path-segment-verb segment)
            (path-segment-points segment)
            (path-segment-conic-weight segment))))
```

Each immutable `path-segment?` describes a stored or iterator-generated operation.
The points are immutable lists of `(list x y)` pairs, already copied from native
storage. Verb-specific point counts are:

| Verb | Points |
|---|---|
| `move` | Destination point |
| `line` | Start, end |
| `quad` | Start, control, end |
| `conic` | Start, control, end; separate conic weight |
| `cubic` | Start, first control, second control, end |
| `close` | Empty list |

The weight is `#f` except for `conic`. `path-segment-closing-line?` identifies a
line synthesized by normal iteration to close a contour; it is always false for
raw iteration. A `close` record is not itself a closing-line record.

`path-segments` returns the complete list. `in-path-segments` returns a sequence
suitable for `for` and `for/list`, but takes its snapshot **at the call**, not
at the first iteration. Sequences are reusable. They remain valid when the source
is mutated, transformed, or closed, including before the first iteration. No
native iterator pointer, callback, or deferred source access escapes.

`#:mode 'normal` is the default. Skia may synthesize closing lines and normalize
some degenerate data. `#:force-closed? #t` views open contours as closed without
changing the path. `#:mode 'raw` exposes stored verbs; forcing closure with raw
mode is an error. Raw inspection recovers Skia's stored geometry, not the author's
original relative commands or higher-level rectangle/oval construction calls.

`path-contours` accepts the same options and returns immutable `path-contour?`
records. `path-contour-segments` supplies each group, and
`path-contour-closed?` reports whether its returned sequence ends with `close`.
Raw mode preserves stored move-only contours. Normal mode follows the native
iterator's handling of them.

Snapshots enforce `current-skia-byte-limit` using a cumulative logical budget of
16 bytes per segment plus 8 bytes per returned point. This is not a measurement
of total Racket heap use. Iteration has a fixed four-point native scratch buffer.

## Rebuilding and transforming

```racket
(with-skia ([rebuilt (make-path (path->commands original)
                               #:fill-rule (path-fill-rule original))]
            [shifted (path-transform original (matrix-translate 50 0))])
  (draw-path canvas rebuilt paint)
  (draw-path canvas shifted paint))
```

`path->commands` always uses raw iteration and returns absolute commands accepted
by `make-path`, including conic weights and `close`. Fill rule is separate; pass
it as shown. `path-transform` returns an independently owned path and preserves
fill rule. `path-transform!` changes the existing path. The measurement layer
continues to retain its own source snapshot.

A transformed path and a transformed canvas are not interchangeable for every
paint: **transforming a path does not transform the paint or scale stroke widths**.
Transforming the canvas transforms the complete drawing operation. The visual
probe compares filled shapes, for which the two geometries agree.

## Measurement frames

```racket
(define frame (path-measure-matrix measure distance))
(when frame
  (with-canvas-state canvas
    (canvas-concat! canvas frame)
    (draw-path canvas arrow paint)))
```

`#:mode` is `'position+tangent` by default, or `'position` / `'tangent`.
The combined matrix translates the origin to the sampled point and aligns its
local x-axis with the unit tangent. Distance must be finite and nonnegative;
Skia clamps a distance beyond the current contour's length to its endpoint.
Empty/zero-length contours return `#f`. The current contour is controlled by the
existing `path-measure-next-contour!`; this function does not advance it.

## Shader-local matrices

`(shader-with-local-matrix shader matrix)` returns a new owned shader, retaining
the source natively. The caller may close its original wrapper afterward. The
matrix changes the shader's sampling coordinates rather than the drawn geometry.
Chaining this operation composes with existing shader-local transforms according
to Skia's native semantics; it does not destructively edit the original shader.

The pinned SVG serializer does **not** reliably serialize shader-local matrices.
Use `draw-rasterized` for that group when exporting to SVG. This release's shader
panel does exactly that. Canvas affine transforms and transformed paths remain
ordinary vector operations in SVG and PDF. General perspective/3D transforms,
SVG shader-local repair, advanced filter families, and GPU contexts are not part
of this API.

## Validation

Run `RACKET="/Applications/Racket v9.3.0.2/bin/racket" bash tools/validate-path-matrix.sh`.
It compiles every `tests/*.rkt` file using the selected Racket's `raco` module,
including all suites loaded dynamically by the test runner. It never silently
clears caches and never launches a separate PATH-selected `raco` executable.

The probe writes `output/path-matrix-0.24.pdf`, three SVGs, three independently
drawn raster-reference PNGs, and `output/path-matrix-0.24.review.html`. The first
two SVGs should contain no embedded images; the shader page contains exactly one
1220-by-212 PNG. The inspector checks this structure, not rendered appearance.
Compare actual browser SVG and PDF-viewer output with the reference PNGs.
