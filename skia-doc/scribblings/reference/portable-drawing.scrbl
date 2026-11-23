#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia skia/portable-drawing))

@title[#:tag "skia-portable-drawing"]{Portable Markers and Atlases}

@defmodule[skia/portable-drawing #:no-declare]
@(declare-exporting skia skia/portable-drawing #:use-sources (skia/portable-drawing))

@deftech{Portable drawing} expresses markers, image grids, and atlas sprites
using simpler shape and image-drawing operations. Use these helpers when the
corresponding native batch operation is unsupported by a document writer, such
as isolated-point drawing in SVG. You choose the helper explicitly; it does not
switch the canvas to a different output target.

When drawing to a recording, the helper records the simpler operations.
Images still contain raster pixels, not vector geometry. Paint effects and
other output restrictions still apply, and results need not be identical
across document viewers or drawing backends.

The drawing operations require live canvases, images, and paints, with their
ordinary lifetime and context restrictions. For portable nine-patch and lattice
drawing, see @secref["skia-portable-image-grids"]; for inspecting their layouts,
see @secref["skia-image-grid-plans"].

@section{Marker Geometry}

@defproc[(draw-markers [canvas canvas?]
          [points (or/c list? vector?)]
          [size (and/c real? (>/c 0))]
          [paint paint?]
          [#:shape shape (or/c 'circle 'square) 'circle])
          void?]{
Draws a circle or square centered at each two-coordinate point. Size is the
geometric diameter or side length, not stroke width. Paint style remains
meaningful, so stroke paints outline the marker geometry. Markers overlap in
input order rather than being combined into one path.

Use this function for point markers in SVG output. It draws ordinary shapes,
avoiding the version-specific Skia SVG limitation described under
@racket[draw-point]. Attached paint effects still have their own backend
restrictions.

The complete batch, including computed marker bounds, is validated before drawing.
Empty input still requires a live canvas and paint.

@racketblock[
(with-skia ([surface (make-surface 180 90 #:background 'white)]
            [blue (make-paint #:color "#326DE6")]
            [orange (make-paint #:color "#EFA02B")])
  (draw-markers (surface-canvas surface)
                '((25 25) (55 45) (85 25)) 18 blue #:shape 'circle)
  (draw-markers (surface-canvas surface)
                '((115 25) (145 45) (165 25)) 16 orange #:shape 'square))
]

@reference-figure["portable-markers.png"
                  "Three blue circular markers followed by three orange square markers."]
}

@section{Portable Atlas Drawing}

Use @racket[draw-atlas/portable] to draw atlas sprites as separate transformed
image rectangles. For the native batch operation, see @racket[draw-atlas].
Sampling, opacity, and shared image restrictions are described in
@secref["skia-portable-image-grids"].

@defproc[(draw-atlas/portable [canvas canvas?]
          [image image?]
          [transforms (or/c list? vector?)]
          [sources (or/c list? vector?)]
          [#:sampling sampling (or/c 'nearest 'linear) 'linear]
          [#:alpha alpha byte? 255])
          void?]{
Draws matching @tech{atlas transforms} and source rectangles as separate transformed
image rectangles. Unlike @racket[draw-atlas], every source rectangle must have
integer coordinates and dimensions. The rectangles must be nonempty and inside
the image. This prevents silent rounding of fractional atlas selections.

Each sprite's local origin is the origin of its extracted source rectangle.
A zero-scale transform is omitted. Canvas state is restored around each sprite;
the function does not group all sprites into an isolated compositing layer.
An empty batch still validates its canvas, image, and options.

@racketblock[
(with-skia ([tile (make-surface 2 2 #:background 'red)]
            [image (surface-snapshot tile)]
            [target (make-surface 12 6)])
  (draw-atlas/portable
   (surface-canvas target) image
   (list (make-atlas-transform 1 1) (make-atlas-transform 7 1 #:scale 2))
   '((0 0 2 2) (0 0 2 2))))
]

The repeated source rectangle is extracted once within this call. Both transformed
copies use the same caller-owned image.

@reference-figure["portable-atlas.png"
                  "A nearest-neighbor enlargement of the transparent 12 by 6 atlas target. A two-by-two red source tile begins at one, one; its second copy begins at seven, one and is four by four. A gray checkerboard belongs only to the preview."]

The figure magnifies the exact 12 by 6 target. Its checkerboard makes the target's transparent
pixels visible; it is not part of the atlas image.


@racketblock[
(with-skia ([surface (make-surface 220 100 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([source (make-surface 18 18 #:background "#326DE6")])
    (with-skia ([image (surface-snapshot source)])
      (draw-atlas/portable canvas image
                           (list (make-atlas-transform 25 20 #:scale 2.5)
                                 (make-atlas-transform 95 20 #:scale 2.5)
                                 (make-atlas-transform 165 20 #:scale 2.5))
                           '((0 0 18 18) (0 0 18 18) (0 0 18 18))
                           #:sampling 'nearest #:alpha 110))))
]
@reference-figure["portable-atlas-alpha-stage10.png"
                  "Three portable atlas sprites are drawn with the same reduced alpha over a white background."]
}
