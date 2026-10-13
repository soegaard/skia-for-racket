#lang scribble/manual

@(require (for-label racket/base racket/contract skia))

@title[#:tag "skia-drawing"]{Drawing}

Drawing procedures use the native Skia canvas API. The receiving canvas can
belong to a surface, a recording, a document, or a GPU frame, subject to its
lifetime and backend restrictions.

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
}

@section{Other Primitives}

Unless an entry says otherwise, these procedures use the current transform,
clip, and paint settings just like @racket[draw-rect]. They do not mutate the
paint or retain a borrowed canvas for later use. All coordinates are
@tech{drawing scalar}s. Drawing to a recording stores an operation rather than
immediately producing pixels.

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
two-element list; vectors are not accepted by this procedure. The default adds
a closing segment from the last point to the first. A single point is accepted,
although it need not produce visible output.

The @racket[#f] option leaves the contour open for stroking. Filling still uses
an implicit closing edge, as for any open path contour. Use a stroke paint to
draw an unfilled open polyline. The temporary path used by this procedure is
released before the call returns.

@racketblock[
(with-skia ([surface (make-surface 120 80 #:background 'white)]
            [paint (make-paint #:style 'stroke #:stroke-width 3 #:cap 'round)])
  (draw-polygon (surface-canvas surface) '((10 60) (55 15) (100 60))
                paint #:closed? #f)
  (save-png surface "polyline.png" #:exists 'replace))
]
}
