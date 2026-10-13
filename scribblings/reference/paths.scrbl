#lang scribble/manual

@(require (for-label racket/base racket/contract racket/sequence skia))

@title[#:tag "skia-paths"]{Paths}

A @deftech{path} stores contours made from straight segments, quadratic and
cubic Bézier curves, rational quadratic curves, and close commands. It is an
owned, mutable native resource. A @deftech{contour} starts with a move and can
be open or explicitly closed. A path stores geometry and a fill rule, not a
paint or canvas transform. The predicate is @racket[skia-path?], which is distinct
from Racket's filesystem-path predicate.

Path coordinates are local coordinates and must be @tech{drawing scalar}s.
Construction and mutation do not use a canvas's current transform. Each native
operation requires an open path on its owning thread. A copied or transformed
path has its own lifetime.

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
contracts as the corresponding path-mutating procedure.

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

The @racket['winding] rule fills points with nonzero signed winding number.
The @racket['even-odd] rule fills points crossed an odd number of times by a ray
to the exterior. Both treat open contours as closed for filling. Explicit
closure still matters for stroke caps and joins. Reversing an inner contour
can create a winding-rule hole; an even-odd hole does not depend on direction.

@racketblock[
(with-skia ([path (make-path '((move 0 0) (line 40 0) (line 20 30) (close)))])
  (path-contains? path 20 10))
]
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
}

@defproc[(path-reset! [path skia-path?]) void?]{
Removes the geometry and resets the fill rule to @racket['winding]. The path
resource remains open and can be reused.
}

@section[#:tag "skia-path-segments-add"]{Adding Segments}

The segment operations below return @racket[(void)]. A move selects the start
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
heights, and radii must be nonnegative. Rectangle right and bottom coordinates
must also be in the drawing-scalar range.

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
}

@defproc[(path-add-reversed-path! [destination skia-path?] [source skia-path?]) void?]{
Appends the source's contours with their traversal direction reversed. It
reverses segment order and curve controls, not just a list of endpoints. The
destination retains its fill rule and the source remains unchanged.
}

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
Returns detached coordinate pairs for all stored points in order. Use
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
}

@defproc[(path->svg-path [path skia-path?]) string?]{
Returns SVG path data for the geometry. It does not include the path's fill
rule, a paint, or an SVG element. The result is not required to preserve the
source spelling, relative commands, or exact curve representation.
}

@defproc[(path->commands [path skia-path?]) list?]{
Returns a detached list of commands accepted by @racket[make-path], derived
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
Their result records and coordinate lists are detached values, not native
iterators or resources. A later mutation or closure of the source is safe.
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
Returns a sequence over the same detached snapshot as @racket[path-segments].
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
Groups a detached segment snapshot into contours. A move begins a new group.
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
}

@defproc[(path-simplify [path skia-path?]) skia-path?]{
Returns a path for the same filled region with overlaps and self-intersections
resolved by Skia. It is not a point-count minimizer or a command-preserving copy.
}

@defproc[(path-as-winding [path skia-path?]) skia-path?]{
Returns a winding-rule path representing the input's filled region. Unlike
merely setting the fill rule, this operation can change contour directions or
geometry to preserve the represented region. Failure raises an exception.
}

@section[#:tag "skia-path-measure"]{Measuring Contours}

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

The positive drawing scalar @racket[resolution-scale] controls approximation
precision; values above one request finer measurement at additional cost. It is
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
The distance must be a nonnegative drawing scalar no greater than the current
contour's measured length. An out-of-range value raises an exception.
An unavailable position, such as on a zero-length contour, returns four
@racket[#f] values instead of uninitialized coordinates.

@racketblock[
(with-skia ([path (make-path '((move 0 0) (line 30 40)))]
            [measure (make-path-measure path)])
  (path-measure-position+tangent measure 25))
]
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
(with-skia ([path (make-path '((move 10 20) (line 90 20)))]
            [measure (make-path-measure path)]
            [moved (path-measure-segment measure 20 40)]
            [unmoved (path-measure-segment measure 20 40 #:start-with-move-to? #f)])
  (list (path->commands moved) (path->commands unmoved)))
]

The first result starts at coordinates 30 and 20 and draws a line to coordinates
50 and 20. The second starts at coordinates 0 and 0 and draws a line to coordinates
50 and 20. Omitting the move therefore changes the geometry; it does not simply
remove a redundant command from the independently returned path.
}

@defproc[(path-measure-matrix [measure path-measure?]
                             [distance (and/c real? (>=/c 0))]
                             [#:mode mode (or/c 'position 'tangent 'position+tangent)
                                    'position+tangent]) (or/c matrix? #f)]{
Returns a detached placement matrix at @racket[distance]. Position mode supplies
translation to the measured point; tangent mode supplies a rotation aligning
the x axis with the tangent; the default combines both. An unavailable
measurement returns @racket[#f].

Unlike @racket[path-measure-position+tangent], this function accepts a distance
past the contour's end: the native measurement clamps it to the contour length.
Negative distances are still rejected by the wrapper. The distinction matters
when sharing a distance between the two APIs.
}
