#lang scribble/manual

@(require (for-label racket/base racket/contract file/convertible skia))

@title[#:tag "skia-images"]{Images}

An @deftech{image} is an immutable source of pixels for drawing, encoding, or
readback. Its native storage is owned by its resource wrapper. Immutability
means that drawing to another target does not edit the image; it does not mean
that decoding must already be complete or that storage must be CPU-resident.
An image snapshot and its source surface have separate lifetimes.

The constructors here create CPU-compatible images. GPU images satisfy the
same @racket[image?] predicate but retain additional context requirements.
CPU readback, subsetting, and encoding functions in this chapter reject
GPU-dependent input instead of transferring it implicitly.

@section{Standard Conversion}

Images implement @racket[file/convertible]'s protocol. A live CPU image accepts
@racket['png-bytes], with the same encoder defaults, color/alpha behavior,
byte limit, and failure behavior as @racket[image->png-bytes]. The result is a
detached byte string. Other conversion requests return their supplied default
unchanged (including a procedure value) without inspecting or decoding the
image. A supported request propagates its ordinary error instead of using the
default.

@racketblock[
(require file/convertible skia)
(with-skia ([image (rgba-bytes->image 1 1 (bytes 255 0 0 255))])
  (convert image 'png-bytes))
]

GPU images also satisfy @racket[convertible?], but @racket['png-bytes] retains
the ordinary explicit-transfer error. Convert a GPU image through its explicit
GPU raster-transfer API before converting the resulting CPU image; conversion
never performs hidden readback.

The @tt{pict:bitmap} constructor requests PNG bytes through this protocol. It
therefore works for a live CPU image and produces a detached raster pict; it
does not preserve a live Skia image or a vector representation.

@section{Construction}

@defproc[(image? [v any/c]) boolean?]{
Returns @racket[#t] for an image, including a GPU image or a closed wrapper,
and @racket[#f] otherwise. It does not establish that pixels are decoded or
that the resource is valid for native use.
}

@defproc[(rgba-bytes->image [width (integer-in 1 32768)]
                           [height (integer-in 1 32768)] [pixels bytes?]
                           [#:premultiplied? premultiplied? boolean? #f]
                           [#:color-space space (or/c color-space? #f) #f]) image?]{
Copies tightly packed RGBA bytes into a new owned raster image. The byte string
must contain exactly @racket[(* width height 4)] bytes, within
@racket[current-skia-byte-limit]. Rows run from top to bottom, with no padding.
Later mutation of @racket[pixels] does not change the image.

The default interprets RGB as unpremultiplied. With @racket[premultiplied?] true,
each RGB byte must be no greater than its pixel's alpha byte; otherwise the
operation raises an exception. The option describes the supplied bytes, not a
request to multiply them. A supplied @racket[space] declares their interpretation
without converting them. The image retains its own native color-space reference.

@racketblock[
(with-skia ([image (rgba-bytes->image 2 1 (bytes 255 0 0 255 0 0 255 128))])
  (bytes->list (image->rgba-bytes image)))
]
}

@defproc[(image-from-bytes [encoded bytes?]) image?]{
Creates an owned image from a copy of encoded image data. The bytes must be
nonempty and fit @racket[current-skia-byte-limit]. The decoded width and height
must satisfy the same dimension and RGBA-size limits as @racket[make-surface].
An unsupported or invalid image raises an exception; no @racket[#f] result is
used for decode failure.

The native decoder can defer pixel decoding until drawing or readback, so
successful construction does not guarantee that later decoding will succeed.
The operation does not expose an animation's individual frames. Frame selection
and explicit encoded-orientation handling belong to the codec interfaces.
}

@defproc[(image-from-file [filename path-string?]) image?]{
Creates an image from a nonempty encoded file. The file must exist, its size
must fit @racket[current-skia-byte-limit], and its path must not contain an
embedded NUL. Native image construction applies the dimension checks described
for @racket[image-from-bytes]. The native image retains encoded data
for deferred decoding; no Racket input port remains open on the caller's behalf.
}

@section{Image Properties}

@defproc[(image-width [image image?]) exact-positive-integer?]{
Returns the stored pixel width, including after the resource is closed. This
metadata query does not decode pixels or activate a GPU context.
}

@defproc[(image-height [image image?]) exact-positive-integer?]{
Returns the stored pixel height, including after closure. The same metadata
restrictions as @racket[image-width] apply.
}

@defproc[(image-color-type [image image?]) symbol?]{
Returns the native pixel-format name, such as @racket['rgba-8888],
@racket['bgra-8888], or @racket['rgba-f16]. The result is not the encoded file
format: a PNG and a JPEG may decode into the same pixel format. Unlike the stored
dimension queries, this call requires the image to be valid for native use.
}

@defproc[(image-alpha-type [image image?]) (or/c 'unknown 'opaque 'premul 'unpremul)]{
Returns the image's native alpha interpretation. Opaque means no transparency;
premultiplied means stored RGB is multiplied by alpha; unpremultiplied means
RGB is stored independently. The unknown value denotes no usable declared alpha
type, rather than a fourth blending rule. The query requires native resource validity.
}

@defproc[(image-color-space [image image?]) (or/c color-space? #f)]{
Returns an independently owned reference to the image's color space, or
@racket[#f] for an untagged image. The returned reference remains usable after
the image is closed. It is a CPU color-space resource even when obtained from
a GPU image, although querying the GPU image requires its normal context rules.
}

@defproc[(image-original-encoded-bytes [image image?]) (or/c bytes? #f)]{
Returns a new mutable copy of retained encoded data when the native image has
such data, or @racket[#f] otherwise. It does not encode raster pixels. A surface
snapshot or a raw-byte image therefore need not have an original encoded form.
The copied data must fit @racket[current-skia-byte-limit]. GPU-dependent input
is not accepted by this ordinary CPU API.
}

@section{Pixel Copies and Subsets}

@defproc[(image->rgba-bytes [image image?]
                           [#:premultiplied? premultiplied? boolean? #f]
                           [#:color-space space (or/c color-space? #f) #f]) bytes?]{
Returns a new mutable, tightly packed RGBA byte string. Row order, alpha
interpretation, destination color-space selection, and size limits are the
same as for @racket[surface->rgba-bytes]. The read may trigger deferred decoding.
A failed native read raises an exception instead of returning partial bytes.
The image itself is unchanged.
}

@defproc[(image-subset [image image?]
                      [x exact-nonnegative-integer?] [y exact-nonnegative-integer?]
                      [width exact-positive-integer?] [height exact-positive-integer?]) image?]{
Returns an independently owned raster subset. The rectangle must fit entirely
within the image; it is not silently clipped. Unlike drawing source rectangles,
these coordinates and extents must be exact integers. The subset remains usable
after the source is closed, although native storage may be shared. GPU-dependent
images require an explicit GPU-subset or transfer operation instead.
}

@section[#:tag "skia-image-drawing"]{Drawing Images}

Drawing uses image coordinates for a source rectangle and canvas-local
coordinates for a destination rectangle. The canvas transform and clip apply
to the destination. Nearest sampling selects individual source pixels; linear
sampling interpolates adjacent samples. Sampling is independent of a paint's
shape-antialiasing setting.

The optional paint can supply alpha, blending, and filters. The image supplies
the source pixels; its destination rectangle is not outlined when the paint's
style is stroke. The source image is unchanged. GPU-dependent images or paint
content must match the receiving active GPU context; they are not implicitly
read back for a CPU or document target.

@defproc[(draw-image [canvas canvas?] [image image?] [x real?] [y real?]
                     [#:sampling sampling (or/c 'nearest 'linear) 'nearest]
                     [#:paint paint (or/c paint? #f) #f]) void?]{
Draws the image with its upper-left corner at coordinates @racket[x] and
@racket[y], using its pixel width and height as local drawing dimensions.
The default sampling is nearest, unlike the scaled rectangle operations below.
}

@defproc[(draw-image-rect [canvas canvas?] [image image?] [x real?] [y real?]
                          [width (and/c real? (>=/c 0))]
                          [height (and/c real? (>=/c 0))]
                          [#:sampling sampling (or/c 'nearest 'linear) 'linear]
                          [#:paint paint (or/c paint? #f) #f]) void?]{
Scales the complete image to the destination rectangle. Horizontal and vertical
scales are independent; the operation does not preserve aspect ratio by
cropping or adding borders. Destination extents may be zero but not negative.
Use a reflected canvas transform to mirror an image.

@racketblock[
(with-skia ([image (rgba-bytes->image 2 1 (bytes 255 0 0 255 0 0 255 255))]
            [surface (make-surface 80 40)])
  (draw-image-rect (surface-canvas surface) image 0 0 80 40 #:sampling 'nearest)
  (save-png surface "image-pair.png" #:exists 'replace))
]
}

@defproc[(draw-image-subrect [canvas canvas?] [image image?]
                             [source-x (and/c real? (>=/c 0))]
                             [source-y (and/c real? (>=/c 0))]
                             [source-width (and/c real? (>=/c 0))]
                             [source-height (and/c real? (>=/c 0))]
                             [x real?] [y real?]
                             [width (and/c real? (>=/c 0))]
                             [height (and/c real? (>=/c 0))]
                             [#:sampling sampling (or/c 'nearest 'linear) 'linear]
                             [#:paint paint (or/c paint? #f) #f]) void?]{
Draws the selected source rectangle into the destination rectangle. Source
coordinates and sizes can be fractional drawing scalars, but the entire source
rectangle must fit inside the image. Destination position and size follow the
same rules as @racket[draw-image-rect]. Zero source or destination extents are
accepted by the wrapper but need not produce visible output.
}
