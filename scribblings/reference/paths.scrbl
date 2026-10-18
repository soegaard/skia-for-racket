#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract racket/sequence skia skia/geometry))

@title[#:tag "skia-paths"]{Paths}

Use a path for a custom outline, curved boundary, or shape with holes that the
basic drawing primitives cannot express directly. Build it with
@racket[make-path] and the path-mutating operations, then fill or stroke it with
@racket[draw-path], or use it as a clip with @racket[canvas-clip-path!]. The same
geometry can be reused with different paints and transforms.

A @deftech{path} stores @tech{contours} made from straight segments, quadratic and
cubic Bézier curves, rational quadratic curves, and close commands. It is an
owned, mutable native resource. A @deftech{contour} starts with a move and can
be open or explicitly closed. A path stores geometry and a @tech{fill rule}, not a
@tech{paint} or @tech{canvas transform}. The predicate is @racket[skia-path?], which is distinct
from Racket's filesystem-path predicate.

For explicit conversion to and from Racket @racket[dc-path%] values, see
@racketmodname[skia/racket-draw]. That bridge retains fill interpretation as a
separate Draw value and rejects topology that one @racket[dc-path%] cannot
represent without changing open contours.

Path coordinates are @tech{local coordinates}.
Construction and mutation do not use a canvas's current transform. Each native
operation requires an open path on its owning thread. A copied or transformed
path has its own lifetime.

@local-table-of-contents[#:style 'immediate-only]

@section[#:tag "skia-path-creation"]{Construction and Fill Rules}

@defproc[(skia-path? [v any/c]) boolean?]{
Returns @racket[#t] for a Skia path and @racket[#f] otherwise. The predicate
remains true after the path is closed as a resource. Closing a contour with
@racket[path-close!] is unrelated to closing the resource with @racket[skia-close!].
}

@defproc[(make-path [commands list? '()]
                    [#:fill-rule fill-rule (or/c 'winding 'even-odd) 'winding]) skia-path?]{
Returns a new path by applying @racket[commands] in order. Each command is a
list in one of the following forms. Coordinates and weights use the same
contracts as the corresponding path-mutating function.

@verbatim{
(move x y)                         (rmove dx dy)
(line x y)                         (rline dx dy)
(quad cx cy x y)                    (rquad dcx dcy dx dy)
(conic cx cy x y weight)            (rconic dcx dcy dx dy weight)
(cubic cx1 cy1 cx2 cy2 x y)          (rcubic dcx1 dcy1 dcx2 dcy2 dx dy)
(close)
}

A relative command measures all its coordinate offsets from the current point
at the start of that command; its second control point is not relative to its
first control point. Commands are processed immediately, not retained as a
Racket program. An invalid command raises an exception, and construction releases
the partially built path.

A @deftech{fill rule} determines which points are inside a path for filling.
The @racket['winding] rule fills points with nonzero signed winding number.
The @racket['even-odd] rule fills points crossed an odd number of times by a ray
to the exterior. Both treat open contours as closed for filling. Explicit
closure still matters for stroke caps and joins. Reversing an inner contour
can create a winding-rule hole; an even-odd hole does not depend on direction.

@bold{Conceptual diagram.} Winding considers a signed total, while even-odd
considers only crossing parity. The annotated nested-contour cases make the
direction dependency explicit: reversing the inner contour can turn a winding
center into a hole, but it does not change an even-odd hole. Open contours are
still treated as closed for filling; that does not replace @racket[path-close!]
when stroke joins matter.

@reference-figure["concept-fill-rules.png"
                  "A two-by-two comparison of same and reversed inner contour direction under winding and even-odd fill. Direction arrows, signed winding totals, crossing parity labels, and the resulting filled or hollow centers are shown in every panel."]

@racketblock[
(with-skia ([path (make-path '((move 0 0) (line 40 0) (line 20 30) (close)))])
  (path-contains? path 20 10))
]


@racketblock[
(with-skia ([surface (make-surface 200 110 #:background 'white)]
            [path (make-path '((move 20 85)
                               (rline 35 -55)
                               (rline 35 55)
                               (rline 35 -55)
                               (rline 35 55)))]
            [paint (make-paint #:color "#326DE6" #:style 'stroke
                               #:stroke-width 5 #:join 'round)])
  (draw-path (surface-canvas surface) path paint))
]
@reference-figure["relative-path-stage8.png"
                  "A blue zigzag built entirely from relative line commands climbs and descends across the surface."]

@racketblock[
(with-skia ([surface (make-surface 240 120 #:background 'white)]
            [quad (make-path '((move 15 95) (quad 60 10 110 95)))]
            [cubic (make-path '((move 130 95) (cubic 145 10 210 10 225 95)))]
            [blue (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 5)]
            [orange (make-paint #:color "#EFA02B" #:style 'stroke #:stroke-width 5)])
  (draw-path (surface-canvas surface) quad blue)
  (draw-path (surface-canvas surface) cubic orange))
]
@reference-figure["quad-cubic-stage8.png"
                  "A blue quadratic arch and an orange cubic arch show the different curve shapes side by side."]
}

@defproc[(path-copy [path skia-path?]) skia-path?]{
Returns an independently owned path with the same geometry and fill rule.
Subsequent mutation or closure of either wrapper does not affect the other.
Native storage may be shared until a change requires separation.
}

@defproc[(path-fill-rule [path skia-path?]) (or/c 'winding 'even-odd)]{
Returns the path's fill rule. The operation requires an open path.
}

@defproc[(path-set-fill-rule! [path skia-path?]
                             [fill-rule (or/c 'winding 'even-odd)]) void?]{
Changes how the path's contours combine when filled or used as a clip. The
stored points and verbs are unchanged. This interface does not accept inverse
fill-rule symbols.

@racketblock[
(with-skia ([even-odd (make-path #:fill-rule 'even-odd)]
            [winding (make-path #:fill-rule 'winding)]
            [paint (make-paint #:color "#326DE6")]
            [surface (make-surface 190 90 #:background 'white)])
  (for ([path (in-list (list even-odd winding))]
        [x (in-list '(48 142))])
    (path-add-circle! path x 45 34)
    (path-add-circle! path x 45 15))
  (draw-path (surface-canvas surface) even-odd paint)
  (draw-path (surface-canvas surface) winding paint))
]

@reference-figure["fill-rules.png"
                  "Two pairs of concentric blue circles: even-odd filling leaves a white center hole, while winding filling keeps the center blue."]
}

@defproc[(path-reset! [path skia-path?]) void?]{
Removes the geometry and resets the fill rule to @racket['winding]. The path
resource remains open and can be reused.
}

@section[#:tag "skia-path-segments-add"]{Adding Segments}

The segment operations in this section return @racket[(void)]. A move selects the start
of a contour without adding an edge. A segment appended to an empty path has
an implicit start at the origin. After a close, a following segment starts a
new contour at the preceding contour's start; an explicit move avoids relying
on that implicit start.

@defproc[(path-move-to! [path skia-path?] [x real?] [y real?]) void?]{
Starts a contour at coordinates @racket[x] and @racket[y]. It does not draw a
line from the previous contour. Consecutive moves need not retain redundant
move-only contours in the native representation.
}

@defproc[(path-rmove-to! [path skia-path?] [dx real?] [dy real?]) void?]{
Starts a contour offset by @racket[dx] and @racket[dy] from the current point.
After a close, that point is the preceding contour's start, not its last stored
endpoint. For an empty path, the start coordinates are @racket[dx] and @racket[dy].
}

@defproc[(path-line-to! [path skia-path?] [x real?] [y real?]) void?]{
Adds a straight segment from the current point to coordinates @racket[x] and
@racket[y], making that endpoint the new current point.
}

@defproc[(path-rline-to! [path skia-path?] [dx real?] [dy real?]) void?]{
Adds a straight segment whose endpoint is offset from the current point by
@racket[dx] and @racket[dy].
}

@defproc[(path-quad-to! [path skia-path?] [cx real?] [cy real?]
                       [x real?] [y real?]) void?]{
Adds a quadratic Bézier segment from the current point to coordinates
@racket[x] and @racket[y], with control point @racket[cx], @racket[cy].
The control point sets the endpoint tangent directions; the curve generally
does not pass through it.
}

@defproc[(path-rquad-to! [path skia-path?] [dcx real?] [dcy real?]
                        [dx real?] [dy real?]) void?]{
Like @racket[path-quad-to!], with both the control point and endpoint given as
offsets from the current point at the start of the call.
}

@defproc[(path-conic-to! [path skia-path?] [cx real?] [cy real?]
                        [x real?] [y real?] [weight real?]) void?]{
Adds a rational quadratic segment with one control point and an endpoint.
The endpoints have weight one; @racket[weight] is the control point's weight.
After conversion to native precision, a weight of one produces an ordinary
quadratic verb. A weight no greater than zero produces a line directly to the
endpoint, ignoring the control point. Other positive finite weights produce
a conic verb. The wrapper rejects non-finite weights but does not reject zero
or negative weights. The resulting verb therefore need not be conic.
}

@defproc[(path-rconic-to! [path skia-path?] [dcx real?] [dcy real?]
                         [dx real?] [dy real?] [weight real?]) void?]{
Like @racket[path-conic-to!], with control and endpoint offsets relative to the
current point at the start of the call. The weight is not a coordinate offset.
}

@defproc[(path-cubic-to! [path skia-path?] [cx1 real?] [cy1 real?]
                        [cx2 real?] [cy2 real?] [x real?] [y real?]) void?]{
Adds a cubic Bézier segment to coordinates @racket[x] and @racket[y]. The first
control point sets the departure tangent from the current point; the second
sets the arrival tangent at the endpoint. Neither control point is generally
on the curve.
}

@defproc[(path-rcubic-to! [path skia-path?] [dcx1 real?] [dcy1 real?]
                         [dcx2 real?] [dcy2 real?] [dx real?] [dy real?]) void?]{
Like @racket[path-cubic-to!], with all three coordinate pairs expressed as
offsets from the current point at the start of the call.
}

@defproc[(path-close! [path skia-path?]) void?]{
Closes the current contour, adding a connection to its starting point when
needed. The close command gives stroked geometry a join instead of two end
caps. Closing an already closed contour or an empty path adds no new edge.
The native path resource remains open.
}

@section{Adding Complete Shapes}

These operations append a contour; they do not replace the existing geometry.
The @racket['cw] and @racket['ccw] directions refer to clockwise and
counterclockwise winding in the initial downward-y coordinate system. Widths,
heights, and radii must be nonnegative.

@defproc[(path-add-rect! [path skia-path?] [x real?] [y real?]
                        [width (and/c real? (>=/c 0))]
                        [height (and/c real? (>=/c 0))]
                        [#:direction direction (or/c 'cw 'ccw) 'cw]) void?]{
Appends a closed rectangle with the given position, size, and winding direction.
}

@defproc[(path-add-rounded-rect! [path skia-path?] [x real?] [y real?]
                                [width (and/c real? (>=/c 0))]
                                [height (and/c real? (>=/c 0))]
                                [radius-x (and/c real? (>=/c 0))]
                                [radius-y (and/c real? (>=/c 0))]
                                [#:direction direction (or/c 'cw 'ccw) 'cw]) void?]{
Appends a closed rounded rectangle. Skia scales radii that are too large so the
corners fit. A zero radius in either direction reduces the shape to a rectangle.
}

@defproc[(path-add-oval! [path skia-path?] [x real?] [y real?]
                        [width (and/c real? (>=/c 0))]
                        [height (and/c real? (>=/c 0))]
                        [#:direction direction (or/c 'cw 'ccw) 'cw]) void?]{
Appends the closed ellipse inscribed in the specified rectangle. Width and
height are the ellipse's diameters.
}

@defproc[(path-add-circle! [path skia-path?] [x real?] [y real?]
                          [radius (and/c real? (>=/c 0))]
                          [#:direction direction (or/c 'cw 'ccw) 'cw]) void?]{
Appends a closed circle centered at coordinates @racket[x] and @racket[y]. A
zero radius is accepted but need not add visible geometry.
}

@defproc[(path-add-path! [destination skia-path?] [source skia-path?]
                        [#:dx dx real? 0] [#:dy dy real? 0]
                        [#:mode mode (or/c 'append 'extend) 'append]) void?]{
Adds @racket[source]'s geometry to @racket[destination], translating its points
by @racket[dx] and @racket[dy]. Append mode preserves the source's initial move.
Extend mode connects the destination's last contour to the source's first
contour with a line when appropriate. The destination's fill rule is unchanged;
it does not adopt the source's rule. Later changes to the source do not edit
the appended geometry.


@racketblock[
(with-skia ([surface (make-surface 220 100 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([source-a (make-path '((move 60 24) (line 92 76)))]
              [append-path (make-path '((move 18 76) (line 50 24)))]
              [source-b (make-path '((move 170 24) (line 202 76)))]
              [extend-path (make-path '((move 128 76) (line 160 24)))]
              [blue (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 5
                                #:cap 'round)]
              [orange (make-paint #:color "#EFA02B" #:style 'stroke #:stroke-width 5
                                  #:cap 'round)])
    (path-add-path! append-path source-a #:mode 'append)
    (path-add-path! extend-path source-b #:mode 'extend)
    (draw-path canvas append-path blue)
    (draw-path canvas extend-path orange))
)
]
@reference-figure["path-extend-stage9.png"
                  "Append mode leaves two blue path segments disconnected on the left, while extend mode adds the orange connecting edge on the right."]
}

@defproc[(path-add-reversed-path! [destination skia-path?] [source skia-path?]) void?]{
Appends the source's contours with their traversal direction reversed. It
reverses segment order and curve controls, not just a list of endpoints. The
destination retains its fill rule and the source remains unchanged.
}

@racketblock[
(with-skia ([path
             (make-path
              '((move 15 75)
                (cubic 45 10 135 10 165 75)))]
            [paint (make-paint #:color "#326DE6"
                               #:style 'stroke
                               #:stroke-width 5)]
            [surface (make-surface 180 100 #:background 'white)])
  (draw-path (surface-canvas surface) path paint))
]

@reference-figure["bezier-path.png"
                  "A thick blue cubic Bezier curve arching upward between two low endpoints."]

@section[#:tag "skia-path-geometry"]{Geometry and Bounds}

@defproc[(path-point-count [path skia-path?]) exact-nonnegative-integer?]{
Returns the number of stored points, including curve controls. This is not the
number of contours or drawing segments.
}

@defproc[(path-point-ref [path skia-path?] [index exact-nonnegative-integer?])
         (values real? real?)]{
Returns the stored point at @racket[index] as x and y values. Indices start at
zero and must be less than @racket[(path-point-count path)].
}

@defproc[(path-points [path skia-path?]) (listof (list/c real? real?))]{
Returns coordinate pairs for all stored points in order. Use
@racket[path-segments] when the distinction between endpoints and control
points is needed.
}

@defproc[(path-last-point [path skia-path?]) (values real? real?)]{
Returns the last stored point as x and y values. An empty path raises an
exception; this operation does not manufacture an origin for an empty path.
}

@defproc[(path-bounds [path skia-path?]) (values real? real? real? real?)]{
Returns the bounds of the stored points, including control points, as left,
top, width, and height. The result can be larger than the curves themselves.
An empty path has zero bounds. This is a geometry query, not a stroke, filter,
clip, or final-pixel bounds calculation.
}

@defproc[(path-tight-bounds [path skia-path?]) (values real? real? real? real?)]{
Returns tighter geometric bounds computed from the curves rather than simply
the control-point bounds. It can require more work than @racket[path-bounds].
It still does not include stroke widths, paint effects, or the canvas transform.
}

@bold{Conceptual diagram.} A cubic's off-curve controls are stored points, but
the curve normally does not pass through them. @racket[path-bounds] encloses all
stored endpoints and controls; @racket[path-tight-bounds] encloses the curve
geometry itself. Both are path-space geometry measurements, not painted-pixel
bounds.

@reference-figure["concept-path-bounds.png"
                  "A cubic Bezier arch shows its two off-curve controls and dashed control polygon. A red rectangle encloses stored points, while a smaller green rectangle encloses tight curve geometry; labels state that neither includes stroke, filters, transforms, or clips."]

@defproc[(path-contains? [path skia-path?] [x real?] [y real?]) boolean?]{
Reports whether the point is contained in the path's filled region according
to its fill rule. The coordinates are in path space. Paint stroke settings
and canvas transforms are not applied, so this is not a stroked-outline hit test.
}

@defproc[(path-convex? [path skia-path?]) boolean?]{
Returns Skia's convexity classification for the path. Skia may compute and cache
the classification. The query does not change the visible geometry.
}

@section{Transforming and Serializing Geometry}

@defproc[(path-transform [path skia-path?] [matrix matrix?]) skia-path?]{
Returns a new owned path containing the affine transformation of @racket[path].
The source is not changed, and the result does not borrow the source. This
operation changes geometry rather than a canvas's drawing state.
}

@defproc[(path-transform! [path skia-path?] [matrix matrix?]) void?]{
Applies the affine transform to @racket[path] in place. Its current geometry is
replaced by the transformed geometry; earlier canvas drawing is unaffected.
}

@defproc[(svg-path->path [data string?]
                        [#:fill-rule fill-rule (or/c 'winding 'even-odd) 'winding]) skia-path?]{
Parses SVG path-data syntax into an owned path. The string is the contents of a
path's @tt{d} attribute, not an entire SVG document. Embedded NUL characters and
invalid path syntax raise exceptions. The supplied fill rule is independent
of the command string.


@racketblock[
(with-skia ([surface (make-surface 220 120 #:background 'white)]
            [path (svg-path->path
                   "M20 38 C20 12 55 12 55 38 C55 12 90 12 90 38 C90 65 55 88 55 88 C55 88 20 65 20 38 Z")]
            [paint (make-paint #:color "#E94F37")])
  (with-canvas-state (surface-canvas surface)
    (canvas-translate! (surface-canvas surface) 45 5)
    (canvas-scale! (surface-canvas surface) 1.25 1.15)
    (draw-path (surface-canvas surface) path paint)))
]
@reference-figure["svg-path-stage8.png"
                  "A red heart-like filled shape parsed directly from SVG path-data syntax."]
}

@defproc[(path->svg-path [path skia-path?]) string?]{
Returns SVG path data for the geometry. It does not include the path's fill
rule, a paint, or an SVG element. The result is not required to preserve the
source spelling, relative commands, or exact curve representation.
}

@defproc[(path->commands [path skia-path?]) list?]{
Returns a list of commands accepted by @racket[make-path], derived
from raw native path iteration. Commands use absolute coordinates. The list
does not carry the fill rule, so copy that separately when reconstructing a
path. It describes the native geometry, not necessarily the exact commands
originally supplied.

@racketblock[
(with-skia ([path (make-path '((move 2 3) (rline 4 0)) #:fill-rule 'even-odd)]
            [copy (make-path (path->commands path) #:fill-rule (path-fill-rule path))])
  (path-points copy))
]
}

@section[#:tag "skia-path-iteration"]{Inspecting Segments and Contours}

The inspection functions copy their results while the native path is valid.
Their results are Racket structures and coordinate lists, not live iterators.
A snapshot charges a bounded logical payload against
@racket[current-skia-byte-limit]; this is not an exact Racket heap-size estimate.

@defproc[(path-segments [path skia-path?]
                       [#:mode mode (or/c 'normal 'raw) 'normal]
                       [#:force-closed? force-closed? boolean? #f]) (listof path-segment?)]{
Returns a snapshot of path segments. Normal mode uses Skia's drawing-oriented
iterator, which can skip degeneracies and emit an explicit closing line before
a close verb. Raw mode follows the stored verbs and does not mark closing lines.

The @racket[force-closed?] option closes open contours for normal iteration
without modifying the source. Combining raw mode with forced closure raises
an exception.

@racketblock[
(with-skia ([path (make-path '((move 10 20) (line 40 20) (line 40 50) (close)))])
  (for/list ([mode '(normal raw)])
    (for/list ([segment (in-list (path-segments path #:mode mode))])
      (list (path-segment-verb segment)
            (path-segment-closing-line? segment)))))
]

Normal iteration reports three line segments: the third returns to the contour's
starting point and has a true closing-line flag. Raw iteration reports the two
stored line segments followed by @racket['close]; it reports no closing-line
flag. Neither snapshot changes the source path.
}

@defproc[(in-path-segments [path skia-path?]
                          [#:mode mode (or/c 'normal 'raw) 'normal]
                          [#:force-closed? force-closed? boolean? #f]) sequence?]{
Returns a sequence over the same snapshot as @racket[path-segments].
The snapshot is taken when this function is called, not when iteration begins.
}

@defproc[(path-segment? [v any/c]) boolean?]{
Returns @racket[#t] for a segment description produced by path inspection and
@racket[#f] otherwise.
}

@defproc[(path-segment-verb [segment path-segment?])
         (or/c 'move 'line 'quad 'conic 'cubic 'close)]{
Returns the segment's verb. It identifies how to interpret the stored points.
}

@defproc[(path-segment-points [segment path-segment?]) (listof (list/c real? real?))]{
Returns the segment's coordinate pairs. A move has one point; a line has start
and end points; quadratic and conic segments have start, control, and end points;
a cubic has start, two controls, and end; a close has no points. Segment data
therefore includes starts that the command format of @racket[make-path] omits.
}

@defproc[(path-segment-conic-weight [segment path-segment?]) (or/c real? #f)]{
Returns the conic weight for a conic segment, or @racket[#f] for another verb.
}

@defproc[(path-segment-closing-line? [segment path-segment?]) boolean?]{
Returns @racket[#t] only for a line identified as a closing line by normal
iteration. A close verb itself returns @racket[#f], as do all raw-mode segments.
}

@defproc[(path-contours [path skia-path?]
                       [#:mode mode (or/c 'normal 'raw) 'normal]
                       [#:force-closed? force-closed? boolean? #f]) (listof path-contour?)]{
Groups a segment snapshot into contours. A move begins a new group.
The mode and forced-closure restrictions are those of @racket[path-segments].
}

@defproc[(path-contour? [v any/c]) boolean?]{
Returns @racket[#t] for a contour description and @racket[#f] otherwise.
}

@defproc[(path-contour-segments [contour path-contour?]) (listof path-segment?)]{
Returns the segments of the contour snapshot in traversal order.
}

@defproc[(path-contour-closed? [contour path-contour?]) boolean?]{
Reports whether the snapshot ends with a close verb. A forced-closed snapshot
can report @racket[#t] even though the original path was open. Implicit closure
for filling is not the same as an explicit close in a raw snapshot.
}

@section[#:tag "skia-path-operations"]{Combining Filled Regions}

These operations work on filled path geometry and respect the input fill
rules. They do not combine stroked outlines, painted pixels, or filters. Results
are new owned paths; the inputs are unchanged. Skia can reduce curve order and
rearrange contours, so result commands need not resemble the input commands.
A native failure raises an exception and releases the incomplete result.

@defproc[(path-op [first skia-path?] [second skia-path?]
                  [operation (or/c 'difference 'intersect 'union 'xor 'reverse-difference)])
         skia-path?]{
Combines the two filled regions. Difference keeps the first outside the second;
intersection keeps their common region; union keeps either region; exclusive-or
keeps points in exactly one region; reverse difference keeps the second outside
the first.
}

@defproc[(path-union [first skia-path?] [second skia-path?]) skia-path?]{
Returns @racket[(path-op first second 'union)].
}
@defproc[(path-intersect [first skia-path?] [second skia-path?]) skia-path?]{
Returns @racket[(path-op first second 'intersect)].
}
@defproc[(path-difference [first skia-path?] [second skia-path?]) skia-path?]{
Returns @racket[(path-op first second 'difference)]. Argument order matters.
}
@defproc[(path-xor [first skia-path?] [second skia-path?]) skia-path?]{
Returns @racket[(path-op first second 'xor)].
}
@defproc[(path-reverse-difference [first skia-path?] [second skia-path?]) skia-path?]{
Returns @racket[(path-op first second 'reverse-difference)].


@racketblock[
(with-skia ([surface (make-surface 180 110 #:background 'white)]
            [a (make-path)] [b (make-path)]
            [paint (make-paint #:color "#326DE6")])
  (path-add-circle! a 65 55 38)
  (path-add-circle! b 108 55 31)
  (with-skia ([result (path-reverse-difference a b)])
    (draw-path (surface-canvas surface) result paint)))
]
@reference-figure["reverse-difference-stage8.png"
                  "Reverse difference keeps the portion of the second circle that lies outside the first, producing a blue crescent."]
}

@defproc[(path-simplify [path skia-path?]) skia-path?]{
Returns a path for the same filled region with overlaps and self-intersections
resolved by Skia. It is not a point-count minimizer or a command-preserving copy.


@racketblock[
(with-skia ([surface (make-surface 200 110 #:background 'white)]
            [path (make-path '((move 20 90) (line 100 15)
                               (line 180 90) (line 40 45)
                               (line 160 45) (close)))]
            [paint (make-paint #:color "#326DE6")])
  (with-skia ([simple (path-simplify path)])
    (draw-path (surface-canvas surface) simple paint)))
]
@reference-figure["simplify-path-stage8.png"
                  "A self-intersecting star-like contour is resolved into its filled blue region by path simplification."]
}

@defproc[(path-as-winding [path skia-path?]) skia-path?]{
Returns a winding-rule path representing the input's filled region. Unlike
merely setting the fill rule, this operation can change contour directions or
geometry to preserve the represented region. Failure raises an exception.


@racketblock[
(with-skia ([surface (make-surface 200 110 #:background 'white)]
            [path (make-path #:fill-rule 'even-odd)]
            [paint (make-paint #:color "#326DE6")])
  (path-add-circle! path 100 55 43)
  (path-add-circle! path 100 55 20)
  (with-skia ([winding (path-as-winding path)])
    (draw-path (surface-canvas surface) winding paint)))
]
@reference-figure["as-winding-stage8.png"
                  "A winding-rule conversion preserves the white hole inside a blue even-odd ring."]
}

@section[#:tag "skia-path-measure"]{Measuring Contours}

Use a path measure when distances along a curve matter: for example, to place
markers at regular intervals, move an object along a route, or draw only part
of a contour. Create it with @racket[make-path-measure], then query positions
with @racket[path-measure-position+tangent] or extract a portion with
@racket[path-measure-segment].

A @deftech{path measure} is an owned native resource that measures one contour
at a time from a snapshot of a path. It does not measure stroke outlines or a
canvas-transformed version of the path unless that transform was applied to
the path beforehand. Lengths and curve positions are numerical approximations.

@defproc[(path-measure? [v any/c]) boolean?]{
Returns @racket[#t] for a path-measure resource, including a closed wrapper,
and @racket[#f] otherwise.
}

@defproc[(make-path-measure [path skia-path?]
                           [#:force-closed? force-closed? boolean? #f]
                           [#:res-scale resolution-scale (and/c real? (>/c 0)) 1]) path-measure?]{
Creates a measure of an independent snapshot of @racket[path]. Later mutation
or closure of the path does not affect it. Forced closure includes a closing
segment for each open contour without changing the source.

The positive @racket[resolution-scale] controls approximation precision;
values above one request finer measurement at additional cost. It is
not a geometric scale factor and does not multiply reported lengths.
}

@defproc[(path-measure-set-path! [measure path-measure?] [path (or/c skia-path? #f)]
                                [#:force-closed? force-closed? boolean? #f]) void?]{
Replaces the measured path with a fresh snapshot and resets contour traversal.
Passing @racket[#f] removes the path. The constructor's resolution scale remains
in effect. The caller retains ownership of the supplied path wrapper.
}

@defproc[(path-measure-length [measure path-measure?]) real?]{
Returns the length of the current contour, or zero when no measurable contour
is available. It is not the sum of all contour lengths.
}

@defproc[(path-measure-closed? [measure path-measure?]) boolean?]{
Reports whether the current measured contour is closed, taking forced closure
into account.
}

@defproc[(path-measure-next-contour! [measure path-measure?]) boolean?]{
Advances to the next contour and returns @racket[#t] when one exists. Returns
@racket[#f] when there is no next contour. It does not wrap back to the first.
}

@defproc[(path-measure-position+tangent [measure path-measure?]
                                       [distance (and/c real? (>=/c 0))])
         (values (or/c real? #f) (or/c real? #f) (or/c real? #f) (or/c real? #f))]{
Returns the position x and y and the unit tangent x and y at @racket[distance].
The distance must be nonnegative and no greater than the current
contour's measured length. An out-of-range value raises an exception.
An unavailable position, such as on a zero-length contour, returns four
@racket[#f] values instead of uninitialized coordinates.

@racketblock[
(with-skia ([path (make-path '((move 0 0) (line 30 40)))]
            [measure (make-path-measure path)])
  (path-measure-position+tangent measure 25))
]


@racketblock[
(with-skia ([surface (make-surface 240 120 #:background 'white)]
            [path (make-path '((move 20 90) (cubic 70 10 170 10 220 90)))]
            [measure (make-path-measure path)]
            [curve (make-paint #:color "#BBBBBB" #:style 'stroke #:stroke-width 3)]
            [mark (make-paint #:color "#326DE6")]
            [tangent (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 3)])
  (draw-path (surface-canvas surface) path curve)
  (define distance (/ (path-measure-length measure) 2))
  (define-values (x y tx ty)
    (path-measure-position+tangent measure distance))
  (draw-circle (surface-canvas surface) x y 6 mark)
  (draw-line (surface-canvas surface) x y
             (+ x (* 30 tx)) (+ y (* 30 ty))
             tangent))
]
@reference-figure["measure-tangent-stage8.png"
                  "A blue point marks the halfway position on a pale cubic curve, with a short blue line showing its tangent direction."]
}

@defproc[(path-measure-segment [measure path-measure?]
                              [start (and/c real? (>=/c 0))]
                              [stop (and/c real? (>=/c 0))]
                              [#:start-with-move-to? start-with-move-to? boolean? #t])
         (or/c skia-path? #f)]{
Returns a new owned path for the portion between @racket[start] and
@racket[stop]. Both distances must be within the current contour and
@racket[start] must be less than @racket[stop]. An invalid range raises an
exception. A native extraction with no resulting segment returns @racket[#f].

The default starts the result with a move to the segment's starting point.
Passing @racket[#f] omits that move. This binding always creates a new result
path, so Skia inserts an implicit move to the origin before its first segment.
The result does not connect to the source path's current point.

@racketblock[
(with-skia ([surface (make-surface 240 115 #:background 'white)]
            [path (make-path '((move 10 20) (line 90 20)))]
            [measure (make-path-measure path)]
            [moved (path-measure-segment measure 20 40)]
            [unmoved (path-measure-segment measure 20 40 #:start-with-move-to? #f)]
            [guide (make-paint #:color "#C8CDD3" #:style 'stroke #:stroke-width 2)]
            [result (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 4)]
            [font (make-font #:size 12)]
            [label (make-paint #:color "#20344E")])
  (define canvas (surface-canvas surface))
  (draw-simple-text canvas "with initial move" 10 18 font label)
  (with-canvas-state canvas
    (canvas-translate! canvas 10 25)
    (draw-path canvas path guide)
    (draw-path canvas moved result))
  (draw-simple-text canvas "without initial move" 125 18 font label)
  (with-canvas-state canvas
    (canvas-translate! canvas 125 25)
    (draw-path canvas path guide)
    (draw-path canvas unmoved result))
  (list (path->commands moved) (path->commands unmoved)))
]

@reference-figure["path-segment-initial-move.png"
                  "Two coordinate panels for the same extracted path-measure segment. In the left panel the blue segment follows the faint source guide from x=30 to x=50; in the right, omitting the initial move creates a blue line from the coordinate origin to x=50."]

Each faint line is the original source path. The two blue paths are separate returned values;
their difference is caused only by the @racket[#:start-with-move-to?] choice.

The first result starts at coordinates 30 and 20 and draws a line to coordinates
50 and 20. The second starts at coordinates 0 and 0 and draws a line to coordinates
50 and 20. Omitting the move therefore changes the geometry; it does not simply
remove a redundant command from the independently returned path.
}

@defproc[(path-measure-matrix [measure path-measure?]
                             [distance (and/c real? (>=/c 0))]
                             [#:mode mode (or/c 'position 'tangent 'position+tangent)
                                    'position+tangent]) (or/c matrix? #f)]{
Returns a placement matrix at @racket[distance]. Position mode supplies
translation to the measured point; tangent mode supplies a rotation aligning
the x axis with the tangent; the default combines both. An unavailable
measurement returns @racket[#f].

Unlike @racket[path-measure-position+tangent], this function accepts a distance
past the contour's end: the native measurement clamps it to the contour length.
Negative distances are still rejected by the wrapper. The distinction matters
when sharing a distance between the two APIs.
}

@racketblock[
(with-skia ([surface (make-surface 420 235 #:background 'white)]
            [quadratic (make-path '((move 20 140) (quad 70 30 120 140)))]
            [control-polygon (make-path '((move 20 140) (line 70 30) (line 120 140)))]
            [contours (make-path '((move 235 135) (cubic 260 75 330 175 370 105)
                                  (move 235 190) (line 370 190)))]
            [measure (make-path-measure contours)]
            [arrow (make-path '((move -12 -6) (line 10 0) (line -2 5)
                                (line -2 2) (line -12 2) (close)))]
            [dash (make-dash-path-effect '(4 3))]
            [curve (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 4)]
            [control (make-paint #:color "#9BA6B5" #:style 'stroke #:stroke-width 2
                                 #:path-effect dash)]
            [stored-bound (make-paint #:color "#E94F37" #:style 'stroke #:stroke-width 2)]
            [tight-bound (make-paint #:color "#EFA02B" #:style 'stroke #:stroke-width 2)]
            [guide (make-paint #:color "#9BA6B5" #:style 'stroke #:stroke-width 3)]
            [first-arrow (make-paint #:color "#326DE6")]
            [second-arrow (make-paint #:color "#7D5BA6")]
            [font (make-font #:size 10)]
            [label (make-paint #:color "#20344E")])
  (define canvas (surface-canvas surface))
  (define-values (left top width height) (path-bounds quadratic))
  (define-values (tight-left tight-top tight-width tight-height) (path-tight-bounds quadratic))
  (draw-simple-text canvas "quadratic: control points vs. curve" 18 17 font label)
  (draw-path canvas control-polygon control)
  (draw-path canvas quadratic curve)
  (draw-rect canvas left top width height stored-bound)
  (draw-rect canvas tight-left tight-top tight-width tight-height tight-bound)
  (draw-simple-text canvas "red = stored-point bounds" 18 165 font label)
  (draw-simple-text canvas "orange = tight curve bounds" 18 181 font label)
  (draw-simple-text canvas "path-measure-matrix on two contours" 230 17 font label)
  (draw-path canvas contours guide)
  (define first-placement (path-measure-matrix measure (* 0.55 (path-measure-length measure))))
  (with-canvas-state canvas
    (canvas-concat! canvas first-placement)
    (draw-path canvas arrow first-arrow))
  (path-measure-next-contour! measure)
  (define second-placement (path-measure-matrix measure (* 0.55 (path-measure-length measure))))
  (with-canvas-state canvas
    (canvas-concat! canvas second-placement)
    (draw-path canvas arrow second-arrow))
  (draw-simple-text canvas "blue: first contour" 235 210 font label)
  (draw-simple-text canvas "purple: after next-contour!" 235 225 font label)
  surface)
]
@reference-figure["path-bounds-and-measure-matrix.png"
                  "Left: a blue quadratic curve lies inside orange tight geometric bounds, while larger red stored-point bounds include its high control point and dashed control polygon. Right: a blue asymmetric arrow is placed and tangent-aligned on the first gray contour; after advancing the measure, a purple arrow is placed on the second straight contour."]

Neither bounds rectangle includes a stroke width or canvas transform.  The
placement matrices are evaluated from the current contour: advancing with
@racket[path-measure-next-contour!] is what makes the purple arrow use the
second contour rather than another distance on the curve.

@section[#:tag "skia-path-completion"]{Arcs, Recognition, and Ordered Operations}

@(declare-exporting skia skia/geometry #:use-sources (skia/geometry))

These operations extend the path construction and inspection interfaces.
Angles are in degrees. A positive oval sweep is clockwise in the usual
unreflected coordinate system with the y-axis pointing downward.
Rectangle arguments use coordinates, width, and height; positive extents must
remain positive when the right and bottom edges are rounded. Arc radii are
checked for nonnegativity after binary32 rounding; a negative input that rounds
to negative zero is therefore accepted as zero.

The operations require live paths on their owning thread. Construction changes
the destination path, not its paint or a canvas. Native recognition tests
stored representations, not arbitrary geometric equivalence.

@defproc[(path-arc-to! [path path?]
          [rx real?]
          [ry real?]
          [rotation real?]
          [x real?]
          [y real?]
          [#:large? large? boolean? #f]
          [#:direction direction (or/c 'cw 'ccw) 'cw])
          void?]{
Appends an elliptical arc from the current point to coordinates @racket[x]
and @racket[y]. The radii and @racket[rotation] describe the ellipse's axes.
The @racket[large?] flag selects the large rather than small arc, and
@racket[direction] selects its traversal direction. Skia can adjust insufficient
radii to reach the endpoint. Zero radii and coincident endpoints retain native
degenerate behavior; this operation does not create an alternative arc algorithm.
}

@defproc[(path-rarc-to! [path path?]
          [rx real?]
          [ry real?]
          [rotation real?]
          [dx real?]
          [dy real?]
          [#:large? large? boolean? #f]
          [#:direction direction (or/c 'cw 'ccw) 'cw])
          void?]{
Appends an elliptical arc from the current point to the point displaced by
@racket[dx] and @racket[dy]. Raises an exception if adding the offsets to the
current point produces an endpoint outside the numeric limits in
@secref["skia-scalars"]. The radii, axis rotation, and arc choices have the same
meanings as in @racket[path-arc-to!].
}

@defproc[(path-arc-to-oval! [path path?]
          [x real?]
          [y real?]
          [width (and/c real? (>=/c 0))]
          [height (and/c real? (>=/c 0))]
          [start real?]
          [sweep real?]
          [#:force-move? force-move? boolean? #f])
          void?]{
Appends an arc of the specified oval, starting at @racket[start] and sweeping
through @racket[sweep] degrees. A zero start angle is at the oval's rightmost
point. The operation can connect the existing contour to the arc's start.
A true @racket[force-move?] starts a new contour instead of adding that connection.
}

@defproc[(path-tangent-arc-to! [path path?]
          [x1 real?]
          [y1 real?]
          [x2 real?]
          [y2 real?]
          [radius real?])
          void?]{
Appends a circular arc tangent to the line from the current point toward the
first point and the line from the first point toward the second. A connecting
line can precede the arc. The operation does not append a final line to the
second point. Degenerate inputs use Skia's tangent-arc behavior.
}

@defproc[(path-add-arc! [path path?]
          [x real?]
          [y real?]
          [width (and/c real? (>=/c 0))]
          [height (and/c real? (>=/c 0))]
          [start real?]
          [sweep real?])
          void?]{
Adds an oval arc as a new contour, rather than connecting it to the preceding
contour. The oval and angle conventions are those of @racket[path-arc-to-oval!].
The native full-oval and degenerate cases are preserved.
}

@defproc[(path-add-rect-start! [path path?]
          [x real?]
          [y real?]
          [width (and/c real? (>=/c 0))]
          [height (and/c real? (>=/c 0))]
          [start (integer-in 0 3)]
          [#:direction direction (or/c 'cw 'ccw) 'cw])
          void?]{
Adds a rectangle contour with an explicit starting corner. Indices 0, 1, 2,
and 3 select top-left, top-right, bottom-right, and bottom-left, respectively.
An out-of-range index raises an exception; it is not reduced modulo four.
}

@defproc[(path-add-rrect! [path path?]
          [shape rounded-rect?]
          [#:direction direction (or/c 'cw 'ccw) 'cw]
          [#:start-index start (integer-in 0 7) 0])
          void?]{
Adds the native-normalized rounded rectangle as a new contour. The start index
selects one of Skia's eight tangent points, not one of four corner centers.
Indices follow the clockwise boundary: the top edge's left and right tangent
points, the right edge's top and bottom points, the bottom edge's right and left
points, and the left edge's bottom and top points. Direction changes traversal,
not the indexing convention. The shape remains unchanged.
}

@defproc[(path-add-polygon! [path path?]
          [points (or/c list? vector?)]
          [#:closed? closed? boolean? #t])
          void?]{
Adds a contour from a list or vector of two-element point lists or vectors.
All coordinates are validated and copied before mutation. A true @racket[closed?]
closes the contour. Empty input draws nothing but still validates the path.
The submitted point count and bytes are bounded by @racket[current-skia-byte-limit].


@racketblock[
(with-skia ([surface (make-surface 180 100 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([path (make-path)]
              [paint (make-paint #:color "#326DE6")])
    (path-add-polygon! path '((90 12) (160 42) (136 88) (44 88) (20 42)))
    (draw-path canvas path paint))
)
]
@reference-figure["path-polygon-stage9.png"
                  "A filled blue pentagon is drawn from a polygon contour appended to a path."]
}

@defproc[(path-add-transformed! [path path?]
          [other path?]
          [transform matrix?]
          [#:mode mode (or/c 'append 'extend) 'append])
          void?]{
Adds the source geometry after applying the affine transform. Append preserves
its contour starts; extend can join its first contour to the current contour
as in @racket[path-add-path!]. A distinct source path is unchanged. Singular
affine matrices are allowed. This is not a projective path transformation.
}

@defproc[(path-rewind! [path path?])
          void?]{
Clears the path's contours for reuse while retaining native storage where
possible. Native rewind resets the fill type to winding, like
@racket[path-reset!], but preserves internal storage for reuse.
}

@defproc[(path-verbs [path path?])
          (listof (or/c 'move 'line 'quad 'conic 'cubic 'close))]{
Returns the verbs from raw path iteration, in stored order. It is equivalent
to mapping @racket[path-segment-verb] over @racket[path-segments] with
@racket[#:mode 'raw]; no synthetic closing line is inserted.
}

@defproc[(path-segment-kinds [path path?])
          (listof (or/c 'line 'quad 'conic 'cubic))]{
Returns the distinct drawing-segment kinds present, in the order line, quad,
conic, cubic. Moves and closes are not segment kinds, and repeated segments do
not produce repeated names. This is a summary, not contour order.
}

@defproc[(path-fill-bounds [path path?])
          (and/c (vector/c real? real? real? real?) immutable?)]{
Returns the tight rectangle reported by native path operations. Native failure
raises an exception. The result is not a control-point bound, a painted stroke
or filter bound, or a finite description of the area outside an inverse path.
}

@defproc[(path-as-line [path path?])
          (or/c #f (and/c (vector/c (and/c (vector/c real? real?) immutable?)
                                               (and/c (vector/c real? real?) immutable?))
                                               immutable?))]{
Returns the two endpoints when native recognition identifies a line, or
@racket[#f] otherwise. The outer vector and both point vectors are immutable.
}

@defproc[(path-as-oval [path path?])
          (or/c #f (and/c (vector/c real? real? real? real?) immutable?))]{
Returns the oval's bounds when native recognition succeeds, or @racket[#f]
otherwise. An arbitrary curve with a similar outline need not be recognized.
}

@defproc[(path-as-rectangle [path path?])
          (or/c path-rectangle? #f)]{
Returns a rectangle description when native recognition succeeds,
or @racket[#f] otherwise. The description records bounds, explicit closure,
and traversal direction; recognition alone does not imply a closed contour.
}

@defproc[(path-as-rounded-rect [path path?])
          (or/c rounded-rect? #f)]{
Returns a native-normalized rounded rectangle when recognized, or
@racket[#f] otherwise.
}

@defproc[(path-rectangle? [v any/c])
          boolean?]{
Returns @racket[#t] for a rectangle description returned by
@racket[path-as-rectangle], and @racket[#f] otherwise.
}

@defproc[(path-rectangle-bounds [description path-rectangle?])
          (and/c (vector/c real? real? real? real?) immutable?)]{
Returns the immutable coordinates, width, and height of the recognized rectangle.
}

@defproc[(path-rectangle-closed? [description path-rectangle?])
          boolean?]{
Reports whether the recognized rectangle contour was explicitly closed.
}

@defproc[(path-rectangle-direction [description path-rectangle?])
          (or/c 'cw 'ccw)]{
Returns the recognized traversal direction.
}

@defproc[(conic->quadratics [p0 (or/c (list/c real? real?) (vector/c real? real?))]
          [p1 (or/c (list/c real? real?) (vector/c real? real?))]
          [p2 (or/c (list/c real? real?) (vector/c real? real?))]
          [weight (and/c real? (>/c 0))]
          [#:subdivisions power (integer-in 0 5) 2])
          (listof (and/c vector? immutable?))]{
Approximates a rational quadratic with ordinary quadratic segments. The three
points are its start, control point, and end. The weight must remain strictly
positive after binary32 rounding. The subdivision exponent limits the result
to at most @racket[(expt 2 power)] segments, rather than specifying an error tolerance.

Each segment is an immutable vector of three immutable two-coordinate point
vectors. Adjacent triples have equal endpoint values. The native routine's
actual count is used and checked; it need not equal the maximum. Temporary
point storage is bounded by @racket[current-skia-byte-limit].
}

@defproc[(path-combine [operations (or/c list? vector?)])
          path?]{
Combines a list or vector of two-element operation/path pairs, starting with
an empty accumulator. Operations are @racket['union], @racket['difference],
@racket['intersect], @racket['xor], and @racket['reverse-difference], applied
in input order. The input paths remain unchanged and the result is independently owned.
An empty batch returns an owned empty path.

The batch is bounded by @racket[current-path-operation-limit] and by the submitted
point/verb payload under @racket[current-skia-byte-limit]. These are not native
heap or running-time bounds. Failure raises without publishing a partial result.

@racketblock[
(with-skia ([outer (make-path)] [hole (make-path)])
  (path-add-rect! outer 20 15 120 70)
  (path-add-circle! hole 80 50 22)
  (with-skia ([result (path-combine
                      (list (list 'union outer) (list 'difference hole)))])
    (list (path-contains? result 25 20) (path-contains? result 80 50))))
]

The result contains the corner point but not the center of the removed circle.

@reference-figure["path-hole.png"
                  "A blue rectangular path with a circular hole removed from its center."]
}

@defparam[current-path-operation-limit limit (integer-in 1 #x7fffffff) #:value 4096]{
Bounds the number of entries accepted by @racket[path-combine]. The default is
4096. Lowering this parameter does not change an already constructed path.
}

@section{Additional Visual Examples}

These examples compare curve kinds, path transforms, measurement, and Boolean operations.

@racketblock[
(with-skia ([path (make-path)]
            [paint (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 5)]
            [surface (make-surface 180 100 #:background 'white)])
  (path-move-to! path 15 80)
  (path-quad-to! path 90 5 165 80)
  (draw-path (surface-canvas surface) path paint))
]
@reference-figure["quadratic-path.png"
                  "A thick blue quadratic Bezier arc rising from two low endpoints toward one high control point."]

@racketblock[
(with-skia ([path (make-path)]
            [paint (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 5)]
            [surface (make-surface 180 100 #:background 'white)])
  (path-move-to! path 15 80)
  (path-conic-to! path 90 5 165 80 0.45)
  (draw-path (surface-canvas surface) path paint))
]
@reference-figure["conic-path.png"
                  "A thick blue rational quadratic curve whose weight pulls it differently from an ordinary quadratic."]

@racketblock[
(with-skia ([path (make-path)]
            [paint (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 5)]
            [surface (make-surface 180 100 #:background 'white)])
  (path-add-arc! path 25 15 130 70 200 250)
  (draw-path (surface-canvas surface) path paint))
]
@reference-figure["path-arc.png"
                  "A blue elliptical arc drawn as its own path contour."]

@racketblock[
(with-skia ([source (make-path '((move 20 85) (line 70 20) (line 110 85) (close)))]
            [surface (make-surface 190 120 #:background 'white)]
            [paint (make-paint #:color "#326DE6")])
  (with-skia ([moved (path-transform source
                     (matrix-compose (matrix-translate 55 5)
                                     (matrix-rotate-degrees 12)))])
    (draw-path (surface-canvas surface) moved paint)))
]
@reference-figure["path-transform.png"
                  "A filled blue triangle after an affine translation and rotation have been applied to its path geometry."]

@racketblock[
(with-skia ([path (make-path '((move 20 40) (line 170 40)))]
            [measure (make-path-measure path)]
            [paint (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 6)]
            [surface (make-surface 190 80 #:background 'white)])
  (with-skia ([segment (path-measure-segment measure 35 120)])
    (draw-path (surface-canvas surface) segment paint)))
]
@reference-figure["path-measure-segment.png"
                  "A blue middle segment extracted by measured distances from a longer horizontal path."]

@racketblock[
(with-skia ([a (make-path)] [b (make-path)]
            [surface (make-surface 170 100 #:background 'white)]
            [paint (make-paint #:color "#326DE6")])
  (path-add-circle! a 65 50 34)
  (path-add-circle! b 105 50 34)
  (with-skia ([result (path-union a b)])
    (draw-path (surface-canvas surface) result paint)))
]
@reference-figure["path-union.png"
                  "The union of two overlapping circles, filled as one blue shape."]

@racketblock[
(with-skia ([a (make-path)] [b (make-path)]
            [surface (make-surface 170 100 #:background 'white)]
            [paint (make-paint #:color "#326DE6")])
  (path-add-circle! a 65 50 34)
  (path-add-circle! b 105 50 34)
  (with-skia ([result (path-intersect a b)])
    (draw-path (surface-canvas surface) result paint)))
]
@reference-figure["path-intersection.png"
                  "Only the lens-shaped overlap of two circles remains after path intersection."]

@racketblock[
(with-skia ([a (make-path)] [b (make-path)]
            [surface (make-surface 170 100 #:background 'white)]
            [paint (make-paint #:color "#326DE6")])
  (path-add-circle! a 65 50 34)
  (path-add-circle! b 105 50 34)
  (with-skia ([result (path-xor a b)])
    (draw-path (surface-canvas surface) result paint)))
]
@reference-figure["path-xor.png"
                  "Two blue crescent regions remain after exclusive-or removes the circles' overlap."]
