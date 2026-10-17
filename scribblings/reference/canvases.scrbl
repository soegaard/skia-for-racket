#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia))

@title[#:tag "skia-canvas-state"]{Canvas State}

A @tech{canvas} carries a @tech{canvas transform}, a @tech{clip}, and a stack of saved drawing states.
These operations change how subsequent drawing is placed; they do not transform
pixels that have already been drawn. Several wrappers for the same target share
this state. Canvas operations require a live canvas and its owner's thread; a GPU
canvas also requires its matching active lease.

@local-table-of-contents[#:style 'immediate-only]

@section[#:tag "skia-canvas-clear"]{Clearing}

@defproc[(canvas-clear! [canvas canvas?] [color color?]) void?]{
Replaces the content inside the current clip with @racket[color], using source
replacement rather than source-over blending. The current transform does not
move the clear operation. Clearing with transparent color therefore removes
existing content inside the clip. The operation does not reset the transform,
clip, or save stack.
}

@section[#:tag "skia-canvas-save"]{Saving and Restoring State}

The @deftech{save count} is the number of canvas states, including the base state.
A new ordinary canvas has a save count of one. Saving pushes a copy of the
current transform and clip. Restoring removes saved states; it does not undo
drawing or restore mutations of a @tech{paint} or @tech{path}.

@defproc[(call-with-canvas-state [canvas canvas?] [proc (-> any)]) any]{
Saves the canvas state, calls @racket[proc] with no arguments, and returns its
results. On normal return or escape, the saved transform and clip are restored,
including when @racket[proc] saved additional states. The scope prevents explicit
restoration below its protected save count and establishes a continuation
barrier. A continuation cannot re-enter an expired scope.

Closing an ordinary CPU owner in @racket[proc] does not cause restoration through
an invalid native pointer: the cleanup skips native restoration for a closed
owner. Other borrowing and GPU restrictions on closing still apply. In normal
use, keep the owner alive for the entire scope.


@racketblock[
(with-skia ([surface (make-surface 200 110 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([blue (make-paint #:color "#326DE6")]
              [orange (make-paint #:color "#EFA02B")])
    (draw-rounded-rect canvas 15 18 55 40 8 8 blue)
    (with-canvas-state canvas
      (canvas-translate! canvas 62 18)
      (draw-rounded-rect canvas 15 18 55 40 8 8 orange)
      (with-canvas-state canvas
        (canvas-translate! canvas 62 18)
        (canvas-rotate! canvas 12)
        (draw-rounded-rect canvas 15 18 55 40 8 8 blue))))
)
]
@reference-figure["canvas-nested-state-stage9.png"
                  "Three rounded rectangles show nested saved canvas states, each adding another local transform without disturbing the outer state."]
}

@defform[(with-canvas-state canvas-expr body ...+)
         #:contracts ([canvas-expr canvas?])]{
Like @racket[call-with-canvas-state], with @racket[body] as the function body.
The canvas expression is evaluated once. Internal definitions are permitted.
The form restores canvas state, not pixels or resource lifetimes.

@racketblock[
(with-skia ([surface (make-surface 100 80 #:background 'white)]
            [paint (make-paint #:color 'blue)])
  (define canvas (surface-canvas surface))
  (with-canvas-state canvas
    (canvas-translate! canvas 20 10)
    (canvas-clip-rect! canvas 0 0 40 30)
    (draw-rect canvas 0 0 60 50 paint))
  (equal? (canvas-transform canvas) matrix-identity))
]

@reference-figure["canvas-state.png"
                  "A blue rectangle translated to the right and down and clipped to a smaller rectangle on a white background."]
}

@section[#:tag "skia-canvas-transforms"]{Changing Coordinates}

A @deftech{canvas transform} maps @deftech{local coordinates}, supplied to
drawing operations, to @deftech{device coordinates} in the drawing target.
Changing the transform changes where subsequent drawing appears; it does not
move existing pixels.

Canvas concatenation uses the product @math{C M}, where @math{C} is the current
transform and @math{M} is the newly supplied transform. A point is mapped by
@math{M} first and by @math{C} second. Consequently, translating and then scaling
scales the drawing's local coordinates without scaling the earlier translation.
See @racket[matrix-compose] for the corresponding operation on detached values.

@bold{Conceptual diagram.} The two transform orders use @math{T=(10,20)}, uniform
@math{S=2}, and @math{p=(3,4)}. @racket[(matrix-compose T S)] maps the point
by @math{S} first, producing @math{(16,28)}, while
@racket[(matrix-compose S T)] produces @math{(26,48)}. Canvas calls accumulate
the same products: translate then scale gives @math{T S}; scale then translate
gives @math{S T}. Existing pixels do not move when a later transform changes.

@reference-figure["concept-transform-order.png"
                  "Two coordinate-grid panels show p=(3,4), the initial rightward-x/downward-y axes, and mapped points (16,28) for T after S versus (26,48) for S after T. Each panel names the matching canvas-call order."]

@defproc[(canvas-translate! [canvas canvas?] [x real?] [y real?]) void?]{
Concatenates a translation by @racket[x] and @racket[y] in the current local
coordinate system. The displacement is transformed by any earlier scale or
rotation. Both arguments must be @tech{drawing scalar}s.
}

@defproc[(canvas-scale! [canvas canvas?] [x real?] [y real? x]) void?]{
Concatenates scaling by @racket[x] horizontally and @racket[y] vertically. A
negative factor reflects an axis. A zero factor is accepted and makes the
transform singular. Omitting @racket[y] uses @racket[x] on both axes.


@racketblock[
(with-skia ([surface (make-surface 240 110 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([blue (make-paint #:color "#326DE6")]
              [orange (make-paint #:color "#EFA02B")])
    (with-canvas-state canvas
      (canvas-clip-rect! canvas 0 0 120 110)
      (canvas-translate! canvas 20 25)
      (canvas-scale! canvas 1.6 1)
      (draw-rect canvas 0 0 45 55 blue))
    (with-canvas-state canvas
      (canvas-clip-rect! canvas 120 0 120 110)
      (canvas-scale! canvas 1.6 1)
      (canvas-translate! canvas 82 25)
      (draw-rect canvas 0 0 45 55 orange)))
)
]
@reference-figure["transform-order-stage9.png"
                  "Blue and orange rectangles demonstrate that translating then scaling differs from scaling then translating."]
}

@defproc[(canvas-rotate! [canvas canvas?] [degrees real?]) void?]{
Concatenates a rotation about the local origin by @racket[degrees]. Positive
angles rotate clockwise in the initial downward-y coordinate system. Translate
the origin first to rotate around another point.


@racketblock[
(with-skia ([surface (make-surface 200 120 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([paint (make-paint #:color "#326DE6")]
              [axis (make-paint #:color "#AEB7C2" #:style 'stroke #:stroke-width 1)])
    (draw-line canvas 100 12 100 108 axis)
    (draw-line canvas 18 60 182 60 axis)
    (with-canvas-state canvas
      (canvas-translate! canvas 100 60)
      (canvas-rotate! canvas 30)
      (draw-rect canvas -55 -20 110 40 paint)))
)
]
@reference-figure["rotate-around-point-stage9.png"
                  "A blue rectangle rotates around the translated canvas origin at the center of the figure."]
}

@defproc[(canvas-rotate-radians! [canvas canvas?] [radians real?]) void?]{
Like @racket[canvas-rotate!], but the angle is measured in radians.
}

@defproc[(canvas-skew! [canvas canvas?] [x real?] [y real?]) void?]{
Concatenates a shear with horizontal factor @racket[x] and vertical factor
@racket[y]. The factors are not angles: the local mapping is
@math{u' = u + x v} and @math{v' = y u + v} for an input point
with coordinates @math{u} and @math{v}.
}

@defproc[(canvas-reset-transform! [canvas canvas?]) void?]{
Replaces the current transform with the identity. It does not reset the clip.
A clip established before this call remains in the target's coordinate system.
The established-clip state diagram in @secref["skia-clipping"] shows this
separation explicitly.


@racketblock[
(with-skia ([surface (make-surface 200 110 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([blue (make-paint #:color "#326DE6")]
              [orange (make-paint #:color "#EFA02B")])
    (canvas-translate! canvas 95 20)
    (draw-rect canvas 0 0 70 45 blue)
    (canvas-reset-transform! canvas)
    (draw-rect canvas 20 45 70 45 orange))
)
]
@reference-figure["canvas-reset-transform-stage9.png"
                  "A literal-pixel capture of the 200 by 110 target: a translated blue 70 by 45 rectangle and an equally sized orange rectangle drawn after reset-transform replaces the transform with identity."]

The preview enlarges the captured target only after the program runs. Resetting the transform
therefore does not retain a hidden device-density scale.
}

@defproc[(canvas-transform [canvas canvas?]) matrix?]{
Returns a detached snapshot of the current two-dimensional affine transform.
The call raises an exception when the current native transform contains
perspective or three-dimensional components that the six-coefficient
@tech{affine matrix} cannot represent. It does not silently discard them.
}

@defproc[(canvas-set-transform! [canvas canvas?] [matrix matrix?]) void?]{
Replaces the current transform with @racket[matrix]. The matrix is a detached
value; the canvas does not borrow its storage. The clip is unchanged.


@racketblock[
(with-skia ([surface (make-surface 200 110 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([paint (make-paint #:color "#326DE6")])
    (canvas-set-transform!
     canvas
     (matrix-compose (matrix-translate 55 25)
                     (matrix-scale 1.6 0.75)))
    (draw-rect canvas 0 0 70 65 paint))
)
]
@reference-figure["canvas-set-transform-stage9.png"
                  "A literal-pixel capture of a blue rectangle through the installed translation and nonuniform-scale transform; its placement and size come from the replacement matrix."]

As with reset-transform, the figure is enlarged only after capturing the example's actual target.
}

@defproc[(canvas-concat! [canvas canvas?] [matrix matrix?]) void?]{
Concatenates @racket[matrix] after the current transform, using the product
@math{C M}, where @math{C} is the current transform and @math{M} is
@racket[matrix]. The canvas reads the coefficients during the call. The
resulting native transform uses single-precision arithmetic.
}

@section[#:tag "skia-clipping"]{Clipping}

A @deftech{clip} limits the coverage affected by later drawing. The geometry supplied to
a clipping operation is transformed by the current transform when the operation
runs. Subsequent transform changes do not move the established clip. Saving and
restoring canvas state is the usual way to apply a temporary clip.

@bold{Conceptual diagram.} Establishing a local @math{(0,0,75,55)} clip after
translation by @math{(40,55)} fixes target coverage at @math{(40,55,75,55)}.
Resetting the transform changes later drawing coordinates, not that established
clip. Restoring a saved state restores transform and clip; it never rolls back
pixels already drawn.

@reference-figure["concept-clip-state.png"
                  "Three gridded panels show a translated established clip, drawing after reset-transform through the unchanged target clip, and a restored outer state with prior pixels still present. Red outlines identify the established clips."]

@defproc[(canvas-clip-rect! [canvas canvas?] [x real?] [y real?]
                           [width (and/c real? (>=/c 0))]
                           [height (and/c real? (>=/c 0))]
                           [#:operation operation (or/c 'intersect 'difference) 'intersect]
                           [#:antialias? antialias? boolean? #f]) void?]{
Combines the current clip with the transformed rectangle. The default
@racket['intersect] keeps only their overlap; @racket['difference] removes the
rectangle's coverage from the current clip. Neither operation enlarges the clip.
@tech{Antialiasing} permits fractional edge coverage. Zero extents are accepted; the
computed right and bottom coordinates must be @tech{drawing scalar}s.

The following comparison starts each operation with the same clip, covering the
left six columns of an eight-column surface. A second rectangle either intersects
that clip or is subtracted from it. Each state scope restores the original clip
before the next iteration; it does not undo the drawing.

@racketblock[
(with-skia ([surface (make-surface 8 6 #:background 'white)]
            [paint (make-paint #:color 'blue #:antialias? #f)])
  (define canvas (surface-canvas surface))
  (for/list ([operation '(intersect difference)])
    (canvas-clear! canvas 'white)
    (with-canvas-state canvas
      (canvas-clip-rect! canvas 0 0 6 6)
      (canvas-clip-rect! canvas 2 2 2 2 #:operation operation)
      (draw-paint canvas paint))
    (for/list ([x '(3 1 7)])
      (equal? (surface-pixel surface x 3) (color->rgba 'blue)))))
]

The result is @racket['((#t #f #f) (#f #t #f))]. The first sample is inside the
second rectangle, the next is outside it but inside the initial clip, and the
last is outside the initial clip. Difference removes an area from the current
clip; it does not select everything outside the rectangle across the surface.

@reference-figure["clip-within-existing-clip.png"
                  "Nearest-neighbor enlargements of the two actual eight-by-six clip states. Intersection leaves only the central two-by-two blue area; difference leaves the initial six-column blue region with that two-by-two area removed. The legend identifies samples at y three with x coordinates three, one, and seven."]

Both panels start with the same left-six-column clip. The sample legend identifies
the positions tested by the example; the image adds no marks to the pixel results.


@racketblock[
(with-skia ([surface (make-surface 220 100 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([paint (make-paint #:color "#326DE6")]
              [separator (make-paint #:color "#BCC5CF" #:style 'stroke #:stroke-width 1)])
    (with-canvas-state canvas
      (canvas-clip-rect! canvas 15.5 15.5 75 68 #:antialias? #f)
      (draw-paint canvas paint))
    (with-canvas-state canvas
      (canvas-clip-rect! canvas 129.5 15.5 75 68 #:antialias? #t)
      (draw-paint canvas paint))
    (draw-line canvas 110 8 110 92 separator))
)
]
@reference-figure["clip-antialias-stage9.png"
                  "Two literal-pixel clipped rectangles compare a hard fractional clip edge on the left with an antialiased edge on the right, whose boundary pixels have intermediate blue coverage."]

The source target is captured at one device pixel per coordinate unit and enlarged afterwards;
scaling the program first would turn the half-pixel edges into integral edges and hide the comparison.
}

@defproc[(canvas-clip-path! [canvas canvas?] [path skia-path?]
                           [#:operation operation (or/c 'intersect 'difference) 'intersect]
                           [#:antialias? antialias? boolean? #f]) void?]{
Like @racket[canvas-clip-rect!], but uses the filled region of @racket[path] and
its fill rule. Paint stroke settings do not affect this operation. Subsequent
mutation or closure of the path does not change the established clip.


@racketblock[
(with-skia ([surface (make-surface 180 100 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([path (make-path)]
              [paint (make-paint #:color "#326DE6")])
    (path-add-circle! path 90 50 38)
    (canvas-clip-path! canvas path #:antialias? #t)
    (draw-paint canvas paint))
)
]
@reference-figure["clip-path-circle-stage9.png"
                  "A blue fill is restricted to a circular path clip, leaving the surrounding surface white."]
}

@section[#:tag "skia-clip-queries"]{Rounded Clips and Clip Queries}

@(declare-exporting skia)

Clip queries describe the current saved drawing state. Bounds can be conservative
and do not replace a clip or prove that a shape will draw visible pixels.

@defproc[(canvas-clip-rounded-rect! [canvas canvas?]
          [shape rounded-rect?]
          [#:operation operation (or/c 'intersect 'difference) 'intersect]
          [#:antialias? antialias? boolean? #f])
          void?]{
Combines the current clip with the native-normalized rounded boundary in local
coordinates. The current transform applies; antialiasing is optional and off by
default. The boundary is preserved through a path representation so unequal
corner radii are not reduced to a single SVG radius pair.


@racketblock[
(with-skia ([surface (make-surface 180 100 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([paint (make-paint #:color "#326DE6")])
    (define shape (make-rounded-rect 22 15 136 70 #:radii 24))
    (canvas-clip-rounded-rect! canvas shape #:antialias? #t)
    (draw-paint canvas paint))
)
]
@reference-figure["clip-rrect-stage9.png"
                  "A blue fill is clipped to a rounded rectangle with broad rounded corners."]
}

@defproc[(canvas-local-clip-bounds [canvas canvas?])
          (or/c #f (and/c (vector/c real? real? real? real?) immutable?))]{
Returns detached conservative clip bounds in current local coordinates, or
@racket[#f] when native bounds are unavailable. Inverse mapping and antialiasing
can expand these bounds. Changing the transform can change the reported bounds
without changing the device clip.
}

@defproc[(canvas-device-clip-bounds [canvas canvas?])
          (or/c #f (and/c (vector/c exact-integer? exact-integer? exact-integer? exact-integer?)
          immutable?))]{
Returns detached integer clip bounds in device coordinates, or @racket[#f]
when native bounds are unavailable. The current local transform does not move
these coordinates.
}

@defproc[(canvas-clip-empty? [canvas canvas?])
          boolean?]{
Reports whether the current clip is empty. It does not test whether pixels
already stored in the destination are transparent.
}

@defproc[(canvas-clip-rect? [canvas canvas?])
          boolean?]{
Reports whether the current clip is represented as a nonempty rectangle.
An empty clip is not reported as rectangular.
}

@defproc[(canvas-quick-reject? [canvas canvas?]
          [x real?]
          [y real?]
          [width (and/c real? (>=/c 0))]
          [height (and/c real? (>=/c 0))])
          boolean?]{
Returns @racket[#t] when the transformed local rectangle can be rejected
against the current clip. A false result does not prove intersection or visible
output. The query has no paint argument and does not expand the rectangle for
strokes, filters, or other painted extents.
}

@section[#:tag "skia-canvas-manual-state"]{Manual Canvas State Management}

Use @racket[with-canvas-state] or @racket[call-with-canvas-state] to restore the
transform and clip automatically when a drawing scope ends. The operations in
this section control individual saved states. The caller must balance saves
and restores, including when drawing raises an exception or exits early.

@defproc[(canvas-save! [canvas canvas?]) exact-positive-integer?]{
Saves the current transform and clip and returns the save count from before
this save. Passing that result to @racket[canvas-restore-to-count!] later restores
the state that was current before the call.
}

@defproc[(canvas-save-count [canvas canvas?]) exact-positive-integer?]{
Returns the current number of states, including the base state.
}

@defproc[(canvas-restore! [canvas canvas?]) void?]{
Restores the previous transform and clip by removing the top state. An attempt
to remove the base state, or a state protected by an enclosing state or layer
scope, raises an exception instead of silently doing nothing.
}

@defproc[(canvas-restore-to-count! [canvas canvas?]
                                  [count exact-positive-integer?]) void?]{
Restores states until the save count is @racket[count]. The requested count must
be at least the current protected floor and no greater than the current save
count. A count equal to the current count leaves the state unchanged.
}

@section[#:tag "skia-canvas-backend"]{Backend Queries}

@defproc[(canvas-execution-backend [canvas canvas?]) symbol?]{
Returns the execution backend of a valid canvas. Ordinary targets report
@racket['raster], @racket['recording], @racket['pdf], or @racket['svg]; GPU targets
report the selected GPU backend, such as @racket['opengl], @racket['metal], or
@racket['direct3d]. Specialized canvases report their declared execution backend.
Unlike @racket[surface-backend], this operation validates native use of the canvas.
A backend name does not guarantee that every paint effect is supported.
}

@section{Additional Visual Examples}

These examples isolate common transform and clip operations.

@racketblock[
(with-skia ([surface (make-surface 180 100 #:background 'white)]
            [guide (make-paint #:color "#D9DEE4")]
            [paint (make-paint #:color "#326DE6")])
  (define canvas (surface-canvas surface))
  (draw-rect canvas 20 20 50 35 guide)
  (with-canvas-state canvas
    (canvas-translate! canvas 75 30)
    (draw-rect canvas 20 20 50 35 paint)))
]
@reference-figure["canvas-translate.png"
                  "A gray reference rectangle and the same rectangle translated down and right in blue."]

@racketblock[
(with-skia ([surface (make-surface 180 110 #:background 'white)]
            [guide (make-paint #:color "#D9DEE4")]
            [paint (make-paint #:color "#326DE6")])
  (define canvas (surface-canvas surface))
  (draw-rect canvas 18 18 45 30 guide)
  (with-canvas-state canvas
    (canvas-translate! canvas 75 20)
    (canvas-scale! canvas 1.8 1.6)
    (draw-rect canvas 0 0 45 30 paint)))
]
@reference-figure["canvas-scale.png"
                  "A small gray reference rectangle and a larger blue rectangle produced by canvas scaling."]

@racketblock[
(with-skia ([surface (make-surface 180 120 #:background 'white)]
            [guide (make-paint #:color "#D9DEE4")]
            [paint (make-paint #:color "#326DE6")])
  (define canvas (surface-canvas surface))
  (draw-rect canvas 55 40 70 40 guide)
  (with-canvas-state canvas
    (canvas-translate! canvas 90 60)
    (canvas-rotate! canvas 28)
    (draw-rect canvas -35 -20 70 40 paint)))
]
@reference-figure["canvas-rotate.png"
                  "A blue rectangle rotated clockwise over a gray unrotated reference rectangle."]

@racketblock[
(with-skia ([surface (make-surface 180 110 #:background 'white)]
            [paint (make-paint #:color "#326DE6")])
  (define canvas (surface-canvas surface))
  (canvas-translate! canvas 60 0)
  (canvas-skew! canvas 0.55 0)
  (draw-rect canvas 0 30 60 45 paint))
]
@reference-figure["canvas-skew.png"
                  "A blue rectangle sheared horizontally by the canvas skew transform."]

@racketblock[
(with-skia ([surface (make-surface 180 100 #:background 'white)]
            [paint (make-paint #:color "#326DE6")])
  (define canvas (surface-canvas surface))
  (canvas-clip-rect! canvas 20 15 120 70)
  (canvas-clip-rect! canvas 65 30 90 45 #:operation 'intersect)
  (draw-paint canvas paint))
]
@reference-figure["clip-intersect.png"
                  "Blue paint appears only in the intersection of two rectangular canvas clips."]

@racketblock[
(with-skia ([surface (make-surface 180 100 #:background 'white)]
            [paint (make-paint #:color "#326DE6")])
  (define canvas (surface-canvas surface))
  (canvas-clip-rect! canvas 20 15 140 70)
  (canvas-clip-rect! canvas 60 30 60 40 #:operation 'difference)
  (draw-paint canvas paint))
]
@reference-figure["clip-difference.png"
                  "A blue rectangular clipped area with a white rectangular hole removed by difference clipping."]
