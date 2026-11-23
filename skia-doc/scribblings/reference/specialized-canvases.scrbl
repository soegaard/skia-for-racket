#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia skia/specialized-canvases))

@title[#:tag "skia-specialized-canvases"]{Specialized Canvases}

@defmodule[skia/specialized-canvases #:no-declare]
@(declare-exporting skia skia/specialized-canvases #:use-sources (skia/specialized-canvases))

Specialized canvases let a drawing function run without producing pixels,
send the same drawing to several surfaces, or measure @tech{overdraw}.
Each helper calls a function with a canvas and returns the function's results.
The supplied canvas cannot be used after the function returns or exits early.
A continuation cannot reenter the callback after the call ends.

Each supplied surface must have a canvas with @tech{save count} 1, no coordinate
transformation, and a rectangular clip covering the entire surface. A surface
already in use by another specialized-canvas call cannot be supplied.
During the callback, use the supplied canvas instead of accessing the target
surfaces directly. Do not release the targets or use them for another purpose.

The helpers restore the targets' original canvas state when the callback
returns, exits early, or raises an exception. They do not undo drawing or release
the target surfaces. See @secref["skia-gpu-surfaces"] for access to GPU surfaces;
these helpers do not copy GPU pixels to CPU memory. Specialized canvases do not
support the document annotations provided by PDF and SVG canvases.

@section{No-Draw Canvases}

@defproc[(call-with-nodraw-canvas [width (integer-in 1 32768)]
          [height (integer-in 1 32768)]
          [proc (-> canvas? any)])
          any]{
Calls @racket[proc] with a canvas of the given dimensions that discards drawing.
Canvas state changes and argument checks still occur. The function runs
normally and may allocate resources or have other effects.

The size @racket[(* 4 width height)] must not exceed
@racket[(current-skia-byte-limit)], even though the canvas does not allocate
storage for pixels.
}

@section{N-Way Canvases}

@defproc[(call-with-nway-canvas [surfaces (listof surface?)]
          [proc (-> canvas? any)])
          any]{
Calls @racket[proc] once with a canvas that forwards drawing to every surface in
@racket[surfaces]. The list must contain between 1 and 64 distinct surfaces
with the same dimensions and backend. GPU surfaces must belong to the same
GPU context.

If drawing raises an exception, earlier drawing may remain in some or all targets.

@racketblock[
(with-skia ([a (make-surface 16 16)]
            [b (make-surface 16 16)]
            [ink (make-paint #:color 'blue #:antialias? #f)])
  (call-with-nway-canvas
   (list a b)
   (lambda (canvas) (draw-rect canvas 2 2 8 8 ink)))
  (list (equal? (surface-pixel a 4 4) (color->rgba 'blue))
        (equal? (surface-pixel b 4 4) (color->rgba 'blue))))
]

The result is @racket['(#t #t)]: the sampled pixel is blue on both targets.
Both targets contain the blue rectangle and have their root canvas state restored.

@reference-figure["nway-canvas.png"
                  "A nearest-neighbor enlargement of one actual 16 by 16 target from the n-way callback. Its blue square occupies x two through nine and y two through nine; the white surrounding area is the preview background."]
}

@section{Overdraw Canvases}

@deftech{Overdraw} is drawing over the same pixel more than once. An overdraw
canvas estimates how many times drawing covers each pixel.

@defproc[(call-with-overdraw-canvas [surface surface?]
          [proc (-> canvas? any)])
          any]{
Calls @racket[proc] with a canvas that stores estimated @tech{overdraw} counts
in @racket[surface]'s alpha channel. The surface must use the @racket['alpha-8]
format, which stores only an eight-bit alpha component per pixel; see
@secref["skia-pixel-descriptions"].

Create an alpha-only surface with @racket[make-surface-from-info] and
@racket[make-image-info], as in the example below. @racket[make-surface] creates
an RGBA surface and cannot be used for this purpose.

Clear the surface to zero before collecting new counts. The helper does not
clear it automatically. Counts stop increasing at 255. They are estimates
based on Skia's drawing operations, not exact counts for every drawing
primitive or measurements of GPU performance.

The following example counts coverage from two overlapping rectangles. The
new alpha-only surface starts with every alpha value set to zero.

@racketblock[
(with-skia ([surface (make-surface-from-info
                     (make-image-info 12 10 #:color-type 'alpha-8))]
            [ink (make-paint #:color 'blue #:antialias? #f)])
  (call-with-overdraw-canvas
   surface
   (lambda (canvas)
     (draw-rect canvas 2 2 6 6 ink)
     (draw-rect canvas 4 2 6 6 ink)))
  (for/list ([x '(0 3 5)])
    (rgba-alpha (surface-pixel surface x 3))))
]

The result is @racket['(0 1 2)]: the samples are outside both rectangles,
inside only the first, and inside their overlap. Read the stored alpha values
as counts, not as opacity for displaying the result.
}
