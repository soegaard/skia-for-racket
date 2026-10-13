#lang scribble/manual

@(require (for-label racket/base racket/contract skia))

@title[#:tag "skia-text-blobs"]{Text Blobs}

@(declare-exporting skia)

A @deftech{text blob} is an owned native object containing glyphs and their
placement. It retains the font information needed to draw them. A blob does
not contain a paint, perform paragraph wrapping, or turn glyph IDs into a
portable character string.

The constructor below creates a single positioned run. A blob can be drawn
repeatedly with different paints or canvas transforms. Native operations require
open resources and their usual thread or GPU-context conditions.

@defproc[(text-blob? [v any/c]) boolean?]{
Returns @racket[#t] for a text-blob resource and @racket[#f] otherwise. Closure does not change
the result.
}

@defproc[(make-positioned-text-blob [font font?] [glyphs (or/c (listof (integer-in 0 #xffff))
          (vectorof (integer-in 0 #xffff)))]
                [positions
                 (or/c (listof (or/c (list/c real? real?) (vector/c real? real?)))
                       (vectorof (or/c (list/c real? real?) (vector/c real? real?))))]) text-blob?]{
Creates an owned text blob from nonempty glyph and position sequences of
equal length. Each position contains drawing scalars relative to the blob's
origin. Glyph IDs belong to the font's typeface; this is not a character-mapping
or shaping operation. The input payload is bounded by
@racket[current-skia-byte-limit].

The blob copies glyphs and positions and captures font settings. Later mutation
of an input vector or font, and closure of the original font, do not change the
blob. The paint and canvas origin are selected separately when drawing.

@racketblock[
(with-skia ([font (make-font #:size 24)]
            [blob
             (make-positioned-text-blob
              font (font-text->glyphs font "AB") '((0 0) (40 0)))])
  (skia-close! font)
  (call-with-values (lambda () (text-blob-bounds blob)) list))
]
}

@defproc[(text-blob-bounds [blob text-blob?]) (values real? real? real? real?)]{
Returns the native blob bounds as x, y, width, and height, relative to
its stored origin. The bounds can be conservative and include no later canvas
transform, paint stroke, or image filter. They are not the blob's advance.
}

@defproc[(text-blob-unique-id [blob text-blob?]) exact-integer?]{
Returns the native blob identifier. It identifies the native object, not
its text content, and is not a persistent identifier across program runs.
}

@defproc[(draw-text-blob [canvas canvas?] [blob text-blob?] [x real?] [y real?] [paint paint?])
          void?]{
Draws the blob translated by the drawing scalars @racket[x] and @racket[y].
The canvas transform, clip, and supplied paint apply. Reusing a blob does not
reshape it or consult the original font wrapper. The operation leaves the blob
open. Outline output uses @racket[text-blob->path].
}

@defproc[(text-blob->path [blob text-blob?]) skia-path?]{
Returns an owned path of positioned monochrome glyph outlines without
baking in a paint or canvas transform. The path is independent of the blob's
lifetime.

For a blob made by @racket[make-positioned-text-blob], glyphs without outlines
are omitted. Retained multi-run blobs use a stricter conversion: a glyph with
visible bounds but no monochrome outline raises an exception instead of being
silently dropped. This operation is not a general vectorization of color or
bitmap glyphs.
}
