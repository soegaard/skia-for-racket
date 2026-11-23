#lang scribble/manual

@(require (for-label racket/base racket/contract file/convertible skia skia/output))

@title[#:tag "skia-standard-conversion"]{Standard Conversion}

Use @racketmodname[file/convertible] when another Racket library, such as
Scribble, requests an encoded representation of a Skia value. Call an encoder
or exporter directly when you need to choose its options.

The following conversions use the listed functions with their default options:

@tabular[#:sep @hspace[2]
 (list
  (list @bold{Value} @bold{Request} @bold{Operation})
  (list @elem{@tech{Image}} @racket['png-bytes] @racket[image->png-bytes])
  (list @elem{@tech{Surface}} @racket['png-bytes] @racket[surface->png-bytes])
  (list @elem{@tech{PDF document}} @racket['pdf-bytes] @racket[pdf-document->bytes])
  (list @elem{@tech{SVG document}} @racket['svg-bytes] @racket[svg-document->bytes])
  (list @elem{@tech{Output page}} @racket['png-bytes]
        @elem{@racket[output-page->image], then @racket[image->png-bytes]})
  (list @elem{@tech{Output page}} @racket['pdf-bytes] @racket[(output->bytes page 'pdf)])
  (list @elem{@tech{Output page}} @racket['svg-bytes] @racket[(output->bytes page 'svg)]))]

A supported request has the same resource requirements, size limits, and error
behavior as the listed operation. Errors propagate even when a default value
is supplied to @racket[convert]. An unsupported request returns that exact
default unchanged, without checking the resource, decoding pixels, or invoking
a page callback. If the default is a procedure, it is returned, not called.

@racketblock[
(require file/convertible skia)
(with-skia ([image (rgba-bytes->image 1 1 (bytes 255 0 0 255))])
  (convert image 'png-bytes))
]

@section[#:tag "skia-conversion-resources"]{Resource Requirements}

Conversion does not close supplied resources. PDF and SVG documents must
already be finished and still open; conversion does not finish or abort them.
Their ordinary state and owning-thread restrictions apply.

PNG conversion requires an open CPU-compatible image or surface and uses the
encoder's default color and alpha behavior. GPU images and surfaces also
satisfy @racket[convertible?], but requesting their PNG bytes raises an exception.
First obtain a CPU image through an explicit @tech{GPU readback} operation.
Conversion does not transfer GPU pixels implicitly.

@section[#:tag "skia-conversion-output-pages"]{Output-Page Conversion}

Each supported conversion of an output page invokes its drawing callback once.
Converting the same page again invokes the callback again; the page is not a
recording or a cache. Resources captured by the callback must remain usable
until conversion occurs, including when Scribble requests a format later.
Captured GPU resources keep their ordinary explicit-transfer requirements.

PNG conversion rasterizes at 96 DPI. Pixel dimensions use
@racket[output-page->image]'s ceiling rule, and the temporary image is released
after encoding, including on failure or escape. PDF and SVG conversion use
@racket[output->bytes]'s defaults, including native text mode for PDF and
outline text mode for SVG.
