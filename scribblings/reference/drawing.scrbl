#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia skia/canvas-primitives))

@title[#:tag "skia-drawing"]{Drawing Primitives}

Drawing functions use the native Skia canvas API. The receiving canvas can
belong to a surface, a recording, a document, or a GPU frame, subject to its
lifetime and backend restrictions.

Unless an entry says otherwise, drawing functions use the canvas's current
transform and clip. Functions that accept a paint do not mutate it, and no
function retains a borrowed canvas for later use. Coordinates are
@tech{drawing scalar}s. Drawing to a recording stores an operation rather than
immediately producing pixels.

@local-table-of-contents[#:style 'immediate-only]

@section{Shapes, Paint, and Paths}

@defproc[(draw-rect [canvas canvas?]
                    [x real?] [y real?]
                    [width (and/c real? (>=/c 0))]
                    [height (and/c real? (>=/c 0))]
                    [paint paint?]) void?]{
Draws a rectangle on @racket[canvas] with its upper-left corner at coordinates
@racket[x] and @racket[y], the given @racket[width] and @racket[height], and the
specified @racket[paint]. The current canvas transform and clip apply. The paint's style
selects a fill, a stroke, or both. Drawing does not reset the transform, clip,
or paint.

The coordinates and dimensions must be @tech{drawing scalar}s. The computed
right and bottom coordinates must also be in range. Width and height may be
zero but must not be negative. Stroke and filter output may extend outside the
rectangle's geometric bounds; the receiving clip still applies.

The canvas and paint must be valid for native use. GPU-dependent paint content
requires the matching active GPU context; it is not implicitly read back for
CPU or document drawing. A recorded or document operation does not by itself
promise immediate pixels or a vector-only representation.

@racketblock[
(with-skia ([surface (make-surface 160 100 #:background 'white)]
            [paint (make-paint #:color "#326DE6")])
  (draw-rect (surface-canvas surface) 20 20 120 60 paint)
  (save-png surface "rectangle.png" #:exists 'replace))
]

@reference-figure["rectangle.png"
                  "A blue filled rectangle on a white background."]
}

@defproc[(draw-paint [canvas canvas?] [paint paint?]) void?]{
Draws @racket[paint] across the current clip without a separate geometric shape.
The paint's shader and blending apply. A stroke style does not turn the clip
boundary into an outlined shape. Unlike @racket[canvas-clear!], this operation
uses the supplied paint's blending and effects.
}

@defproc[(draw-line [canvas canvas?] [x0 real?] [y0 real?]
                    [x1 real?] [y1 real?] [paint paint?]) void?]{
Draws a line segment from coordinates @racket[x0], @racket[y0] to coordinates
@racket[x1], @racket[y1]. The paint's stroke width and cap apply; its fill style
does not make the segment a filled polygon. Zero stroke width requests a
hairline. The endpoints may coincide.
}

@defproc[(draw-rounded-rect [canvas canvas?] [x real?] [y real?]
                            [width (and/c real? (>=/c 0))]
                            [height (and/c real? (>=/c 0))]
                            [radius-x (and/c real? (>=/c 0))]
                            [radius-y (and/c real? (>=/c 0))]
                            [paint paint?]) void?]{
Draws a rectangle with elliptical corner radii. Skia scales overlapping radii
so the corners fit inside the rectangle. Zero radii give square corners.
The width, height, and radii must be nonnegative; the computed right and bottom
coordinates must also be in range. The paint selects filling, stroking, or both.
}

@defproc[(draw-circle [canvas canvas?] [x real?] [y real?]
                      [radius (and/c real? (>=/c 0))] [paint paint?]) void?]{
Draws a circle centered at coordinates @racket[x] and @racket[y]. Its radius is
measured in local coordinates, so nonuniform canvas scaling produces an ellipse.
The radius may be zero but must not be negative.
}

@defproc[(draw-oval [canvas canvas?] [x real?] [y real?]
                    [width (and/c real? (>=/c 0))]
                    [height (and/c real? (>=/c 0))] [paint paint?]) void?]{
Draws the ellipse inscribed in the rectangle given by position and size.
The width and height are diameters, not radii. Both extents and the computed
right and bottom coordinates follow the same restrictions as @racket[draw-rect].
}

@defproc[(draw-path [canvas canvas?] [path skia-path?] [paint paint?]) void?]{
Draws the contours of @racket[path] using @racket[paint]. Filling uses the path's
fill rule. Stroking follows its contours, with the paint's width, cap, join, and
path effect. The path itself is unchanged. A recording captures the drawing
operation; later mutation of the source path does not edit earlier drawing.
}

@defproc[(draw-polygon [canvas canvas?]
                       [points (and/c pair? (listof (list/c real? real?)))]
                       [paint paint?] [#:closed? closed? boolean? #t]) void?]{
Draws connected straight segments through @racket[points]. Each point must be a
two-element list; vectors are not accepted by this function. The default adds
a closing segment from the last point to the first. A single point is accepted,
although it need not produce visible output.

The @racket[#f] option leaves the contour open for stroking. Filling still uses
an implicit closing edge, as for any open path contour. Use a stroke paint to
draw an unfilled open polyline. The temporary path used by this function is
released before the call returns.

@racketblock[
(with-skia ([surface (make-surface 120 80 #:background 'white)]
            [paint (make-paint #:style 'stroke #:stroke-width 3 #:cap 'round)])
  (draw-polygon (surface-canvas surface) '((10 60) (55 15) (100 60))
                paint #:closed? #f)
  (save-png surface "polyline.png" #:exists 'replace))
]

@reference-figure["polyline.png"
                  "A black open polyline with rounded endpoints on a white background."]
}

@(declare-exporting skia skia/canvas-primitives #:use-sources (skia/canvas-primitives))

@section[#:tag "skia-drawing-batches"]{Points and Arcs}

These primitives use the same drawing-scalar, resource, transform, and clip
rules as the other drawing functions. Batch input is validated before drawing;
an empty point batch still requires a valid canvas and paint. Native point
batches do not imply portable SVG output. Use @racket[draw-markers] for
explicitly lowered marker geometry.

@defproc[(draw-point [canvas canvas?]
          [x real?]
          [y real?]
          [paint paint?])
          void?]{
Draws a point using the paint's stroke width and cap. A round cap gives a
round mark; the other caps give a square mark. A zero stroke width uses native
hairline coverage. Paint style does not turn the point into a filled path.
}

@defproc[(draw-points [canvas canvas?]
          [points (or/c list? vector?)]
          [paint paint?]
          [#:mode mode (or/c 'points 'lines 'polygon) 'points])
          void?]{
Draws a list or vector of two-coordinate point lists or vectors. Points mode
draws independent points. Lines mode draws independent consecutive pairs and
requires an even count. Polygon mode draws consecutive capped segments without
closing the final point to the first. These segments are not a joined path:
paint joins do not join their endpoints. A single polygon point draws nothing.

The submitted buffer, including the explicit segment-pair expansion for polygon
mode, must fit the native count and @racket[current-skia-byte-limit]. Input
coordinates are copied; later mutation does not change a recorded operation.
}

@defproc[(draw-arc [canvas canvas?]
          [x real?]
          [y real?]
          [width (and/c real? (>=/c 0))]
          [height (and/c real? (>=/c 0))]
          [start real?]
          [sweep real?]
          [paint paint?]
          [#:use-center? use-center? boolean? #f])
          void?]{
Draws an arc of the oval bounds. Angles are degrees, with zero at the right
and positive sweep clockwise in the usual y-down coordinates. A true
@racket[use-center?] includes the center to form a wedge. Without it, a filled
arc is closed by its chord; a stroked arc follows the native open-arc behavior.
A sweep of at least a full turn in magnitude draws the oval.
}

@section{Rounded-Rectangle Values}

The functions in this section draw the detached rounded-rectangle
specifications described in @secref["skia-rounded-rectangles"].

@defproc[(draw-rrect [canvas canvas?]
          [shape rounded-rect?]
          [paint paint?])
          void?]{
Draws the native-normalized rounded rectangle with the paint's fill/stroke
style. The detached specification is unchanged. Normalization can reduce radii
that do not fit the supplied bounds.
}

@defproc[(draw-double-rounded-rect [canvas canvas?]
          [outer rounded-rect?]
          [inner rounded-rect?]
          [paint paint?])
          void?]{
Draws the outer rounded rectangle with the inner shape removed. For a
nonempty inner rectangle, its entire bounding rectangle must fit inside the
native-normalized outer rounded shape. This is a conservative containment
requirement, not an arbitrary Boolean subtraction. Failure raises instead of
submitting undefined native geometry. An inner shape with zero width or height
is ignored and the outer shape is drawn alone.
}

@section{Device-Clip Color}

@defproc[(draw-color [canvas canvas?]
          [color color?]
          [#:blend-mode mode (or/c 'clear 'src 'dst 'src-over 'dst-over 'src-in 'dst-in
                 'src-out 'dst-out 'src-atop 'dst-atop 'xor 'plus 'modulate
                 'screen 'overlay 'darken 'lighten 'color-dodge 'color-burn
                 'hard-light 'soft-light 'difference 'exclusion 'multiply
                 'hue 'saturation 'color 'luminosity) 'src-over])
          void?]{
Blends the color across the current device clip, independently of the current
local transform. The transform is preserved. This differs from drawing a
local-coordinate rectangle and from @racket[canvas-clear!], which replaces
rather than source-over blends by default.

@racketblock[
(with-skia ([surface (make-surface 8 8 #:background 'white)])
  (define canvas (surface-canvas surface))
  (canvas-clip-rect! canvas 0 0 4 8)
  (canvas-translate! canvas 100 100)
  (draw-color canvas 'red)
  (map (lambda (x) (color->argb (surface-pixel surface x 2))) '(2 6)))
]

The point inside the clip becomes red even though the transform moved local
geometry away; the point outside the clip remains white.
}
