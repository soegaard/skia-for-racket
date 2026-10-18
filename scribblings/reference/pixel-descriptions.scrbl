#lang scribble/manual

@(require "support/figures.rkt"
          scribble/eval
          (for-label racket/base racket/contract skia skia/image-info))

@(define pixel-eval (make-base-eval))
@(pixel-eval '(require skia/image-info))

@title[#:tag "skia-pixel-descriptions"]{Pixel Descriptions and Formats}

@defmodule[skia/image-info #:no-declare]
@(declare-exporting skia skia/image-info #:use-sources (skia/image-info))

When a raster buffer or surface needs an explicit pixel format, use
@racket[make-image-info] to describe it. Pass the result to
@racket[make-raster-buffer-from-info] or @racket[make-surface-from-info] to
allocate the buffer or surface in a supported format.

A @deftech{pixel description} is an immutable Racket structure specifying
dimensions, storage format, alpha type, and a @tech{color-space descriptor}.
It describes pixels but does not contain them.
@tech[#:key "scanline batch"]{Scanline batches} and incremental snapshots carry these
descriptions so their byte strings can be interpreted.

Constructing a description validates its representation, not native decoder or
GPU support. It neither allocates a pixel buffer nor performs color conversion.
Native operations can reject a valid description they cannot implement.

With @deftech{premultiplied alpha}, stored RGB components include multiplication
by alpha. With @deftech{unpremultiplied alpha}, RGB components are stored
independently of alpha. An alpha-type declaration describes the supplied
samples; it does not request multiplication or division of their components.

@section{Pixel Descriptions}

@defproc[(image-info? [v any/c])
          boolean?]{
Returns @racket[#t] for a pixel description and @racket[#f] otherwise.
}

@defproc[(make-image-info [width (integer-in 0 32768)] [height (integer-in 0 32768)]
          [#:color-type color-type (or/c 'rgba-8888 'bgra-8888 'rgb-888x 'alpha-8 'gray-8
                                 'rgb-565 'rgba-1010102 'rgba-f16 'rgba-f32) 'rgba-8888]
          [#:alpha-type alpha-type (or/c 'opaque 'premul 'unpremul) 'premul]
          [#:color-space space (or/c #f 'srgb 'linear-srgb bytes?) #f])
          image-info?]{
Returns a pixel description. Zero extents are accepted as descriptions but
cannot allocate a nonempty raster buffer. RGBX, grayscale, and RGB565 require
@racket['opaque]. Alpha-only storage accepts @racket['premul] or @racket['opaque],
rejects @racket['unpremul], and requires a false color-space description.

The space is untagged, sRGB, linear sRGB, or copied @tech{ICC profile} bytes. Mutable ICC bytes
are accepted and copied into immutable storage. The bytes must fit the current
byte limit and contain a complete-length ICC header with an @tt{acsp} signature.
This checks the descriptor header, not full native profile support. A live
@racket[color-space?] resource is not accepted. Declaring a color space does
not convert samples.
}

@defproc[(image-info-width [info image-info?])
          (integer-in 0 32768)]{
Returns the declared pixel width.
}

@defproc[(image-info-height [info image-info?])
          (integer-in 0 32768)]{
Returns the declared pixel height.
}

@defproc[(image-info-color-type [info image-info?])
          (or/c 'rgba-8888 'bgra-8888 'rgb-888x 'alpha-8 'gray-8
                                 'rgb-565 'rgba-1010102 'rgba-f16 'rgba-f32)]{
Returns the declared storage-format symbol.
}

@defproc[(image-info-alpha-type [info image-info?])
          (or/c 'opaque 'premul 'unpremul)]{
Returns the declared alpha interpretation. Premultiplied RGB is stored after
multiplication by alpha; unpremultiplied RGB is stored independently.
}

@defproc[(image-info-color-space [info image-info?])
          color-space-descriptor?]{
Returns the color-space description: @racket[#f], @racket['srgb],
@racket['linear-srgb], or immutable ICC bytes. It is not a live color-space resource.
}

@defproc[(image-info-bytes-per-pixel [info image-info?])
          exact-positive-integer?]{
Returns the storage bytes per pixel: 4 for RGBA8888, BGRA8888, RGBX8888, and
RGBA1010102; 1 for alpha or grayscale; 2 for RGB565; 8 for RGBA F16; and 16 for
RGBA F32. This does not include row padding.
}

@defproc[(image-info-channel-bits [info image-info?])
          (and/c vector? immutable?)]{
Returns immutable logical-channel widths. The vectors are @racket[#(8 8 8 8)]
for RGBA/BGRA8888, @racket[#(8 8 8)] for RGBX8888, @racket[#(8)] for alpha or
grayscale, @racket[#(5 6 5)] for RGB565, @racket[#(10 10 10 2)] for RGBA1010102,
and four equal 16-bit or 32-bit widths for the floating-point formats. These are
channel widths, not a byte-offset table; RGBX's unused byte is not a channel.
}

@defproc[(image-info-sample-type [info image-info?])
          (or/c 'float 'unsigned-integer)]{
Returns @racket['float] for F16/F32 storage and @racket['unsigned-integer] otherwise.
}

@defproc[(image-info-byte-order [info image-info?])
          (or/c 'byte-channels 'big-endian 'little-endian)]{
Returns @racket['byte-channels] for byte-wise channel formats. Packed RGB565,
RGBA1010102, and floating-point samples use the machine's byte order. A storage
snapshot is therefore not automatically a portable interchange format.
}

@defproc[(image-info-min-row-bytes [info image-info?])
          exact-nonnegative-integer?]{
Returns width times bytes per pixel. This query performs no allocation or
current-byte-limit check; use @racket[image-info-storage-layout] to validate a
requested layout.
}

@defproc[(image-info-with-dimensions [info image-info?]
          [width (integer-in 0 32768)] [height (integer-in 0 32768)])
          image-info?]{
Returns a description with new dimensions and the same format, alpha type,
and color interpretation. It does not resize or copy pixels.
}

@defproc[(image-info-storage-layout [info image-info?]
          [#:row-bytes row-bytes (or/c exact-nonnegative-integer? #f) #f])
          (values exact-nonnegative-integer? exact-nonnegative-integer?
                  exact-nonnegative-integer?)]{
Returns the row stride, minimum addressable byte length, and full allocation
size. The @deftech{row stride} is the number of bytes between consecutive row starts.
@deftech{Row padding} consists of unused bytes after a row's pixels that fill out the stride.
A tight stride contains only pixel bytes, without padding.
A false stride means the tight stride. An explicit stride must be at least
the tight stride and divisible by bytes per pixel.

For a nonempty description, the minimum length is the stride times @math{(height - 1)},
plus the tight stride. The full size is stride times height. Thus the minimum
omits final-row padding while the allocation includes it. If either dimension
is zero, both byte lengths are zero, but the stride is still validated.
The stride and full allocation must fit @racket[2147483647], and the allocation
must fit @racket[current-skia-byte-limit]. No storage is allocated.

@bold{Conceptual diagram.} In this three-by-two RGBA8888 example,
each logical pixel occupies four bytes, so tight row length is 12. With a
16-byte stride, the two rows start at offsets 0 and 16. Pixel bytes occupy
0--11 and 16--27; the remaining cells are padding rather than a fourth pixel.
The three returned values are 16, 28, and 32: the stride, minimum addressable
length, and complete allocation (which includes final-row padding), respectively.
The example below collects these values into a list.

@reference-figure["concept-pixel-stride.png"
                  "Two 16-byte rows are divided into three colored four-byte RGBA pixels and four gray padding bytes. Labels identify row starts at offsets zero and sixteen, the stride arrow, and the three returned values: 16, 28, and 32."]

@examples[#:eval pixel-eval
(define info (make-image-info 3 2))
(eval:check
 (call-with-values (lambda () (image-info-storage-layout info #:row-bytes 16)) list)
 '(16 28 32))
]
}

@defproc[(image-info-supports? [info image-info?]
          [operation (or/c 'storage 'sample 'rgba-read 'rgba-write 'convert
                           'image-copy 'raster-canvas 'gpu-readback)])
          boolean?]{
Returns whether the description satisfies this wrapper's format-level rule
for @racket[operation]. Raster canvases reject unpremultiplied alpha. GPU readback
requires RGBA8888 with premultiplied alpha. The other listed operations return
@racket[#t] for a valid description. This is not a probe of a native library,
device, codec, available memory, or a particular resource's lifetime.
}

@close-eval[pixel-eval]

@section[#:tag "skia-pixel-format-inventories"]{Format Inventories}

@(declare-exporting skia skia/image-info #:use-sources (skia/image-info))

@defthing[integer-pixel-formats (and/c (vectorof symbol?) immutable?)]{
The immutable vector of supported integer format symbols, in order: @racket['rgba-8888],
@racket['bgra-8888], @racket['rgb-888x], @racket['alpha-8], @racket['gray-8], @racket['rgb-565],
and @racket['rgba-1010102]. These describe storage, not encoded file formats. Use
@racket[image-info-supports?] to check a particular operation.
}

@defthing[float-pixel-formats (and/c (vectorof symbol?) immutable?)]{
The immutable vector @racket[#(rgba-f16 rgba-f32)] of supported floating-point storage formats.
Both contain four channels; the format names do not imply a color-space interpretation.
}

@defthing[pixel-formats (and/c (vectorof symbol?) immutable?)]{
The immutable vector containing the integer formats followed by the floating-point formats.
Membership does not establish that every decoder, drawing target, or encoder supports a
particular color-type and alpha-type combination.
}
