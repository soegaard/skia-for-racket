#lang scribble/manual

@(require (for-label racket/base racket/class file/convertible
                     (prefix-in draw: racket/draw) skia skia/dc))

@title[#:tag "skia-reference-racket-integration" #:style 'toc]{Racket Integration}

Use these libraries to combine Skia with Racket libraries that consume encoded
images, picts, Racket Draw values, or drawing contexts. Choose an interface
according to what the receiving library needs:

@tabular[#:sep @hspace[2]
 (list
  (list @bold{Task} @bold{Interface})
  (list @elem{Supply encoded bytes through Racket's conversion protocol}
        @elem{@racketmodname[file/convertible]; see @secref["skia-standard-conversion"]})
  (list @elem{Compose Skia artwork with other picts}
        @racketmodname[skia/pict])
  (list @elem{Copy a bitmap, color, or path between Skia and Racket Draw}
        @racketmodname[skia/racket-draw])
  (list @elem{Keep a CPU drawing context for repeated drawing}
        @racketmodname[skia/dc])
  (list @elem{Send Racket Draw commands to PDF, SVG, or a CPU canvas}
        @racketmodname[skia/dc-output])
  (list @elem{Send Racket Draw commands to a GPU frame or surface}
        @racketmodname[skia/gpu-dc]))]

The value conversions copy existing content. The drawing-context adapters
instead let code written for Racket's @racket[draw:dc<%>] interface draw with
Skia. They complement the native Skia canvas API; they do not replace it.

@para{@bold{Drawing-context lifetimes}}

Who creates a drawing context determines who closes it:

@itemlist[
 @item{A standalone @racket[skia-dc%] belongs to its caller. Close it with
       @method[skia-dc% close] when finished, including when drawing raises an
       exception. Use its @tt{close} method, not @racket[skia-close!].}
 @item{An output or GPU adapter supplies a temporary DC to a callback. The
       adapter closes it when the callback returns, raises an exception, or
       escapes. Saving the DC for later use does not extend its lifetime.}
 @item{A GUI canvas manages its own DC. Close the widget rather than closing
       that DC directly; see @secref["skia-gui-cleanup"].}]

The @tt{snapshot} method on a raster or GPU DC returns a separate Skia image.
It remains usable after the DC closes and must itself be closed, for example
with @racket[with-skia].

@para{@bold{Smoothing and compatibility}}

A standalone @racket[skia-dc%] starts with @racket['unsmoothed] drawing. The
output, GPU, and GUI drawing contexts start with @racket['smoothed] drawing.
Set smoothing explicitly when the same drawing code should use the same mode
across these interfaces.

The adapters support a documented subset of @racket[draw:dc<%>]. See
@racket[skia-dc-compatibility] for supported methods and their restrictions;
using the same interface does not guarantee identical pixels or text metrics
across drawing implementations.

@local-table-of-contents[]

@include-section["standard-conversion.scrbl"]
@include-section["pict-bridge.scrbl"]
@include-section["racket-draw.scrbl"]
@include-section["racket-dc.scrbl"]
@include-section["dc-output.scrbl"]
@include-section["gpu-dc.scrbl"]
