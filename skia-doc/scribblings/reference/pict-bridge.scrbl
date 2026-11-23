#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract
                     (prefix-in pict: pict)
                     file/convertible skia skia/bitmap skia/pict))

@title[#:tag "skia-pict-bridge"]{Racket Pict Bridge}

@defmodule[skia/pict #:no-declare]
@(declare-exporting skia/pict #:use-sources (skia/pict))

Use @racketmodname[skia/pict] to combine Skia artwork with other Racket picts,
for example in a diagram or a Scribble document. The library converts Skia
images, surfaces, and recorded pictures to ordinary Racket pict values.
The @racket[image->pict] and @racket[surface->pict] functions copy CPU pixels;
@racket[picture->pict] draws a recorded picture into a temporary CPU surface.
Each operation creates an independent bitmap-backed pict. Closing the source,
or drawing further on a source surface, does not change the result.

The conversions are explicit: they neither add pict-conversion properties to
Skia values nor read back GPU data automatically. Unlike conversion through
@racketmodname[file/convertible], they transfer pixels without encoding and
decoding PNG. For a Racket @tt{bitmap%} instead of a pict, use
@racket[image->bitmap] or @racket[surface->bitmap] from
@racketmodname[skia/bitmap]. Those bitmap conversions use the same sRGB
color-space conversion as this pict bridge; see
@secref["skia-racket-bitmap-conversion"].

Import @racketmodname[skia/pict] separately; it is not re-exported by
@racketmodname[skia]. Requiring it does not load the native Skia library,
create a GPU context, or initialize a GUI.

@local-table-of-contents[#:style 'immediate-only]

@section{Images and Surfaces}

@defproc[(image->pict [image image?]
                      [#:backing-scale backing-scale (and/c real? (>/c 0)) 1])
         pict:pict?]{
Creates a Racket pict by copying the image's pixels before returning.

The source must be live and CPU-accessible. A GPU-dependent image is rejected
instead of being read back implicitly; transfer it explicitly with the GPU
raster-transfer API first.

The pict's underlying bitmap has the image's physical pixel width and height.
The @racket[backing-scale] changes only the pict's logical dimensions: its width
is @racket[(/ (image-width image) backing-scale)] and its height is
@racket[(/ (image-height image) backing-scale)]. The bridge does not infer a
display DPI or resample the source merely because the backing scale differs
from 1. The scale and resulting dimensions must be positive finite values
representable by the drawing implementation.

@bold{Conceptual diagram.} A 120 by 80 pixel image passed through
@racket[image->pict] with backing scale 2 remains 120 by 80 physical pixels but
becomes a 60 by 40 logical pict. This is separate from a picture viewport of
120 by 80 logical units rendered by @racket[picture->pict] at raster scale 2:
that route produces 240 by 160 physical pixels while retaining 120 by 80 logical
dimensions.

@reference-figure["concept-raster-density.png"
                  "Two routes distinguish physical pixels from logical units: image-to-pict changes 120 by 80 pixels to 60 by 40 logical units through backing scale two, while picture-to-pict keeps a 120 by 80 logical viewport and renders it as 240 by 160 pixels at raster scale two."]

Tagged images are read into sRGB before the Racket bitmap is created. Untagged
images keep their numerical RGBA samples, which the display bridge treats as
sRGB values. The transfer is an 8-bit display conversion; floating-point or HDR
source precision is not preserved in the returned pict.
}

@defproc[(surface->pict [surface surface?]
                        [#:backing-scale backing-scale (and/c real? (>/c 0)) 1])
         pict:pict?]{
Creates a Racket pict by copying the surface's current pixels before returning.
Subsequent drawing to the surface cannot change the pict.

The result uses the same logical-size and sRGB rules as @racket[image->pict].

A GPU surface is not an implicit bridge source. Obtain an explicit CPU image
with the GPU transfer API before converting it to a pict. Ordinary closed-value,
owner-thread, and active-borrow restrictions remain in force during conversion.
}

@section{Recorded Pictures}

@defproc[(picture->pict
          [picture picture?]
          [#:bounds bounds
           (or/c #f
                 (vector/c real? real?
                           (and/c real? (>/c 0))
                           (and/c real? (>/c 0)))) #f]
          [#:raster-scale raster-scale (and/c real? (>/c 0)) 1])
         pict:pict?]{
Creates a Racket pict by replaying @racket[picture] once.

The drawing uses a temporary, transparent sRGB surface in CPU memory. The
picture must be replayable on a CPU raster target; GPU-dependent content used
by the picture is not transferred implicitly.

When @racket[bounds] is @racket[#f], the viewport uses
@racket[(vector 0 0 (picture-width picture) (picture-height picture))].
A picture with a zero nominal width or height therefore requires explicit
positive bounds. An explicit vector contains x, y, width,
and height. Its coordinates and extents must be finite drawing values, width
and height must be positive, and the vector is copied before drawing so later
mutation cannot change the conversion.

The @racket[raster-scale] controls sampling density, not the pict's logical
size. Physical raster dimensions are
@racket[(ceiling (* width raster-scale))] by
@racket[(ceiling (* height raster-scale))], while the resulting pict still
measures exactly @racket[width] by @racket[height]. Ceiling can make the actual
x and y pixel scales differ slightly. Playback translates the requested bounds
to the raster origin and clips to that viewport.
}

@section{Pixel Transfer and Limits}

The pixel copy preserves alpha. RGB values hidden beneath fully transparent
pixels are not preserved reliably because the copy uses @tech{premultiplied
alpha}. It does not use a temporary file or share native pixel storage with the
source.

@subsection{Viewport Translation and Raster Density}

The picture below is recorded in a larger coordinate system, then converted
using a nonzero viewport. Both returned picts measure 100 by 70 logical units.
The previews are enlarged twofold to show the different sampling densities.

@racketblock[
(require (prefix-in pict: pict) skia skia/pict skia/racket-draw)

(define bounds (vector 36 22 100 70))
(with-skia ([font (make-font #:size 14)]
            [background (make-paint #:color "#EEF2F7")]
            [ink (make-paint #:color "#20344E")]
            [orange (make-paint #:color "#EFA02B")]
            [grid (make-paint #:color "#C9D2DF" #:style 'stroke #:stroke-width 1)]
            [picture
             (call-with-picture
              160 110
              (lambda (canvas)
                (draw-rect canvas 0 0 160 110 background)
                (for ([x '(20 40 60 80 100 120 140)])
                  (draw-line canvas x 0 x 110 grid))
                (for ([y '(20 40 60 80 100)])
                  (draw-line canvas 0 y 160 y grid))
                (draw-circle canvas 42 29 18 orange)
                (draw-line canvas 36 92 130 30 ink)
                (draw-simple-text canvas "viewport" 62 88 font ink)))])
  (define one (picture->pict picture #:bounds bounds #:raster-scale 1))
  (define three (picture->pict picture #:bounds bounds #:raster-scale 3))
  (define one-preview (pict:pict->bitmap (pict:scale one 2)))
  (define three-preview (pict:pict->bitmap (pict:scale three 2)))
  (with-skia ([one-image (bitmap->image one-preview #:mask #f)]
              [three-image (bitmap->image three-preview #:mask #f)])
    (list (list (pict:pict-width one) (pict:pict-height one))
          (list (pict:pict-width three) (pict:pict-height three)))))
]
@reference-figure["picture-pict-viewport-density.png"
                  "Two magnified Racket pict previews made from the same nonzero 100-by-70 picture viewport: the left was rasterized at scale one and the right at scale three, while both retain the same logical dimensions."]

The usual image and surface dimension limits still apply. Before transferring
pixels, the bridge checks that @racket[current-skia-byte-limit] can hold both
temporary byte strings: the RGBA pixels and their ARGB copy. Together, these
require eight bytes per pixel. This is not a total-memory bound: a
@racket[picture->pict] call also owns its temporary CPU raster surface until the
independent pict has been created.

Bitmap-backed picts use Racket's ordinary baseline convention: ascent equals
the pict's logical height and descent is zero.

@racketblock[
(require skia skia/pict (prefix-in pict: pict))

(define icon
  (with-skia ([surface (make-surface 240 140 #:background 'white)]
              [paint (make-paint #:color 'blue)])
    (draw-circle (surface-canvas surface) 70 70 45 paint)
    (surface->pict surface #:backing-scale 2)))

(list (pict:pict-width icon)
      (pict:pict-height icon))
]

The final value is @racket['(120 70)]. The surface and paint are already closed;
the pict remains usable by ordinary Racket pict consumers.

@reference-figure["pict-bridge.png"
                  "The pict produced from the surface example: a blue circle on a white background."]
}
