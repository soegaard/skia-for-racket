#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/class (only-in racket/draw bitmap%) skia/bitmap)
          (for-label racket/base racket/contract skia skia/image-operations))

@title[#:tag "skia-image-operations"]{CPU Image Operations}

@defmodule[skia/image-operations #:no-declare]
@(declare-exporting skia skia/image-operations #:use-sources (skia/image-operations))

Use these operations to finish decoding an image before drawing, copy pixels
into editable storage, or create a filtered image for reuse. For ordinary
drawing, @racket[draw-image] and @racket[draw-image-rect] can decode pixels as
needed; no preparation step is required.

The image operations require CPU images. They reject GPU-owned or texture-backed
inputs instead of reading pixels back from the GPU implicitly. Use an explicit
@tech{GPU readback} operation first; see @secref["skia-gpu-transfers"]. The
source must also satisfy its resource-lifetime and thread requirements.

For queries about an image's format, validity, or pixel availability, see
@secref["skia-image-properties"].

@local-table-of-contents[#:style 'immediate-only]

@section[#:tag "skia-image-preparation"]{Preparing CPU Images}

Use @racket[image->raster-image] when you want an image's pixels ready in CPU
memory, with any required decoding or generation completed before the function
returns. For ordinary drawing, this preparation is usually unnecessary:
drawing can decode the image as needed.

The related @racket[image->non-texture-image] provides a weaker guarantee: the
result does not use a GPU texture, but its pixels may still need decoding.

Both functions require a CPU image that does not use a GPU texture. Passing a
GPU-owned or texture-backed image raises an exception; neither function
transfers pixels from the GPU. For that, see @secref["skia-gpu-transfers"].

The result and source are separate image resources. Closing either does not
close the other, although they may share pixel storage.

These operations do not reduce floating-point color precision. Images with
32-bit floating-point components keep that format; images with 16-bit
floating-point components may use either 16-bit or 32-bit components in the
result. If Skia cannot create a valid CPU image meeting these requirements,
the operation raises an exception.

The image's width and height must each be between 1 and 32768 pixels. These
operations also check the image size using an estimate of 16 bytes per pixel,
regardless of its actual pixel format. If either dimension is outside its
allowed range, or @math{width × height × 16} exceeds either
@racket[current-skia-byte-limit] or 2,147,483,647 bytes, the operation raises an
exception. This check does not limit the total memory Skia may use internally.

@defproc[(image->non-texture-image [image image?])
          image?]{
Returns an image that does not use a GPU texture.

Its pixels may still be decoded or generated later. Use
@racket[image->raster-image] if you need the pixels to be available immediately.
}

@defproc[(image->raster-image [image image?])
          image?]{
Returns an image whose pixels are immediately available in CPU memory.

Any required decoding or pixel generation finishes before the function
returns. If Skia cannot provide the pixels immediately, the function raises
an exception.

The result is still an immutable image. To obtain pixels that you can edit,
use @racket[image->raster-buffer] instead.
}

The following example prepares an image loaded from PNG data, closes the
source, and checks that the result no longer defers decoding and has
immediately available pixels:

@racketblock[
(with-skia ([surface (make-surface 2 2 #:background 'red)]
            [snapshot (surface-snapshot surface)])
  (define encoded (image->png-bytes snapshot))
  (with-skia ([source (image-from-bytes encoded)]
              [raster (image->raster-image source)])
    (skia-close! source)
    (list (image-lazy-generated? raster) (image-pixels-available? raster))))
]

The result is @racket['(#f #t)].

@section{Copies into Pixel Views}

Use @racket[image-read-pixmap!] to fill existing writable pixel storage from
part of an image, or @racket[image-scale-pixmap!] to resize the entire image
into that storage. The destination is a @tech{pixmap}, which describes the
pixels available for writing. If you simply want a new editable copy, use
@racket[image->raster-buffer] instead.

The destination pixmap must be live and writable. Source and destination must
either both have a color-space interpretation or both be untagged. If only one
is tagged, the operation raises an exception before converting or writing pixels;
it does not assign sRGB to the untagged value.

Pixel data are prepared and checked in temporary storage before the destination is changed.
Failed native reads, scaling, or invalid converted samples leave the destination unchanged.
Only pixel bytes are copied to the destination; @tech{row padding} is preserved.
The caching option is a native caching hint,
not an ownership transfer or a promise that data will remain cached.

@defproc[(image-read-pixmap! [image image?] [destination pixmap?] [#:source-x x
          exact-nonnegative-integer? 0] [#:source-y y exact-nonnegative-integer? 0] [#:cache?
          cache? boolean? #f])
          void?]{
Copies an image rectangle to the entire destination view without resizing. The source rectangle
begins at the given coordinates and has the destination's dimensions. It must lie wholly inside
the image. If any part lies outside the image, the function raises an exception
without changing the destination.
}

@defproc[(image-scale-pixmap! [image image?] [destination pixmap?] [#:sampling sampling (or/c
          'nearest 'linear) 'linear] [#:cache? cache? boolean? #f])
          void?]{
Resizes the entire image to the destination view's dimensions, with the specified sampling. The
destination description determines storage format, alpha representation, and any permitted
color-space conversion.
}

@racketblock[
(with-skia ([surface (make-surface 420 240 #:background 'white)]
            [source (rgba-bytes->image
                     4 3
                     (bytes 255 0 0 255   0 255 0 128   0 0 255 255   255 220 0 64
                            0 220 220 255  150 60 200 128  239 79 55 255  80 80 80 0
                            50 109 230 255  125 91 166 128  34 139 34 255  255 255 255 255))]
            [read-buffer (make-raster-buffer 2 2)]
            [nearest-buffer (make-raster-buffer 8 6)]
            [linear-buffer (make-raster-buffer 8 6)]
            [source-buffer (image->raster-buffer source)]
            [font (make-font #:size 10)]
            [label (make-paint #:color "#20344E")]
            [outline (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)])
  (call-with-raster-buffer-pixmap
   read-buffer (lambda (destination) (image-read-pixmap! source destination #:source-x 1 #:source-y 1))
   #:writable? #t)
  (call-with-raster-buffer-pixmap
   nearest-buffer (lambda (destination) (image-scale-pixmap! source destination #:sampling 'nearest))
   #:writable? #t)
  (call-with-raster-buffer-pixmap
   source-buffer
   (lambda (source-view)
     (call-with-raster-buffer-pixmap
      linear-buffer (lambda (destination) (pixmap-scale! destination source-view #:sampling 'linear))
      #:writable? #t)))
  (with-skia ([read-image (raster-buffer->image read-buffer)]
              [nearest-image (raster-buffer->image nearest-buffer)]
              [linear-image (raster-buffer->image linear-buffer)])
    (define canvas (surface-canvas surface))
    (draw-simple-text canvas "source image: 4 × 3" 20 17 font label)
    (draw-simple-text canvas "read 2 × 2 from (1, 1)" 200 17 font label)
    (draw-image-rect canvas source 20 30 120 90 #:sampling 'nearest)
    (draw-image-rect canvas read-image 200 30 90 90 #:sampling 'nearest)
    (draw-rect canvas 20 30 120 90 outline)
    (draw-rect canvas 200 30 90 90 outline)
    (draw-simple-text canvas "image-scale-pixmap!: nearest" 20 132 font label)
    (draw-simple-text canvas "pixmap-scale!: linear" 220 132 font label)
    (draw-image-rect canvas nearest-image 20 145 120 90 #:sampling 'nearest)
    (draw-image-rect canvas linear-image 220 145 120 90 #:sampling 'nearest)
    (draw-rect canvas 20 145 120 90 outline)
    (draw-rect canvas 220 145 120 90 outline)
    surface))
]
@reference-figure["image-pixmap-copy-scaling.png"
                  "An asymmetric 4 by 3 RGBA source is enlarged with nearest sampling. The upper-right 2 by 2 result is copied from source offset one, one. The bottom row shows actual 8 by 6 writable destinations populated by image-scale-pixmap with nearest sampling and pixmap-scale with linear sampling; the latter blends the colored source pixels."]

@defproc[(image->raster-buffer [image image?] [#:info info (or/c #f image-info?) #f]
          [#:row-bytes row-bytes (or/c #f exact-positive-integer?) #f] [#:sampling sampling
          (or/c 'nearest 'linear) 'linear] [#:cache? cache? boolean? #f])
          raster-buffer?]{
Copies the image's pixels into a new raster buffer that can be edited.

The buffer is an owned resource. An omitted description uses @racket[image->image-info]; an
explicit description selects the destination dimensions and format. Matching dimensions use
@racket[image-read-pixmap!]; different dimensions use @racket[image-scale-pixmap!]. Sampling is
validated even when resizing is unnecessary.

The destination stride defaults to tight storage. An explicitly selected destination format
may reduce pixel precision. Source and destination must still either both specify a color
space or both be untagged. Failure releases the new buffer and leaves the source unchanged.
}

@section[#:tag "skia-image-filter-results"]{Filtering and Result Placement}

Use @racket[image-apply-filter] when you need a separate filtered image to
reuse, inspect, or encode. If the effect is needed only while drawing, attach
the filter to a paint with @racket[make-paint]'s @racket[#:image-filter] option
and pass that paint to an image-drawing operation instead.

Filtering can change the size and position of the visible pixels. The required
@racket[#:clip] argument bounds the requested output. The returned rectangle
and offset describe which pixels to use and where to draw them.

@defproc[(image-apply-filter
          [image image?] [filter image-filter?]
          [#:clip clip
           (or/c (list/c exact-integer? exact-integer?
                         (integer-in 1 32768) (integer-in 1 32768))
                 (vector/c exact-integer? exact-integer?
                           (integer-in 1 32768) (integer-in 1 32768)))]
          [#:subset subset
           (or/c #f
                 (list/c exact-integer? exact-integer?
                         (integer-in 1 32768) (integer-in 1 32768))
                 (vector/c exact-integer? exact-integer?
                           (integer-in 1 32768) (integer-in 1 32768))) #f])
          (values image?
                  (and/c (vector/c exact-integer? exact-integer?
                                   exact-positive-integer? exact-positive-integer?) immutable?)
                  (and/c (vector/c exact-integer? exact-integer?) immutable?))]{
Applies @racket[filter] to @racket[image] on the CPU.

Returns three values:

@itemlist[
 @item{The result image, an @tech{owned resource} that remains usable after the
   input image and filter are closed.}
 @item{An immutable source-rectangle vector @racket[#(x y width height)],
   selecting the pixels to use within the result image.}
 @item{An immutable offset vector @racket[#(x y)], giving the position of that
   rectangle's upper-left corner in the input image's coordinate system.
   This is not necessarily the position of the full result image's origin.}]

The @racket[subset] and @racket[clip] rectangles are lists or vectors of four
exact integers: x, y, width, and height. The subset selects input pixels and
must lie entirely inside the image; @racket[#f] selects the whole image.
The clip bounds output in the input image's coordinate system.

Each width and height must be between 1 and 32768. The left, top, right, and
bottom edges must fit signed 32-bit integers, from -2,147,483,648 through
2,147,483,647. The clip's edges must also fit this range after subtracting the
subset's upper-left corner. An invalid rectangle raises an exception.

The floating-point precision and image-size rules in
@secref["skia-image-preparation"] also apply here. The input image, requested
clip, and result image are each checked using 16 bytes per pixel.
GPU-dependent filters are rejected. If Skia cannot produce a valid CPU image
with the required precision, the function raises an exception. It also raises
if the returned source rectangle lies outside the result image or its placement
lies outside the requested clip. A rejected result is released before the
exception is raised; the input resources remain open and unchanged.
}

The diagram shows how the source rectangle selects pixels within the result
image and the offset positions those pixels relative to the input image.

@reference-figure["concept-image-placement.png"
                  "An input image, its returned filtered image with the native returned source rectangle highlighted, and a placement panel connected by an arrow. Red marks the selected source rectangle and purple brackets mark the returned offset position where its upper-left corner is placed."]

@racketblock[
(with-skia ([surface (make-surface 6 4 #:background 'red)]
            [image (surface-snapshot surface)]
            [filter (make-offset-image-filter 2 1)])
  (define-values (result source offset)
    (image-apply-filter image filter #:clip '(0 0 12 10)))
  (call-with-skia-resource result
    (lambda (result)
      (with-skia ([part (apply image-subset result (vector->list source))]
                  [destination (make-surface 12 10)])
        (draw-image (surface-canvas destination) part
                    (vector-ref offset 0) (vector-ref offset 1))
        (surface-pixel destination 3 2)))))
]

@reference-figure["image-filter-placement.png"
                  "A nearest-neighbor enlargement of the transparent 12 by 10 destination. The returned red filtered subset begins at offset two, one; the sampled pixel at three, two is inside it. The gray checkerboard is only a preview background."]

Only the reported source rectangle is drawn, at its reported offset. The figure enlarges the
actual 12 by 10 destination; its checkerboard is not stored in that destination.

@section{Racket Bitmap Conversion}

@defmodule[skia/bitmap #:no-declare]
@(declare-exporting skia/bitmap #:use-sources (skia/bitmap))

@defproc*[([(image->bitmap [image image?]) (is-a?/c bitmap%)]
           [(surface->bitmap [surface surface?]) (is-a?/c bitmap%)])]{
Creates a Racket bitmap by copying the image's or surface's pixels. The bitmap
has an alpha channel and can be edited independently of the source.

Pixel access follows @racket[image->rgba-bytes] or
@racket[surface->rgba-bytes], respectively, with @tech{premultiplied alpha}.
The corresponding function's format and CPU-access restrictions apply. The
copy uses eight-bit color components; extended floating-point values and
ICC metadata are not preserved.

Closing the source does not close the bitmap. The result follows Racket bitmap
ownership, not @racket[skia-close!]. Neither conversion creates a window or
exposes a borrowed native canvas.

For the reverse conversion, use @racket[bitmap->image] from
@racketmodname[skia/racket-draw]. It has options for physical or logical pixel
dimensions and for applying a loaded mask. Image-consuming operations do not
convert Racket bitmaps implicitly.
}

See @secref["skia-racket-draw"] for a bitmap round-trip example.
