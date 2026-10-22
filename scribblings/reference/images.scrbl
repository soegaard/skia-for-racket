#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract file/convertible
                     skia skia/image-operations skia/pict))

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

Use @racket[image-from-file] to load a file, or @racket[image-from-bytes] when
you already have its encoded contents. Both check the following limits when
creating the image, even if pixel decoding is deferred:

@itemlist[
 @item{The encoded data must be nonempty and fit @racket[current-skia-byte-limit].}
 @item{The image's width and height must each be between 1 and 32768 pixels.}
 @item{@math{4 × width × height} must fit @racket[current-skia-byte-limit],
   whose initial value is 256 MiB. This is a size check, not a promise that
   decoding uses exactly four bytes per pixel.}]

Exceeding any of these limits raises an exception. Raising
@racket[current-skia-byte-limit] can allow a larger file or image, but does not
remove the 32768-pixel limit on either dimension or guarantee enough memory
for decoding. The parameter is not a limit on all memory used by Skia.

@defproc[(image? [v any/c]) boolean?]{
Returns @racket[#t] for an image, including a GPU image or a closed wrapper,
and @racket[#f] otherwise. It does not establish that pixels are decoded or
that the resource is valid for native use.
}

@defproc[(image-from-file [filename path-string?]) image?]{
Creates an image from a nonempty encoded file. The native library supplied by
the installer supports these file types; see @secref["skia-native-libraries"]
for library versions and selection:

@;{Decoder list: mono/skia at 40f75dc0051d141913c07c20d4c19590c7da0cb7,
   src/codec/SkCodec.cpp and gn/skia.gni; mono/SkiaSharp v3.119.1,
   native/macos/build.cake, native/linux/build.cake, and native/windows/build.cake.
   SkIcoCodec.cpp also recognizes CUR. SkRawCodec.cpp reads JPEG previews
   before falling back to DNG decoding.}
@itemlist[
 @item{PNG (@tt{.png}).}
 @item{JPEG (@tt{.jpg}, @tt{.jpeg}).}
 @item{WebP (@tt{.webp}).}
 @item{GIF (@tt{.gif}).}
 @item{BMP (@tt{.bmp}).}
 @item{Windows icons and cursors (@tt{.ico}, @tt{.cur}).}
 @item{WBMP (@tt{.wbmp}).}
 @item{DNG (@tt{.dng}).}
]

The format is detected from the file contents, not the filename extension.
For some other camera-raw formats, Skia reads an embedded JPEG preview rather
than the raw sensor data. Using a different native library can change the
available decoders.

The file must exist, and its path must not contain an embedded NUL. The
loading limits above apply to both the file size and image dimensions.
The native image stores the encoded data
for deferred decoding; no Racket input port remains open on the caller's behalf.
}

@defproc[(image-from-bytes [encoded bytes?]) image?]{
Creates an owned image from a copy of encoded image data. The supported formats
are listed under @racket[image-from-file].

The loading limits above apply to both the encoded bytes and image dimensions.
An unsupported or invalid image raises an exception rather than returning
@racket[#f].

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

Drawing uses image coordinates for a source rectangle and @tech{local
coordinates} for a destination rectangle. The @tech{canvas transform} and @tech{clip} apply
to the destination. @deftech{Nearest sampling} selects individual source pixels;
@deftech{linear sampling} interpolates adjacent samples. Sampling is independent
of a paint's @tech{antialiasing} setting.

Nearest sampling preserves hard pixel boundaries and is useful for pixel art.
Linear sampling blends neighboring pixels and is useful when resizing an
image. A canvas transform can resize an image drawn with @racket[draw-image],
even though the function has no width or height arguments. Pass
@racket[#:sampling] @racket['linear] when you want interpolation in that case.

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

The optional paint can supply alpha, blending, and filters. The image supplies
the source pixels; its destination rectangle is not outlined when the paint's
style is stroke. The source image is unchanged. GPU-dependent images or paint
content must match the receiving active GPU context; they are not implicitly
read back for a CPU or document target.

For example, a paint can make an image translucent without changing its pixels:

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

To mirror an image horizontally, translate the canvas to the desired right
edge and use a horizontal scale of @racket[-1]:

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
coordinates and sizes can be fractional, but the entire source
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
Creates a raster image from the selected rectangle of @racket[image].

The result is independently owned. The rectangle must fit entirely within the
image; it is not silently clipped. Unlike drawing source rectangles,
these coordinates and extents must be exact integers. The subset remains usable
after the source is closed, although native storage may be shared. GPU-dependent
images require an explicit GPU-subset or transfer operation instead.

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
}

@section[#:tag "skia-image-picts"]{Using Images as Picts}

Use @racket[image->pict] from @racketmodname[skia/pict] to construct a pict
without PNG encoding and decoding. It also supports an explicit logical
backing scale through @racket[#:backing-scale].

When given a Skia image, @tt{pict:bitmap} obtains PNG bytes through
@racketmodname[file/convertible] and constructs an independent raster pict.
The original Skia image can be closed after the pict is constructed.
See @secref["skia-standard-conversion"] for the shared PNG conversion rules,
including the requirement to transfer GPU images explicitly before conversion.

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
Copies the image's pixels into a mutable RGBA byte string, with no padding
between rows.

Row order, alpha interpretation, destination color-space selection, and size limits are the
same as for @racket[surface->rgba-bytes]. The read may trigger deferred decoding.
A failed native read raises an exception instead of returning partial bytes.
The image itself is unchanged.
}

@section[#:tag "skia-image-properties"]{Image Properties}

@(declare-exporting skia skia/image-operations #:use-sources (skia skia/image-operations))

Use these queries to inspect an image's pixel format, color space, or decoding
state before choosing a pixel operation. Ordinary drawing does not require
them. Use @racket[image-width] and @racket[image-height] for dimensions.

Unlike the stored dimension queries, the queries below require an open image
and enforce its thread and any GPU-context restrictions. Validity, deferred
decoding, texture backing, and immediately available pixels are separate
properties: none alone establishes the others.

@subsection[#:tag "skia-image-storage-properties"]{Storage Format and Color Space}

@defproc[(image-color-type [image image?]) symbol?]{
Returns the native pixel-format name, such as @racket['rgba-8888],
@racket['bgra-8888], or @racket['rgba-f16]. The result is not the encoded file
format: a PNG and a JPEG may decode into the same pixel format.
}

@defproc[(image-alpha-type [image image?]) (or/c 'unknown 'opaque 'premul 'unpremul)]{
Returns the image's native alpha interpretation. Opaque means no transparency.
With @tech{premultiplied alpha}, stored RGB is multiplied by alpha. With
@tech{unpremultiplied alpha}, RGB is stored independently. The unknown value means
that no usable alpha type is declared; it is not a fourth blending rule.
}

@defproc[(image-alpha-only? [image image?]) boolean?]{
Reports whether the image's pixel format stores only alpha. It does not check
whether the pixels happen to be opaque or all their RGB components are zero.
}

@defproc[(image-color-space [image image?]) (or/c color-space? #f)]{
Returns an independently owned reference to the image's color space, or
@racket[#f] for an untagged image. The returned reference remains usable after
the image is closed. It is a CPU color-space resource even when obtained from
a GPU image, although querying the GPU image requires its normal context rules.
}

@subsection[#:tag "skia-image-decoding-properties"]{Decoding and Pixel Availability}

@defproc[(image-lazy-generated? [image image?]) boolean?]{
Reports whether the image uses deferred generation. The query itself does not
decode or generate pixels.
}

@defproc[(image-texture-backed? [image image?]) boolean?]{
Reports whether the image uses a GPU texture. It does not transfer pixels or
establish that CPU pixel access is available.
}

@defproc[(image-pixels-available? [image image?]) boolean?]{
Reports whether pixel storage can be inspected immediately. The query does not
decode or read back pixels and returns no pointer to their storage. A
@racket[#f] result does not mean that later decoding will fail.
}

@subsection[#:tag "skia-image-validity"]{Validity}

@defproc[(image-valid? [image image?]) boolean?]{
Asks Skia whether an open image is valid, using the image's GPU context when
applicable. A valid image need not have immediately available CPU pixels.

Use @racket[skia-closed?] to check whether an image has been closed.
@racket[image-valid?] is not a general check that catches every reason an
image operation might fail. A closed image or invalid context raises an
exception rather than producing @racket[#f].
}

@subsection[#:tag "skia-image-identification"]{Identification and Encoded Data}

@defproc[(image-unique-id [image image?]) exact-nonnegative-integer?]{
Returns Skia's identifier for the image within the current process. It is not
a content hash or a persistent file identifier, and does not imply that the
image owns a unique copy of its pixels.
}

@defproc[(image-original-encoded-bytes [image image?]) (or/c bytes? #f)]{
Returns a new mutable copy of the encoded data stored by the native image, or
@racket[#f] when no encoded data are available. It does not encode raster pixels.
A surface snapshot or a raw-byte image therefore need not have an original encoded form.
The copied data must fit @racket[current-skia-byte-limit]. GPU-dependent input
is not accepted by this ordinary CPU API.
}
