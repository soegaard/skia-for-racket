#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract file/convertible skia skia/pict))

@title[#:tag "skia-images"]{Images}

An @deftech{image} is an immutable source of pixels for drawing, encoding, or
readback. Its native storage is owned by its resource wrapper. Immutability
means that drawing to another target does not edit the image; it does not mean
that decoding must already be complete or that storage must be CPU-resident.
An image snapshot and its source surface have separate lifetimes.

The constructors here create CPU-compatible images. GPU images satisfy the
same @racket[image?] predicate but retain additional context requirements.
CPU readback, subsetting, and encoding reject GPU-dependent input instead of
transferring it implicitly.

@local-table-of-contents[#:style 'immediate-only]

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
The default sampling is nearest; @racket[draw-image-rect] and
@racket[draw-image-subrect] default to linear sampling.
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

@section{Further Visual Examples}

These examples compare sampling and source selection using small synthetic
images so every result is deterministic.

@racketblock[
(with-skia ([image (rgba-bytes->image
                    2 2
                    (bytes 255 0 0 255   0 0 255 255
                           0 128 0 255   255 215 0 255))]
            [surface (make-surface 180 90 #:background 'white)])
  (draw-image-rect (surface-canvas surface) image 20 10 140 70
                   #:sampling 'nearest))
]
@reference-figure["nearest-upscale-stage8.png"
                  "A two-by-two red, blue, green, and yellow image enlarged with nearest sampling into four crisp color blocks."]

@racketblock[
(with-skia ([image (rgba-bytes->image
                    2 2
                    (bytes 255 0 0 255   0 0 255 255
                           0 128 0 255   255 215 0 255))]
            [surface (make-surface 180 90 #:background 'white)])
  (draw-image-rect (surface-canvas surface) image 20 10 140 70
                   #:sampling 'linear))
]
@reference-figure["linear-upscale-stage8.png"
                  "The same four-color two-by-two image enlarged with linear sampling, producing blended boundaries between pixels."]

@racketblock[
(with-skia ([source (make-surface 60 60 #:background "#F4D35E")]
            [blue (make-paint #:color "#326DE6")])
  (draw-circle (surface-canvas source) 30 30 20 blue)
  (with-skia ([image (surface-snapshot source)]
              [surface (make-surface 220 100 #:background 'white)])
    (draw-image-rect (surface-canvas surface) image 15 25 190 50)))
]
@reference-figure["stretch-image-stage8.png"
                  "A square source containing a blue circle is stretched into a wide rectangle, turning the circle into an ellipse."]

@racketblock[
(with-skia ([source (make-surface 80 50 #:background "#F4D35E")]
            [blue (make-paint #:color "#326DE6")]
            [red (make-paint #:color "#E94F37")])
  (draw-circle (surface-canvas source) 22 25 17 blue)
  (draw-circle (surface-canvas source) 58 25 17 red)
  (with-skia ([image (surface-snapshot source)]
              [surface (make-surface 220 100 #:background 'white)])
    (draw-image-subrect (surface-canvas surface) image
                        40 0 40 50
                        35 15 150 70)))
]
@reference-figure["subrect-crop-stage8.png"
                  "Only the right half of a two-circle source is selected and enlarged, leaving the red circle as the visible crop."]

@racketblock[
(with-skia ([source (make-surface 40 40)]
            [red (make-paint #:color 'red)]
            [blue (make-paint #:color 'blue)]
            [green (make-paint #:color 'green)]
            [yellow (make-paint #:color 'yellow)])
  (draw-rect (surface-canvas source) 0 0 20 20 red)
  (draw-rect (surface-canvas source) 20 0 20 20 blue)
  (draw-rect (surface-canvas source) 0 20 20 20 green)
  (draw-rect (surface-canvas source) 20 20 20 20 yellow)
  (with-skia ([image (surface-snapshot source)]
              [surface (make-surface 240 110 #:background 'white)])
    (for ([x0 '(0 20 0 20)] [y0 '(0 0 20 20)] [x '(10 70 130 190)])
      (with-skia ([part (image-subset image x0 y0 20 20)])
        (draw-image-rect (surface-canvas surface) part x 25 40 60
                         #:sampling 'nearest)))))
]
@reference-figure["subset-quadrants-stage8.png"
                  "The four colored quadrants of one image are extracted as independent subsets and enlarged in a row."]

@racketblock[
(with-skia ([source (make-surface 80 50)]
            [blue (make-paint #:color (rgba 50 109 230 120))]
            [red (make-paint #:color (rgba 233 79 55 180))])
  (draw-circle (surface-canvas source) 28 25 22 blue)
  (draw-circle (surface-canvas source) 52 25 22 red)
  (with-skia ([image (surface-snapshot source)]
              [surface (make-surface 220 100 #:background "#F4D35E")])
    (draw-image-rect (surface-canvas surface) image 30 15 160 70)))
]
@reference-figure["image-alpha-rows-stage8.png"
                  "Two overlapping translucent source circles are enlarged over a yellow destination, making their alpha blending visible."]

@racketblock[
(with-skia ([tile (make-surface 30 30 #:background "#F4D35E")]
            [blue (make-paint #:color "#326DE6")])
  (draw-circle (surface-canvas tile) 15 15 10 blue)
  (with-skia ([image (surface-snapshot tile)]
              [surface (make-surface 220 110 #:background 'white)])
    (for* ([row (in-range 3)] [column (in-range 6)])
      (draw-image (surface-canvas surface) image
                  (+ 10 (* column 34)) (+ 8 (* row 34))))))
]
@reference-figure["image-grid-repeat-stage8.png"
                  "A small yellow tile with a blue circle is drawn repeatedly as an explicit three-by-six image grid."]

@racketblock[
(with-skia ([source (make-surface 80 50 #:background "#F4D35E")]
            [blue (make-paint #:color "#326DE6")])
  (draw-rounded-rect (surface-canvas source) 10 8 60 34 8 8 blue)
  (with-skia ([image (surface-snapshot source)]
              [surface (make-surface 220 100 #:background 'white)])
    (draw-image (surface-canvas surface) image 20 25)))
]
@reference-figure["image-native-size-stage8.png"
                  "An eighty-by-fifty source image is drawn at its natural size without destination scaling."]
@section{Further Visual Examples}

The following examples show additional visible consequences of the drawing operations in this chapter.

@racketblock[
(with-skia ([surface (make-surface 180 100 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([source (make-surface 4 4 #:background 'red)]
              [blue (make-paint #:color "#326DE6")]
              [yellow (make-paint #:color "#F4D35E")]
              [green (make-paint #:color "#10988E")])
    (draw-rect (surface-canvas source) 2 0 2 2 blue)
    (draw-rect (surface-canvas source) 0 2 2 2 yellow)
    (draw-rect (surface-canvas source) 2 2 2 2 green)
    (with-skia ([image (surface-snapshot source)])
      (draw-image-rect canvas image 10 10 160 80 #:sampling 'nearest)))
)
]
@reference-figure["image-nearest-stage9.png"
                  "A four-color miniature is enlarged with nearest sampling, preserving hard block boundaries."]

@racketblock[
(with-skia ([surface (make-surface 180 100 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([source (make-surface 4 4 #:background 'red)]
              [blue (make-paint #:color "#326DE6")]
              [yellow (make-paint #:color "#F4D35E")]
              [green (make-paint #:color "#10988E")])
    (draw-rect (surface-canvas source) 2 0 2 2 blue)
    (draw-rect (surface-canvas source) 0 2 2 2 yellow)
    (draw-rect (surface-canvas source) 2 2 2 2 green)
    (with-skia ([image (surface-snapshot source)])
      (draw-image-rect canvas image 10 10 160 80 #:sampling 'linear)))
)
]
@reference-figure["image-linear-stage9.png"
                  "The same four-color miniature is enlarged with linear sampling, blending colors at the block boundaries."]

@racketblock[
(with-skia ([surface (make-surface 200 100 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([source (make-surface 4 4 #:background 'red)]
              [blue (make-paint #:color "#326DE6")]
              [yellow (make-paint #:color "#F4D35E")]
              [green (make-paint #:color "#10988E")])
    (draw-rect (surface-canvas source) 2 0 2 2 blue)
    (draw-rect (surface-canvas source) 0 2 2 2 yellow)
    (draw-rect (surface-canvas source) 2 2 2 2 green)
    (with-skia ([image (surface-snapshot source)])
      (draw-image-rect canvas image 10 25 180 50 #:sampling 'nearest)))
)
]
@reference-figure["image-stretch-stage9.png"
                  "A square four-color source is stretched into a wide destination rectangle, changing its aspect ratio."]

@racketblock[
(with-skia ([surface (make-surface 200 100 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([source (make-surface 4 4 #:background 'red)]
              [blue (make-paint #:color "#326DE6")]
              [yellow (make-paint #:color "#F4D35E")]
              [green (make-paint #:color "#10988E")])
    (draw-rect (surface-canvas source) 2 0 2 2 blue)
    (draw-rect (surface-canvas source) 0 2 2 2 yellow)
    (draw-rect (surface-canvas source) 2 2 2 2 green)
    (with-skia ([image (surface-snapshot source)])
      (draw-image-subrect canvas image 2 0 2 4 20 10 160 80 #:sampling 'nearest)))
)
]
@reference-figure["image-subrect-stage9.png"
                  "Only the right half of a four-color source image is selected and enlarged into the destination rectangle."]

@racketblock[
(with-skia ([surface (make-surface 200 100 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([source (make-surface 4 4 #:background 'red)]
              [blue (make-paint #:color "#326DE6")]
              [yellow (make-paint #:color "#F4D35E")]
              [green (make-paint #:color "#10988E")])
    (draw-rect (surface-canvas source) 2 0 2 2 blue)
    (draw-rect (surface-canvas source) 0 2 2 2 yellow)
    (draw-rect (surface-canvas source) 2 2 2 2 green)
    (with-skia ([image (surface-snapshot source)]
                [subset (image-subset image 0 0 2 2)])
      (draw-image-rect canvas subset 20 10 160 80 #:sampling 'nearest)))
)
]
@reference-figure["image-subset-stage9.png"
                  "A two-by-two upper-left subset of the source image is enlarged independently of the original image."]

@racketblock[
(with-skia ([surface (make-surface 200 100 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([background (make-paint #:color "#EFA02B")]
              [source (make-surface 4 4 #:background 'red)]
              [blue (make-paint #:color "#326DE6")]
              [yellow (make-paint #:color "#F4D35E")]
              [green (make-paint #:color "#10988E")]
              [alpha (make-paint #:color (rgba 255 255 255 128))])
    (draw-paint canvas background)
    (draw-rect (surface-canvas source) 2 0 2 2 blue)
    (draw-rect (surface-canvas source) 0 2 2 2 yellow)
    (draw-rect (surface-canvas source) 2 2 2 2 green)
    (with-skia ([image (surface-snapshot source)])
      (draw-image-rect canvas image 20 10 160 80 #:sampling 'nearest #:paint alpha)))
)
]
@reference-figure["image-alpha-stage9.png"
                  "A four-color source image is drawn at half opacity over an orange background."]

@racketblock[
(with-skia ([surface (make-surface 220 120 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([source (make-surface 4 4 #:background 'red)]
              [blue (make-paint #:color "#326DE6")]
              [yellow (make-paint #:color "#F4D35E")]
              [green (make-paint #:color "#10988E")])
    (draw-rect (surface-canvas source) 2 0 2 2 blue)
    (draw-rect (surface-canvas source) 0 2 2 2 yellow)
    (draw-rect (surface-canvas source) 2 2 2 2 green)
    (with-skia ([image (surface-snapshot source)])
      (for* ([row (in-range 2)] [col (in-range 3)])
        (draw-image-rect canvas image (+ 15 (* col 70)) (+ 15 (* row 50))
                         55 40 #:sampling 'nearest))))
)
]
@reference-figure["image-grid-stage9.png"
                  "A small four-color image is repeated in a three-by-two grid at a fixed destination size."]

@racketblock[
(with-skia ([surface (make-surface 220 100 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([source (make-surface 4 4 #:background 'red)]
              [blue (make-paint #:color "#326DE6")]
              [yellow (make-paint #:color "#F4D35E")]
              [green (make-paint #:color "#10988E")])
    (draw-rect (surface-canvas source) 2 0 2 2 blue)
    (draw-rect (surface-canvas source) 0 2 2 2 yellow)
    (draw-rect (surface-canvas source) 2 2 2 2 green)
    (with-skia ([image (surface-snapshot source)])
      (draw-image-subrect canvas image 0 0 2 4 10 10 90 80 #:sampling 'nearest)
      (draw-image-subrect canvas image 2 0 2 4 120 10 90 80 #:sampling 'nearest)))
)
]
@reference-figure["image-subrect-pair-stage9.png"
                  "The left and right halves of one source image are extracted separately and enlarged side by side."]
