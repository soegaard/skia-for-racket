#lang scribble/manual

@(require scribble/eval
          "support/figures.rkt"
          (for-label racket/base racket/contract skia skia/projective-matrix skia/canvas-matrix))

@(define projective-eval (make-base-eval))
@(projective-eval '(require skia/projective-matrix))

@title[#:tag "skia-projective-matrices"]{Projective Matrices}

@defmodule[skia/projective-matrix #:no-declare]
@(declare-exporting skia skia/projective-matrix #:use-sources (skia/projective-matrix))

Use projective matrices for perspective effects, such as making a flat drawing
appear to recede into the distance. Apply a matrix to later drawing with
@racket[canvas-concat-matrix3!] or @racket[canvas-concat-matrix4!]. For ordinary
translation, rotation, scaling, and shearing, the simpler
@seclink["skia-matrices"]{affine matrices} are sufficient. A projective canvas
transform does not provide a complete 3D renderer.

The immutable Racket structures @deftech{matrix3} and @deftech{matrix4} store
three by three and four by four matrices. They are distinct from the six-coefficient
@tech{affine matrix} type. Public coefficient vectors are row-major, and matrices
multiply column vectors. Composition applies the rightmost operand first.

Coefficients and mapping inputs must be finite reals in the full @tech{binary32} range,
from -3.4028234663852886e38 through 3.4028234663852886e38, and are rounded to
that precision on entry. This range is slightly wider than the ordinary @tech{drawing scalar}
range. New matrix results are also rounded. Constructors and composition
operations raise an exception if a coefficient is nonfinite or lies outside
this range.
The inversion functions instead return @racket[#f] if the matrix is singular
or an inverse coefficient would lie outside the range.
Mapping queries return immutable vectors whose coordinates are
double-precision flonums, or @racket[#f] when a finite result is unavailable.

These values and their arithmetic do not load Skia. Arithmetic uses the exact
values of the stored coefficients to avoid introducing a singularity tolerance.
This does not promise bit-for-bit equality with native canvas matrix arithmetic.

@local-table-of-contents[#:style 'immediate-only]

@section{Three-by-Three Matrices}

@defproc[(matrix3? [v any/c])
          boolean?]{
Returns @racket[#t] for a three by three matrix and @racket[#f] otherwise.
}

@defproc[(make-matrix3 [a real? 1]
          [b real? 0]
          [c real? 0]
          [d real? 0]
          [e real? 1]
          [f real? 0]
          [g real? 0]
          [h real? 0]
          [i real? 1])
          matrix3?]{
Returns a matrix with the supplied row-major coefficients. The first row is
@racket[a], @racket[b], @racket[c]; the second is @racket[d], @racket[e],
@racket[f]; the third is @racket[g], @racket[h], @racket[i]. With no arguments,
the result is the identity. Every omitted suffix uses the displayed defaults.
}

@defthing[matrix3-identity matrix3?]{
The immutable three by three identity matrix.
}

@defproc[(vector->matrix3 [coefficients vector?])
          matrix3?]{
Copies exactly nine row-major coefficients into a new matrix. Later mutation
of the input vector does not change the result.
}

@defproc[(matrix3->vector [matrix matrix3?])
          (and/c vector? immutable?)]{
Returns the immutable nine-coefficient row-major vector.
}

@defproc[(matrix3-ref [matrix matrix3?]
          [row (integer-in 0 2)]
          [column (integer-in 0 2)])
          real?]{
Returns the coefficient at the zero-based row and column. Indices are not
wrapped.
}

@defproc[(matrix3-compose [matrix matrix3?]
          ...)
          matrix3?]{
Returns the left-to-right matrix product, applying the rightmost transform
first to a point. Zero arguments return the identity. Each multiplication uses
exact products and sums of its stored inputs, then rounds the resulting matrix
to @tech{binary32} before the next multiplication.
}

@defproc[(matrix3-transpose [matrix matrix3?])
          matrix3?]{
Returns the matrix with its rows and columns interchanged.
}

@defproc[(matrix3-invert [matrix matrix3?])
          (or/c matrix3? #f)]{
Returns the inverse, or @racket[#f] when the stored matrix is singular
or any inverse coefficient is outside the finite @tech{binary32} range. Singularity is
checked exactly using the stored, rounded matrix values; no tolerance is used.
}

@defproc[(matrix3-perspective [px real?]
          [py real?])
          matrix3?]{
Returns the identity with its last row replaced by @racket[px], @racket[py], 1.
Mapping coordinates @racket[x] and @racket[y] divides each by
@racket[(+ 1 (* px x) (* py y))]. This is a projective mapping, not a camera
with a near plane, far plane, or visibility test.

@examples[#:eval projective-eval
 (define perspective (matrix3-perspective 1 0))
 (eval:check (matrix3-map-point perspective 1 2) #(0.5 1.0))
 (eval:check (matrix3-map-point perspective -1 2) #f)
 (eval:check (matrix3-map-rect perspective -2 0 2 1) #f)]

The point at x = -1 lies on the projective horizon. The rectangle crosses that
horizon, so four independently projected corners would not provide a finite bound.
}

@defproc[(matrix3-affine? [matrix matrix3?])
          boolean?]{
Reports whether the bottom row has zero first and second coefficients and a
nonzero third coefficient. Such a matrix describes an affine mapping after
homogeneous division, even when that third coefficient is not 1.
}

@defproc[(matrix->matrix3 [matrix matrix?])
          matrix3?]{
Embeds a six-coefficient affine matrix into homogeneous coordinates.
}

@defproc[(matrix3->matrix [matrix matrix3?])
          (or/c matrix? #f)]{
Returns an affine matrix after dividing by the nonzero bottom-right coefficient,
or @racket[#f] if the matrix is not affine or the normalized coefficients exceed
the ordinary affine constructor's range. The input is unchanged.
}

@defproc[(matrix3-map-homogeneous [matrix matrix3?]
          [x real?]
          [y real?]
          [w real? 1])
          (or/c #f (and/c (vector/c real? real? real?) immutable?))]{
Returns the product with the homogeneous vector, without dividing by its last
coordinate. A zero or negative resulting homogeneous coordinate is allowed.
The result is @racket[#f] only when a finite binary64 result is unavailable.
}

@defproc[(matrix3-map-point [matrix matrix3?]
          [x real?]
          [y real?])
          (or/c #f (and/c (vector/c real? real?) immutable?))]{
Maps a point with input homogeneous coordinate 1 and divides by the resulting
homogeneous coordinate. A zero divisor or nonfinite projected coordinate yields
@racket[#f]. A negative divisor is allowed; the query does not perform visibility culling.
}

@defproc[(matrix3-map-rect [matrix matrix3?]
          [x real?]
          [y real?]
          [width real?]
          [height real?])
          (or/c #f (and/c (vector/c real? real? real? real?) immutable?))]{
Returns finite axis-aligned bounds of the projected rectangle, or @racket[#f]
when its homogeneous divisor reaches or crosses zero or a finite result cannot
be represented. All four corner divisors must have the same strict sign.
Rounded widths and heights must be nonnegative; corner sums must remain valid
mapping inputs. Zero extents are allowed;
the result is not a paint, clip, or perspective-visibility calculation.
}

@section{Four-by-Four Matrices}

@defproc[(matrix4? [v any/c])
          boolean?]{
Returns @racket[#t] for a four by four matrix and @racket[#f] otherwise.
}

@defproc[(make-matrix4 [a real? 1]
          [b real? 0]
          [c real? 0]
          [d real? 0]
          [e real? 0]
          [f real? 1]
          [g real? 0]
          [h real? 0]
          [i real? 0]
          [j real? 0]
          [k real? 1]
          [l real? 0]
          [m real? 0]
          [n real? 0]
          [o real? 0]
          [p real? 1])
          matrix4?]{
Returns the matrix of sixteen row-major coefficients. Successive groups of
four arguments form successive rows. With no arguments the result is identity;
all optional suffixes use the displayed defaults.
}

@defthing[matrix4-identity matrix4?]{
The immutable four by four identity matrix.
}

@defproc[(vector->matrix4 [coefficients vector?])
          matrix4?]{
Copies exactly sixteen row-major coefficients into a new matrix. Later
mutation of the input vector does not change the result.
}

@defproc[(matrix4->vector [matrix matrix4?])
          (and/c vector? immutable?)]{
Returns the immutable sixteen-coefficient row-major vector.
}

@defproc[(matrix4-ref [matrix matrix4?]
          [row (integer-in 0 3)]
          [column (integer-in 0 3)])
          real?]{
Returns the coefficient at the zero-based row and column.
}

@defproc[(matrix4-compose [matrix matrix4?]
          ...)
          matrix4?]{
Returns the matrix product, applying the rightmost operand first. Zero
arguments return identity. The arithmetic and rounding rules are the same as
for @racket[matrix3-compose].
}

@defproc[(matrix4-transpose [matrix matrix4?])
          matrix4?]{
Returns the matrix with rows and columns interchanged.
}

@defproc[(matrix4-invert [matrix matrix4?])
          (or/c matrix4? #f)]{
Returns the inverse, or @racket[#f] for a singular matrix or an inverse whose
coefficients exceed the finite @tech{binary32} range. No singularity epsilon is used.
}

@defproc[(matrix4-translate [x real?]
          [y real?]
          [z real? 0])
          matrix4?]{
Returns a translation in three dimensions. The optional z translation defaults
to zero; it is not silently discarded from the stored matrix.
}

@defproc[(matrix4-scale [x real?]
          [y real? x]
          [z real? 1])
          matrix4?]{
Returns a three-dimensional scale. Omitting @racket[y] uses @racket[x], while
omitting @racket[z] uses 1. Zero and negative scales are allowed.
}

@defproc[(matrix4-rotate-x-degrees [degrees real?])
          matrix4?]{
Returns a rotation around the x-axis. Angles follow the affine degree
normalization, including exact quarter turns. Constructing the matrix does not
install camera or depth-buffer state.
}

@defproc[(matrix4-rotate-y-degrees [degrees real?])
          matrix4?]{
Returns a rotation around the y-axis. Angles follow the affine degree
normalization, including exact quarter turns. Constructing the matrix does not
install camera or depth-buffer state.
}

@defproc[(matrix4-rotate-z-degrees [degrees real?])
          matrix4?]{
Returns a rotation around the z-axis. Angles follow the affine degree
normalization, including exact quarter turns. Constructing the matrix does not
install camera or depth-buffer state.
}

@defproc[(matrix4-perspective [distance (and/c real? (>/c 0))])
          matrix4?]{
Returns a matrix mapping homogeneous coordinates x, y, z, 1 to x, y, z,
@racket[(+ 1 (/ z distance))]. The distance must remain positive when rounded to
@tech{binary32}, and its reciprocal must fit in that format's finite range.
The camera interpretation is at z = -distance looking along positive z.
No depth buffer or near/far clipping planes are established.
}

@defproc[(matrix4-affine-2d? [matrix matrix4?])
          boolean?]{
Reports whether the matrix has the strict two-dimensional affine embedding:
no z coupling or translation, unit z scale, and bottom row 0, 0, 0, 1. This is
stricter than asking whether its projection onto z = 0 happens to be affine.
}

@defproc[(matrix->matrix4 [matrix matrix?])
          matrix4?]{
Embeds an affine matrix into four-dimensional homogeneous coordinates,
preserving a unit z axis.
}

@defproc[(matrix4->matrix [matrix matrix4?])
          (or/c matrix? #f)]{
Returns the affine matrix only for the strict two-dimensional embedding and
representable ordinary affine coefficients. Otherwise returns @racket[#f].
Use an explicit projection when discarding three-dimensional information is intended.
}

@defproc[(matrix3->matrix4 [matrix matrix3?])
          matrix4?]{
Embeds the projective x/y mapping into four by four storage with a separate
unit z axis. Perspective coefficients become the x/y coefficients of the last row.
}

@defproc[(matrix4->matrix3 [matrix matrix4?])
          (or/c matrix3? #f)]{
Returns the three by three matrix only when the input is a lossless embedding
of that representation: there is no z coupling, z scale is 1, and z translation
is zero. Otherwise returns @racket[#f]. The accepted result can still contain x/y perspective.
}

@defproc[(matrix4-project-xy [matrix matrix4?])
          matrix3?]{
Extracts the x/y homogeneous mapping on the plane z = 0. This is an explicitly
lossy operation: z-related coefficients are discarded whether or not the full
matrix is a two-dimensional embedding. It must not be substituted for
@racket[matrix4->matrix3] when lossless conversion is required.
}

@defproc[(matrix4-map-homogeneous [matrix matrix4?]
          [x real?]
          [y real?]
          [z real? 0]
          [w real? 1])
          (or/c #f (and/c (vector/c real? real? real? real?) immutable?))]{
Returns the homogeneous product without division, in an immutable vector of
four coordinates. The result may have zero or negative w. Returns @racket[#f]
if a finite binary64 result is unavailable.
}

@defproc[(matrix4-map-point [matrix matrix4?]
          [x real?]
          [y real?]
          [z real? 0])
          (or/c #f (and/c (vector/c real? real? real?) immutable?))]{
Returns three projected coordinates after homogeneous division. A zero divisor
or nonfinite result yields @racket[#f]; a negative divisor is not rejected as
being behind a camera.
}

@defproc[(matrix4-map-rect [matrix matrix4?]
          [x real?]
          [y real?]
          [width real?]
          [height real?])
          (or/c #f (and/c (vector/c real? real? real? real?) immutable?))]{
Maps a rectangle in the plane z = 0 using @racket[matrix4-project-xy] and
@racket[matrix3-map-rect]. The same horizon and finite-bound checks apply.
This is not a bounding-volume operation for a three-dimensional box.
}

@racketblock[
(with-skia ([surface (make-surface 300 190 #:background 'white)]
            [grid (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 1)]
            [axis (make-paint #:color "#E94F37" #:style 'stroke #:stroke-width 3)]
            [marker (make-paint #:color "#7D5BA6")]
            [font (make-font #:size 10)]
            [label (make-paint #:color "#20344E")])
  (define canvas (surface-canvas surface))
  (define tilt
    (matrix4-compose (matrix4-translate 150 105 0)
                     (matrix4-perspective 420)
                     (matrix4-rotate-y-degrees 38)
                     (matrix4-rotate-x-degrees -14)
                     (matrix4-translate -70 -45 40)))
  (draw-simple-text canvas "matrix4-projected asymmetric grid" 68 17 font label)
  (with-canvas-matrix canvas tilt
    (for ([x (in-range 0 141 20)]) (draw-line canvas x 0 x 90 grid))
    (for ([y (in-range 0 91 15)]) (draw-line canvas 0 y 140 y grid))
    (draw-line canvas 0 0 140 90 axis)
    (draw-circle canvas 18 18 6 marker))
  (draw-simple-text canvas "purple corner marker prevents mirror ambiguity" 35 175 font label)
  surface)
]
@reference-figure["matrix4-projected-grid.png"
                  "An asymmetric blue grid with a thick red diagonal and a purple corner marker is tilted by a 4 by 4 canvas matrix. The finite projection narrows the far edge without crossing a horizon."]

This projects the plane carrying the grid.  It does not set up a 3D camera,
depth buffer, visibility sorting, or clipping planes.


@section[#:tag "skia-canvas-projective-matrix"]{Canvas Matrix State}

@defmodule[skia/canvas-matrix #:no-declare]
@(declare-exporting skia skia/canvas-matrix #:use-sources (skia/canvas-matrix))

These operations read or change the full native canvas matrix. They require
an active borrowed canvas and follow its owning thread and GPU-context rules.
They do not add a depth buffer, convert a path to projective coordinates, or
promise that PDF or SVG preserves a perspective transformation.

@defproc[(canvas-matrix4 [canvas canvas?])
          matrix4?]{
Returns the full native canvas matrix as a @tech{matrix4} value. A
nonfinite native matrix cannot be represented and raises an exception.
}

@defproc[(canvas-set-matrix3! [canvas canvas?]
          [matrix matrix3?])
          void?]{
Replaces the canvas matrix. The supplied matrix is copied into native state;
later value reuse does not borrow the canvas.
The three by three value is embedded with @racket[matrix3->matrix4].
}

@defproc[(canvas-concat-matrix3! [canvas canvas?]
          [matrix matrix3?])
          void?]{
Concatenates the matrix as current times local, so the supplied transform
acts first on subsequently drawn local geometry. The exact product is checked
before mutation. Native multiplication still uses native precision; if it
produces a nonfinite matrix, the previous transform is restored and an exception
is raised. A successful finite product need not equal the pure matrix product bit for bit.
The three by three value is embedded with @racket[matrix3->matrix4].
}

@defproc[(canvas-set-matrix4! [canvas canvas?]
          [matrix matrix4?])
          void?]{
Replaces the canvas matrix. The supplied matrix is copied into native state;
later value reuse does not borrow the canvas.
}

@defproc[(canvas-concat-matrix4! [canvas canvas?]
          [matrix matrix4?])
          void?]{
Concatenates the matrix as current times local, so the supplied transform
acts first on subsequently drawn local geometry. The exact product is checked
before mutation. Native multiplication still uses native precision; if it
produces a nonfinite matrix, the previous transform is restored and an exception
is raised. A successful finite product need not equal the pure matrix product bit for bit.
}

@racketblock[
(with-skia ([surface (make-surface 180 110 #:background 'white)]
            [paint (make-paint #:color "#326DE6")])
  (define canvas (surface-canvas surface))
  (with-canvas-matrix canvas
      (make-matrix3 1 0 25
                    0 1 20
                    0.004 0 1)
    (draw-rect canvas 0 0 110 60 paint)))
]

@reference-figure["projective-transform.png"
                  "A blue quadrilateral narrowed toward the right by an x-dependent projective transform on a white canvas."]

@defproc[(call-with-canvas-matrix [canvas canvas?]
          [matrix (or/c matrix? matrix3? matrix4?)]
          [thunk (-> any)]
          [#:replace? replace? boolean? #f])
          any]{
Calls the zero-argument function under a protected canvas-state scope.
By default the matrix is concatenated; a true @racket[replace?] replaces it.
The callback cannot require keyword arguments, and its return values are preserved.

Transform, clip, and save-stack state are restored on normal return or escape.
The protected save floor and continuation barrier are those of
@racket[call-with-canvas-state]. Drawing already performed is not rolled back.

@racketblock[
(with-skia ([surface (make-surface 20 20)]
            [inside (make-paint #:color 'red)]
            [restored (make-paint #:color 'blue)])
  (define canvas (surface-canvas surface))
  (with-canvas-matrix canvas (matrix4-translate 5 6)
    (draw-rect canvas 0 0 4 3 inside))
  (draw-rect canvas 0 0 4 3 restored)
  (equal? (canvas-matrix4 canvas) matrix4-identity))
]

@reference-figure["canvas-matrix-scope.png"
                  "An actual transparent 20-by-20 canvas enlarged with nearest-neighbor sampling. The blue 4-by-3 mark is drawn after the scope at the restored origin; the red 4-by-3 mark is drawn inside the matrix scope at offset (5,6)."]

The enclosing rectangle is only the enlarged-target boundary. It is not canvas geometry.

The matrix is identity after the scope, while both drawn rectangles remain.
}

@defform[(with-canvas-matrix canvas-expr matrix-expr option ... body ...+)
         #:grammar [(option (code:line #:replace? replace?-expr))]]{
Like @racket[call-with-canvas-matrix], with the nonempty body supplying the callback.
The optional @racket[#:replace?] clause appears before the body, at most once.
The body may contain internal definitions and must end with an expression.
}

@close-eval[projective-eval]
