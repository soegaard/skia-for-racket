#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract file/convertible skia))

@title[#:tag "skia-svg-documents"]{SVG Documents}

@(declare-exporting skia)

An @deftech{SVG document} owns one canvas and an XML output stream. It has a
single viewport rather than a @tech{PDF document}'s sequence of pages. Coordinates
start at the upper-left, with y increasing downward. Width and height are SVG
user units, not a request to allocate an equally sized raster surface.

Finalization completes the XML and invalidates the drawing canvas. The document
must remain open to retrieve the finished bytes. Releasing unfinished storage
is not a way to publish SVG. For shared physical sizes in PDF and SVG, use the
@seclink["skia-output-pages"]{output-page interface}.

@local-table-of-contents[#:style 'immediate-only]

@section[#:tag "skia-svg-output"]{Creating SVG Output}

Use @racket[call-with-svg-file] to write a file, @racket[call-with-svg-string]
to obtain XML text, or @racket[call-with-svg-bytes] to obtain bytes. Each helper
passes a canvas to a drawing callback, finishes the document, and releases it.

@defproc[(call-with-svg-file [filename path-string?]
                            [width (real-in 1/1000 32768)]
                            [height (real-in 1/1000 32768)]
                            [proc (-> canvas? any)]
                            [#:exists exists (or/c 'error 'replace) 'error]
          [#:title title string? ""]
          [#:description description string? ""]
          [#:id-prefix id-prefix string? "skia"]) void?]{
Runs @racket[call-with-svg-bytes] and publishes the completed output according
to @racket[save-svg]'s file rules. The destination is resolved and checked before
the callback, so changing @racket[current-directory] cannot redirect the file.
Callback and finalization failures leave any existing destination untouched.
}

@defproc[(call-with-svg-bytes [width (real-in 1/1000 32768)]
                             [height (real-in 1/1000 32768)]
                             [proc (-> canvas? any)]
          [#:title title string? ""]
          [#:description description string? ""]
          [#:id-prefix id-prefix string? "skia"]) (and/c bytes? (not/c immutable?))]{
Creates an SVG document and calls @racket[proc] with its canvas. After the
callback returns, the helper discards its results, finishes the XML, and returns
the bytes. Settings have the meaning described at @racket[make-svg-document].
The document is released on success or escape; the canvas cannot be retained
for later drawing. Bytes are returned only if both drawing and finalization succeed.
}

@defproc[(call-with-svg-string [width (real-in 1/1000 32768)]
                              [height (real-in 1/1000 32768)]
                              [proc (-> canvas? any)]
          [#:title title string? ""]
          [#:description description string? ""]
          [#:id-prefix id-prefix string? "skia"]) string?]{
Like @racket[call-with-svg-bytes], returning the UTF-8-decoded SVG string.
The callback receives a canvas, not a document.
}

@section{Construction and Lifetime}

For automatic finalization and cleanup, use @racket[call-with-svg-file],
@racket[call-with-svg-string], or @racket[call-with-svg-bytes]. Explicit
construction keeps the document open across separate drawing calls. The caller
must finish it before reading or saving the result, and must release it on
success or failure.

@defproc[(svg-document? [v any/c]) boolean?]{
Returns @racket[#t] for an SVG document and @racket[#f] otherwise.
}

@defproc[(make-svg-document [width (real-in 1/1000 32768)]
                            [height (real-in 1/1000 32768)]
          [#:title title string? ""]
          [#:description description string? ""]
          [#:id-prefix id-prefix string? "skia"]) svg-document?]{
Returns an owned SVG document in the @racket['open] state. No destination file
is opened. The title and description must contain only XML 1.0 characters and
are escaped as metadata, not interpreted as markup. Their escaped UTF-8 size
must fit @racket[current-skia-byte-limit].

The ID prefix has 1 through 64 ASCII characters. It starts with a letter or
underscore; subsequent characters may also be digits, period, or hyphen.
Finalization gives generated resource IDs this prefix and updates their
references. Distinct prefixes help avoid collisions when combining SVGs, but
do not rewrite arbitrary external documents.
}

@defproc[(svg-document-width [document svg-document?]) real?]{
Returns the stored viewport width. This metadata remains readable after closure.
}

@defproc[(svg-document-height [document svg-document?]) real?]{
Returns the stored viewport height, independently of the native resource lifetime.
}

@defproc[(svg-document-state [document svg-document?])
          (or/c 'open 'finishing 'finished 'aborted 'closed)]{
Returns the stored lifecycle state, accounting for release. Drawing is permitted
only in @racket['open]. Finalization passes through @racket['finishing] before
reaching @racket['finished]; a finished document is readable but not drawable.
Aborting reports @racket['aborted]; ordinary release reports @racket['closed].
}

@defproc[(svg-document-canvas [document svg-document?]) canvas?]{
Returns a borrowed canvas for an open, unfinished document. Repeated calls may
produce different wrappers for the same drawing target. Finishing, aborting,
or releasing the document ends the lifetime of all those wrappers.
}

@defproc[(svg-document-finish! [document svg-document?]) void?]{
Completes the SVG XML, normalizes generated IDs and metadata, and finalizes
annotations. The document must be open with no active protected canvas-state
scope. A second call on a still-open finished document is harmless.

All referenced named destinations must be defined. A missing destination is
reported before the canvas is destroyed, so a manual caller can define it and
retry. A failure after native finalization starts aborts and releases the
document. The complete output must fit @racket[current-skia-byte-limit].
Unlike a PDF document, an SVG with no drawing commands may be finished.
}

@defproc[(svg-document-abort! [document svg-document?]) void?]{
Releases the native storage and marks the document aborted. It can be repeated
on the owning thread. It invalidates the canvas and prevents later byte retrieval,
but does not remove previously published files.
}

@section{Reading and Publishing SVG}

@defproc[(svg-document->bytes [document svg-document?])
          (and/c bytes? (not/c immutable?))]{
Returns a fresh mutable copy of the finished SVG. The document must be finished
and still open. The call does not finalize it implicitly. Changes to the copy
do not affect later results.
}

@defproc[(svg-document->string [document svg-document?]) string?]{
Returns the finished SVG as a UTF-8-decoded string, with the same lifecycle and
size requirements as @racket[svg-document->bytes].
}

@defproc[(save-svg [document svg-document?] [filename path-string?]
                   [#:exists exists (or/c 'error 'replace) 'error]) void?]{
Publishes the finished SVG to a file without finishing or closing the document.
The parent directory must exist. The default refuses an existing destination;
@racket['replace] permits replacement. The helper writes a temporary file in the
same directory and renames it only after a complete successful write. Failure
before publication does not replace an existing file with partial XML.

@racketblock[
(with-skia ([document (make-svg-document 120 80 #:title "A blue circle")]
            [paint (make-paint #:color 'blue)])
  (draw-circle (svg-document-canvas document) 60 40 24 paint)
  (svg-document-finish! document)
  (save-svg document "circle.svg" #:exists 'replace))
]

@reference-figure["svg-document.png"
                  "A raster content preview of the same centered blue-circle drawing commands as the SVG example. It is not a rendering or verification of the exported SVG file."]

The preview shows the callback's geometry only; SVG representation and publication remain
separate checks.
}

@subsection{Standard Conversion}

SVG documents participate in @racketmodname[file/convertible] as
@racket['svg-bytes]. It has exactly @racket[svg-document->bytes]'s lifecycle:
the document must have finished successfully and must remain open. Conversion
does not complete, abort, or release it. Unsupported requests return their
supplied default unchanged without checking the document; supported requests
preserve ordinary unfinished, aborted, closed, and wrong-thread errors rather
than replacing them with that default.
