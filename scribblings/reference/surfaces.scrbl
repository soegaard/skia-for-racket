#lang scribble/manual

@(require (for-label racket/base racket/contract file/convertible skia))

@title[#:tag "skia-surfaces"]{Surfaces and Canvases}

A @deftech{surface} owns a pixel-based drawing target. A @deftech{canvas}
provides access to a drawing target and carries drawing state, including the
current transform and clip. A surface has an associated canvas; canvases can
also belong to recordings, documents, or GPU frames.

Several canvas wrappers obtained from one surface refer to the same target and
state; they are not independent layers. A surface canvas is a
@tech{borrowed canvas}, not an independently closeable resource.

@defproc[(surface? [v any/c]) boolean?]{
Returns @racket[#t] for a Skia surface and @racket[#f] otherwise. The predicate
recognizes CPU and GPU surfaces, including closed ones. It does not establish
that a surface is open or CPU-backed.
}

@defproc[(canvas? [v any/c]) boolean?]{
Returns @racket[#t] for a Skia canvas and @racket[#f] otherwise. A canvas still
satisfies this predicate after its owner or scope has expired.
}

@defproc[(make-surface [width (integer-in 1 32768)]
                       [height (integer-in 1 32768)]
                       [#:background background color? 'transparent]
                       [#:color-space space (or/c color-space? #f) #f]) surface?]{
Creates an owned CPU raster surface with the given pixel dimensions and clears
it to @racket[background]. It uses eight-bit RGBA storage with premultiplied
alpha. The required @racket[(* 4 width height)] bytes must not exceed
@racket[(current-skia-byte-limit)]. Native allocation can still fail below that
limit.

The @racket[space] argument supplies a color-space tag. The default @racket[#f]
leaves the surface untagged; it does not declare sRGB. A supplied color-space
resource must be open on the appropriate thread during construction. The native
surface retains its own reference to that space, rather than taking ownership
of the caller's wrapper.

The constructor requires the native Skia library. It does not initialize a GUI,
create a GPU context, or select a fallback backend. See
@secref["skia-resources"] for release rules.

@racketblock[
(define surface (make-surface 120 80 #:background 'white))
]
}

@defproc[(surface-canvas [surface surface?]) canvas?]{
Returns a canvas for @racket[surface]. The surface must be open, accessible on
the owning thread, and not exclusively borrowed by another target scope.
The result borrows the surface's lifetime. Closing the surface invalidates it.
The call does not clear pixels or reset the surface's drawing state.

For a GPU surface, the matching GPU activation is also required and the returned
canvas is limited to that activation's lease. Retaining the wrapper outside
that scope does not extend the lease. Use the canvas supplied by each GPU frame
callback during that callback, rather than keeping a canvas for a later frame.

@racketblock[
(define surface (make-surface 120 80))
(define canvas (surface-canvas surface))
]
}

@section{Dimensions and Backing}

@defproc[(surface-width [surface surface?]) exact-positive-integer?]{
Returns the stored width of @racket[surface] in pixels. This is a metadata query:
it remains available after closure and does not require GPU activation.
}

@defproc[(surface-height [surface surface?]) exact-positive-integer?]{
Returns the stored height of @racket[surface] in pixels, including after closure.
Like @racket[surface-width], it does not validate the surface for drawing.
}

@defproc[(surface-backend [surface surface?]) symbol?]{
Returns @racket['raster] for an ordinary CPU surface or the selected GPU backend
for a GPU surface. The result describes backing, not resource liveness. It can
be read after closure and without activating a GPU context.
}

@defproc[(surface-color-space [surface surface?]) (or/c color-space? #f)]{
Returns an independently owned reference to the surface's color space, or
@racket[#f] for an untagged surface. A returned resource can be closed separately
and remains usable after the surface is closed. The surface must be valid for
native use; GPU surfaces require their matching active context.
}

@section[#:tag "skia-surface-readback"]{Snapshots and Pixel Copies}

The following operations accept CPU surfaces. They reject GPU surfaces instead
of performing an implicit readback. A GPU application must request a CPU copy
through its explicit GPU-transfer API first. These operations read pixels, not
the canvas's current local coordinate system.

@subsection{Standard PNG Conversion}

Surfaces implement @racketmodname[file/convertible]'s protocol for
@racket['png-bytes]. It is equivalent to calling @racket[surface->png-bytes]
with its defaults, so each conversion reflects the surface's current pixels;
encoded data is not cached. The returned bytes are detached from the surface.
Unsupported conversion requests return the exact supplied default without
checking the resource or doing native work. Supported requests preserve the
ordinary lifetime, thread, byte-limit, and encoder errors even when a default
is supplied. GPU surfaces remain convertible values, but PNG conversion still
requires an explicit CPU transfer and never initiates implicit readback.

@defproc[(surface-snapshot [surface surface?]) image?]{
Returns an owned immutable image of the surface's current pixels. Subsequent
drawing to the surface does not change the snapshot, and the image remains
usable after the surface is closed. The native implementation may share storage
until a write requires separation; the call does not promise an immediate copy
of every pixel. The image has its own lifetime.

@racketblock[
(with-skia ([surface (make-surface 2 1 #:background 'red)]
            [image (surface-snapshot surface)])
  (canvas-clear! (surface-canvas surface) 'blue)
  (bytes->list (image->rgba-bytes image)))
]
}

@defproc[(surface->rgba-bytes [surface surface?]
                             [#:premultiplied? premultiplied? boolean? #f]
                             [#:color-space space (or/c color-space? #f) #f]) bytes?]{
Returns a new mutable byte string containing tightly packed rows from top to
bottom. Each pixel has red, green, blue, and alpha bytes in that order; the row
length is four times the surface width. The result has no row padding and does
not borrow the surface. Its length must fit @racket[current-skia-byte-limit].

The default returns unpremultiplied RGB. Supplying @racket[#t] requests RGB
multiplied by alpha. Low-alpha conversion may lose precision, and RGB at zero
alpha cannot be recovered from premultiplied storage. A supplied @racket[space]
requests a destination color space for native pixel conversion. The default
@racket[#f] requests an untagged destination; it does not attach an sRGB profile.
Native read or conversion failure raises an exception rather than returning
partial bytes.
}

@defproc[(surface-pixel [surface surface?]
                        [x exact-nonnegative-integer?]
                        [y exact-nonnegative-integer?]) rgba?]{
Returns one pixel as an unpremultiplied @racket[rgba] value. The coordinates are
integer pixel indices: @racket[x] must be less than the width and @racket[y]
less than the height. The canvas transform and clip do not affect the query.
The result is detached; it does not include a color-space tag.
}
