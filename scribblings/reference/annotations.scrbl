#lang scribble/manual

@(require scribble/eval
          (for-label racket/base racket/contract skia skia/annotations))

@(define destination-eval (make-base-eval))
@(destination-eval '(require skia/annotations))

@title[#:tag "skia-annotations"]{Links and Named Destinations}

@defmodule[skia/annotations #:no-declare]
@(declare-exporting skia skia/annotations #:use-sources (skia/annotations))

A @deftech{named destination} associates a case-sensitive name with a point in
one PDF or SVG document. A link rectangle refers to a URI or to a named
destination. Annotations do not paint a visible label or border; draw those
separately. Destination names are scoped to the whole PDF document, across
pages, or to one SVG document.

Names must be nonempty strings. They cannot contain character codes below 32,
DEL (127), U+FFFE, or U+FFFF. Names are not Unicode-normalized, case-folded, or
implicitly converted from symbols. UTF-8 names and their encoded identifiers
are subject to @racket[current-skia-byte-limit].

@section{Backend Behavior}

@defproc[(canvas-annotation-backend [canvas canvas?])
          (or/c 'pdf 'svg 'raster 'recording)]{
Reports the annotation behavior of a live supported canvas. Ordinary PDF and SVG
canvases emit document annotations. Raster annotations are invisible no-ops
under ordinary drawing policy. A picture-recording canvas can record URI links,
but not named destinations or links to them. Unsupported specialized canvases
raise an exception.

GPU-surface canvases are also classified as @racket['raster], since they do not
produce document annotations. This classification is independent of the surface's
rendering backend. Use @racket[canvas-execution-backend] to distinguish CPU and GPU
execution.
}

@defproc[(canvas-annotate-url! [canvas canvas?] [x real?] [y real?]
                              [width (and/c real? (>=/c 0))]
                              [height (and/c real? (>=/c 0))] [uri string?]) void?]{
Associates a link rectangle with a URI. The rectangle uses current local canvas
coordinates and must satisfy the normal drawing-scalar rectangle checks.
Zero-width or zero-height rectangles emit no URI annotation, but their arguments
are still validated. Picture recordings retain the URI annotation for replay.
Ordinary raster targets ignore the annotation after validation; an active output
policy may reject annotation loss instead of accepting that no-op.

The URI must be a nonempty printable ASCII string with valid percent escapes.
Spaces, non-ASCII characters, quotes, angle brackets, backslashes, carets,
backticks, braces, vertical bars, and DEL must not appear literally. Supported
explicit schemes are HTTP, HTTPS, and mailto; relative URIs are also accepted.
HTTP(S) requires an authority and mailto requires a nonempty target. A leading
fragment marker is rejected: use @racket[canvas-link-destination!] for a link
inside the current document. Validation does not access the network or establish
that the target exists.
}

@section{Defining and Linking Destinations}

@defproc[(canvas-define-destination! [canvas canvas?] [name string?]
                                    [x real?] [y real?]) void?]{
Defines a destination at the given drawing-scalar point in a PDF or SVG document.
The @racket[name] must be valid for a @tech{named destination} and must not already
be defined in that document, even at the same point. PDF destinations can be
referenced across pages.
SVG destinations capture the current affine point and become named views when
the SVG is finalized.

A picture-recording canvas rejects this operation; define document destinations
after replaying a picture on a live PDF or SVG canvas. An ordinary raster canvas
performs no destination registration after validating arguments, subject to the
active output policy. Keeping a name in Racket does not extend a page's lifetime.
}

@defproc[(canvas-link-destination! [canvas canvas?] [x real?] [y real?]
                                  [width (and/c real? (>=/c 0))]
                                  [height (and/c real? (>=/c 0))] [name string?]) void?]{
Links a rectangle to a destination in the current document. Forward references
are permitted, but finishing the PDF or SVG fails if any referenced name is
undefined. Zero-size and fully clipped references are still checked at finish;
visibility does not make a misspelled name acceptable.

The rectangle uses local coordinates and the normal drawing-scalar checks.
Picture recording rejects named links rather than deferring their document
scope. Ordinary raster targets perform no link registration after validation,
subject to the active output policy.

@racketblock[
(with-skia ([document (make-pdf-document)])
  (with-document-page (canvas document 120 80)
    (canvas-link-destination! canvas 10 10 80 20 "details"))
  (with-document-page (canvas document 120 80)
    (canvas-define-destination! canvas "details" 10 10))
  (document-finish! document)
  (save-pdf document "linked-pages.pdf" #:exists 'replace))
]

The first page links forward to the second. The example adds no visible text
inside the clickable rectangle.
}

@section{Portable Destination Identifiers}

@defproc[(destination-id [name string?]) (and/c string? immutable?)]{
Returns the ASCII identifier used for a valid destination name: @tt{dest-}
followed by the lowercase hexadecimal UTF-8 bytes. The encoding distinguishes
names exactly; the result is detached immutable data, not a registered destination.
}

@defproc[(svg-destination-id [name string?] [#:id-prefix id-prefix string? "skia"])
          (and/c string? immutable?)]{
Returns the SVG identifier consisting of the document prefix, a hyphen, and the
encoded destination ID. The prefix obeys the same rules as
@racket[make-svg-document] and must match that document's chosen prefix. Calling
this function does not add a named view to a document.

@examples[#:eval destination-eval
(eval:check (destination-id "A") "dest-41")
(eval:check (svg-destination-id "A" #:id-prefix "page") "page-dest-41")
]
@close-eval[destination-eval]
}
