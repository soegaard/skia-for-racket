#lang scribble/manual

@(require
          (for-label racket/base racket/contract skia skia/raster-buffers))

@title[#:tag "skia-raster-buffers"]{Raster Buffers and Pixmaps}

@defmodule[skia/raster-buffers #:no-declare]
@(declare-exporting skia skia/raster-buffers #:use-sources (skia/raster-buffers))

A @tech{raster buffer} owns mutable CPU pixel storage. Its format and color interpretation are
described by @racket[raster-buffer-image-info]. A @deftech{pixmap} is a temporary view of that
storage, not an independently owned resource. Use @racket[call-with-raster-buffer-pixmap] to
obtain one. Use @racket[call-with-raster-buffer-canvas] to draw directly into the same buffer.

Buffer operations require an open resource on its creating thread. Only one canvas or pixmap
scope may use a buffer at a time. Ordinary buffer reads, writes, copying, and nested scopes are
rejected while it is borrowed. Width, height, stride, byte-size, and image-description queries
remain available during a scope. See @secref["skia-pixel-descriptions"] for the format
descriptions and @racket[raster-buffer?], @racket[raster-buffer-image-info], and
@racket[raster-buffer->image].

@local-table-of-contents[#:style 'immediate-only]

@section{Allocation and Copies}

@defproc[(make-raster-buffer [width (integer-in 1 32768)] [height (integer-in 1 32768)]
          [#:row-bytes row-bytes (or/c #f exact-positive-integer?) #f] [#:color-space space
          (or/c #f color-space?) #f])
          raster-buffer?]{
Creates an owned RGBA8888 premultiplied buffer initialized to transparent black. The default
stride is four times the width. An explicit stride must be at least that large and divisible by
four. The full stride times height must fit @racket[current-skia-byte-limit] and the native
signed pointer-arithmetic range. Padding is initialized to zero.

A supplied live color space is retained independently; closing its wrapper does not invalidate
the buffer. The space describes the stored samples. It does not convert incoming colors or make
a metadata assignment into a sample conversion.
}

@defproc[(make-raster-buffer-from-info [info image-info?] [#:row-bytes row-bytes (or/c #f
          exact-positive-integer?) #f])
          raster-buffer?]{
Creates an owned buffer in the specified integer or floating-point format. Both dimensions must
be positive. The stride follows @racket[image-info-storage-layout]. The color-space description
is materialized and retained independently. Invalid or unsupported ICC data can fail at this
point even when its header was accepted by @racket[make-image-info].

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
Returns the buffer's byte stride between row starts. This live-resource query is also allowed
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
Returns a detached mutable copy of the full allocation, including all row padding. Its length is
@racket[raster-buffer-byte-size]. The buffer must be idle, and the copy must fit the current
byte limit. Modifying the returned bytes does not modify the buffer.
}

@defproc[(raster-buffer-write-storage! [buffer raster-buffer?] [data bytes?])
          void?]{
Replaces the full allocation, including padding. The input length must equal
@racket[raster-buffer-byte-size], not merely the minimum length that contains the final row's
pixels. A detached copy is validated before any destination write. Invalid samples, incorrect
length, or a byte-limit failure leave the buffer unchanged. The buffer must be idle.
}

@defproc[(raster-buffer->rgba-bytes [buffer raster-buffer?] [#:premultiplied? premultiplied?
          boolean? #f])
          bytes?]{
Returns a detached mutable, tightly packed RGBA8888 copy. The default is unpremultiplied alpha.
This converts storage format and alpha representation through the native pixel reader, retaining
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
Returns the view's detached image description, with the view's dimensions. The view must be live
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
(with-skia ([buffer (make-raster-buffer 3 2)])
  (define expired
    (call-with-raster-buffer-pixmap buffer
      (lambda (view)
        (define corner (pixmap-subset view 2 1 1 1))
        (pixmap-fill! corner 'red)
        corner)
      #:writable? #t))
  (list (pixmap? expired)
        (with-handlers ([exn:fail? (lambda (_) 'expired)])
          (pixmap-width expired))))
]

The result is @racket['(#t expired)]. The wrapper remains recognizable, but its borrow has ended.

@section[#:tag "skia-pixel-samples"]{Samples, Colors, and Byte Copies}

A @deftech{pixel sample} contains stored logical channels, not necessarily a display color.
Integer channels use the widths returned by @racket[image-info-channel-bits]. BGRA storage still
uses logical RGBA channel order in a sample. Premultiplied integer RGB must not exceed alpha
when both are compared at their respective bit depths. Opaque storage requires maximum alpha.

Floating-point samples contain four finite channels within the selected binary16 or binary32
range. Alpha is between zero and one. Extended RGB may be negative or greater than alpha.
Premultiplied zero alpha requires zero RGB, including after storage rounding. Binary16 storage
reads and writes preserve subnormal values; native drawing is not promised to do so.

All coordinate queries below use integer coordinates within the view. Mutators require a
writable view. Raw sample and storage-byte operations do not perform color-space conversion.

@defproc[(pixmap-sample [view pixmap?] [x exact-nonnegative-integer?] [y
          exact-nonnegative-integer?])
          (and/c vector? immutable?)]{
Returns the stored logical channels as a detached immutable vector. Its length and component
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
Fills the view through the native color eraser. Opaque storage forces maximum alpha rather than
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
Returns a detached mutable copy of the view's pixels in their stored format. Rows are tightly
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
Returns tightly packed, mutable RGBA8888 bytes for the view. Alpha is unpremultiplied by
default. Storage-format and alpha conversion follow @racket[raster-buffer->rgba-bytes]; no
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

Native conversion is staged and validated before committing pixels. A failed conversion leaves
the destination unchanged, including padding. This operation does not resize pixels.
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
Returns an independent Alpha8 buffer containing normalized alpha quantized to eight bits.
Formats without alpha yield 255. Two-bit alpha expands by multiplication by 85; floating-point
alpha rounds to the nearest eight-bit value. RGB and the source color-space description are not
copied. The source must be idle.
}

@defproc[(image->image-info [image image?])
          image-info?]{
Returns a detached description of the image's dimensions, native color/alpha types, and copied
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
buffer or retain the canvas for later use.
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

The sample is @racket[#(20 40 60 255)], but the stored bytes are 60, 40, 20, 255.
Logical channel order is not byte order.

@section{Color-Space Descriptions}

@defproc[(color-space->descriptor [space color-space?])
          (or/c 'srgb 'linear-srgb (and/c bytes? immutable?))]{
Returns a detached color-space description. Standard spaces use their named symbols; other
spaces use copied immutable ICC bytes. The result survives closure of the source resource. ICC
export has the representation and quantization limits described in
@secref["skia-color-management"]. It is not a pixel conversion.
}

@defproc[(descriptor->color-space [description (or/c #f 'srgb 'linear-srgb bytes?)])
          (or/c #f color-space?)]{
Returns @racket[#f] for an absent description, or a newly owned native color space for a named
description or copied ICC bytes. Mutable byte input is accepted and copied;
@racket[color-space-descriptor?] describes already-detached values and therefore has a stricter
immutability requirement. Structural header acceptance does not ensure that the native library
supports the profile.
}
