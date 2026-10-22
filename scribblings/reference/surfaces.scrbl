#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia))

@title[#:tag "skia-surfaces"]{Surfaces and Canvas Access}

A @deftech{surface} is a drawing target that stores pixels. A @deftech{canvas}
provides drawing operations for a target and keeps track of drawing state,
including the current @tech{canvas transform} and @tech{clip}. A surface has an
associated canvas; canvases can also draw into recordings, documents, or
@tech{GPU frames}.

Use @racket[make-surface] for ordinary eight-bit RGBA drawing and
@racket[surface-canvas] to obtain its canvas. For other pixel formats, use
@racket[make-surface-from-info]. See @secref["skia-resources"] for general rules
about resource lifetimes and Racket threads.

@local-table-of-contents[#:style 'immediate-only]

@section{Working with Surfaces}

In DrRacket's interactions window, evaluating a surface created by
@racket[make-surface] displays its current pixels. Evaluate the surface again
after drawing to see the updated pixels. Use @racket[save-png] to save the
drawing to a file, or @racket[surface->png-bytes] to obtain PNG bytes; see
@secref["skia-encoding"].

The following example displays a blue rectangle:

@racketblock[
(require skia)
(define surface (make-surface 120 80 #:background 'white))
(canvas-clear! (surface-canvas surface) 'blue)
surface
]

@section{Construction and Canvas Access}

@defproc[(surface? [v any/c]) boolean?]{
Returns @racket[#t] for a Skia surface and @racket[#f] otherwise.
}

@defproc[(canvas? [v any/c]) boolean?]{
Returns @racket[#t] for a Skia canvas and @racket[#f] otherwise.
}

@defproc[(make-surface [width (integer-in 1 32768)]
                       [height (integer-in 1 32768)]
                       [#:background background color? 'transparent]
                       [#:color-space space (or/c color-space? #f) #f]) surface?]{
Creates a surface containing a bitmap that is @racket[width] pixels wide and
@racket[height] pixels high. It initially fills every pixel with
@racket[background], which defaults to @racket['transparent].

Each pixel has eight-bit red, green, blue, and alpha components. The RGB
components use @tech{premultiplied alpha}. The bitmap requires
@racket[(* 4 width height)] bytes of storage. This size must not exceed
@racket[(current-skia-byte-limit)]. Creation can still fail if memory is
unavailable.

For another pixel format, such as alpha-only or floating-point storage, use
@racket[make-surface-from-info] with a description created by
@racket[make-image-info].

The @racket[space] argument associates a @tech{color space} with the surface.
The default, @racket[#f], means that no color space is associated with the
surface.

The returned surface is a resource with its own lifetime. See
@secref["skia-resources"] for release rules.

@racketblock[
(define surface (make-surface 120 80 #:background 'white))
]
}

@defproc[(surface-canvas [surface surface?]) canvas?]{
Returns a canvas wrapper for @racket[surface]. Each call returns a new wrapper,
but all wrappers for one surface access the same canvas and share its drawing
state. The call does not clear pixels or reset that state.

The returned canvas cannot be used after @racket[surface] is released.
For GPU surfaces, see @secref["skia-gpu-surfaces"].

@racketblock[
(define surface (make-surface 120 80))
(define canvas (surface-canvas surface))
]
}

@section{Dimensions and Backing}

For pixel geometry and rendering flags, use @racket[surface-properties-of],
documented in @secref["skia-surface-properties"]. It accepts both raster surfaces
and GPU surfaces.

@defproc[(surface-width [surface surface?]) exact-positive-integer?]{
Returns the stored width of @racket[surface] in pixels.
}

@defproc[(surface-height [surface surface?]) exact-positive-integer?]{
Returns the stored height of @racket[surface] in pixels.
}

@defproc[(surface-backend [surface surface?])
          (or/c 'raster 'opengl 'metal 'direct3d)]{
Returns @racket['raster] for a surface stored in CPU memory, or the selected
backend for a @tech{GPU surface}. Surfaces created by @racket[make-surface]
use @racket['raster].
}

@defproc[(surface-color-space [surface surface?]) (or/c color-space? #f)]{
Returns the @tech{color space} associated with @racket[surface], or @racket[#f]
if no color space is associated with it.
}

@section[#:tag "skia-surface-readback"]{Snapshots and Pixel Copies}

The operations in this section require a surface whose pixels are stored in
CPU memory, such as one created by @racket[make-surface]. Supplying a GPU surface
raises an exception. For GPU surfaces, see @secref["skia-gpu-surfaces"] for snapshots and
@secref["skia-gpu-transfers"] for pixel copies.

@defproc[(surface-snapshot [surface surface?]) image?]{
Returns an @tech{image} of @racket[surface]'s current pixels. Later drawing
to @racket[surface] does not change the image.

@racketblock[
(with-skia ([surface (make-surface 2 1 #:background 'red)]
            [image (surface-snapshot surface)])
  (canvas-clear! (surface-canvas surface) 'blue)
  (bytes->list (image->rgba-bytes image)))
]

@reference-figure["surface-snapshot-independence.png"
                  "Two nearest-neighbor enlargements of the same two-by-one surface at different times. The snapshot remains two opaque red pixels, while the surface after clear has two opaque blue pixels."]

The snapshot keeps the two red pixels captured before the surface is cleared
to blue. Both results are enlarged to make the pixels visible.
}

@defproc[(surface->rgba-bytes [surface surface?]
                             [#:premultiplied? premultiplied? boolean? #f]
                             [#:color-space space (or/c color-space? #f) #f]) bytes?]{
Returns a new mutable byte string containing @racket[surface]'s pixels. Rows
are stored from top to bottom, with pixels from left to right. Each pixel
occupies four bytes: red, green, blue, and alpha, in that order. There are no
extra bytes between rows.

The default uses @tech{unpremultiplied alpha}. When @racket[premultiplied?]
is @racket[#t], the result uses @tech{premultiplied alpha}. Converting from
premultiplied storage can lose precision, especially for small alpha values.
The original RGB values cannot be recovered when alpha is zero.

The @racket[space] argument selects a destination @tech{color space} for the
pixel conversion. With the default, @racket[#f], no color-space conversion is
applied. Pixels are still converted to eight-bit RGBA using the requested alpha
representation. The byte string does not include color-space information.

The byte string's length is four times the product of the surface width and
height. It must not exceed @racket[(current-skia-byte-limit)].
If reading or converting the pixels fails, the function raises an exception.
}

@defproc[(surface-pixel [surface surface?]
                        [x exact-nonnegative-integer?]
                        [y exact-nonnegative-integer?]) rgba?]{
Returns the pixel at @racket[x], @racket[y] as an @racket[rgba] value using
@tech{unpremultiplied alpha}. The top-left pixel has both coordinates equal
to @racket[0].
The @racket[x] coordinate must be less than the surface width, and @racket[y]
must be less than the surface height. The @tech{canvas transform} and
@tech{clip} do not affect which pixel is read.
}
