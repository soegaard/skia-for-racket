# Perspective and general canvas matrices

`skia/projective-matrix` provides pure, immutable `matrix3?` and `matrix4?`
values. `skia/canvas-matrix` submits them to a canvas. Both modules are also
exported by `skia`. The existing `skia/matrix` module and its six-coefficient
`matrix?` type are unchanged.

## Coordinate and multiplication conventions

Public vectors use **row-major order**. Points are column vectors. A 3 x 3
matrix maps `(x y w)` to `(X Y W)`; an ordinary point uses `w = 1` and projects
to `(X/W Y/W)`. A 4 x 4 matrix maps `(x y z w)` and projects to
`(X/W Y/W Z/W)`. Canvas artwork lies in the local plane `z = 0`.

`(matrix4-compose A B)` means **A * B**, applying B first. Native canvas
concatenation means **current * local**. It preserves exporter unit scaling
and margins. Replacement discards that existing matrix, but not the clip.

In the ordinary y-down canvas, the supplied axis rotations have these signs:

```text
Rx(a): x' = x;          y' = cos(a)y - sin(a)z; z' = sin(a)y + cos(a)z
Ry(a): x' = cos(a)x + sin(a)z; y' = y;          z' = -sin(a)x + cos(a)z
Rz(a): x' = cos(a)x - sin(a)y; y' = sin(a)x + cos(a)y; z' = z
```

The rotation constructor names explicitly say **degrees**. A positive Z
rotation looks clockwise in y-down coordinates. The perspective-distance
constructor uses `W = 1 + Z/distance`: the camera is at negative Z, looking
along positive Z. There is no near/far plane API, depth buffer, lighting, or
hidden-surface removal. Drawing order is still compositing order.

## Immutable matrix values

```racket
(matrix3? value)
(make-matrix3 [m00 1] [m01 0] [m02 0]
              [m10 0] [m11 1] [m12 0]
              [m20 0] [m21 0] [m22 1])
matrix3-identity
(vector->matrix3 coefficients)
(matrix3->vector matrix)
(matrix3-ref matrix row column)

(matrix4? value)
(make-matrix4 [m00 1] [m01 0] [m02 0] [m03 0]
              [m10 0] [m11 1] [m12 0] [m13 0]
              [m20 0] [m21 0] [m22 1] [m23 0]
              [m30 0] [m31 0] [m32 0] [m33 1])
matrix4-identity
(vector->matrix4 coefficients)
(matrix4->vector matrix)
(matrix4-ref matrix row column)
```

`vector->matrix3` requires nine elements; `vector->matrix4` requires sixteen.
They copy input vectors. Inspection returns immutable vectors with no native
pointer or mutable backing storage. Indices are exact integers in the matrix's
zero-based range. These values do not have a resource lifetime and can be
used by different Racket threads.

Coefficients must be finite reals within the binary32 range. They are rounded
to native single precision when stored. Very small values can underflow to
zero. NaN, infinities, non-real values, and out-of-range coefficients are rejected.

```racket
(matrix3-compose matrix ...)
(matrix4-compose matrix ...)
(matrix3-transpose matrix)
(matrix4-transpose matrix)
(matrix3-invert matrix)
(matrix4-invert matrix)
```

Empty composition returns identity. Multiplication operates on the exact
values of the stored coefficients and rounds each returned matrix to binary32.
An unrepresentable result raises a contract error. This is not a promise of
bit-identical arithmetic to every native SIMD implementation.

Inversion uses exact elimination on the stored coefficients. It returns `#f`
when the matrix is singular or the inverse coefficients exceed the native
range. It does not use an arbitrary near-singularity epsilon. The returned
inverse is still rounded to binary32, so it need not compose to an exactly
represented identity, especially for an ill-conditioned matrix.

## Constructors for common transforms

```racket
(matrix3-perspective px py)
(matrix4-translate x y [z 0])
(matrix4-scale x [y x] [z 1])
(matrix4-rotate-x-degrees degrees)
(matrix4-rotate-y-degrees degrees)
(matrix4-rotate-z-degrees degrees)
(matrix4-perspective distance)
```

`matrix3-perspective` produces:

```text
[ 1   0   0 ]
[ 0   1   0 ]
[ px  py  1 ]
```

Thus its denominator is `1 + px*x + py*y`. Translation, scaling, and other
ordinary 2D components can be created with the existing affine constructors
and converted with `matrix->matrix3`.

