#lang scribble/manual

@(require scribble/eval
          "support/figures.rkt"
          (for-label racket/base racket/contract skia skia/matrix skia/geometry-primitives))
@(define matrix-eval (make-base-eval))
@(matrix-eval '(require skia/matrix))

@title[#:tag "skia-matrices"]{Affine Matrices}

@defmodule[skia/matrix #:no-declare]
@(declare-exporting skia skia/matrix #:use-sources (skia/matrix))

Use an affine matrix to combine translations, rotations, scales, or shears into
one reusable transform. Apply it to drawing with @racket[canvas-concat!], or
use @racket[matrix-map-point] to calculate transformed coordinates without
drawing. For a single canvas translation or rotation, the corresponding
canvas operation is usually simpler.

An @deftech{affine matrix} maps two-dimensional coordinates by a linear
transformation followed by translation. Skia represents it as an immutable,
detached Racket value with coefficients in the order
@tt{xx, yx, xy, yy, x0, y0}. The mapping is
@math{x' = xx x + xy y + x0} and @math{y' = yx x + yy y + y0}.
This order matches a six-element SVG affine transform; it is not row-major
order for a three-by-three matrix.

Affine-matrix operations are independent of native Skia. Coefficients are
rounded to IEEE single precision when stored. Mapping operations round input
coordinates and results in the same way. A computed coefficient or result
outside the numeric limits in @secref["skia-scalars"] raises an exception,
except that @racket[matrix-invert] returns
@racket[#f] when an inverse is unavailable. Matrices need neither
@racket[with-skia] nor @racket[skia-close!].

@local-table-of-contents[#:style 'immediate-only]

@section{Construction and Inspection}

@defproc[(matrix? [v any/c]) boolean?]{
Returns @racket[#t] for an affine matrix and @racket[#f] otherwise. A six-element
vector is not a matrix until converted with @racket[vector->matrix].
}

@defproc[(make-matrix [xx real? 1] [yx real? 0] [xy real? 0]
                      [yy real? 1] [x0 real? 0] [y0 real? 0]) matrix?]{
Returns an affine matrix with the given coefficients. Omitted trailing
coefficients use the displayed defaults. Singularity is permitted: a matrix
need not have an inverse to be constructed or used for drawing.

@examples[#:eval matrix-eval
(matrix->vector (make-matrix))
(matrix-map-point (make-matrix 2 0 0 3 10 20) 4 5)
]
}

@defthing[matrix-identity matrix?]{
The identity matrix, with coefficients @tt{1, 0, 0, 1, 0, 0}. It leaves
coordinates unchanged apart from the rounding performed by mapping operations.
}

@defproc[(matrix-xx [matrix matrix?]) real?]{
Returns the coefficient multiplying an input x coordinate in the output x coordinate.
}
@defproc[(matrix-yx [matrix matrix?]) real?]{
Returns the coefficient multiplying an input x coordinate in the output y coordinate.
}
@defproc[(matrix-xy [matrix matrix?]) real?]{
Returns the coefficient multiplying an input y coordinate in the output x coordinate.
}
@defproc[(matrix-yy [matrix matrix?]) real?]{
Returns the coefficient multiplying an input y coordinate in the output y coordinate.
}
@defproc[(matrix-x0 [matrix matrix?]) real?]{
Returns the horizontal translation coefficient.
}
@defproc[(matrix-y0 [matrix matrix?]) real?]{
Returns the vertical translation coefficient.
}

@defproc[(matrix->vector [matrix matrix?]) (vectorof real?)]{
Returns an immutable six-element vector in the order
@tt{xx, yx, xy, yy, x0, y0}.
}

@defproc[(vector->matrix [coefficients (vector/c real? real? real? real? real? real?)]) matrix?]{
Returns a matrix from the six coefficients in @racket[coefficients]. The input
may be mutable; later mutation of the vector does not change the matrix.
}

@section{Common Transforms}

@defproc[(matrix-translate [x real?] [y real?]) matrix?]{
Returns a translation matrix. It adds @racket[x] and @racket[y] to point
coordinates but leaves displacement vectors unchanged.
}

@defproc[(matrix-scale [x real?] [y real? x]) matrix?]{
Returns an axis-aligned scaling matrix. A negative factor reflects the
corresponding axis; zero is accepted. Omitting @racket[y] uses @racket[x] for
both axes.
}

@defproc[(matrix-rotate [radians real?]) matrix?]{
Returns a rotation about the origin. Positive angles rotate clockwise when
y increases downward. The angle and resulting sine and cosine coefficients
are rounded to single precision; arbitrary rotations are not exact.
}

@defproc[(matrix-rotate-degrees [degrees real?]) matrix?]{
Like @racket[matrix-rotate], with the angle measured in degrees. After rounding
the input angle, complete turns are removed. Quarter turns use exact zero and
unit coefficients instead of approximations to the sine and cosine.

@examples[#:eval matrix-eval
(matrix-map-point (matrix-rotate-degrees 90) 3 2)
(matrix->vector (matrix-rotate-degrees 360))
]
}

@defproc[(matrix-skew [x real?] [y real?]) matrix?]{
Returns a shear matrix with horizontal factor @racket[x] and vertical factor
@racket[y]. These are factors, not angles. An input point with coordinates
@math{u} and @math{v} maps to @math{u + x v} and @math{y u + v}.
}

@section{Composition and Inversion}

@defproc[(matrix-compose [matrix matrix?] ...) matrix?]{
Returns the product of the supplied matrices in argument order. The last
matrix acts on a point first. With no arguments, the result is
@racket[matrix-identity]. Each successive product is rounded to the stored
single-precision coefficient representation; rearranging products may change
rounding even though exact matrix multiplication is associative.

For the same two orders shown as local canvas coordinates and calls, see
@secref["skia-canvas-transforms"].

@examples[#:eval matrix-eval
(define translation (matrix-translate 10 20))
(define scaling (matrix-scale 2))
(matrix-map-point (matrix-compose translation scaling) 3 4)
(matrix-map-point (matrix-compose scaling translation) 3 4)
]
}

@racketblock[
(with-skia ([surface (make-surface 180 120 #:background 'white)]
            [paint (make-paint #:color "#326DE6")])
  (define canvas (surface-canvas surface))
  (with-canvas-state canvas
    (canvas-concat! canvas
                    (matrix-compose (matrix-translate 90 60)
                                    (matrix-rotate-degrees 25)))
    (draw-rect canvas -45 -20 90 40 paint)))
]

@reference-figure["affine-transform.png"
                  "A blue rectangle rotated about its center and translated to the middle of a white canvas."]

@defproc[(matrix-invert [matrix matrix?]) (or/c matrix? #f)]{
Returns the inverse of @racket[matrix].
Returns @racket[#f] when the determinant of the stored linear coefficients is
zero, or an inverse coefficient is outside the accepted range. The test does
not use an arbitrary near-zero tolerance. A returned inverse can still magnify
rounding errors when the original matrix is poorly conditioned.

@examples[#:eval matrix-eval
(matrix->vector (matrix-invert (matrix-translate 10 20)))
(matrix-invert (matrix-scale 0))
]
}

@section{Mapping Geometry}

@defproc[(matrix-map-point [matrix matrix?] [x real?] [y real?]) (values real? real?)]{
Returns the transformed point as two values, including the translation terms.
}

@defproc[(matrix-map-vector [matrix matrix?] [x real?] [y real?]) (values real? real?)]{
Returns the transformed displacement as two values, omitting translation.
This is appropriate for a direction or an offset, rather than a point.

@examples[#:eval matrix-eval
(matrix-map-point (matrix-translate 10 20) 3 4)
(matrix-map-vector (matrix-translate 10 20) 3 4)
]
}

@defproc[(matrix-map-rect [matrix matrix?] [x real?] [y real?]
                          [width (and/c real? (>=/c 0))]
                          [height (and/c real? (>=/c 0))])
         (values real? real? real? real?)]{
Returns the axis-aligned bounding rectangle of the four transformed corners,
as left, top, width, and height. The result bounds the transformed rectangle;
it does not preserve a rotated rectangle as an oriented shape. Width and height
must be nonnegative, and all input corners and computed results must remain
within the accepted range.

@examples[#:eval matrix-eval
(matrix-map-rect (matrix-rotate-degrees 90) 0 0 20 10)
]
}

@racketblock[
(with-skia ([surface (make-surface 420 260 #:background 'white)]
            [shape (make-path '((move 0 0) (line 35 0) (line 35 12)
                                (line 12 12) (line 12 35) (line 0 35) (close)))]
            [ghost (make-paint #:color "#D9DEE6")]
            [ink (make-paint #:color "#326DE6")]
            [grid (make-paint #:color "#D9DEE6" #:style 'stroke #:stroke-width 1)]
            [box (make-paint #:color "#E94F37" #:style 'stroke #:stroke-width 2)]
            [font (make-font #:size 10)]
            [label (make-paint #:color "#20344E")])
  (define canvas (surface-canvas surface))
  (define translation (matrix-translate 28 12))
  (define scaling (matrix-scale 1.4))
  (define (composition-panel x transform title)
    (draw-simple-text canvas title x 17 font label)
    (with-canvas-state canvas
      (canvas-translate! canvas x 35)
      (for ([n '(0 20 40 60 80)])
        (draw-line canvas n 0 n 80 grid)
        (draw-line canvas 0 n 80 n grid))
      (draw-path canvas shape ghost)
      (canvas-concat! canvas transform)
      (draw-path canvas shape ink)))
  (composition-panel 18 (matrix-compose translation scaling) "T × S: S acts first")
  (composition-panel 215 (matrix-compose scaling translation) "S × T: T acts first")
  (draw-simple-text canvas "gray = same local L; blue = composed result" 18 130 font label)
  (define bound-transform
    (matrix-compose (matrix-translate 210 195) (matrix-rotate-degrees 28)))
  (define-values (left top width height)
    (matrix-map-rect bound-transform -45 -22 90 44))
  (draw-simple-text canvas "matrix-map-rect returns an axis-aligned box" 90 145 font label)
  (with-canvas-state canvas
    (canvas-concat! canvas bound-transform)
    (draw-rect canvas -45 -22 90 44 ink))
  (draw-rect canvas left top width height box)
  (draw-simple-text canvas "red = mapped bounds, not an oriented rectangle" 85 250 font label)
  surface)
]
@reference-figure["matrix-composition-and-bounds.png"
                  "Top row: the same gray L-shaped path is transformed in two orders. Translation composed before scale leaves the blue result closer to the grid origin than scale composed before translation. Bottom: a rotated blue rectangle is enclosed by the red axis-aligned rectangle returned by matrix-map-rect."]

Matrix products act from right to left on points, which is why the two blue
shapes differ even though they use the same translation and scale.  The red
result is a bounding box for four mapped corners, not a second rotation or a
replacement for the existing canvas transform-order comparison.

@close-eval[matrix-eval]


@section[#:tag "skia-atlas-transforms"]{Atlas Transforms}

@(define atlas-eval (make-base-eval))
@(atlas-eval '(require (only-in skia/geometry-primitives
                               make-atlas-transform atlas-transform-coefficients)))

@defmodule[skia/geometry-primitives #:no-declare]
@(declare-exporting skia skia/geometry-primitives #:use-sources (skia/geometry-primitives))

An @deftech{atlas transform} is a detached immutable value representing uniform
scale, rotation, and translation. It is used for sprite placement and for the
per-glyph transforms accepted by @racket[text-blob-builder-add-transformed-run!].
It is not a six-coefficient @tech{affine matrix} and contains no native resource.

@defproc[(atlas-transform? [v any/c]) boolean?]{
Returns @racket[#t] for an atlas transform and @racket[#f] otherwise. A raw
four-element coefficient vector is not an atlas-transform value.
}

@defproc[(make-atlas-transform
          [x real?] [y real?]
          [#:scale scale (and/c real? (>=/c 0)) 1]
          [#:rotation degrees real? 0]
          [#:anchor anchor (or/c (list/c real? real?) (vector/c real? real?)) '(0 0)])
          atlas-transform?]{
Returns a transform that maps the local @racket[anchor] to coordinates
@racket[x] and @racket[y], with uniform @racket[scale] and rotation by
@racket[degrees]. Positive angles rotate clockwise in downward-positive drawing
coordinates. The scale must be nonnegative. Zero scale is accepted and
collapses local points to the target location. The anchor is copied, not
retained as a mutable input.

For angle @math{r} in radians and anchor coordinates @math{ax} and @math{ay},
the four coefficients are @math{scos = scale cos(r)},
@math{ssin = scale sin(r)}, @math{tx = x - scos ax + ssin ay}, and
@math{ty = y - ssin ax - scos ay}. This representation does not support a
nonuniform scale, general shear, or reflection.

@examples[#:eval atlas-eval
(define transform
  (make-atlas-transform 10 20
                        #:scale 2
                        #:anchor '(3 4)))
(eval:check (atlas-transform-coefficients transform)
            (vector-immutable 2.0 0.0 4.0 12.0))
]

The translation compensates for the scaled anchor, so the local point at
coordinates 3 and 4 maps to coordinates 10 and 20.
}

@defproc[(atlas-transform-coefficients [transform atlas-transform?])
          (vector/c real? real? real? real?)]{
Returns the immutable vector of coefficients in order @math{scos},
@math{ssin}, @math{tx}, and @math{ty}. They map a local point to
@math{(scos x - ssin y + tx, ssin x + scos y + ty)}. The vector is detached.
}

@close-eval[atlas-eval]
