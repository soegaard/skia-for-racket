#lang scribble/manual

@(require "../support/reader.rkt" "../support/accessible-figures.rkt")

@(require racket/file racket/runtime-path "eval.rkt" "../support/source.rkt"
          (for-label racket skia))
@(define-runtime-path program-source "badge.rkt")

@title[#:style (tutorial-feedback-style)]{Path Operations — Construct a Cutout Badge}
@(tutorial-navigation "path-ops")

@section[#:tag "finished-result"]{The Finished Badge}

@(tutorial-figure
   (string-append
    "The left diagram shows the disk, cross, outer boundary, inner rim boundary, and "
    "central hole. The completed badge on the right has a central opening and four gaps "
    "revealing the checkerboard.")
   (badge-pict))

The badge on the right is one path, assembled from circles and rectangles.
Its center and surrounding gaps are genuinely empty. The checkerboard shows
through because those regions are not part of the filled path, not because we
painted them in a matching background color. The left diagram shows all five
operands: the disk, cross, outer boundary, inner rim boundary, and central hole.

@centered{@bold{Combine filled regions first. Draw the resulting geometry afterward.}}

The @tutorial-link["logo"] lesson constructed contours command by command. This one
builds new contours by taking unions, intersections, differences, and exclusive
regions. Save the complete @filepath{badge.rkt} file at the end to use its helpers.

@tutorial-entry["path-ops"]

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

@(tutorial-figure
   (string-append
    "A disk and a cross share the same model coordinates. The cross consists of two "
    "overlapping rectangle contours whose shared region is filled.")
   (operands-pict))

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

@(tutorial-figure
   (string-append
    "The union of the disk and cross has one outer boundary with four tabs. The internal "
    "edges of the original rectangles are absent.")
   (shape-pict 'joined))

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

@(tutorial-figure
   (string-append
    "The left panel overlays the joined shape and its circular limit. The right panel "
    "keeps their intersection, trimming the four tab tips to the circle.")
   (trim-pair))

The tips of the tabs now follow the circular boundary. This is not a temporary
canvas clip: @racket[trimmed] is a new path that can be filled, stroked, inspected,
or drawn on a different canvas without reinstalling a clip.

@section{Cut a Hole}

Subtract a small circle from the trimmed shape:

@paths-racketblock+eval[
(define hole (circle-path 38))
(define cutout (path-difference trimmed hole))
]

@(tutorial-figure
   (string-append
    "Subtracting the inner circle from the body makes a hole. Subtracting the body from "
    "that inner circle leaves no filled region, so the right panel is only checkerboard.")
   (difference-pair))

The first operand is the region to keep; the second is the region to remove.
Reversing them is a different operation. Here the small circle lies entirely
inside the trimmed badge, so subtracting the badge from the small circle would
leave no filled region. The right panel shows the empty result over an unobstructed checkerboard.

A containment query confirms that the center is absent while a point in the
body remains:

@paths-interaction[
(path-contains? cutout 160 160)
(path-contains? cutout 160 80)
]

The query tests filled containment. It is not a distance-to-stroke test and
does not automatically apply the canvas transform. Convert input coordinates
before querying a transformed drawing, as shown in @tutorial-link["navigation"].

@section{Add a Rim with Exclusive Regions}

An exclusive-or keeps points in exactly one operand, excluding their overlap.
For nested circles, that leaves a ring:

@paths-racketblock+eval[
(define rim-inside (circle-path 108))
(define rim (path-xor boundary rim-inside))
]

@(tutorial-figure
   (string-append
    "Exclusive-or of two nested circles produces a thin rim. The shared central region is "
    "excluded.")
   (shape-pict 'rim))

Both circles contain the center, so it is excluded. Only the larger circle
contains a point near the outside edge, so that part remains. For two crossing
shapes, exclusive-or would keep both non-overlapping portions instead; it is
not generally the same as subtraction. For these nested circles,
@racket[(path-difference boundary rim-inside)] would happen to produce the
same ring: the smaller operand has no area outside the larger one.

The distinction becomes visible when neither circle contains the other:

@paths-racketblock+eval[
(define left-circle (make-path))
(define right-circle (make-path))
(path-add-circle! left-circle 80 100 62)
(path-add-circle! right-circle 140 100 62)
(define one-sided (path-difference left-circle right-circle))
(define both-sides (path-xor left-circle right-circle))
]

@(tutorial-figure
   (string-append
    "Overlapping circles A and B are followed by A minus B, which keeps one crescent, and "
    "A exclusive-or B, which keeps both outer crescents but excludes their overlap.")
   (xor-comparison))

The middle panel keeps only the part of A outside B. The right panel also
keeps the part of B outside A. Both exclude the shared lens. The badge uses
the nested-circle case, but exclusive-or is not a synonym for cutting one
shape out of another.

Return to the badge and join its rim to the cutout body:

@paths-racketblock+eval[
(define badge (path-union cutout rim))
]

@(tutorial-figure
   (string-append
    "The final union connects the rim to the body at four tabs. The central hole and four "
    "gaps remain empty.")
   (shape-pict 'badge))

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

@(tutorial-figure
   (string-append
    "The original cross shows the internal rectangle seams when stroked. Simplifying its "
    "winding-filled region removes those seams without changing the filled area.")
   (simplify-pict))

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

@(tutorial-figure
   (string-append
    "The same badge is drawn over a gradient and over horizontal stripes. Both "
    "backgrounds show through its central hole and four outer gaps.")
   (backgrounds-pict))

Both panels draw the same completed badge path. Only the background changes.
The stripes continue through the center and outer gaps, while the other panel
reveals the gradient through those same regions. No background-colored circles
are painted over the badge. True holes reveal whatever was drawn underneath.

The construction is performed before drawing the comparison sheet. In a
repeatedly rendered application, reuse a result until an operand changes rather
than recomputing the Boolean operations for every repaint.

@section[#:tag "try-it"]{Try It}

Increase the hole radius from 38 to 55. Then change the inner rim radius from
108 to 100. One edit changes the central opening; the other changes the rim's
thickness. Inspect their effects separately.

Try @racket[path-xor] instead of @racket[path-union] for the disk and cross.
Predict which overlapping parts disappear before rendering. Then restore the
union and move one operand in path coordinates rather than translating the
receiving canvas.

@section[#:tag "next-steps"]{Where to Go From Here}

To try rounded operands, use @racket[path-add-rounded-rect!]. Its coordinate
form takes a position, size, and two radii shared by all four corners. Its
value form takes a @racket[make-rounded-rect] result, which can specify different
radii at each corner. Both forms append a closed contour that can participate
in the same Boolean operations.

The operations combine filled areas. A stroke-to-path conversion can turn a painted
outline into an operand. The @api-link[] covers that conversion and operation failures.
A failed operation raises an error; it is not an empty but valid result.

@tutorial-next["path-ops"]

@section[#:tag "example-source"]{The Complete Example}

@tutorial-sources["path-ops"]

Run the example with @tt{racket badge.rkt}. It writes @filepath{cutout-badge.png}.
The result can also use the drawing routes from @tutorial-link["pdf-svg"];
there is no new export API to learn here.

@codeblock[(file->string program-source)]

The intermediate paths are ordinary owned CPU resources. A Boolean operation
can change the number and order of contours while preserving the intended
filled region. Use the resulting geometry without assuming that its point
sequence mirrors the way the operands were constructed.