`matrix4-perspective` leaves X, Y, and Z unchanged before the divide and sets
`W = 1 + Z/distance`. Distance must be positive after native rounding, and its
reciprocal must be representable. The Z scaling default is **1**, not X: the
one-argument scale is convenient for 2D artwork without changing its depth.

## Conversions: lossless conversion versus plane projection

```racket
(matrix->matrix3 affine)
(matrix3-affine? matrix)
(matrix3->matrix matrix)
(matrix->matrix4 affine)
(matrix4-affine-2d? matrix)
(matrix4->matrix matrix)
(matrix3->matrix4 matrix)
(matrix4->matrix3 matrix)
(matrix4-project-xy matrix)
```

`matrix3-affine?` recognizes a last row `(0 0 k)` with nonzero k.
`matrix3->matrix` explicitly normalizes by k, or returns `#f` if the mapping
is not affine or cannot satisfy the existing affine constructor's range.

`matrix3->matrix4` embeds all nine coefficients, preserving the Z coordinate:

```text
[ a b c ]        [ a b 0 c ]
[ d e f ]   ->   [ d e 0 f ]
[ g h i ]        [ 0 0 1 0 ]
                 [ g h 0 i ]
```

`matrix4->matrix3` returns `#f` unless the full matrix has exactly this
embedding structure. It never silently discards Z state.
`matrix4-affine-2d?` and `matrix4->matrix` are stricter: they recognize the
canonical embedded affine structure, including W's constant equal to 1.
This agrees with the existing `canvas-transform` readback contract.

**`matrix4-project-xy` is explicitly lossy.** It selects the X, Y, and W rows
and the X, Y, and constant columns, describing only the current local plane
`z = 0`. It is useful for mathematical point queries. Do not project each
operand before composing 4D transforms: discarded Z contributions can affect
the final X, Y, and W. Even an invertible 4 x 4 matrix can project to a singular
3 x 3 matrix, for example an edge-on plane.

## Homogeneous and projected queries

```racket
(matrix3-map-homogeneous matrix x y [w 1])
(matrix4-map-homogeneous matrix x y [z 0] [w 1])
(matrix3-map-point matrix x y)
(matrix4-map-point matrix x y [z 0])
(matrix3-map-rect matrix x y width height)
(matrix4-map-rect matrix x y width height)
```

Coordinate arguments are finite native-range reals and are rounded to
binary32 on input. Results are **immutable vectors of double-precision Racket
reals**, not multiple values. The old affine query API keeps its existing
multiple-value behavior.

Homogeneous queries return three or four components without division.
Projected point queries return two or three components after division, or
`#f` at `W = 0` or if the result is not finite. They divide before rounding
intermediate homogeneous results. A direction may be supplied with `w = 0`,
but its homogeneous image is not a position-independent screen-space vector;
perspective changes screen directions with position.

Rectangle queries return `(x y width height)` bounds, or `#f` if W vanishes
anywhere on the closed rectangle, including a corner or edge. Checking all
four strict W signs prevents the error of returning a finite corner box for
a rectangle that crosses infinity. With a fixed nonzero W sign, extrema are
obtained from projected corners. Zero extents are permitted; negative extents
are rejected. `matrix4-map-rect` concerns only the drawing plane `z = 0`.

These are **mathematical queries, not native visibility, clipping, hit testing,
or conservative stroke/effect bounds**. Points with negative W can have finite
mathematical images even when native drawing clips them. Values extremely
close to a horizon can be very large. Bounds do not include antialiasing,
strokes, image filters, or outward rounding for pixel coverage.

## Canvas operations and scoped state

```racket
(canvas-matrix4 canvas)
(canvas-set-matrix4! canvas matrix4)
(canvas-concat-matrix4! canvas matrix4)
(canvas-set-matrix3! canvas matrix3)
(canvas-concat-matrix3! canvas matrix3)
(call-with-canvas-matrix canvas matrix thunk #:replace? [replace? #f])
(with-canvas-matrix canvas matrix body ...)
(with-canvas-matrix canvas matrix #:replace? replace? body ...)
```

`canvas-matrix4` returns an independent snapshot of all sixteen native
coefficients. It remains usable after the canvas changes or its owner closes.
The canvas itself must be live and used on its creator thread. Expired PDF
page, SVG callback, and picture-recorder canvases are rejected normally.

