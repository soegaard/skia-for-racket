#lang scribble/manual

@(require (for-label racket/base racket/contract skia skia/canvas-primitives))

@title[#:tag "skia-canvas-state"]{Canvas State}

A @tech{canvas} carries a transform, a clip, and a stack of saved drawing states.
These operations change how subsequent drawing is placed; they do not transform
pixels that have already been drawn. Several wrappers for the same target share
this state. All operations in this chapter require a live canvas and its owner's
thread; a GPU canvas also requires its matching active lease.

@section{Clearing and Backend Queries}

@defproc[(canvas-clear! [canvas canvas?] [color color?]) void?]{
Replaces the content inside the current clip with @racket[color], using source
replacement rather than source-over blending. The current transform does not
move the clear operation. Clearing with transparent color therefore removes
existing content inside the clip. The operation does not reset the transform,
clip, or save stack.
}

@defproc[(canvas-execution-backend [canvas canvas?]) symbol?]{
Returns the execution backend of a valid canvas. Ordinary targets report
@racket['raster], @racket['recording], @racket['pdf], or @racket['svg]; GPU targets
report the selected GPU backend, such as @racket['opengl], @racket['metal], or
@racket['direct3d]. Specialized canvases report their declared execution backend.
Unlike @racket[surface-backend], this operation validates native use of the canvas.
A backend name does not guarantee that every paint effect is supported.
}

@section[#:tag "skia-canvas-save"]{Saving and Restoring State}

A new ordinary canvas has a save count of one. Saving pushes a copy of the
current transform and clip. Restoring removes saved states; it does not undo
drawing or restore mutations of a @tech{paint} or @tech{path}.

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
}

@defform[(with-canvas-state canvas-expr body ...+)
         #:contracts ([canvas-expr canvas?])]{
Like @racket[call-with-canvas-state], with @racket[body] as the procedure body.
The canvas expression is evaluated once. Internal definitions are permitted.
The form restores canvas state, not pixels or resource lifetimes.

@racketblock[
(with-skia ([surface (make-surface 100 80)]
            [paint (make-paint #:color 'blue)])
  (define canvas (surface-canvas surface))
  (with-canvas-state canvas
    (canvas-translate! canvas 20 10)
    (canvas-clip-rect! canvas 0 0 40 30)
    (draw-rect canvas 0 0 60 50 paint))
  (equal? (canvas-transform canvas) matrix-identity))
]
}

@section[#:tag "skia-canvas-transforms"]{Changing Coordinates}

Canvas concatenation uses the product @math{C M}, where @math{C} is the current
transform and @math{M} is the newly supplied transform. A point is mapped by
@math{M} first and by @math{C} second. Consequently, translating and then scaling
scales the drawing's local coordinates without scaling the earlier translation.
See @racket[matrix-compose] for the corresponding operation on detached values.

@defproc[(canvas-translate! [canvas canvas?] [x real?] [y real?]) void?]{
Concatenates a translation by @racket[x] and @racket[y] in the current local
coordinate system. The displacement is transformed by any earlier scale or
rotation. Both arguments must be @tech{drawing scalar}s.
}

@defproc[(canvas-scale! [canvas canvas?] [x real?] [y real? x]) void?]{
Concatenates scaling by @racket[x] horizontally and @racket[y] vertically. A
negative factor reflects an axis. A zero factor is accepted and makes the
transform singular. Omitting @racket[y] uses @racket[x] on both axes.
}

@defproc[(canvas-rotate! [canvas canvas?] [degrees real?]) void?]{
Concatenates a rotation about the local origin by @racket[degrees]. Positive
angles rotate clockwise in the initial downward-y coordinate system. Translate
the origin first to rotate around another point.
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
}

@defproc[(canvas-concat! [canvas canvas?] [matrix matrix?]) void?]{
Concatenates @racket[matrix] after the current transform, using the product
@math{C M} described above. The canvas reads the matrix coefficients during the
call. The resulting native transform uses single-precision arithmetic.
}

@section[#:tag "skia-clipping"]{Clipping}

A clip limits the coverage affected by later drawing. The geometry supplied to
a clipping operation is transformed by the current transform when the operation
runs. Subsequent transform changes do not move the established clip. Saving and
restoring canvas state is the usual way to apply a temporary clip.

@defproc[(canvas-clip-rect! [canvas canvas?] [x real?] [y real?]
                           [width (and/c real? (>=/c 0))]
                           [height (and/c real? (>=/c 0))]
                           [#:operation operation (or/c 'intersect 'difference) 'intersect]
                           [#:antialias? antialias? boolean? #f]) void?]{
Combines the current clip with the transformed rectangle. The default
@racket['intersect] keeps only their overlap; @racket['difference] removes the
rectangle's coverage from the current clip. Neither operation enlarges the clip.
Antialiasing permits fractional edge coverage. Zero extents are accepted; the
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
}

@defproc[(canvas-clip-path! [canvas canvas?] [path skia-path?]
                           [#:operation operation (or/c 'intersect 'difference) 'intersect]
                           [#:antialias? antialias? boolean? #f]) void?]{
Like @racket[canvas-clip-rect!], but uses the filled region of @racket[path] and
its fill rule. Paint stroke settings do not affect this operation. Subsequent
mutation or closure of the path does not change the established clip.
}

@section[#:tag "skia-clip-queries"]{Rounded Clips and Clip Queries}

@(declare-exporting skia skia/canvas-primitives #:use-sources (skia/canvas-primitives))

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
