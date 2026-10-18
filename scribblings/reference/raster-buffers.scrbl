#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia skia/raster-buffers))

@title[#:tag "skia-raster-buffers"]{Raster Buffers and Pixmaps}

@defmodule[skia/raster-buffers #:no-declare]
@(declare-exporting skia skia/raster-buffers #:use-sources (skia/raster-buffers))

Use a raster buffer when you need to inspect or edit individual pixel samples,
exchange raw pixel storage, or alternate direct pixel edits with canvas
drawing. A @tech{pixmap} provides scoped access to those pixels. For drawing
shapes and saving the result without direct sample access, a @tech{surface}
is usually simpler.

A @deftech{raster buffer} owns mutable CPU pixel storage. Its format and color interpretation are
described by @racket[raster-buffer-image-info]. A @deftech{pixmap} is a temporary view of that
storage, not an independently owned resource. Use @racket[call-with-raster-buffer-pixmap] to
obtain one. Use @racket[call-with-raster-buffer-canvas] to draw directly into the same buffer.

Buffer operations require an open resource on its creating thread. Only one canvas or pixmap
scope may use a buffer at a time. Ordinary buffer reads, writes, copying, and nested scopes are
rejected while it is borrowed. Width, height, @tech[#:key "row stride"]{stride}, byte-size,
and image-description queries
remain available during a scope. See @secref["skia-pixel-descriptions"] for the format
descriptions and @racket[raster-buffer?], @racket[raster-buffer-image-info], and
@racket[raster-buffer->image].

@local-table-of-contents[#:style 'immediate-only]

@section{Buffer Identity and Image Conversion}

@defproc[(raster-buffer? [v any/c])
          boolean?]{
Returns @racket[#t] for a raster buffer, including a closed one, and @racket[#f] otherwise.
}

@defproc[(raster-buffer-image-info [buffer raster-buffer?])
          image-info?]{
Returns a description of an open buffer's dimensions, storage format,
alpha type, and color interpretation. This metadata query is permitted during
a buffer borrow; it does not lend pixel storage to the caller.
}

@defproc[(raster-buffer->image [buffer raster-buffer?])
          image?]{
Creates an image by copying the buffer's pixels, preserving their color and
alpha format. Later buffer mutation or closure does not change the image.

The image is independently owned. The buffer must be open and have no active
canvas or pixmap scope. The storage copy must fit @racket[current-skia-byte-limit].
The operation does not normalize an encoded orientation or concatenate separate scanline batches.
It does not check whether incremental decoding has finished; a successful copy can contain
an incomplete image.
}

@section{Allocation and Copies}

@defproc[(make-raster-buffer [width (integer-in 1 32768)] [height (integer-in 1 32768)]
          [#:row-bytes row-bytes (or/c #f exact-positive-integer?) #f] [#:color-space space
          (or/c #f color-space?) #f])
          raster-buffer?]{
Creates a raster buffer of the given size, initialized to transparent black.

The buffer uses RGBA8888 pixels with premultiplied alpha. The default stride is
four times the width. An explicit stride must be at least that large and divisible by
four. The full stride times height must fit @racket[current-skia-byte-limit] and the native
signed pointer-arithmetic range. Padding is initialized to zero.

The buffer keeps its own native reference to a supplied live color space; closing its wrapper
does not invalidate the buffer. The space describes the stored samples. It does not convert
incoming colors or make a metadata assignment into a sample conversion.
}

@defproc[(make-raster-buffer-from-info [info image-info?] [#:row-bytes row-bytes (or/c #f
          exact-positive-integer?) #f])
          raster-buffer?]{
Creates an owned buffer in the specified integer or floating-point format. Both dimensions must
be positive. The stride follows @racket[image-info-storage-layout]. When present,
the color-space description is used to create a native color space owned by the buffer.
Invalid or unsupported ICC data can fail at this point even when its header was
accepted by @racket[make-image-info].

The byte-grid explanation in @secref["skia-pixel-descriptions"] distinguishes
row stride, minimum addressable bytes, final-row padding, and allocation size.

Pixels start at black, with maximum alpha for opaque formats and zero alpha otherwise. The
unused RGBX byte starts at 255. Padding starts at zero. Unpremultiplied formats can hold pixels
even when they cannot be used as drawing targets.
}

@defproc[(raster-buffer-width [buffer raster-buffer?])
          exact-positive-integer?]{
Returns the buffer's width in pixels. This live-resource query is also allowed during its canvas
or pixmap scope.
}

@defproc[(raster-buffer-height [buffer raster-buffer?])
          exact-positive-integer?]{
Returns the buffer's height in pixels. This live-resource query is also allowed during its
canvas or pixmap scope.
}

@defproc[(raster-buffer-row-bytes [buffer raster-buffer?])
          exact-positive-integer?]{
Returns the buffer's @tech{row stride}. This live-resource query is also allowed
during its canvas or pixmap scope.
}

@defproc[(raster-buffer-byte-size [buffer raster-buffer?])
          exact-positive-integer?]{
Returns the buffer's full allocation size, including padding after every row. This live-resource
query is also allowed during its canvas or pixmap scope.
}

@defproc[(raster-buffer-copy [buffer raster-buffer?] [#:row-bytes row-bytes (or/c #f
          exact-positive-integer?) #f])
          raster-buffer?]{
Returns an independently owned copy with the same dimensions, format, and color interpretation.
An omitted stride selects tight storage, not the source stride. Only pixel bytes are copied; the
new row padding stays zero. Subsequent writes to either buffer do not affect the other. This
operation requires the source to be idle.
}

@defproc[(raster-buffer->storage-bytes [buffer raster-buffer?])
          bytes?]{
Returns a mutable byte-string copy of the full allocation, including all row padding. Its length is
@racket[raster-buffer-byte-size]. The buffer must be idle, and the copy must fit the current
byte limit. Modifying the returned bytes does not modify the buffer.
}

@defproc[(raster-buffer-write-storage! [buffer raster-buffer?] [data bytes?])
          void?]{
Replaces the full allocation, including padding. The input length must equal
@racket[raster-buffer-byte-size], not merely the minimum length that contains the final row's
pixels. A copy of the input is validated before any destination write. Invalid samples, incorrect
length, or a byte-limit failure leave the buffer unchanged. The buffer must be idle.
}

@defproc[(raster-buffer->rgba-bytes [buffer raster-buffer?] [#:premultiplied? premultiplied?
          boolean? #f])
          bytes?]{
Returns a mutable byte string containing tightly packed RGBA8888 pixels. The
default is @tech{unpremultiplied alpha}.
This converts storage format and alpha representation while retaining
the buffer's color interpretation rather than implicitly converting to sRGB. Floating-point
samples can lose range and precision. There is no row padding in the result.
}

@defproc[(raster-buffer-write-rgba! [buffer raster-buffer?] [data bytes?] [#:row-bytes row-bytes
          (or/c #f exact-positive-integer?) #f] [#:premultiplied? premultiplied? boolean? #f])
          void?]{
Writes RGBA8888 input using @racket[pixmap-write-rgba!] in an exclusive writable scope. The
buffer must be idle. The input stride describes the source bytes, not the destination buffer.
Pixel conversion does not replace the destination color-space description.
}

@defproc[(raster-buffer-opaque? [buffer raster-buffer?])
          boolean?]{
Scans the pixels and reports whether their alpha is fully opaque. This is a content query, not
just a test of the declared alpha type. It requires an idle buffer and leaves its bytes
unchanged.
}

@section[#:tag "skia-pixmap-scopes"]{Scoped Pixel Views}

@defproc[(pixmap? [v any/c])
          boolean?]{
Returns @racket[#t] for a pixmap wrapper, including an expired wrapper. The predicate does not
establish that the view can still be used.
}

@defproc[(call-with-raster-buffer-pixmap [buffer raster-buffer?] [proc (-> pixmap? any)]
          [#:writable? writable? boolean? #f])
          any]{
Calls @racket[proc] with a view of the entire buffer and returns its values. The callback must
accept one argument without required keywords. Views are read-only unless @racket[writable?] is
true. The buffer is exclusively borrowed until the callback exits, normally or exceptionally.

The view and all its subsets expire on exit and are restricted to the callback's thread. Keeping
a wrapper does not extend its lifetime. Do not close the buffer during the callback. Completed
writes persist after an exception; scope cleanup is not pixel rollback. Continuations cannot
reenter the scope after leaving it.
}

@defproc[(pixmap-width [view pixmap?])
          exact-positive-integer?]{
Returns the view's width in pixels. The view must be live and used on its creating thread.
}

@defproc[(pixmap-height [view pixmap?])
          exact-positive-integer?]{
Returns the view's height in pixels. The view must be live and used on its creating thread.
}

@defproc[(pixmap-row-bytes [view pixmap?])
          exact-positive-integer?]{
Returns the view's byte stride of its underlying buffer. The view must be live and used on its
creating thread.
}

@defproc[(pixmap-writable? [view pixmap?])
          boolean?]{
Returns the view's write permission. The view must be live and used on its creating thread.
}

@defproc[(pixmap-image-info [view pixmap?])
          image-info?]{
Returns the view's image description, with the view's dimensions. The view must be live
and used on its creating thread.
}

@defproc[(pixmap-subset [view pixmap?] [x exact-nonnegative-integer?] [y
          exact-nonnegative-integer?] [width exact-positive-integer?] [height
          exact-positive-integer?])
          pixmap?]{
Returns a subview wholly inside @racket[view]. Coordinates are relative to that view. The subset
shares its storage, row stride, write permission, creating thread, and expiration time. It is
not a copy or a new borrow. Zero-sized or out-of-bounds subsets raise an exception.
}

@racketblock[
(with-skia ([buffer (make-raster-buffer 3 2)]
            [surface (make-surface 190 150 #:background 'white)]
            [dark (make-paint #:color "#D9DEE4")]
            [light (make-paint #:color "#F1F3F5")]
            [outline (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)]
            [font (make-font #:size 12)]
            [label (make-paint #:color "#20344E")])
  (define expired
    (call-with-raster-buffer-pixmap buffer
      (lambda (view)
        (define corner (pixmap-subset view 2 1 1 1))
        (pixmap-fill! corner 'red)
        corner)
      #:writable? #t))
  (with-skia ([image (raster-buffer->image buffer)])
    (define canvas (surface-canvas surface))
    (draw-simple-text canvas "actual 3 x 2 buffer after borrow" 20 20 font label)
    (for* ([row (in-range 4)] [column (in-range 6)])
      (draw-rect canvas (+ 20 (* column 25)) (+ 35 (* row 25)) 25 25
                 (if (even? (+ row column)) light dark)))
    (draw-image-rect canvas image 20 35 150 100 #:sampling 'nearest)
    (draw-rect canvas 20 35 150 100 outline))
  (list (pixmap? expired)
        (with-handlers ([exn:fail? (lambda (_) 'expired)])
          (pixmap-width expired))))
]

@reference-figure["pixmap-subset-write.png"
                  "A nearest-neighbor view of the actual 3-by-2 parent raster buffer after the writable subset pixmap expires. Only bottom-right pixel (2,1) is red; the other initialized pixels are transparent over a declared checkerboard preview."]

The rendering uses an image made from the parent buffer only after the borrow ends; it does not
attempt to draw with the expired pixmap.

The result is @racket['(#t expired)]. The wrapper remains recognizable, but its borrow has ended.

@section[#:tag "skia-pixel-samples"]{Samples, Colors, and Byte Copies}

Use @racket[pixmap-sample] and @racket[pixmap-set-sample!] when an algorithm
needs the stored channel values, including their bit depths and
premultiplication. Use @racket[pixmap-color4f] instead to read an
unpremultiplied color in the pixmap's color space. This distinction matters
when processing pixels numerically rather than just displaying them.

A @deftech{pixel sample} contains stored logical channels, not necessarily a display color.
Integer channels use the widths returned by @racket[image-info-channel-bits]. BGRA storage still
uses logical RGBA channel order in a sample. Premultiplied integer RGB must not exceed alpha
when both are compared at their respective bit depths. Opaque storage requires maximum alpha.

Floating-point samples contain four finite channels within the selected binary16 or binary32
range. Alpha is between zero and one. Extended RGB may be negative or greater than alpha.
Premultiplied zero alpha requires zero RGB, including after storage rounding. Binary16 storage
reads and writes preserve subnormal values; native drawing is not promised to do so.

All coordinate queries in this section use integer coordinates within the view. Mutators
require a writable view. Raw sample and storage-byte operations do not perform color-space conversion.

@defproc[(pixmap-sample [view pixmap?] [x exact-nonnegative-integer?] [y
          exact-nonnegative-integer?])
          (and/c vector? immutable?)]{
Returns the stored logical channels as an immutable vector. Its length and component
interpretation follow the view's format. Floating-point channels retain the stored
premultiplication; this operation does not return the unpremultiplied color of
@racket[pixmap-color4f].
}

@defproc[(pixmap-set-sample! [view pixmap?] [x exact-nonnegative-integer?] [y
          exact-nonnegative-integer?] [sample (or/c list? vector?)])
          void?]{
Validates and stores one sample in the view's format. The logical channel count, channel ranges,
opaque-alpha rule, and premultiplied-alpha rules must all hold. Floating-point rounding is
validated before writing. A rejected sample leaves the destination unchanged.
}

@defproc[(pixmap-pixel [view pixmap?] [x exact-nonnegative-integer?] [y
          exact-nonnegative-integer?])
          rgba?]{
Returns an unpremultiplied eight-bit color. For floating-point storage, this explicitly clips
extended RGB to the unit range and quantizes it. The result is not a raw sample and is not an
automatic conversion to sRGB.
}

@defproc[(pixmap-color4f [view pixmap?] [x exact-nonnegative-integer?] [y
          exact-nonnegative-integer?])
          color4f?]{
Returns the unpremultiplied floating-point color in the pixmap's color space. It does not
convert to sRGB. Use @racket[pixmap-sample] to inspect stored, possibly premultiplied channels
instead.
}

@defproc[(pixmap-alphaf [view pixmap?] [x exact-nonnegative-integer?] [y
          exact-nonnegative-integer?])
          (real-in 0 1)]{
Returns normalized alpha without returning or converting the RGB channels. A nonfinite or
out-of-range native alpha result raises an exception.
}

@defproc[(pixmap-fill! [view pixmap?] [color color?])
          void?]{
Fills the view's pixels with the supplied color. Opaque storage forces maximum alpha rather than
storing the supplied translucent alpha. Only the view's pixels are written, not row padding or
pixels outside a subset.
}

@defproc[(pixmap-set-pixel! [view pixmap?] [x exact-nonnegative-integer?] [y
          exact-nonnegative-integer?] [color color?])
          void?]{
Like @racket[pixmap-fill!], but writes one pixel. It uses color conversion rather than a raw
stored sample.
}

@defproc[(pixmap-fill-color4f! [view pixmap?] [color color4f?])
          void?]{
Fills the view with an unpremultiplied sRGB color converted to the destination color space and
storage format. Unlike @racket[pixmap-color4f], this operation interprets its argument in sRGB.
Opaque storage requires alpha one; translucent input is rejected, not made opaque.

The converted sample is validated before destination mutation. Overflow or invalid
premultiplication leaves the view unchanged. Row padding is not written.
}

@defproc[(pixmap-set-color4f! [view pixmap?] [x exact-nonnegative-integer?] [y
          exact-nonnegative-integer?] [color color4f?])
          void?]{
Like @racket[pixmap-fill-color4f!], but writes one pixel. Its input is unpremultiplied sRGB, not
an uninterpreted destination-space sample.
}

@defproc[(pixmap-opaque? [view pixmap?])
          boolean?]{
Reports whether all pixels in the view have fully opaque alpha. Pixels outside the view and row
padding do not affect the result.
}

@defproc[(pixmap->storage-bytes [view pixmap?])
          bytes?]{
Returns a mutable byte-string copy of the view's pixels in their stored format. Rows are tightly
packed even when the buffer or subset has a larger stride. No padding bytes are included.
}

@defproc[(pixmap-write-storage! [view pixmap?] [data bytes?] [#:row-bytes row-bytes (or/c #f
          exact-positive-integer?) #f])
          void?]{
Copies validated stored samples into the view. The input stride defaults to the view's tight
stride and follows @racket[image-info-storage-layout]. The input must contain at least the
minimum byte length, including the final row's pixels, and the complete supplied byte string
must fit the current byte limit. Extra source bytes are not copied. Destination padding is
unchanged.

The input is copied and all samples are validated before any destination write. Its color-space
interpretation is the destination's; this operation does not convert samples between spaces.
}

@defproc[(pixmap->rgba-bytes [view pixmap?] [#:premultiplied? premultiplied? boolean? #f])
          bytes?]{
Copies the view's pixels into a mutable byte string in RGBA8888 format.

Rows are tightly packed, and alpha is unpremultiplied by default.
Storage-format and alpha conversion follow @racket[raster-buffer->rgba-bytes]; no
implicit sRGB conversion occurs.
}

@defproc[(pixmap-write-rgba! [view pixmap?] [data bytes?] [#:row-bytes row-bytes (or/c #f
          exact-positive-integer?) #f] [#:premultiplied? premultiplied? boolean? #f])
          void?]{
Converts RGBA8888 input into the view's storage format. The source stride defaults to four times
the view width. Input must contain the final row's pixels and fit the byte limit. Premultiplied
input must have valid premultiplied samples.

Input samples use the destination's color interpretation; they are not implicitly tagged sRGB.
The conversion is prepared before destination writes, and destination padding is unchanged.
Buffers created by @racket[make-raster-buffer] retain the byte-exact Racket premultiplication
behavior of the original RGBA interface; explicitly described formats use native conversion.
}

@racketblock[
(with-skia ([buffer (make-raster-buffer 2 1 #:row-bytes 12)])
  (raster-buffer-write-storage! buffer (bytes 0 0 0 0 0 0 0 0 9 8 7 6))
  (define tight
    (call-with-raster-buffer-pixmap buffer pixmap->storage-bytes))
  (list (bytes-length tight) (bytes-length (raster-buffer->storage-bytes buffer))))
]

The result is @racket['(8 12)]. A pixmap copy omits the four padding bytes.

@section{Conversion and Drawing}

@defproc[(pixmap-convert! [destination pixmap?] [source pixmap?])
          void?]{
Converts source pixels into the destination format and color space. Dimensions must match and
the two views must belong to distinct buffers. The destination must be writable. Both buffers
must be tagged or both untagged; a tagged/untagged pair raises an exception rather than assuming
sRGB.

Pixels are converted and checked in temporary storage before the destination is changed.
A failed conversion leaves the destination unchanged, including padding.
This operation does not resize pixels.
}

@defproc[(pixmap-scale! [destination pixmap?] [source pixmap?] [#:sampling sampling (or/c
          'nearest 'linear) 'linear])
          void?]{
Scales and converts the source into the destination. Views must belong to distinct buffers, and
the destination must be writable. When either buffer was constructed from an explicit image
description, tagged and untagged color interpretations cannot be mixed. Both legacy buffers
retain their existing native conversion behavior.

This operation writes through the native scaler directly. Unlike @racket[pixmap-convert!], it
does not promise that a failed native call leaves the destination unchanged.
}

@defproc[(raster-buffer-convert [buffer raster-buffer?] [info image-info?] [#:row-bytes
          row-bytes (or/c #f exact-positive-integer?) #f])
          raster-buffer?]{
Returns a new owned buffer converted to @racket[info]. Dimensions must match. The source must be
idle. Color interpretation and conversion checks follow @racket[pixmap-convert!]. Failure
releases the new buffer and leaves the source unchanged. A missing stride selects tight
destination storage.
}

@defproc[(raster-buffer-extract-alpha [buffer raster-buffer?])
          raster-buffer?]{
Extracts the buffer's alpha channel into a separate Alpha8 buffer.

The result stores normalized alpha quantized to eight bits. Formats without
alpha yield 255. Two-bit alpha expands by multiplication by 85; floating-point
alpha rounds to the nearest eight-bit value. RGB and the source color-space description are not
copied. The source must be idle.
}

@racketblock[
(with-skia ([surface (make-surface 300 140 #:background 'white)]
            [source (make-raster-buffer 4 1)]
            [font (make-font #:size 11)]
            [label (make-paint #:color "#20344E")]
            [outline (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)])
  (call-with-raster-buffer-pixmap
   source
   (lambda (view)
     (for ([x (in-range 4)] [alpha '(0 85 170 255)])
       (pixmap-set-sample! view x 0
                           (vector (quotient (* 50 alpha) 255)
                                   (quotient (* 109 alpha) 255)
                                   (quotient (* 230 alpha) 255)
                                   alpha))))
   #:writable? #t)
  (with-skia ([alpha-buffer (raster-buffer-extract-alpha source)]
              [source-image (raster-buffer->image source)]
              [alpha-image (raster-buffer->image alpha-buffer)])
    (define canvas (surface-canvas surface))
    (draw-simple-text canvas "source blue with alpha 0, 85, 170, 255" 20 18 font label)
    (draw-image-rect canvas source-image 20 30 240 35 #:sampling 'nearest)
    (draw-simple-text canvas "extracted Alpha8 shown as black over white" 20 87 font label)
    (draw-image-rect canvas alpha-image 20 99 240 35 #:sampling 'nearest)
    (draw-rect canvas 20 30 240 35 outline)
    (draw-rect canvas 20 99 240 35 outline)
    surface))
]
@reference-figure["raster-buffer-extracted-alpha.png"
                  "Four blue samples with alpha values zero, 85, 170, and 255 appear increasingly opaque over white. The independent Alpha8 buffer extracted from those samples is displayed below as black-to-white grayscale: transparent black appears white over the page and opaque black appears black."]

@defproc[(image->image-info [image image?])
          image-info?]{
Returns a description of the image's dimensions, native color/alpha types, and copied
color interpretation. Unsupported native formats can raise an exception because not every native
image format has a public @racket[image-info?] representation. The operation does not decode or
copy the image's pixels.
}

@defproc[(make-surface-from-info [info image-info?] [#:row-bytes row-bytes (or/c #f
          exact-positive-integer?) #f] [#:background background (or/c #f color?) #f])
          surface?]{
Creates an owned CPU surface in a supported drawing format. Dimensions must be positive;
unpremultiplied raster targets are rejected. Stride and allocation follow
@racket[image-info-storage-layout]. The default clear is opaque black for opaque formats and
transparent black otherwise. An explicit background uses @racket[canvas-clear!]. The surface has
independent storage, not a borrow from a raster buffer.
}

@defproc[(call-with-raster-buffer-canvas [buffer raster-buffer?] [proc (-> canvas? any)])
          any]{
Calls @racket[proc] once with a canvas drawing directly into the buffer and returns its values.
The buffer must be idle and support raster drawing. The callback must accept one canvas without
required keywords. Pixels are not copied or cleared on entry.

The canvas is borrowed, protected by a canvas-state scope, and expires on exit. Buffer storage
cannot be accessed through a second canvas or pixmap scope while this callback runs. Drawn
pixels persist after an exception; state restoration is not a transaction. Do not close the
buffer during the callback or use the canvas after the callback ends.

@racketblock[
(with-skia ([buffer (make-raster-buffer 160 80)])
  (call-with-raster-buffer-canvas
   buffer
   (lambda (canvas)
     (with-skia ([blue (make-paint #:color "#326DE6")]
                 [orange (make-paint #:color "#EFA02B")])
       (canvas-clear! canvas 'white)
       (draw-rounded-rect canvas 15 15 80 50 10 10 blue)
       (draw-circle canvas 120 40 22 orange))))
  (with-skia ([image (raster-buffer->image buffer)]
              [surface (make-surface 180 100 #:background 'white)])
    (draw-image (surface-canvas surface) image 10 10)))
]

@reference-figure["raster-buffer-canvas.png"
                  "A blue rounded rectangle and orange circle drawn directly through a raster-buffer canvas."]
}

@racketblock[
(with-skia ([buffer (make-raster-buffer-from-info
                     (make-image-info 2 1 #:color-type 'bgra-8888))])
  (call-with-raster-buffer-pixmap buffer
    (lambda (view) (pixmap-set-sample! view 0 0 #(20 40 60 255)))
    #:writable? #t)
  (define sample
    (call-with-raster-buffer-pixmap buffer
      (lambda (view) (pixmap-sample view 0 0))))
  (list sample (subbytes (raster-buffer->storage-bytes buffer) 0 4)))
]

The written sample is @racket[#(20 40 60 255)] and the untouched sample is
@racket[#(0 0 0 0)], but the written storage bytes are 60, 40, 20, 255.
Logical channel order is not byte order.

@reference-figure["raster-buffer-bgra-sample.png"
                  "A nearest-neighbor view of the actual two-pixel BGRA buffer after its writable pixmap scope ends. The written left pixel displays as opaque RGB 20, 40, 60; the untouched right pixel is transparent over a preview checkerboard."]

The checkerboard is only behind the preview. It does not turn BGRA storage order into a different
displayed color.

@section{Color-Space Descriptions}

@defproc[(color-space->descriptor [space color-space?])
          (or/c 'srgb 'linear-srgb (and/c bytes? immutable?))]{
Returns a color-space descriptor. Standard spaces use their named symbols; other
spaces use copied immutable ICC bytes. ICC export has the representation and
quantization limits described in
@secref["skia-color-management"]. It is not a pixel conversion.
}

@defproc[(descriptor->color-space [description (or/c #f 'srgb 'linear-srgb bytes?)])
          (or/c #f color-space?)]{
Returns @racket[#f] for an absent description, or a newly owned native color space for a named
description or copied ICC bytes. Mutable byte input is accepted and copied;
@racket[color-space-descriptor?] instead requires ICC byte strings to be immutable.
An ICC profile can pass the header checks but still be unsupported by Skia.
}