Set operations **replace** the current matrix, including any physical-unit,
page-margin, or earlier authoring transform. Concat operations preserve those
transforms and multiply `current * supplied`. The 3 x 3 setters/concatenators
embed the matrix into the full 4 x 4 representation; they do not flatten an
existing 3D current matrix before concatenation.

Concatenation rejects a mathematically unrepresentable product before calling
Skia. Native arithmetic can also overflow in an intermediate calculation;
when native readback is non-finite, the previous matrix is restored and an
error is raised. A successful call leaves a finite native matrix, not a
matrix containing infinities or NaN. This check does not make ill-conditioned
arithmetic numerically exact.

A matrix scope accepts the existing affine `matrix?`, a `matrix3?`, or a
`matrix4?`. Its thunk takes zero arguments with no required keywords and may
return any number of values. It composes by default; `#:replace? #t` replaces.
The existing protected canvas-state scope restores the **full matrix and
clip**, unwinds extra saves, and performs exception cleanup. It also retains
the existing save-floor, continuation, and page/recorder lifetime guards.

The legacy `canvas-transform` remains an affine-only query. It raises an error
under a full 3D or projective matrix rather than returning six misleading
numbers. `canvas-set-transform!` still performs an explicit affine replacement.

## PDF/SVG output policy

Canonical embedded affine matrices retain the ordinary `transform` feature
and remain eligible for vector-only export. Other general matrices also emit
**`projective-transform`**, conservatively classified as `needs-raster` for
both PDF and SVG. This is a wrapper policy, not a claim that every individual
PDF primitive is incapable of being transformed by the native backend.

General matrix use is recorded in picture provenance even when a picture is
created before auditing. A later export therefore does not mistake that picture
for ordinary affine vectors. The policy is operation-conservative: installing
and then undoing a general matrix can leave the requirement in the report or
picture summary even if no drawing occurred between those operations.

Apply a projective matrix **inside** an explicit `draw-rasterized` callback:

```racket
#lang racket/base
(require skia)

(define tilt
  (matrix4-compose (matrix4-translate 150 90)
                    (matrix4-perspective 380)
                    (matrix4-rotate-y-degrees 40)
                    (matrix4-translate -150 -90)))

(define page
  (make-output-page
   360 260
   (lambda (canvas)
     (draw-rasterized
      canvas 30 40 300 180
      (lambda (raster)
        (with-canvas-matrix raster tilt
          (with-skia ([paint (make-paint #:color 'blue)])
            (draw-rect raster 30 20 240 140 paint))))
      #:scale 2))
   #:background 'white))

(save-output/audit page "tilted-card.svg" 'svg #:policy 'error #:exists 'replace)
(save-output/audit page "tilted-card.pdf" 'pdf #:policy 'error #:exists 'replace)
```

Only the bounded panel is rasterized. Surrounding document artwork and labels
can remain vectors. Bounds are supplied in the **receiving canvas's coordinate
system**; the callback's origin is reset to that panel. Ensure the projected
content and any filter padding fit inside the chosen bounds. Placing a general
matrix on the outer document canvas and rasterizing later does not resolve it:
the embedded image would still need a projective outer transformation.

Rasterization discards text and annotation semantics inside the group. Put
clickable regions on the receiving document canvas, outside the group, and
compute any projected hit regions explicitly. No automatic fallback, camera
clipping, image-density selection, or hit-region projection is installed.

## Native boundary

All canvas operations reuse the existing m119 `sk_canvas_get_matrix`,
`sk_canvas_set_matrix`, and `sk_canvas_concat` bindings. No native symbols or
C record layouts are added. The pinned bridge reinterprets `sk_matrix44_t`
as **column-major SkM44**, despite the C header's row-major-looking field names.
The Racket public vectors are row-major, so the bridge explicitly transposes
storage order. Translation X/Y/Z is at byte offsets 48/52/56; W's X/Y/Z/constant
coefficients are at 12/28/44/60. See also [the original matrix ABI audit](PATH-MATRIX-ABI.md).

The host C mirror checks offsets and packing only. Native tests independently
use old translation/skew calls, inspect new readback, and verify projected raster
coverage, so a self-consistent but transposed read/write bridge cannot pass only
by round-tripping its own mistake.

Primary pinned sources:

- [Canvas declarations](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/c/sk_canvas.h)
- [Canvas shim](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/c/sk_canvas.cpp)
- [SkM44 representation](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/core/SkM44.h)

[Validation and visual review](PROJECTIVE-TESTING.md)
