#lang scribble/manual

@(require (for-label racket/base racket/contract
                     (prefix-in pict: pict)
                     file/convertible skia skia/bitmap skia/pict))

@title[#:tag "skia-pict-bridge"]{Racket Pict Bridge}

@defmodule[skia/pict #:no-declare]
@(declare-exporting skia/pict #:use-sources (skia/pict))

The @racketmodname[skia/pict] module converts Skia images, surfaces, and
recorded pictures to ordinary Racket @racket[pict:pict?] values.
@racket[image->pict] and @racket[surface->pict] copy CPU pixels;
@racket[picture->pict] draws a recorded picture into a temporary CPU surface.
Each operation creates an independent bitmap-backed pict. Closing the source,
or drawing further on a source surface, does not change the result.

The conversions are explicit: they neither add pict-conversion properties to
Skia values nor read back GPU data automatically. Unlike conversion through
@racketmodname[file/convertible], they transfer pixels without encoding and
decoding PNG. For a Racket @tt{bitmap%} instead of a pict, use
@racket[image->bitmap] or @racket[surface->bitmap] from
@racketmodname[skia/bitmap].

Import @racketmodname[skia/pict] separately; it is not re-exported by
@racketmodname[skia]. Requiring it does not load the native Skia library,
create a GPU context, or initialize a GUI.

@section{Images and Surfaces}

@defproc[(image->pict [image image?]
                      [#:backing-scale backing-scale (and/c real? (>/c 0)) 1])
         pict:pict?]{
Returns an ordinary Racket pict containing an eager copy of the CPU image.
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

Tagged images are read into sRGB before the Racket bitmap is created. Untagged
images keep their numerical RGBA samples, which the display bridge treats as
sRGB values. The transfer is an 8-bit display conversion; floating-point or HDR
source precision is not preserved in the returned pict.
}

@defproc[(surface->pict [surface surface?]
                        [#:backing-scale backing-scale (and/c real? (>/c 0)) 1])
         pict:pict?]{
Returns a pict from an eager snapshot of the CPU surface's current pixels. The
result uses the same logical-size and sRGB rules as @racket[image->pict]. The
snapshot and transfer finish before the function returns, so subsequent drawing
to the surface cannot change the pict.

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
Returns an ordinary pict by replaying @racket[picture] once into a transparent
CPU sRGB surface. The picture must be replayable on a CPU raster target;
retained GPU-dependent content is not transferred implicitly.

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

The bridge reads premultiplied RGBA pixels and rearranges them to the
premultiplied ARGB layout expected by Racket's bitmap implementation. Alpha is
preserved; RGB hidden beneath fully transparent premultiplied pixels is not a
stable result. No PNG encoding, temporary file, or borrowed native bitmap is
involved.

The usual image and surface dimension limits still apply. In addition, the
bridge preflights the two simultaneous Racket byte buffers used during transfer:
the RGBA readback and its ARGB copy together require twice the physical RGBA
byte count within @racket[current-skia-byte-limit]. A @racket[picture->pict]
call also owns its temporary CPU raster surface until the independent pict has
been created.

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
