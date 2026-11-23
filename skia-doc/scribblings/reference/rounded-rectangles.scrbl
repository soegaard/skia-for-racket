#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia))

@title[#:tag "skia-rounded-rectangles"]{Rounded Rectangles}

@(declare-exporting skia)

Use a rounded-rectangle value when corners need different radii, or when the
same rounded boundary will be used for drawing, clipping, and path
construction. For a single drawing operation with the same radii at every
corner, use the coordinate-based form of @racket[draw-rounded-rect] without
creating a separate value. For path construction with shared corner radii,
@racket[path-add-rounded-rect!] also accepts coordinates directly.

A @deftech{rounded rectangle} is an immutable Racket structure containing a
rectangle and four pairs of corner radii. Drawing and path construction use
@seclink["skia-rounded-rectangle-normalization"]{Skia's normalization rules}
to adjust the bounds and radii when needed. The stored radii need not fit the bounds.

Corners are ordered top-left, top-right, bottom-right, bottom-left. The two
components at each corner
are its horizontal and vertical radii. Use @racket[draw-rounded-rect] to draw a value,
@racket[canvas-clip-rounded-rect!] to clip with one, or @racket[path-add-rounded-rect!]
to convert its boundary to path commands.

@section{Drawing}

@defproc*[([(draw-rounded-rect [canvas canvas?]
                              [shape rounded-rect?]
                              [paint paint?]) void?]
           [(draw-rounded-rect [canvas canvas?] [x real?] [y real?]
                               [width (and/c real? (>=/c 0))]
                               [height (and/c real? (>=/c 0))]
                               [radius-x (and/c real? (>=/c 0))]
                               [radius-y (and/c real? (>=/c 0))]
                               [paint paint?]) void?])]{
Draws a rounded rectangle. The paint selects filling, stroking, or both.

The first form takes a @tech{rounded rectangle}, normally created with
@racket[make-rounded-rect]. Use it when corners need different radii or when
the same shape is also used for clipping or path construction.

The second form takes the rectangle's position and size directly. Its
@racket[radius-x] and @racket[radius-y] apply to all four corners. The width,
height, and radii must be nonnegative; the computed right and bottom
coordinates must also be in range.

Both forms use @seclink["skia-rounded-rectangle-normalization"]{Skia's
normalization rules}: overlapping radii are scaled to fit, and a corner
with a zero radius component becomes square.
}

@racketblock[
(with-skia ([surface (make-surface 160 90 #:background 'white)]
            [paint (make-paint #:color "#326DE6")])
  (define shape
    (make-rounded-rect 20 15 120 60
                       #:radii '((24 24) (8 8) (24 8) (8 24))))
  (draw-rounded-rect (surface-canvas surface) shape paint))
]

@reference-figure["rounded-rect.png"
                  "A blue rounded rectangle with four visibly different corner-radius pairs."]

@section{Path Construction}

@defproc*[([(path-add-rounded-rect! [path skia-path?]
                                  [shape rounded-rect?]
                                  [#:direction direction (or/c 'cw 'ccw) 'cw]
                                  [#:start-index start (integer-in 0 7) 0]) void?]
           [(path-add-rounded-rect! [path skia-path?] [x real?] [y real?]
                                   [width (and/c real? (>=/c 0))]
                                   [height (and/c real? (>=/c 0))]
                                   [radius-x (and/c real? (>=/c 0))]
                                   [radius-y (and/c real? (>=/c 0))]
                                   [#:direction direction (or/c 'cw 'ccw) 'cw]) void?])]{
Appends a closed rounded rectangle to @racket[path], leaving its existing
contours in place.

The first form takes a @tech{rounded rectangle}, normally created with
@racket[make-rounded-rect]. Use it for different radii at each corner, to reuse
a shape, or to choose the contour's starting point with @racket[#:start-index].

The second form takes the rectangle's position and size directly. Its
@racket[radius-x] and @racket[radius-y] apply to all four corners. The width,
height, and radii must be nonnegative; the computed right and bottom
coordinates must also be in range.

Both forms use @seclink["skia-rounded-rectangle-normalization"]{Skia's
normalization rules}: overlapping radii are scaled to fit, and a corner
with a zero radius component becomes square. The @racket['cw] and
@racket['ccw] directions select clockwise and counterclockwise winding in
the initial downward-y coordinate system.

Only the value form accepts @racket[#:start-index]. Indices 0 through 7
select the boundary's tangent points in clockwise order: the top edge's
left and right points, the right edge's top and bottom points, the bottom
edge's right and left points, and the left edge's bottom and top points.
Direction changes traversal, not this indexing convention. An out-of-range
index raises an exception; it is not reduced modulo eight. Supplying
@racket[#:start-index] with the coordinate form also raises an exception.

The two forms can start the contour at different points. Use the value
form with an explicit start index when the starting point matters, for
example when aligning a dashed stroke.
}

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
Creates a rounded rectangle with its upper-left corner at
@math{(x, y)} and the given width and height.

A single radius supplies both the horizontal and vertical radius at every
corner. Alternatively, supply a list or vector of four radius pairs, ordered
top-left, top-right, bottom-right, bottom-left. Each pair is a two-element list
or vector.

Width, height, and radii must be nonnegative; zero is allowed.

The constructor preserves oversized radii. When the shape is used for drawing,
clipping, or path construction, Skia adjusts them to fit the rectangle according
to its @seclink["skia-rounded-rectangle-normalization"]{normalization rules}.
}

@defproc[(rounded-rect-bounds [shape rounded-rect?])
          (and/c (vector/c real? real? real? real?) immutable?)]{
Returns the stored immutable bounds as coordinates, width, and height.
}

@defproc[(rounded-rect-radii [shape rounded-rect?])
          (and/c vector? immutable?)]{
Returns the radii for the four corners, in top-left, top-right, bottom-right,
bottom-left order.

The result is an immutable vector containing four immutable two-coordinate
vectors. These are the stored specification values, which may differ from the
radii used after normalization.
}

@defproc[(make-empty-rounded-rect)
          rounded-rect?]{
Equivalent to @racket[(make-rounded-rect 0 0 0 0)].
}


@section[#:tag "skia-rounded-rectangle-normalization"]{Normalization and Transformations}

These operations require Skia and return new rounded-rectangle values.
Normalization adjusts bounds and corner radii according to Skia's rounded-rectangle
rules. It can reduce oversized radii and replace degenerate corners; inspect
the result rather than assuming that the supplied radii are unchanged.
Radius components and inset/outset distances must be nonnegative after @tech{binary32}
rounding. A negative input that rounds to
negative zero is accepted as zero; offsets remain signed.

@defproc[(rounded-rect-normalize [shape rounded-rect?])
          rounded-rect?]{
Returns a new rounded rectangle with bounds and corner radii adjusted according
to Skia's rounded-rectangle rules. An invalid result from Skia raises an exception.

@racketblock[
(define shape (make-rounded-rect 0 0 20 10 #:radii 30))
(define normalized (rounded-rect-normalize shape))
(list (rounded-rect-radii shape) (rounded-rect-radii normalized))
]

The first value records the requested radius 30 at every corner. The second
records the radii that Skia can represent within the bounds.
}

@racketblock[
(with-skia ([surface (make-surface 180 100 #:background 'white)]
            [paint (make-paint #:color "#326DE6")])
  (define normalized
    (rounded-rect-normalize (make-rounded-rect 25 20 130 60 #:radii 80)))
  (draw-rounded-rect (surface-canvas surface) normalized paint))
]
@reference-figure["rounded-rect-normalized.png"
                  "A blue rounded rectangle after oversized corner radii have been normalized to fit its bounds."]

@defproc[(rounded-rect-type [shape rounded-rect?])
          (or/c 'empty 'rect 'oval 'simple 'nine-patch 'complex)]{
Classifies the shape after normalization:

@itemlist[
 @item{@racket['empty]: no area.}
 @item{@racket['rect]: a rectangle with square corners.}
 @item{@racket['oval]: an ellipse.}
 @item{@racket['simple]: the same horizontal/vertical radius pair at all four
       corners. The horizontal and vertical radii may differ.}
 @item{@racket['nine-patch]: matching horizontal radius components on each
       vertical side and matching vertical radius components on each horizontal side.}
 @item{@racket['complex]: a valid rounded rectangle that does not fit the
       preceding categories.}]

The result describes the normalized shape, not just the supplied radii.
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
Constructs a rounded rectangle with corner pairs left/top, right/top,
right/bottom, and left/bottom, and returns its normalized form. The four side
arguments are radius components, not margins and not an image nine-patch grid.
Positive widths and heights must remain positive after edge rounding.

Each radius component must be nonnegative after the rounding described above;
otherwise, the function raises an exception.
}

@racketblock[
(with-skia ([surface (make-surface 180 100 #:background 'white)]
            [paint (make-paint #:color "#326DE6")])
  (define shape (make-nine-patch-rounded-rect 20 15 140 70 30 10 16 28))
  (draw-rounded-rect (surface-canvas surface) shape paint))
]
@reference-figure["rounded-rect-nine-patch.png"
                  "A blue rounded rectangle whose four corner radii come from independent left, top, right, and bottom components."]

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
Moves the left and right bounds inward by @racket[dx] and the top and bottom
bounds inward by @racket[dy], adjusting the corner radii with them. Both
distances must be nonnegative after the rounding described above; otherwise,
the function raises an exception. Collapsed results are normalized; the
operation does not return negative dimensions.
}

@defproc[(rounded-rect-outset [shape rounded-rect?]
          [dx real?]
          [dy real?])
          rounded-rect?]{
Moves the left and right bounds outward by @racket[dx] and the top and bottom
bounds outward by @racket[dy], adjusting the corner radii with them. Both
distances must be nonnegative after the rounding described above; otherwise,
the function raises an exception. This changes the shape's geometry; it does
not create a stroked outline.
}

@racketblock[
(with-skia ([surface (make-surface 260 165 #:background 'white)]
            [outset-paint (make-paint #:color "#E94F37" #:style 'stroke #:stroke-width 3)]
            [original-paint (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 3)]
            [inset-paint (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 3)]
            [font (make-font #:size 11)]
            [label (make-paint #:color "#20344E")])
  (define original (make-rounded-rect 65 52 130 65 #:radii 28))
  (define inset (rounded-rect-inset original 12 8))
  (define outset (rounded-rect-outset original 12 8))
  (define canvas (surface-canvas surface))
  (draw-rounded-rect canvas outset outset-paint)
  (draw-rounded-rect canvas original original-paint)
  (draw-rounded-rect canvas inset inset-paint)
  (draw-simple-text canvas "orange: outset (12, 8)" 54 22 font label)
  (draw-simple-text canvas "dark: original" 88 137 font label)
  (draw-simple-text canvas "blue: inset (12, 8)" 72 153 font label)
  surface)
]
@reference-figure["rounded-rect-inset-outset.png"
                  "Three concentric rounded-rectangle outlines: a large orange outset expanded by 12 horizontal and 8 vertical units, the dark original, and a smaller blue inset using the same distances. Their corner radii change with the native rounded-rectangle rules."]

Insets and outsets change the bounds and radii; they do not add strokes.

@defproc[(rounded-rect-transform [shape rounded-rect?]
          [transform matrix?])
          (or/c rounded-rect? #f)]{
Applies the affine transform and returns a rounded rectangle, or @racket[#f]
if the transformed shape cannot be represented as one.

The result uses normalized bounds and radii. Not every affine transformation
preserves this representation. The operation does not silently approximate,
flatten, or rasterize an unrepresentable shape. For general affine geometry,
add the rounded rectangle to a path and use @racket[path-transform].
}

The following shear cannot be represented as a rounded rectangle, so
@racket[rounded-rect-transform] returns @racket[#f]:

@racketblock[
(rounded-rect-transform (make-rounded-rect 0 0 40 20 #:radii 4)
                        (make-matrix 1 0 0.5 1 0 0)) ; => #f
]
