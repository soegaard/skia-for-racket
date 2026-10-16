#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract file/convertible skia))

@title[#:tag "skia-pdf-documents"]{PDF Documents}

@(declare-exporting skia)

A @deftech{PDF document} owns an output stream and at most one active page.
A page canvas borrows that page's lifetime. Ending the page invalidates every
canvas wrapper for it; beginning another page does not revive an old canvas.
Finishing, releasing, and writing the document are separate operations.

Page dimensions are in points, with 72 points per inch. Skia drawing coordinates
start at the upper-left and increase downward in y; callers do not need to invert
the coordinate system to compensate for the PDF file's internal conventions.
Dimensions need not be integer pixel counts, and beginning a vector page does
not charge a complete RGBA image against the byte limit.

@local-table-of-contents[#:style 'immediate-only]

@section[#:tag "skia-pdf-settings"]{Construction and Settings}

@defproc[(document? [v any/c]) boolean?]{
Returns @racket[#t] for a PDF document, including a closed one, and @racket[#f] otherwise.
An SVG document is a separate kind of resource.
}

@defproc[(make-pdf-document
          [#:title title string? ""]
          [#:author author string? ""]
          [#:subject subject string? ""]
          [#:keywords keywords string? ""]
          [#:creator creator string? "skia-for-racket"]
          [#:producer producer string? "Skia/PDF m119; skia-for-racket"]
          [#:creation-date creation-date (or/c date? #f) #f]
          [#:modified-date modified-date (or/c date? #f) #f]
          [#:raster-dpi raster-dpi (real-in 1 9600) 144]
          [#:encoding-quality encoding-quality (integer-in 0 101) 101]
          [#:pdfa? pdfa? boolean? #f]) document?]{
Returns an owned document in the @racket['open] state with no completed pages.
No file is opened. Native construction failure raises an exception.

Metadata strings must be NUL-free; their combined UTF-8 size must fit
@racket[current-skia-byte-limit]. Omitted dates are unspecified, not requests
to insert the current time. Supplied dates must have a valid calendar date in
years 1 through 9999, time components excluding leap seconds, a weekday from 0
through 6, and a whole-minute UTC offset between -86340 and 86340 seconds.
The literal creator and producer defaults shown in the signature are the values
written by this API.

The raster DPI controls native fallback resolution for features that PDF cannot
represent directly. It does not change page dimensions or rescale all vector
commands. Encoding quality 101 selects lossless encoding; values from 0 through
100 permit JPEG encoding of suitable opaque images at that quality. These
settings do not imply that every draw stays vector or that every embedded image
is re-encoded.

Setting @racket[pdfa?] requests the native backend's XMP metadata, document UUID,
and sRGB output intent. It is not a caller-selected ICC profile or a color-sample
conversion, and the UUID prevents a promise of byte-identical repeated exports.
The option alone is not a PDF/A conformance validation of the completed document.
}

@section[#:tag "skia-pdf-lifecycle"]{Pages and Document State}

@defproc[(document-state [document document?])
          (or/c 'open 'page 'finished 'aborted 'closed)]{
Returns the current lifecycle state. The @racket['open] state means that another
page can begin; @racket['page] means a page is active; @racket['finished] means
completed PDF bytes can be read while the resource remains open. Aborting
releases the native resource and reports @racket['aborted]. Ordinary release
reports @racket['closed]. This query remains usable after release.
}

@defproc[(document-page-count [document document?]) exact-nonnegative-integer?]{
Returns the number of successfully ended pages. An active or failed page is not
included. The stored count remains readable after finishing, aborting, or closing.
It does not imply that an aborted document can be saved.
}

@defproc[(document-begin-page! [document document?]
                                [width (real-in 1/1000 14400)]
                                [height (real-in 1/1000 14400)]) canvas?]{
Begins a page and returns its borrowed canvas. The document must be open and
between pages. Native page-creation failure aborts and releases the document.
The result is not an independently closable canvas.
}

@defproc[(document-end-page! [document document?]) void?]{
Ends the active page, increments the completed-page count, and returns the
document to @racket['open]. It rejects a document with no active page and refuses
to end a protected page callback or an active protected canvas-state/layer scope.
After success, the page's canvas is no longer usable.
}

@defproc[(call-with-document-page [document document?]
                                  [width (real-in 1/1000 14400)]
                                  [height (real-in 1/1000 14400)]
                                  [proc (-> canvas? any)]) any]{
Begins a protected page, calls @racket[proc] with its canvas, ends the page on
normal return, and returns all of the callback's results. Ending this page
manually or finishing the document inside the callback is not permitted.
The canvas must not escape for later use.

An exception, arbitrary raised value, break, or continuation escape before page
completion aborts the whole document, including any earlier pages. Catching the
error outside this helper does not make that document usable again. The helper
uses a continuation barrier; a completed page callback cannot be re-entered to
resume drawing on an expired page.

@racketblock[
(with-skia ([document (make-pdf-document)])
  (define result
    (call-with-document-page document 120 80
      (lambda (canvas)
        (with-skia ([paint (make-paint #:color 'blue)])
          (draw-rect canvas 10 10 100 60 paint))
        'page-complete)))
  (list result (document-state document) (document-page-count document)))
]

This example completes a page but deliberately does not publish a file.

@reference-figure["pdf-document.png"
                  "A raster content preview of the same blue-rectangle drawing commands as the PDF page. It is not a rendering or verification of the exported PDF file."]

This preview makes the page callback's content visible without claiming that a PDF renderer was
used as part of an ordinary Reference build.
}

@defform[(with-document-page
           (canvas-id document-expr width-expr height-expr)
           body ...+)]{
Like @racket[call-with-document-page], with @racket[canvas-id] bound to the page's
canvas in @racket[body]. The body must be nonempty and end with an expression.
It may contain internal definitions and return multiple values. The same page
protection, abort-on-escape, and lifetime rules apply.
}

@defproc[(document-finish! [document document?]) void?]{
Finalizes a document that is open between pages and has at least one completed
page. Every named destination referenced by the document must be defined.
A missing destination is reported before finalization, allowing a manual caller
to add the missing destination on another page and retry.

Success changes the state to @racket['finished] without releasing the document.
Repeating the call on that still-open finished resource is harmless. Finishing
an active page, an empty document, or a released resource is an error. A native
finalization, stream, or output-size failure aborts and releases the document.
The completed byte count must be positive and fit @racket[current-skia-byte-limit].
}

@defproc[(document-abort! [document document?]) void?]{
Discards access to the document's bytes, ends any active page, releases its
native resources, and reports @racket['aborted]. It may be repeated on the owning
thread. Aborting does not remove a file already saved or change a byte string
already returned to the caller.
}

@section{Reading and Publishing PDF}

@subsection{Standard Conversion}

PDF documents participate in @racketmodname[file/convertible] as
@racket['pdf-bytes]. This delegates to @racket[document->pdf-bytes]: the
document must already be finished and still open. Conversion neither finishes,
aborts, nor closes the document, so an open document, active page, aborted
document, released document, or wrong-thread resource reports the same error as
the ordinary reader. Unsupported conversion requests return the exact supplied
default unchanged before any resource check. A supported request never catches
an exporter failure to substitute that default.

@defproc[(document->pdf-bytes [document document?]) (and/c bytes? (not/c immutable?))]{
Returns a fresh mutable copy of a finished document's bytes. It does not finish
the document implicitly and requires the native resource to remain open.
Mutating the returned bytes does not change the document or a later copy.
}

@defproc[(save-pdf [document document?] [filename path-string?]
                   [#:exists exists (or/c 'error 'replace) 'error]) void?]{
Writes an already-finished, still-open document. The destination's parent must
exist. The default refuses an existing file or link; @racket['replace] permits
replacement. The complete byte string is obtained before writing a temporary
file in the destination directory, which is renamed only after writing succeeds.
A failed read, write, or rename does not publish a partial PDF. The helper does
not finish or close the supplied document.

@racketblock[
(with-skia ([document (make-pdf-document #:title "Two pages")]
            [paint (make-paint #:color 'blue)])
  (for ([size '(20 40)])
    (with-document-page (canvas document 120 80)
      (draw-rect canvas 10 10 size size paint)))
  (document-finish! document)
  (save-pdf document "two-pages.pdf" #:exists 'replace))
]

@reference-figure["pdf-two-pages.png"
                  "Two raster content previews of the drawing commands for the PDF's two 120-by-80 pages. Both blue squares begin at (10,10); page 1 is 20 by 20 and page 2 is 40 by 40. This is not a rendering or verification of the exported PDF."]

The paired preview makes the page order and geometry visible without claiming that an ordinary
Reference build has rendered or inspected the written PDF file.
}

@defproc[(call-with-pdf-bytes [proc (-> document? any)]
          [#:title title string? ""]
          [#:author author string? ""]
          [#:subject subject string? ""]
          [#:keywords keywords string? ""]
          [#:creator creator string? "skia-for-racket"]
          [#:producer producer string? "Skia/PDF m119; skia-for-racket"]
          [#:creation-date creation-date (or/c date? #f) #f]
          [#:modified-date modified-date (or/c date? #f) #f]
          [#:raster-dpi raster-dpi (real-in 1 9600) 144]
          [#:encoding-quality encoding-quality (integer-in 0 101) 101]
          [#:pdfa? pdfa? boolean? #f]) (and/c bytes? (not/c immutable?))]{
Creates a document with the settings described at @racket[make-pdf-document],
calls @racket[proc] with the document, discards its results, finishes the document,
and returns its bytes. The callback must complete at least one page and leave
no page active. The document is released on success or escape. Returning bytes
transfers only the detached byte string, not the document resource.
}

@defproc[(call-with-pdf-file [filename path-string?] [proc (-> document? any)]
          [#:exists exists (or/c 'error 'replace) 'error]
          [#:title title string? ""]
          [#:author author string? ""]
          [#:subject subject string? ""]
          [#:keywords keywords string? ""]
          [#:creator creator string? "skia-for-racket"]
          [#:producer producer string? "Skia/PDF m119; skia-for-racket"]
          [#:creation-date creation-date (or/c date? #f) #f]
          [#:modified-date modified-date (or/c date? #f) #f]
          [#:raster-dpi raster-dpi (real-in 1 9600) 144]
          [#:encoding-quality encoding-quality (integer-in 0 101) 101]
          [#:pdfa? pdfa? boolean? #f]) void?]{
Runs @racket[call-with-pdf-bytes] and publishes the completed bytes using the
file rules of @racket[save-pdf]. It resolves and checks the destination before
calling @racket[proc]. Changing @racket[current-directory] in the callback does
not redirect the output. Callback or finalization failure leaves an existing
file untouched rather than replacing it with a partial document.
}
