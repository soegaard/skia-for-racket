#lang scribble/manual

@(require (for-label racket/base racket/contract skia skia/canvas-primitives skia/geometry))

@title[#:tag "skia-rounded-rectangles"]{Rounded Rectangles}

@(declare-exporting skia skia/canvas-primitives skia/geometry
                    #:use-sources (skia/canvas-primitives skia/geometry))

A @deftech{rounded rectangle} is a detached immutable specification of a rectangle
and four pairs of corner radii. It is not an owned native resource. Drawing or
path construction normalizes that specification according to Skia's rounded
rectangle rules. The stored radii are not a promise that those radii fit the bounds.

Coordinates and radius components are @tech{drawing scalar}s. Corners are ordered
top-left, top-right, bottom-right, bottom-left. The two components at each corner
are its horizontal and vertical radii. Use @racket[draw-rrect] to draw a value,
@racket[canvas-clip-rounded-rect!] to clip with one, or @racket[path-add-rrect!]
to convert its boundary to path commands.

@section{Specifications}

@defproc[(rounded-rect? [v any/c])
          boolean?]{
Returns @racket[#t] for a rounded-rectangle specification and @racket[#f] otherwise.
}

@defproc[(make-rounded-rect [x real?]
          [y real?]
          [width (and/c real? (>=/c 0))]
          [height (and/c real? (>=/c 0))]
          [#:radii radii (or/c real? list? vector?) 0])
          rounded-rect?]{
Returns a copied specification. A nonnegative real radius uses that value for
both components at every corner. Otherwise, radii must be a list or vector of
four two-element point lists or vectors, with nonnegative components.

Bounds use nonnegative dimensions and finite drawing-scalar edges. Stored bounds
reflect the native rectangle's binary32 edges; radius components are stored as
inexact values and converted on native submission. This constructor does not load
Skia or normalize oversized radii. Zero dimensions are allowed.
}

@defproc[(rounded-rect-bounds [shape rounded-rect?])
          (and/c (vector/c real? real? real? real?) immutable?)]{
Returns the stored immutable bounds as coordinates, width, and height.
}

@defproc[(rounded-rect-radii [shape rounded-rect?])
          (and/c vector? immutable?)]{
Returns an immutable vector of four immutable two-coordinate radius vectors
in top-left, top-right, bottom-right, bottom-left order. These are the stored
specification values, not necessarily the native-normalized radii.
}

@defproc[(make-empty-rounded-rect)
          rounded-rect?]{
Returns a pure specification with zero bounds and zero radii, equivalent to
@racket[(make-rounded-rect 0 0 0 0)].
}


@section{Normalization and Transformations}

These operations create temporary native rounded rectangles and copy the results
back into detached values. They require Skia, but the returned values have no
native lifetime. Inputs are unchanged. Native normalization can reduce oversized
radii and replace degenerate corners; inspect the result rather than assuming
that supplied radii were retained. Radius components and inset/outset distances
must be nonnegative after binary32 rounding. A negative input that rounds to
negative zero is accepted as zero; offsets remain signed.

@defproc[(rounded-rect-normalize [shape rounded-rect?])
          rounded-rect?]{
Returns native-normalized bounds and radii. The result is checked for native
validity and does not alias mutable native storage.

@racketblock[
(define shape (make-rounded-rect 0 0 20 10 #:radii 30))
(define normalized (rounded-rect-normalize shape))
(list (rounded-rect-radii shape) (rounded-rect-radii normalized))
]

The first value records the requested radius 30 at every corner. The second
records the radii that Skia can represent within the bounds.
}

@defproc[(rounded-rect-type [shape rounded-rect?])
          (or/c 'empty 'rect 'oval 'simple 'nine-patch 'complex)]{
Classifies the native-normalized shape. Empty has no area; rect has square
corners; oval is an ellipse; simple uses equal corner radii; nine-patch has
matching radius components along each side; complex is a remaining valid
rounded rectangle. The query classifies the normalized shape, not just the
literal radius array.
}

@defproc[(make-nine-patch-rounded-rect [x real?]
          [y real?]
          [width (and/c real? (>=/c 0))]
          [height (and/c real? (>=/c 0))]
          [left real?]
          [top real?]
          [right real?]
          [bottom real?])
          rounded-rect?]{
Returns a native-normalized specification with corner pairs left/top,
right/top, right/bottom, and left/bottom. The four side arguments are radius
components, not margins and not an image nine-patch grid. Positive bounds must
remain representable after edge rounding.
}

@defproc[(rounded-rect-offset [shape rounded-rect?]
          [dx real?]
          [dy real?])
          rounded-rect?]{
Translates the normalized shape by signed offsets and returns a new normalized
specification. The original shape is unchanged.
}

@defproc[(rounded-rect-inset [shape rounded-rect?]
          [dx real?]
          [dy real?])
          rounded-rect?]{
Insets the bounds by nonnegative horizontal and vertical distances and adjusts
the radii using native rounded-rectangle rules. Collapsed results are normalized;
the operation does not return negative dimensions.
}

@defproc[(rounded-rect-outset [shape rounded-rect?]
          [dx real?]
          [dy real?])
          rounded-rect?]{
Expands the bounds by nonnegative horizontal and vertical distances and adjusts
the radii using native rounded-rectangle rules. This is not a stroked-outline
operation; use path and paint geometry for that purpose.
}

@defproc[(rounded-rect-transform [shape rounded-rect?]
          [transform matrix?])
          (or/c rounded-rect? #f)]{
Returns the native-normalized affine image when it can be represented as a
rounded rectangle, or @racket[#f] otherwise. Not every affine transformation
preserves this representation. The operation does not silently approximate,
flatten, or rasterize an unrepresentable shape. For general affine geometry,
add the rounded rectangle to a path and use @racket[path-transform].
}
