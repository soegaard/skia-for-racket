#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract file/convertible skia skia/pict))

@title[#:tag "skia-images"]{Images}

An @deftech{image} is an immutable source of pixels for drawing, encoding, or
readback. Drawing to another target does not change its pixels. Pixel decoding
can be deferred, and pixels may be stored in CPU or GPU memory.

An image value wraps a native Skia object. Racket can reclaim a CPU image when
it becomes unreachable. Use @racket[skia-close!] to release it at a specific
time; see @secref["skia-resources"]. An image returned by
@racket[surface-snapshot] remains usable after its source @tech{surface} is
released.

The constructors here create CPU-compatible images. @tech{GPU images} satisfy the
same @racket[image?] predicate but retain additional context requirements.
CPU readback, subsetting, and encoding reject GPU-dependent input instead of
transferring it implicitly.

@local-table-of-contents[#:style 'immediate-only]

@section[#:tag "skia-image-loading"]{Loading Images}

@defproc[(image? [v any/c]) boolean?]{
Returns @racket[#t] for an image, including a GPU image or a closed wrapper,
and @racket[#f] otherwise. It does not establish that pixels are decoded or
that the resource is valid for native use.
}

@defproc[(image-from-file [filename path-string?]) image?]{
Creates an image from a nonempty encoded file. The file must exist, its size
must fit @racket[current-skia-byte-limit], and its path must not contain an
embedded NUL. Native image construction applies the dimension checks described
for @racket[image-from-bytes]. The native image retains encoded data
for deferred decoding; no Racket input port remains open on the caller's behalf.
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
and explicit @tech{encoded orientation} handling belong to the @tech{codec} interfaces.
}

@section[#:tag "skia-image-dimensions"]{Image Dimensions}

@defproc[(image-width [image image?]) exact-positive-integer?]{
Returns the stored pixel width, including after the resource is closed. This
metadata query does not decode pixels or activate a GPU context.
}

@defproc[(image-height [image image?]) exact-positive-integer?]{
Returns the stored pixel height, including after closure. The same metadata
restrictions as @racket[image-width] apply.
}

@section[#:tag "skia-image-drawing"]{Drawing Images}

Drawing uses image coordinates for a source rectangle and canvas-local
coordinates for a destination rectangle. The @tech{canvas transform} and @tech{clip} apply
to the destination. @deftech{Nearest sampling} selects individual source pixels;
@deftech{linear sampling} interpolates adjacent samples. Sampling is independent
of a paint's @tech{antialiasing} setting.

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
The default is @tech{nearest sampling}; @racket[draw-image-rect] and
@racket[draw-image-subrect] default to @tech{linear sampling}.
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

@reference-figure["image-pair.png"
                  "An enlarged two-pixel image, red on the left and blue on the right, using nearest sampling."]
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

For a CPU filter result's separate returned source rectangle and placement
offset, see @secref["skia-image-filter-results"].

@racketblock[
(with-skia ([source (make-surface 80 50 #:background "#F4D35E")]
            [blue (make-paint #:color "#326DE6")])
  (draw-circle (surface-canvas source) 40 25 18 blue)
  (with-skia ([image (surface-snapshot source)]
              [target (make-surface 220 90 #:background 'white)])
    (draw-image-rect (surface-canvas target) image 10 15 80 50 #:sampling 'nearest)
    (draw-image-subrect (surface-canvas target) image
                        20 5 40 40 125 5 80 80 #:sampling 'nearest)))
]

@reference-figure["image-subrect.png"
                  "The complete yellow-and-blue source image on the left and an enlarged central source rectangle on the right."]
}

@section[#:tag "skia-image-subsets"]{Image Subsets}

@defproc[(image-subset [image image?]
                      [x exact-nonnegative-integer?] [y exact-nonnegative-integer?]
                      [width exact-positive-integer?] [height exact-positive-integer?]) image?]{
Returns an independently owned raster subset. The rectangle must fit entirely
within the image; it is not silently clipped. Unlike drawing source rectangles,
these coordinates and extents must be exact integers. The subset remains usable
after the source is closed, although native storage may be shared. GPU-dependent
images require an explicit GPU-subset or transfer operation instead.
}

@section{Standard Conversion}

Images implement @racketmodname[file/convertible]'s protocol. A live CPU image accepts
@racket['png-bytes], with the same encoder defaults, color/alpha behavior,
byte limit, and failure behavior as @racket[image->png-bytes]. The result is a
detached byte string. Other conversion requests return their supplied default
unchanged (including a function value) without inspecting or decoding the
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

When given a Skia image, @tt{pict:bitmap} obtains PNG bytes through
@racketmodname[file/convertible] and constructs an independent raster pict.
The original Skia image can be closed after the pict is constructed.

To construct a pict without PNG encoding and decoding, use @racket[image->pict]
from @racketmodname[skia/pict]. It also supports an explicit logical backing
scale through @racket[#:backing-scale].

@section[#:tag "skia-image-pixel-copies"]{Raw Pixel Construction and Readback}

To load encoded images, use @racket[image-from-file] or @racket[image-from-bytes].
To display an image, use @racket[draw-image] or @racket[draw-image-rect]. The
operations in this section instead accept or return raw RGBA pixels. Callers
must account for the pixel layout and alpha representation.

@defproc[(rgba-bytes->image [width (integer-in 1 32768)]
                           [height (integer-in 1 32768)] [pixels bytes?]
                           [#:premultiplied? premultiplied? boolean? #f]
                           [#:color-space space (or/c color-space? #f) #f]) image?]{
Copies tightly packed RGBA bytes into a new owned raster image. The byte string
must contain exactly @racket[(* width height 4)] bytes, within
@racket[current-skia-byte-limit]. Rows run from top to bottom, with no padding.
Later mutation of @racket[pixels] does not change the image.

The default uses @tech{unpremultiplied alpha}. With @racket[premultiplied?] true,
each RGB byte must be no greater than its pixel's alpha byte; otherwise the
operation raises an exception. The option describes the supplied bytes, not a
request to multiply them. A supplied @racket[space] declares their interpretation
without converting them. The image retains its own native color-space reference.

@racketblock[
(with-skia ([image (rgba-bytes->image 2 1 (bytes 255 0 0 255 0 0 255 128))]
            [surface (make-surface 200 100 #:background 'white)]
            [dark (make-paint #:color "#D9DEE4")]
            [light (make-paint #:color "#F1F3F5")]
            [outline (make-paint #:color "#20344E" #:style 'stroke #:stroke-width 1)]
            [font (make-font #:size 12)]
            [label (make-paint #:color "#20344E")])
  (define canvas (surface-canvas surface))
  (draw-simple-text canvas "opaque red" 20 20 font label)
  (draw-simple-text canvas "blue alpha 128" 105 20 font label)
  (for* ([row (in-range 3)] [column (in-range 8)])
    (draw-rect canvas (+ 20 (* column 20)) (+ 35 (* row 20)) 20 20
               (if (even? (+ row column)) light dark)))
  (draw-image-rect canvas image 20 35 160 50 #:sampling 'nearest)
  (draw-rect canvas 20 35 160 50 outline)
  (bytes->list (image->rgba-bytes image)))
]

@reference-figure["image-rgba-alpha.png"
                  "An actual two-pixel RGBA image enlarged with nearest-neighbor sampling. The opaque red pixel is at left; the half-alpha blue pixel is at right over a declared gray checkerboard preview."]

The checkerboard is behind the image only to expose blue's alpha 128. It is not part of
the supplied RGBA bytes.
}

@defproc[(image->rgba-bytes [image image?]
                           [#:premultiplied? premultiplied? boolean? #f]
                           [#:color-space space (or/c color-space? #f) #f]) bytes?]{
Returns a new mutable, tightly packed RGBA byte string. Row order, alpha
interpretation, destination color-space selection, and size limits are the
same as for @racket[surface->rgba-bytes]. The read may trigger deferred decoding.
A failed native read raises an exception instead of returning partial bytes.
The image itself is unchanged.
}

@section{Image Properties}

Use @racket[image-width] and @racket[image-height] for image dimensions. These
queries inspect storage formats, color spaces, and retained encoded data;
ordinary drawing does not require them.

@defproc[(image-color-type [image image?]) symbol?]{
Returns the native pixel-format name, such as @racket['rgba-8888],
@racket['bgra-8888], or @racket['rgba-f16]. The result is not the encoded file
format: a PNG and a JPEG may decode into the same pixel format. Unlike the stored
dimension queries, this call requires the image to be valid for native use.
}

@defproc[(image-alpha-type [image image?]) (or/c 'unknown 'opaque 'premul 'unpremul)]{
Returns the image's native alpha interpretation. Opaque means no transparency.
With @tech{premultiplied alpha}, stored RGB is multiplied by alpha. With
@tech{unpremultiplied alpha}, RGB is stored independently. The unknown value means
that no usable alpha type is declared; it is not a fourth blending rule.
The image must be valid for native use.
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

@section{Additional Visual Examples}

@racketblock[
(with-skia ([image (rgba-bytes->image 2 2
                 (bytes 255 0 0 255 0 128 0 255
                        0 0 255 255 255 255 0 255))]
            [surface (make-surface 210 100 #:background 'white)])
  (draw-image-rect (surface-canvas surface) image 10 10 85 80 #:sampling 'nearest)
  (draw-image-rect (surface-canvas surface) image 115 10 85 80 #:sampling 'linear))
]
@reference-figure["sampling-comparison.png"
                  "The same four-color image enlarged with nearest sampling on the left and linear sampling on the right."]

@racketblock[
(with-skia ([source (make-surface 80 60 #:background "#F4D35E")]
            [blue (make-paint #:color "#326DE6")])
  (draw-circle (surface-canvas source) 40 30 22 blue)
  (with-skia ([image (surface-snapshot source)]
              [part (image-subset image 20 10 40 40)]
              [target (make-surface 220 100 #:background 'white)])
    (draw-image-rect (surface-canvas target) image 10 20 80 60 #:sampling 'nearest)
    (draw-image-rect (surface-canvas target) part 125 5 80 80 #:sampling 'nearest)))
]
@reference-figure["image-subset.png"
                  "A complete yellow image with a blue circle beside an enlarged independently owned central subset."]

@racketblock[
(with-skia ([source (make-surface 40 40 #:background "#326DE6")]
            [image (surface-snapshot source)]
            [alpha-paint (make-paint #:color (rgba 255 255 255 100))]
            [target (make-surface 200 90 #:background "#EFA02B")])
  (draw-image-rect (surface-canvas target) image 20 20 50 50 #:sampling 'nearest)
  (draw-image-rect (surface-canvas target) image 125 20 50 50
                   #:sampling 'nearest #:paint alpha-paint))
]
@reference-figure["image-alpha-paint.png"
                  "Two blue images on orange: the right copy is translucent because its drawing paint reduces alpha."]

@racketblock[
(with-skia ([image (rgba-bytes->image 2 1 (bytes 255 0 0 255 0 0 255 255))]
            [surface (make-surface 220 90 #:background 'white)])
  (define canvas (surface-canvas surface))
  (draw-image-rect canvas image 15 20 80 50 #:sampling 'nearest)
  (with-canvas-state canvas
    (canvas-translate! canvas 205 20)
    (canvas-scale! canvas -1 1)
    (draw-image-rect canvas image 0 0 80 50 #:sampling 'nearest)))
]
@reference-figure["image-mirror.png"
                  "A red-left blue-right image beside a horizontally reflected copy with blue on the left."]
