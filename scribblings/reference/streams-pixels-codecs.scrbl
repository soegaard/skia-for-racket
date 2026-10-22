#lang scribble/manual

@(require (for-label racket/base skia))

@title[#:tag "skia-reference-streams-pixels-codecs" #:style 'toc]{Streams, Pixels, and Codecs}

Use these interfaces when you need control over image input, decoded pixels,
or encoded output. For ordinary image loading and saving, the constructors in
@secref["skia-image-loading"] and encoders in @secref["skia-encoding"] are simpler.
Choose an interface according to the work you need to do:

@itemlist[
 @item{Inspect image metadata, select animation frames, or choose orientation
   and color-space options with a @tech{codec}.}
 @item{Process a complete encoded source a few pixel rows at a time with
   @seclink["skia-scanline-codecs"]{scanline decoding}.}
 @item{Supply encoded bytes in successive chunks and control when decoding
   advances with @seclink["skia-incremental-codecs"]{incremental decoding}.}
 @item{Inspect or modify pixels with a @tech{raster buffer} and scoped
   @tech{pixmap} views. Use a @tech{pixel description} to choose their storage format.}
 @item{Connect Racket ports with @seclink["skia-buffered-ports"]{buffered adapters}
   or @seclink["skia-live-streams"]{live port operations}. Use a
   @tech{native stream} when you need a Skia byte source or destination with
   its own cursor and lifetime.}]

Scanline decoding controls how many decoded rows you receive at once;
incremental decoding controls how encoded input becomes available. Neither
promises constant memory. Buffered input stores the complete encoded source
before constructing a resource, while live input reads from the port during
native work. Their limits and cleanup rules are described in the linked sections.

The decoding interfaces also differ in their defaults. In the table, the
@italic{codec's space} means the color space Skia reports for the encoded input,
without requesting conversion to a different destination space.

@tabular[#:sep @hspace[2]
 (list
  (list @bold{Interface} @bold{Orientation} @bold{Alpha} @bold{Color space})
  (list @seclink["skia-image-loading"]{File, bytes, buffered port}
        "Applied" "Premultiplied or opaque" "Codec's space")
  (list @racket[image-from-port] "Applied by default" "Premultiplied" "Codec's space")
  (list @racket[codec->image] "Applied by default" "Premultiplied" "Codec's space")
  (list @seclink["skia-scanline-codecs"]{Scanline decoding}
        "Not applied" "Unpremultiplied" "sRGB")
  (list @seclink["skia-incremental-codecs"]{Incremental decoding}
        "Not applied" "Unpremultiplied" "sRGB"))]

Applying @tech{encoded orientation} arranges pixels for display and can exchange
the width and height. @racket[image-from-port] and @racket[codec->image] allow
this to be disabled; scanline and incremental output always use encoded
coordinates. The @racket[image-frame-from-file] and @racket[image-frame-from-bytes]
conveniences follow @racket[codec->image]. See @secref["skia-pixel-descriptions"]
for alpha representations and the different forms of color-space arguments.

The file, byte-string, and buffered-port image constructors can defer pixel
decoding until drawing or readback. In contrast, @racket[image-from-port] and
@racket[codec->image] finish decoding the requested image before returning.
A scanline read returns one batch, possibly shorter than requested. An
incremental step returns progress, which must be checked before treating a
pixel snapshot as a complete image.

@local-table-of-contents[]

@include-section["streams.scrbl"]
@include-section["live-streams.scrbl"]
@include-section["pixel-descriptions.scrbl"]
@include-section["raster-buffers.scrbl"]
@include-section["codecs.scrbl"]
@include-section["scanline-codecs.scrbl"]
@include-section["incremental-codecs.scrbl"]
