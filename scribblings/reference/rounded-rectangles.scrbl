#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia))

@title[#:tag "skia-rounded-rectangles"]{Rounded Rectangles}

@(declare-exporting skia)

A @deftech{rounded rectangle} is a detached immutable specification of a rectangle
and four pairs of corner radii. It is not an owned native resource. Drawing or
path construction normalizes that specification according to Skia's rounded
rectangle rules. The stored radii are not a promise that those radii fit the bounds.

Corners are ordered top-left, top-right, bottom-right, bottom-left. The two
components at each corner
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

Bounds use nonnegative dimensions. Stored bounds reflect the native rectangle's
binary32 edges; radius components are stored as
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

These operations require Skia but return detached values that need no explicit
closure. Inputs are unchanged. Native normalization can reduce oversized
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

@racketblock[
(with-skia ([surface (make-surface 160 90 #:background 'white)]
            [paint (make-paint #:color "#326DE6")])
  (define shape
    (make-rounded-rect 20 15 120 60
                       #:radii '((24 24) (8 8) (24 8) (8 24))))
  (draw-rrect (surface-canvas surface) shape paint))
]

@reference-figure["rounded-rect.png"
                  "A blue rounded rectangle with four visibly different corner-radius pairs."]
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
  (draw-rrect canvas outset outset-paint)
  (draw-rrect canvas original original-paint)
  (draw-rrect canvas inset inset-paint)
  (draw-simple-text canvas "orange: outset (12, 8)" 54 22 font label)
  (draw-simple-text canvas "dark: original" 88 137 font label)
  (draw-simple-text canvas "blue: inset (12, 8)" 72 153 font label)
  surface)
]
@reference-figure["rounded-rect-inset-outset.png"
                  "Three concentric rounded-rectangle outlines: a large orange outset expanded by 12 horizontal and 8 vertical units, the dark original, and a smaller blue inset using the same distances. Their corner radii change with the native rounded-rectangle rules."]

Insets and outsets change detached rounded-rectangle specifications; they are
not strokes.  A translation or axis-aligned scale can produce another
representable rounded rectangle, but that is not a distinct visual concept from
the canvas transforms shown elsewhere.  The deliberately numerical shear case
remains useful because it establishes the refusal to approximate:

@racketblock[
(rounded-rect-transform (make-rounded-rect 0 0 40 20 #:radii 4)
                        (make-matrix 1 0 0.5 1 0 0)) ; => #f
]

@section{Additional Visual Examples}

@racketblock[
(with-skia ([surface (make-surface 180 100 #:background 'white)]
            [paint (make-paint #:color "#326DE6")])
  (define normalized
    (rounded-rect-normalize (make-rounded-rect 25 20 130 60 #:radii 80)))
  (draw-rrect (surface-canvas surface) normalized paint))
]
@reference-figure["rounded-rect-normalized.png"
                  "A blue rounded rectangle after oversized corner radii have been normalized to fit its bounds."]

@racketblock[
(with-skia ([surface (make-surface 180 100 #:background 'white)]
            [paint (make-paint #:color "#326DE6")])
  (define shape (make-nine-patch-rounded-rect 20 15 140 70 30 10 16 28))
  (draw-rrect (surface-canvas surface) shape paint))
]
@reference-figure["rounded-rect-nine-patch.png"
                  "A blue rounded rectangle whose four corner radii come from independent left, top, right, and bottom components."]
