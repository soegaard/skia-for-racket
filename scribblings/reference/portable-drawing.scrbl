#lang scribble/manual

@(require "support/figures.rkt"
          scribble/eval
          (for-label racket/base racket/contract skia skia/portable-drawing))

@(define grid-eval (make-base-eval))
@(grid-eval '(require skia/portable-drawing))

@title[#:tag "skia-portable-drawing"]{Portable Markers and Image Grids}

@defmodule[skia/portable-drawing #:no-declare]
@(declare-exporting skia skia/portable-drawing #:use-sources (skia/portable-drawing))

These functions explicitly lower markers and image batches to ordinary shapes
and image rectangles before recording. They do not change the native batch
functions or silently select a backend. Portable image lowering still embeds
raster image samples; it is not conversion to vector geometry or a guarantee
about every viewer, font, color profile, or paint effect.

The planning operations return detached immutable cells without reading pixels,
loading Skia, or retaining an image. The drawing operations require live canvases,
images, and paints, with their ordinary lifetime and context restrictions.

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

The complete batch, including computed marker bounds, is validated before drawing.
Empty input still requires a live canvas and paint. This avoids the isolated-point
operation used by @racket[draw-points], but does not make arbitrary attached
paint effects portable.

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

@section{Detached Grid Plans}

Plans use row-major cell order. Each cell has integer source-image geometry and
finite destination geometry. Adjacent cells share rounded binary32 destination
edges rather than rounding their widths independently. A plan can include cells
with zero destination area, which the drawing functions omit.

@defproc[(image-grid-cell? [v any/c])
          boolean?]{
Returns @racket[#t] for a detached grid-plan cell and @racket[#f] otherwise.
}

@defproc[(image-nine-plan [image-width (integer-in 1 1073741823)]
          [image-height (integer-in 1 1073741823)]
          [center (or/c (list/c exact-integer? exact-integer? exact-integer? exact-integer?)
                 (vector/c exact-integer? exact-integer? exact-integer? exact-integer?))]
          [x real?]
          [y real?]
          [width (and/c real? (>=/c 0))]
          [height (and/c real? (>=/c 0))])
          (listof image-grid-cell?)]{
Returns the nine row-major cells for an image and its nonempty center
rectangle. The center must lie within the supplied image dimensions. Fixed
outer spans retain their size when possible; if they do not fit, they shrink
proportionally and the corresponding center span collapses.

@examples[#:eval grid-eval
 (define cells (image-nine-plan 10 10 '(2 2 6 6) 0 0 20 20))
 (eval:check (image-grid-cell-source (list-ref cells 4)) #(2 2 6 6))
 (eval:check (image-grid-cell-destination (list-ref cells 4)) #(2.0 2.0 16.0 16.0))]

The two-pixel borders retain their widths while the center expands to sixteen pixels.
}

@defproc[(image-lattice-plan [image-width (integer-in 1 1073741823)]
          [image-height (integer-in 1 1073741823)]
          [lattice image-lattice?]
          [x real?]
          [y real?]
          [width (and/c real? (>=/c 0))]
          [height (and/c real? (>=/c 0))])
          (listof image-grid-cell?)]{
Returns the row-major cells for the lattice after checking bounds and
interior divisions against the image dimensions. Cell kinds and fixed colors
are preserved. An undivided axis maps its whole source extent to the destination.
The plan does not contain sampled image pixels.
}

@defproc[(image-grid-cell-row [cell image-grid-cell?])
          exact-nonnegative-integer?]{
Returns the zero-based row index in the plan.
}

@defproc[(image-grid-cell-column [cell image-grid-cell?])
          exact-nonnegative-integer?]{
Returns the zero-based column index in the plan.
}

@defproc[(image-grid-cell-kind [cell image-grid-cell?])
          (or/c 'default 'transparent 'fixed-color)]{
Returns whether the cell samples the source image, is omitted, or uses a
fixed color.
}

@defproc[(image-grid-cell-source [cell image-grid-cell?])
          (and/c (vector/c exact-integer? exact-integer? exact-integer? exact-integer?) immutable?)]{
Returns the immutable source rectangle, using coordinates, width, and height.
Some grid edge cells can have zero extent.
}

@defproc[(image-grid-cell-destination [cell image-grid-cell?])
          (and/c (vector/c real? real? real? real?) immutable?)]{
Returns the immutable destination rectangle derived from the shared rounded
edges. A zero extent means the drawing function omits this cell.
}

@defproc[(image-grid-cell-color [cell image-grid-cell?])
          (or/c rgba? #f)]{
Returns a detached RGBA record for a fixed-color cell, or @racket[#f] for
other kinds. This is not the packed integer used by @racket[image-lattice-colors].
}

@defproc[(image-grid-plan->jsexpr [plan (listof image-grid-cell?)])
          (listof hash?)]{
Returns JSON-compatible cell descriptions with row, column, kind, source,
destination, and color keys. Kind symbols become strings, coordinate vectors
become lists, and fixed colors become packed ARGB integers. Missing colors use
@racket[#f], not a fabricated color. An empty plan returns an empty list.
}

@section{Drawing Lowered Image Batches}

These image functions accept nearest or linear sampling and a byte alpha
multiplier. They do not accept an arbitrary paint, sprite tint array, or blend
mode. They draw source-over, in input or cell order. Repeated source rectangles
share temporary subset images during one call; those temporaries are released
before return, including on failure. The original image remains caller-owned.

@defproc[(draw-image-nine/portable [canvas canvas?]
          [image image?]
          [center (or/c (list/c exact-integer? exact-integer? exact-integer? exact-integer?)
                 (vector/c exact-integer? exact-integer? exact-integer? exact-integer?))]
          [x real?]
          [y real?]
          [width (and/c real? (>=/c 0))]
          [height (and/c real? (>=/c 0))]
          [#:sampling sampling (or/c 'nearest 'linear) 'linear]
          [#:alpha alpha byte? 255])
          void?]{
Draws the @racket[image-nine-plan] as ordinary image rectangles. Empty source
or destination cells are omitted. Source samples are sliced without resampling
before destination drawing; interpolation then follows the chosen sampling mode.
The alpha multiplier applies to each cell.


@racketblock[
(with-skia ([surface (make-surface 200 120 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([source (make-surface 30 30 #:background "#326DE6")]
              [orange (make-paint #:color "#EFA02B")])
    (draw-circle (surface-canvas source) 15 15 8 orange)
    (with-skia ([image (surface-snapshot source)])
      (draw-image-nine/portable canvas image '(8 8 14 14) 15 10 170 100
                                #:sampling 'nearest #:alpha 128))))
]
@reference-figure["portable-nine-alpha-stage10.png"
                  "A portable nine-patch is drawn at half alpha, revealing the white background through the image."]
}

@defproc[(draw-image-lattice/portable [canvas canvas?]
          [image image?]
          [lattice image-lattice?]
          [x real?]
          [y real?]
          [width (and/c real? (>=/c 0))]
          [height (and/c real? (>=/c 0))]
          [#:sampling sampling (or/c 'nearest 'linear) 'linear]
          [#:alpha alpha byte? 255])
          void?]{
Draws the @racket[image-lattice-plan] as image rectangles and plain fixed-color
rectangles. Transparent or zero-area cells are omitted. The alpha multiplier
also scales fixed-color alpha, using nearest byte rounding. The lattice's
full-grid validation occurs before drawing.


@racketblock[
(with-skia ([surface (make-surface 200 120 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([source (make-surface 30 30 #:background "#E8EEF9")]
              [blue (make-paint #:color "#326DE6")])
    (draw-rect (surface-canvas source) 0 0 10 30 blue)
    (draw-rect (surface-canvas source) 20 0 10 30 blue)
    (with-skia ([image (surface-snapshot source)])
      (define lattice (make-image-lattice '(10 20) '(10 20)))
      (draw-image-lattice/portable canvas image lattice 15 10 170 100 #:sampling 'nearest))))
]
@reference-figure["portable-lattice-stage10.png"
                  "A portable lattice stretches the center spans while drawing each cell as ordinary rectangles."]
}

@defproc[(draw-atlas/portable [canvas canvas?]
          [image image?]
          [transforms (or/c list? vector?)]
          [sources (or/c list? vector?)]
          [#:sampling sampling (or/c 'nearest 'linear) 'linear]
          [#:alpha alpha byte? 255])
          void?]{
Draws matching atlas transforms and source rectangles as separate transformed
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


@close-eval[grid-eval]
