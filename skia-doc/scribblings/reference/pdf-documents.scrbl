#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract file/convertible skia))

@title[#:tag "skia-pdf-documents"]{PDF Documents}

@(declare-exporting skia)

A @deftech{PDF document} owns an output stream and at most one active page.
A page supplies a @tech{borrowed canvas}. Ending the page invalidates every
canvas wrapper for it; beginning another page does not revive an old canvas.
Finishing, releasing, and writing the document are separate operations.

Page dimensions are in points, with 72 points per inch. Skia drawing coordinates
start at the upper-left and increase downward in y; callers do not need to invert
the coordinate system to compensate for the PDF file's internal conventions.
Dimensions need not be integer pixel counts, and beginning a vector page does
not charge a complete RGBA image against the byte limit.

@local-table-of-contents[#:style 'immediate-only]

@section[#:tag "skia-pdf-output"]{Creating PDF Output}

Use @racket[call-with-pdf-file] to write a file or @racket[call-with-pdf-bytes]
to obtain bytes. Both manage document creation, finalization, and release.
Their callbacks add pages with @racket[with-pdf-page] or
@racket[call-with-pdf-page].

@defproc[(call-with-pdf-file [filename path-string?] [proc (-> pdf-document? any)]
          [#:exists exists (or/c 'error 'replace) 'error]
          [#:title title string? ""]
          [#:author author string? ""]
          [#:subject subject string? ""]
          [#:keywords keywords string? ""]
          [#:creator creator string? "skia-for-racket"]
          [#:producer producer (or/c string? #f) #f]
          [#:creation-date creation-date (or/c date? #f) #f]
          [#:modified-date modified-date (or/c date? #f) #f]
          [#:raster-dpi raster-dpi (real-in 1 9600) 144]
          [#:encoding-quality encoding-quality (integer-in 0 101) 101]
          [#:pdfa? pdfa? boolean? #f]) void?]{
Runs @racket[call-with-pdf-bytes] and saves the completed bytes using the
file rules of @racket[save-pdf]. It resolves and checks the destination before
calling @racket[proc]. Changing @racket[current-directory] in the callback does
not redirect the output. Callback or finalization failure leaves an existing
file untouched rather than replacing it with a partial document.
}

@defproc[(call-with-pdf-bytes [proc (-> pdf-document? any)]
          [#:title title string? ""]
          [#:author author string? ""]
          [#:subject subject string? ""]
          [#:keywords keywords string? ""]
          [#:creator creator string? "skia-for-racket"]
          [#:producer producer (or/c string? #f) #f]
          [#:creation-date creation-date (or/c date? #f) #f]
          [#:modified-date modified-date (or/c date? #f) #f]
          [#:raster-dpi raster-dpi (real-in 1 9600) 144]
          [#:encoding-quality encoding-quality (integer-in 0 101) 101]
          [#:pdfa? pdfa? boolean? #f]) (and/c bytes? (not/c immutable?))]{
Creates a document with the settings described at @racket[make-pdf-document]
and calls @racket[proc] with it. After the callback returns, the helper discards
its results, finishes the document, and returns the document's bytes.
The callback must complete at least one page and leave
no page active. The document is released on success or escape.
}

@section[#:tag "skia-pdf-page-scopes"]{Drawing PDF Pages}

@defproc[(call-with-pdf-page [document pdf-document?]
                                  [width (real-in 1/1000 14400)]
                                  [height (real-in 1/1000 14400)]
                                  [proc (-> canvas? any)]) any]{
Calls @racket[proc] to draw one PDF page and returns all of the callback's results.

The callback receives the new page's canvas. The page ends automatically when
the callback returns normally. Ending this page manually or finishing the
document inside the callback is not permitted.
The canvas must not escape for later use.

If the callback raises any value, receives a break, or escapes through a
continuation before the page is complete, the whole document is aborted.
This includes any earlier pages. Catching the error outside this helper does
not make the document usable again. The helper
uses a continuation barrier; a completed page callback cannot be re-entered to
resume drawing on an expired page.

@racketblock[
(with-skia ([document (make-pdf-document)])
  (define result
    (call-with-pdf-page document 120 80
      (lambda (canvas)
        (with-skia ([paint (make-paint #:color 'blue)])
          (draw-rect canvas 10 10 100 60 paint))
        'page-complete)))
  (list result (pdf-document-state document) (pdf-document-page-count document)))
]

This example completes a page but deliberately does not save a file.

@reference-figure["pdf-document.png"
                  "Raster preview of the PDF page's drawing commands: a blue rectangle inset from the page edges."]
}

@defform[(with-pdf-page
           (canvas-id document-expr width-expr height-expr)
           body ...+)]{
Like @racket[call-with-pdf-page], with @racket[canvas-id] bound to the page's
canvas in @racket[body]. The body must be nonempty and end with an expression.
It may contain internal definitions and return multiple values. The same page
protection, abort-on-escape, and lifetime rules apply.
}

@section[#:tag "skia-pdf-settings"]{Explicit Document Construction}

For automatic document cleanup and finalization, use @racket[call-with-pdf-file]
or @racket[call-with-pdf-bytes]. Explicit construction gives control over when
to add pages, finish the document, and save its bytes. The caller must release
the document, including when an operation fails.

@defproc[(pdf-document? [v any/c]) boolean?]{
Returns @racket[#t] for a PDF document, including a closed one, and @racket[#f] otherwise.
An @tech{SVG document} is a separate kind of resource.
}

@defproc[(make-pdf-document
          [#:title title string? ""]
          [#:author author string? ""]
          [#:subject subject string? ""]
          [#:keywords keywords string? ""]
          [#:creator creator string? "skia-for-racket"]
          [#:producer producer (or/c string? #f) #f]
          [#:creation-date creation-date (or/c date? #f) #f]
          [#:modified-date modified-date (or/c date? #f) #f]
          [#:raster-dpi raster-dpi (real-in 1 9600) 144]
          [#:encoding-quality encoding-quality (integer-in 0 101) 101]
          [#:pdfa? pdfa? boolean? #f]) pdf-document?]{
Returns an owned document in the @racket['open] state with no completed pages.
No file is opened. Native construction failure raises an exception.

Metadata strings must not contain NUL; their combined UTF-8 size must fit
@racket[current-skia-byte-limit]. When a date is @racket[#f], the corresponding
timestamp is omitted from the PDF metadata. The library does not insert the
current time. A supplied date must have a valid calendar date in years 1 through
9999 and valid time components, without leap seconds. Its weekday
must be from 0 through 6. Its UTC offset must be a whole number of minutes,
between -86340 and 86340 seconds.
The default producer, @racket[#f], writes a string identifying the loaded Skia
version and @tt{skia-for-racket}, such as @tt{Skia/PDF 119.0; skia-for-racket}.
It is determined when the document is created, not when the module is imported.
Supply a string to override it. The generated producer is included in the
metadata byte limit. The creator defaults to @tt{skia-for-racket}.

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

Use @racket[with-pdf-page] or @racket[call-with-pdf-page] to end a page
automatically and abort the document if drawing fails. Manual page operations
leave page completion to the caller. A page must end before another begins or
the document is finished.

@defproc[(pdf-document-state [document pdf-document?])
          (or/c 'open 'page 'finished 'aborted 'closed)]{
Returns the current lifecycle state. The @racket['open] state means that another
page can begin; @racket['page] means a page is active; @racket['finished] means
completed PDF bytes can be read while the resource remains open. Aborting
releases the native resource and reports @racket['aborted]. Ordinary release
reports @racket['closed]. This query remains usable after release.
}

@defproc[(pdf-document-page-count [document pdf-document?]) exact-nonnegative-integer?]{
Returns the number of successfully ended pages. An active or failed page is not
included. The stored count remains readable after finishing, aborting, or closing.
It does not imply that an aborted document can be saved.
}

@defproc[(pdf-document-begin-page! [document pdf-document?]
                                [width (real-in 1/1000 14400)]
                                [height (real-in 1/1000 14400)]) canvas?]{
Begins a page and returns its borrowed canvas. The document must be open and
between pages. Native page-creation failure aborts and releases the document.
The result is not an independently closable canvas.
}

@defproc[(pdf-document-end-page! [document pdf-document?]) void?]{
Ends the active page, increments the completed-page count, and returns the
document to @racket['open]. It rejects a document with no active page and refuses
to end a protected page callback or an active protected canvas-state/layer scope.
After success, the page's canvas is no longer usable.
}

@defproc[(pdf-document-finish! [document pdf-document?]) void?]{
Finalizes a document that is open between pages and has at least one completed
page. Every @tech{named destination} referenced by the document must be defined.
A missing destination is reported before finalization, allowing a manual caller
to add the missing destination on another page and retry.

Success changes the state to @racket['finished] without releasing the document.
Repeating the call on that still-open finished resource is harmless. Finishing
an active page, an empty document, or a released resource is an error. A native
finalization, stream, or output-size failure aborts and releases the document.
The completed byte count must be positive and fit @racket[current-skia-byte-limit].
}

@defproc[(pdf-document-abort! [document pdf-document?]) void?]{
Discards access to the document's bytes, ends any active page, releases its
native resources, and reports @racket['aborted]. It may be repeated on the owning
thread. Aborting does not remove a file already saved or change a byte string
already returned to the caller.
}

@section{Reading and Saving PDF}

@defproc[(pdf-document->bytes [document pdf-document?]) (and/c bytes? (not/c immutable?))]{
Returns a fresh mutable copy of a finished document's bytes. It does not finish
the document implicitly and requires the native resource to remain open.
Mutating the returned bytes does not change the document or a later copy.
}

@defproc[(save-pdf [document pdf-document?] [filename path-string?]
                   [#:exists exists (or/c 'error 'replace) 'error]) void?]{
Writes an already-finished, still-open document. The destination's parent must
exist. The default refuses an existing file or link; @racket['replace] permits
replacement. The complete byte string is obtained before writing begins.
It is written to a temporary file in the destination directory. That file is
renamed only after writing succeeds.
A failed read, write, or rename does not leave a partial PDF at the destination. The helper does
not finish or close the supplied document.

@racketblock[
(with-skia ([document (make-pdf-document #:title "Two pages")]
            [paint (make-paint #:color 'blue)])
  (for ([size '(20 40)])
    (with-pdf-page (canvas document 120 80)
      (draw-rect canvas 10 10 size size paint)))
  (pdf-document-finish! document)
  (save-pdf document "two-pages.pdf" #:exists 'replace))
]

@reference-figure["pdf-two-pages.png"
                  "Raster previews of the two pages' drawing commands. Both blue squares begin at (10,10); the first is 20 by 20 and the second is 40 by 40."]
}

For conversion through @racketmodname[file/convertible], a PDF document accepts
@racket['pdf-bytes] and must already be finished and still open. Conversion does
not finish or close it. See @secref["skia-standard-conversion"] for the shared
conversion rules.
