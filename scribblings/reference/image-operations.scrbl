#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/class (only-in racket/draw bitmap%) skia/bitmap)
          (for-label racket/base racket/contract skia skia/image-operations))

@title[#:tag "skia-image-operations"]{CPU Image Operations}

@defmodule[skia/image-operations #:no-declare]
@(declare-exporting skia skia/image-operations #:use-sources (skia/image-operations))

@tech{Images} are immutable drawing resources, but their pixels need not already be decoded or
CPU-accessible. These queries distinguish validity, deferred generation, texture backing, and
immediately available pixels. None of those properties alone proves the others.

The functions that prepare CPU images, transfer pixels, or apply filters require CPU images.
They reject GPU-owned or texture-backed inputs instead of silently reading back a texture. Transfer a GPU
image explicitly before using these operations. Ordinary image queries still enforce the
source resource's lifetime, thread, and any GPU-context restrictions.

@local-table-of-contents[#:style 'immediate-only]

@section{Image Properties}

@defproc[(image-unique-id [image image?])
          exact-nonnegative-integer?]{
Returns the native image's process-local identifier. This is not a content hash or a persistent
file identifier. It does not imply that the image owns a unique copy of its pixels.
}

@defproc[(image-alpha-only? [image image?])
          boolean?]{
Reports whether the image has an alpha-only native format. This does not scan for opaque content
or report that all RGB samples happen to be zero.
}

@defproc[(image-lazy-generated? [image image?])
          boolean?]{
Reports whether the image uses deferred generation. The query itself does not
decode or generate pixels.
}

@defproc[(image-texture-backed? [image image?])
          boolean?]{
Reports whether the native image is texture-backed. It does not perform a transfer or promise
that CPU pixel access is available.
}

@defproc[(image-valid? [image image?])
          boolean?]{
Queries native validity, using the image's GPU context when applicable. A closed wrapper or
invalid context is an error, not a @racket[#f] result from this query. A valid image need not
have immediately available CPU pixels.
}

@defproc[(image-pixels-available? [image image?])
          boolean?]{
Reports whether native pixel storage can be inspected immediately. The query does not decode or
read back pixels and exposes no borrowed pointer. A false result is not a claim that later
decoding will fail.
}

@section{Preparing CPU Images}

The following operations do not silently reduce floating-point pixel precision: F32 must remain F32,
and F16 may remain F16 or become F32. Native allocation or validity failure raises rather than
returning an invalid image. Extents are checked conservatively at 16 bytes per pixel against
both the current byte limit and the native signed allocation range. This is not a bound on all
intermediate native memory.

@defproc[(image->non-texture-image [image image?])
          image?]{
Returns an image that does not use a GPU texture.

The result is independently owned, but may share native storage with the source.
Its pixels need not already be decoded. The input must already be CPU-owned and
non-texture-backed; this operation does not perform GPU readback.
}

@defproc[(image->raster-image [image image?])
          image?]{
Returns an image whose pixels are immediately available in CPU memory.

The result does not defer decoding. Failure to obtain these properties raises
an exception. It is independently owned and remains valid after the source
wrapper closes, but it is not a mutable raster buffer.
}

@racketblock[
(with-skia ([surface (make-surface 2 2 #:background 'red)]
            [snapshot (surface-snapshot surface)])
  (define encoded (image->png-bytes snapshot))
  (with-skia ([source (image-from-bytes encoded)]
              [raster (image->raster-image source)])
    (skia-close! source)
    (list (image-lazy-generated? raster) (image-pixels-available? raster))))
]

The result is @racket['(#f #t)]. Closing the source wrapper does not close the raster result.

@section{Copies into Pixel Views}

The following writes require a live writable destination @tech{pixmap}. Source and destination must
either both have a color-space interpretation or both be untagged. A tagged/untagged pair raises
instead of silently assigning sRGB. Pixel-format and color-space conversion are performed only
after those checks.

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
the image; partial clipping is rejected rather than leaving an apparently initialized
destination.
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

@defproc[(image-apply-filter [image image?] [filter image-filter?] [#:subset subset (or/c #f
          list? vector?) #f] [#:clip clip (or/c list? vector?)])
          (values image?
                  (and/c (vector/c exact-integer? exact-integer?
                                   exact-positive-integer? exact-positive-integer?) immutable?)
                  (and/c (vector/c exact-integer? exact-integer?) immutable?))]{
Applies @racket[filter] to @racket[image] on the CPU.

Returns three values: the result image, a source rectangle within that image,
and a placement offset. The image is an owned resource; the rectangle and
offset are immutable vectors. The source rectangle uses x, y, width, and
height. The offset places its upper-left corner in the original filtering
coordinates; it does not necessarily place the full returned image at the origin.

The optional input subset defaults to the whole image. Subset and clip use exact integers, with
positive dimensions no greater than 32768 and signed 32-bit edges. The subset must be inside the
image. The required clip bounds the requested output. The clip relative to the subset must also
have representable edges. The native result rectangle and its offset are checked against both
the result image and the requested clip before the values are returned.

GPU-dependent filters are rejected. Floating-point pixel precision is preserved:
F32 must remain F32, and F16 may remain F16 or become F32.
Extents use the conservative 16-byte-per-pixel budget. A null native result raises
an exception. The returned image is independent of subsequent closure of the input wrappers.
}

@bold{Conceptual diagram.} The source rectangle selects pixels within the returned
image. The offset places that rectangle's upper-left corner in the original
filtering coordinates; it does not necessarily give the position of the returned image's origin.
The highlighted values come from an offset-filter example, and the final panel
illustrates their placement.

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

@defproc[(image->bitmap [image image?])
          (is-a?/c bitmap%)]{
Creates a Racket bitmap by copying the image's pixels. The bitmap can be edited
independently of the source and has an alpha channel.

Pixel access follows @racket[image->rgba-bytes] with premultiplied alpha, including
that function's format and CPU-access restrictions. The bytes are reordered from
RGBA to ARGB; this is not a promise of preserving extended floating-point values
or ICC metadata.

Closing the source does not close the bitmap. The result follows Racket bitmap ownership, not
@racket[skia-close!]. This conversion does not create a window or expose a borrowed native
canvas.

For the reverse, explicit copy from a Racket @racket[bitmap%] to a CPU Skia image,
use @racketmodname[skia/racket-draw]. Its @racket[bitmap->image] function has
separate physical/logical readback and loaded-mask policies; it is not an
implicit conversion on image-consuming operations.
}

@defproc[(surface->bitmap [surface surface?])
          (is-a?/c bitmap%)]{
Creates a Racket bitmap by copying the surface's pixels. The bitmap can be edited
independently of the source and has an alpha channel.

Pixel access follows @racket[surface->rgba-bytes] with premultiplied alpha, including
that function's format and CPU-access restrictions. The bytes are reordered from
RGBA to ARGB; this is not a promise of preserving extended floating-point values
or ICC metadata.

Closing the source does not close the bitmap. The result follows Racket bitmap ownership, not
@racket[skia-close!]. This conversion does not create a window or expose a borrowed native
canvas.
}

The Racket Draw interoperability chapter contains a visual round-trip using
@racket[bitmap->image], @racket[image->bitmap], and @racket[surface->bitmap].
It deliberately distinguishes an imported loaded mask from a mask-free copy
and separately shows logical versus physical bitmap readback.
