# PDF output

The PDF backend writes drawing operations through Skia's native `SkDocument`.
It is not a screenshot-to-PDF wrapper. A PDF page supplies the same `canvas?`
used by existing paths, paints, images, text, clipping, transforms, and recorded
pictures. Operations that Skia cannot represent directly can be expanded,
rasterized, or handled differently by its PDF backend. Raster/PDF fidelity is
therefore a separate validation question from successful file generation.

## A two-page document

```racket
#lang racket/base
(require "main.rkt") ; use (require skia) when installed as a collection

(call-with-pdf-file
 "example.pdf"
 (lambda (doc)
   (with-document-page (canvas doc 595.28 841.89)
     (with-skia ([paint (make-paint #:color 'blue)]
                 [font (make-font #:size 24)])
       (draw-circle canvas 100 120 40 paint)
       (draw-simple-text canvas "Hello from Skia" 60 220 font paint)))
   (with-document-page (canvas doc 841.89 595.28)
     (with-skia ([paint (make-paint #:color 'red #:style 'stroke #:stroke-width 3)])
       (draw-rect canvas 50 50 300 200 paint))))
 #:title "Example document"
 #:author "Example author"
 #:exists 'replace)
```

Use `call-with-pdf-bytes` with the same drawing procedure to receive a copied
byte string instead. Neither helper exposes a native stream or retains a Racket
port callback. The file helper finalizes first, writes a temporary file in the
destination directory, then renames it. An existing destination survives a
drawing/finalization/write failure before publication. `#:exists 'error` is the
default; the final rename rechecks it to prevent a check-then-overwrite race.
This is not a power-loss durability/fsync guarantee.

## Units and page canvases

Dimensions are PDF points: 72 points per inch. Fractional sizes are supported;
each dimension must be from 0.001 through 14400 points. The initial canvas
coordinate system remains top-left, x right, y down. No special PDF y-flip is
needed in user code. Each page may have a different size. There is no implicit
page margin or content-rectangle translation.

A page canvas is borrowed, not an independently closeable resource. It retains
its document and is valid only until that page ends, the document is aborted,
or the document is released. Starting a later page never revives an old canvas.
`skia-closed?` reports an ended page as closed even while its document stays open.
Closing an owner inside `with-canvas-state` is safe; cleanup does not touch the
expired native canvas. Ending a page while a canvas-state scope is active is an
error.

## Explicit lifecycle

```racket
(with-skia ([doc (make-pdf-document #:title "Explicit lifecycle")])
  (define c (document-begin-page! doc 612 792))
  ;; draw to c
  (document-end-page! doc)
  (document-finish! doc)
  (define pdf (document->pdf-bytes doc))
  (save-pdf doc "explicit.pdf" #:exists 'replace))
```

`document-state` returns `open`, `page`, `finished`, `aborted`, or `closed`.
`document-page-count` counts completed pages. These two Racket-only queries may
be used after release; operations that call native code are thread-confined.

`document-begin-page!` requires an open document between pages. Nested pages are
rejected rather than silently ending the previous page. `document-end-page!`
requires an active page. `document-finish!` requires at least one completed page
and no active page; it is idempotent for a live, finished document.
`document->pdf-bytes` and `save-pdf` require successful explicit finalization.
Each byte read is an independent mutable copy that can outlive the document.

`document-abort!` discards output and releases resources; it is idempotent.
`skia-close!` releases the document, aborting unfinished work rather than relying
on the native destructor to finalize a partial file. Finished documents still
need release, normally through `with-skia`. There is no automatic file output
from a finalizer.

`call-with-document-page` receives a procedure of one canvas argument. It ends
the page on normal return and preserves the procedure's return values. An
exception, arbitrary raised value, break, or continuation escape aborts the
whole document. Manual page-ending is prohibited inside this protected scope.
Continuations cannot reenter expired resource/page scopes.

## Metadata and encoding options

`make-pdf-document`, `call-with-pdf-bytes`, and `call-with-pdf-file` accept:

| Keyword | Default | Meaning |
|---|---|---|
| `#:title`, `#:author`, `#:subject`, `#:keywords` | `""` | NUL-free UTF-8 strings copied into metadata. |
| `#:creator` | `"skia-for-racket"` | Application that authored the document. |
| `#:producer` | `"Skia/PDF m119; skia-for-racket"` | Application/backend that produced the PDF. |
| `#:creation-date`, `#:modified-date` | `#f` | Racket `date?`, or omitted timestamp. |
| `#:raster-dpi` | `144` | Resolution for fallback rasterization, from 1 through 9600. Not a scale factor for page dimensions or ordinary vector geometry. |
| `#:encoding-quality` | `101` | 101 requests lossless image encoding; 0–100 allows native JPEG encoding for opaque images at that quality. |

Dates use their local calendar/clock fields and explicit UTC offset, not the
host's current timezone. Years must be 1–9999, dates must exist, seconds must be
0–59, and UTC offsets must be integral minutes between -23:59 and +23:59.
Subsecond information is not represented by this ABI. The library does not
insert current timestamps automatically or promise binary-identical files.

`current-skia-byte-limit` guards aggregate UTF-8 metadata bytes, finalized PDF
size, and every copied output. It does not cap Skia's intermediate allocations
or aggregate process memory. A vector page does not consume a mandatory
`width*height*4` pixel budget. The backend buffers output in native memory;
very large documents are not streamed directly to a file in this release.

## Scope and limitations

This release generates PDFs; it does not read, edit, concatenate, or render
existing PDF files. It does not expose encryption, forms, links, tagged PDF,
bookmarks, PDF/A certification, per-page color profiles, or a font-subsetting
policy API. PDF/A is disabled. Ordinary font handling and subsetting are left
to the pinned Skia backend; fonts are not bundled with this source distribution.
Shaped text rendering does not guarantee logical reading order or complete
Unicode extraction from every viewer/font combination. Test extraction
separately when it matters.

Full SVG document output is the next output-backend stage. Portability and
packaging work remain deferred.

## Pinned implementation sources

The binding uses SkiaSharp 3.119.1's Skia submodule commit
`40f75dc0051d141913c07c20d4c19590c7da0cb7`:

- [C document shim](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/c/sk_document.cpp)
- [Native document state/lifetime](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/core/SkDocument.cpp)
- [Metadata conversion copies strings and dates](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/src/c/sk_types_priv.h#L311-L343)
- [PDF metadata, points, raster DPI, encoding quality](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/docs/SkPDFDocument.h)
- [C ABI structs](https://github.com/mono/skia/blob/40f75dc0051d141913c07c20d4c19590c7da0cb7/include/c/sk_types.h)
- [Skia PDF backend overview and limitations](https://skia.org/docs/user/sample/pdf/)

The overview is not a version-pinned conformance table. Probe the installed m119
backend rather than treating that page as a guarantee for every effect.
