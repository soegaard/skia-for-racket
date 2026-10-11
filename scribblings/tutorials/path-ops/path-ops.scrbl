#lang scribble/manual

@(require racket/file racket/runtime-path "eval.rkt" "../support/source.rkt"
          (for-label racket skia))
@(define-runtime-path program-source "badge.rkt")

@title{Path Operations — Construct a Cutout Badge}

@section{The Finished Badge}

@(badge-pict)

The badge on the right is one path, assembled from circles and rectangles.
Its center and surrounding gaps are genuinely empty. The checkerboard shows
through because those regions are not part of the filled path, not because we
painted them in a matching background color.

@centered{@bold{Combine filled regions first. Draw the resulting geometry afterward.}}

The earlier path tutorial constructed contours command by command. This one
builds new contours by taking unions, intersections, differences, and exclusive
regions. Save the complete @filepath{badge.rkt} file at the end to use its helpers.

@section{Start with Two Filled Shapes}

A disk forms the body of the badge. Two overlapping rectangles form a cross:

@codeblock[(source-definition program-source 'circle-path)]
@codeblock[(source-definition program-source 'cross-path)]

Create the initial operands:

@paths-racketblock+eval[
(require skia "badge.rkt")
(define disk (circle-path 92))
(define cross (cross-path))
]

@(operands-pict)

All coordinates are in the same model space, centered at (160, 160). The cross
has two contours with the default winding fill. Their overlap is filled.
The internal lines in the stroked cross show its original rectangle boundaries.

A Boolean operation uses each path's @emph{filled region}. It does not look at
the stroke width of a paint or at the transform on some receiving canvas.
Even when the eventual drawing is only an outline, the operation itself is
about filled geometry.

@section{Join the Regions}

The union keeps every point contained in either operand:

@paths-racketblock+eval[
(define joined (path-union disk cross))
]

@(shape-pict 'joined)

The rectangles extend beyond the disk to make four tabs. The union constructs
new boundary geometry; painting the two inputs separately would not remove the
interior edges when stroking their original contours.

The operation returns an independently owned path. The source paths remain
unchanged, so they can be reused for another construction or comparison.

@section{Trim the Outside}

A larger circle limits the badge's outer boundary. The intersection keeps only
the region contained in both the joined shape and that circle:

@paths-racketblock+eval[
(define boundary (circle-path 118))
(define trimmed (path-intersect joined boundary))
]

@(shape-pict 'trimmed)

The tips of the tabs now follow the circular boundary. This is not a temporary
canvas clip: @racket[trimmed] is a new path that can be filled, stroked, inspected,
or drawn on a different canvas without reinstalling a clip.

@section{Cut a Hole}

Subtract a small circle from the trimmed shape:

@paths-racketblock+eval[
(define hole (circle-path 38))
(define cutout (path-difference trimmed hole))
]

@(shape-pict 'cutout)

The first operand is the region to keep; the second is the region to remove.
Reversing them is a different operation. Here the small circle lies entirely
inside the trimmed badge, so subtracting the badge from the small circle would
leave no filled region.

A containment query confirms that the center is absent while a point in the
body remains:

@paths-interaction[
(path-contains? cutout 160 160)
(path-contains? cutout 160 80)
]

The query tests filled containment. It is not a distance-to-stroke test and
does not automatically apply the canvas transform. Convert input coordinates
before querying a transformed drawing, just as in the zoom tutorial.

@section{Add a Rim with Exclusive Regions}

An exclusive-or keeps points in exactly one operand, excluding their overlap.
For nested circles, that leaves a ring:

@paths-racketblock+eval[
(define rim-inside (circle-path 108))
(define rim (path-xor boundary rim-inside))
]

@(shape-pict 'rim)

Both circles contain the center, so it is excluded. Only the larger circle
contains a point near the outside edge, so that part remains. For two crossing
shapes, exclusive-or would keep both non-overlapping portions instead; it is
not generally the same as subtraction.

Join this rim to the cutout body:

@paths-racketblock+eval[
(define badge (path-union cutout rim))
]

@(shape-pict 'badge)

The final union connects the rim to the tabs. It still leaves the central hole
and the four gaps between the disk and rim. A single @racket[draw-path] call can
fill the complete badge.

@section{Resolve Overlapping Contours}

Sometimes the input is already one path containing overlapping contours. The
@racket[path-simplify] function resolves that filled geometry according to its
fill rule:

@paths-racketblock+eval[
(define simplified-cross (path-simplify cross))
]

@(simplify-pict)

The filled cross is the same, but stroking the simplified boundary does not
show the internal rectangle seams. This operation is not a request to flatten
curves, smooth corners, or remove detail within a tolerance. It also does not
promise fewer points in every result.

Our cross uses winding fill. Changing it to even-odd before simplifying would
change the overlap's meaning, so it could change the filled result too. Fill
rules remain relevant even when the shape is later combined with another path.

@section{Draw the Result on Any Background}

The badge is geometry, independent of its appearance. Choose the fill and
outline only when drawing:

@codeblock[(source-definition program-source 'draw-shape)]

@(badge-pict)

The checkerboard is drawn first, then the badge. No background-colored circles
are painted over it. This matters when the background is a photograph, a
gradient, or another drawing: true holes reveal whatever is already there.

The construction is performed before drawing the comparison sheet. In a
repeatedly rendered application, reuse a result until an operand changes rather
than recomputing the Boolean operations for every repaint.

@section{The Complete Program}

Run the example with @tt{racket badge.rkt}. It writes @filepath{cutout-badge.png}.
The result can also use the PDF/SVG drawing routes from earlier tutorials;
there is no new export API to learn here.

@codeblock[(file->string program-source)]

The intermediate paths are ordinary owned CPU resources. Exact contour counts,
point order, and fill-rule normalization in a result are not part of this
example's assumptions. Tests should compare the intended filled geometry rather
than require a particular serialization of Skia's output path.

@section{Try It}

Increase the hole radius from 38 to 55. Then change the inner rim radius from
108 to 100. One edit changes the central opening; the other changes the rim's
thickness. Inspect their effects separately.

Try @racket[path-xor] instead of @racket[path-union] for the disk and cross.
Predict which overlapping parts disappear before rendering. Then restore the
union and move one operand in path coordinates rather than translating the
receiving canvas.

@section{Where to Go From Here}

The example combined filled areas. A stroke-to-path conversion can turn a
painted outline into an operand when a construction needs the outline's actual
area. The Guide covers that conversion, path transforms, inverse fills, bounds,
and failure behavior. Skia raises an error when a path operation fails; a failed
operation is not an empty but valid result.
