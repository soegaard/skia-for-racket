#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia skia/text-blobs))

@title[#:tag "skia-text-blobs"]{Text Blobs}

@(declare-exporting skia)

Use a text blob when glyph placement is already decided and you want to draw it
repeatedly, possibly with different paints or @tech{canvas transforms}. Convert
a @tech{shaped run} with @racket[shaped-run->text-blob], supply positions directly
with @racket[make-positioned-text-blob], or use a @tech{text-blob builder} to
combine runs with different fonts or placement.

A @deftech{text blob} is an @tech{owned resource} containing glyphs, their
placement, and the @tech{font} settings needed to draw them. Unlike a shaped run,
a completed blob does not require the original shaper or font to remain open.
It does not contain a @tech{paint}, reshape text, or perform paragraph wrapping.
Use @tech{text layout} to choose line breaks and alignment before drawing.

Native operations require open resources on their owning thread. Drawing also
follows the canvas's and paint's GPU-context conditions when applicable.

@local-table-of-contents[#:style 'immediate-only]

@section{Creating and Drawing Blobs}

All blob constructors return @racket[#f] when there are no glyphs to store.
They still validate their inputs and required resources. An empty append adds
no run to a builder, and finishing an empty builder returns @racket[#f] and
closes it. These cases do not create an empty drawable blob.

@defproc[(text-blob? [v any/c]) boolean?]{
Returns @racket[#t] for a text-blob resource and @racket[#f] otherwise. Closure does not change
the result.
}

@defproc[(make-positioned-text-blob [font font?] [glyphs (or/c (listof (integer-in 0 #xffff))
          (vectorof (integer-in 0 #xffff)))]
                [positions
                 (or/c (listof (or/c (list/c real? real?) (vector/c real? real?)))
                       (vectorof (or/c (list/c real? real?) (vector/c real? real?))))]) (or/c text-blob? #f)]{
Creates a text blob from the supplied glyphs and positions.

The glyph and position lists or vectors must have equal lengths.
Empty inputs return @racket[#f] after validating the font.
Positions are relative to the blob's origin. Glyph IDs belong to the font's
typeface; this is not a character-mapping or @tech{shaping} operation.
The size of the copied input data is bounded by
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
  (vector->list (text-blob-bounds blob)))
]
}

@defproc[(text-blob-bounds [blob text-blob?]) (and/c (vector/c real? real? real? real?) immutable?)]{
Returns the native blob bounds as an immutable @racket[#(x y width height)] vector, relative to
its stored origin. The bounds can be conservative and include no later canvas
transform, paint stroke, or @tech{image filter}. They are not the blob's @tech{advance}.
}

@defproc[(text-blob-unique-id [blob text-blob?]) exact-integer?]{
Returns the native blob identifier. It identifies the native object, not
its text content, and is not a persistent identifier across program runs.
}

@defproc[(draw-text-blob [canvas canvas?] [blob text-blob?] [x real?] [y real?] [paint paint?])
          void?]{
Draws the blob translated by @racket[x] and @racket[y].
The canvas transform, clip, and supplied paint apply. Reusing a blob does not
reshape it or consult the original font wrapper. The operation leaves the blob
open. Outline output uses @racket[text-blob->path].

@racketblock[
(with-skia ([font (make-font #:size 30)]
            [blob
             (make-positioned-text-blob
              font (font-text->glyphs font "AB") '((0 0) (55 0)))]
            [paint (make-paint #:color 'black)]
            [surface (make-surface 180 80 #:background 'white)])
  (draw-text-blob (surface-canvas surface) blob 20 55 paint))
]

@reference-figure["text-blob.png"
                  "Two black glyphs from a positioned text blob, with extra horizontal spacing between A and B."]
}

@section[#:tag "skia-text-blob-builders"]{Building Multiple Runs}

@defmodule[skia/text-blobs #:no-declare]
@(declare-exporting skia skia/text-blobs #:use-sources (skia/text-blobs))

Use a builder to combine runs with different fonts, sizes, or positioning modes,
or to append runs incrementally before creating one drawable blob. For one
nonempty positioned run, @racket[make-positioned-text-blob] is simpler.

A @deftech{text-blob builder} collects glyph runs into one text blob. Each run
has a positioning mode and captures its font's settings when appended. Different
runs may use different fonts. Successful appends copy their inputs; later input
mutation, font mutation, or closure of the original font does not change them.

Finishing closes the builder; it cannot be reused. A finished blob is independent
of the builder's lifetime and can be used with @racket[draw-text-blob], @racket[text-blob-bounds],
and @racket[text-blob->path]. Closing
an unfinished builder discards its runs and releases the resources it owns.
A builder is not a reusable accumulator, and finishing does not reset it.

@defproc[(text-blob-builder? [v any/c]) boolean?]{
Returns @racket[#t] for a text-blob builder and @racket[#f] otherwise. The
predicate remains true after the builder has been finished or closed.
}

@defproc[(make-text-blob-builder) text-blob-builder?]{
Creates an open, owned builder with no runs. Native allocation failure raises
an exception. The builder follows the ordinary resource lifetime rules.

@racketblock[
(with-skia ([builder (make-text-blob-builder)])
  (define result (text-blob-builder-finish! builder))
  (list result (skia-closed? builder)))
]

The result is @racket['(#f #t)]: an empty builder produces no blob, but is
still closed.
}

@defproc[(text-blob-builder-run-count [builder text-blob-builder?])
          exact-nonnegative-integer?]{
Returns the number of nonempty runs successfully appended to an open builder.
Appending an empty glyph list or vector does not increase the count. This counts
logical appends, not any merging of adjacent runs performed by native storage.
}

@subsection[#:tag "skia-text-run-inputs"]{Run Inputs and Failure Behavior}

Glyph inputs are lists or vectors of unsigned 16-bit glyph IDs. Each ID must
also be less than the glyph count of the selected font's typeface; zero is
permitted. These operations do not map characters, shape text, or select a
fallback typeface. Position and transform lists or vectors must match the glyph
count. A point may be a two-element list or vector.

Input counts must fit a signed 32-bit integer. Copied inputs and accumulated
run data are checked against @racket[current-skia-byte-limit]. The limit bounds
the sizes counted for copied data and bookkeeping, not all native font caches
or allocator overhead. Exceeding a limit raises an exception.

An empty append still validates its options and resources, but creates no run
and captures no font. Invalid arguments detected before native run allocation
leave the builder available. A failure after native run allocation begins
closes the builder because the partial append cannot be rolled back. After an
append exception, check @racket[skia-closed?] before attempting to reuse it.
Finishing a closed builder, or using one from the wrong thread, raises an
exception rather than producing another blob.

@subsection[#:tag "skia-text-run-metadata"]{Optional Text and Clusters}

Supply text and cluster metadata when a glyph run must preserve its association
with the original text. Glyph IDs alone do not recover that text. The
associations can later be inspected through @racket[text-blob-runs].

The four glyph-based append functions accept @racket[#:text] and
@racket[#:clusters]. Both must be @racket[#f], or both must be supplied. Text
may be a Racket string or a byte string containing valid UTF-8; malformed byte
sequences are rejected. Supplied text is stored as an immutable UTF-8 byte string.

The @tech{cluster offset} list or vector contains one exact nonnegative integer
per glyph. Each integer is a byte offset inside the supplied UTF-8 text, at the
beginning of a Unicode scalar value. It is not a Racket character index or necessarily a
grapheme boundary. Repeated and descending offsets are permitted, so clusters
can describe ligatures, combining marks, and right-to-left glyph order.

Nonempty glyphs require nonempty text when metadata is supplied. An empty run
can have empty text and an empty cluster list or vector, but cannot store nonempty
text that would otherwise be discarded. Supplying metadata does not reshape,
reorder, or reposition glyphs. The caller is responsible for making the text,
glyphs, and cluster associations agree; the library checks their representation
and ranges, not whether the supplied glyphs and cluster offsets actually
correspond to the text.

@subsection{Appending Runs}

@defproc[(text-blob-builder-add-run!
          [builder text-blob-builder?] [font font?]
          [glyphs (or/c (listof (integer-in 0 #xffff))
                        (vectorof (integer-in 0 #xffff)))]
          [#:origin origin (or/c (list/c real? real?) (vector/c real? real?)) '(0 0)]
          [#:text text (or/c string? bytes? #f) #f]
          [#:clusters clusters (or/c (listof exact-nonnegative-integer?)
                                     (vectorof exact-nonnegative-integer?) #f) #f]) void?]{
Appends a default-positioned run. Glyph positions begin at @racket[origin] in
blob coordinates and follow the font's unshaped advances. They are not shaped
positions or inter-glyph kerning adjustments. Use
@racket[text-blob-builder-add-shaped-run!] to add an already shaped result to the blob.
Input, lifetime, and metadata rules are described in
@secref["skia-text-run-inputs"] and @secref["skia-text-run-metadata"].

@racketblock[
(with-skia ([font (make-font #:size 24)]
            [builder (make-text-blob-builder)])
  (text-blob-builder-add-run! builder font (font-text->glyphs font "AB")
                            #:origin '(10 30))
  (font-set-size! font 36)
  (text-blob-builder-add-run! builder font (font-text->glyphs font "CD")
                            #:origin '(10 70))
  (with-skia ([blob (text-blob-builder-finish! builder)]
              [first-font (text-blob-run-font blob 0)]
              [second-font (text-blob-run-font blob 1)])
    (list (font-size first-font) (font-size second-font))))
]

The two captured font sizes are 24.0 and 36.0, even though both appends used the
same mutable font.

@racketblock[
(with-skia ([surface (make-surface 260 100 #:background 'white)]
            [font (make-font #:size 24)]
            [builder (make-text-blob-builder)]
            [paint (make-paint #:color "#20344E")])
  (text-blob-builder-add-run! builder font (font-text->glyphs font "small")
                             #:origin '(15 38))
  (font-set-size! font 42)
  (text-blob-builder-add-run! builder font (font-text->glyphs font " BIG")
                             #:origin '(105 68))
  (with-skia ([blob (text-blob-builder-finish! builder)])
    (draw-text-blob (surface-canvas surface) blob 0 0 paint)))
]

@reference-figure["multi-run-text-blob.png"
                  "One text blob containing a smaller word followed by a much larger BIG run."]


@racketblock[
(with-skia ([surface (make-surface 280 120 #:background 'white)]
            [font (make-font #:size 28)]
            [builder (make-text-blob-builder)]
            [paint (make-paint #:color "#20344E")])
  (text-blob-builder-add-run! builder font (font-text->glyphs font "TOP")
                             #:origin '(20 38))
  (text-blob-builder-add-run! builder font (font-text->glyphs font "BOTTOM")
                             #:origin '(95 92))
  (with-skia ([blob (text-blob-builder-finish! builder)])
    (draw-text-blob (surface-canvas surface) blob 0 0 paint)))
]
@reference-figure["blob-run-origins-stage8.png"
                  "Two text runs in one blob use independent origins, placing TOP high on the left and BOTTOM lower on the right."]
}

@defproc[(text-blob-builder-add-horizontal-run!
          [builder text-blob-builder?] [font font?]
          [glyphs (or/c (listof (integer-in 0 #xffff))
                        (vectorof (integer-in 0 #xffff)))]
          [xs (or/c (listof real?) (vectorof real?))]
          [#:y y real? 0]
          [#:text text (or/c string? bytes? #f) #f]
          [#:clusters clusters (or/c (listof exact-nonnegative-integer?)
                                     (vectorof exact-nonnegative-integer?) #f) #f]) void?]{
Appends a run with one absolute x coordinate per glyph and a shared @tech{baseline}
coordinate @racket[y], all relative to the blob's origin. The x values are not
@tech{advances} to be accumulated. Their order is preserved; no sorting or @tech{shaping}
is performed. The shared run-input and metadata rules apply.

@racketblock[
(with-skia ([surface (make-surface 240 90 #:background 'white)]
            [font (make-font #:size 32)] [builder (make-text-blob-builder)]
            [paint (make-paint #:color "#20344E")])
  (define glyphs (font-text->glyphs font "ABC"))
  (text-blob-builder-add-horizontal-run! builder font glyphs '(0 55 125) #:y 0)
  (with-skia ([blob (text-blob-builder-finish! builder)])
    (draw-text-blob (surface-canvas surface) blob 20 58 paint)))
]
@reference-figure["horizontal-text-run.png"
                  "The glyphs A, B, and C placed at explicit horizontal positions with uneven spacing."]
}

@defproc[(text-blob-builder-add-positioned-run!
          [builder text-blob-builder?] [font font?]
          [glyphs (or/c (listof (integer-in 0 #xffff))
                        (vectorof (integer-in 0 #xffff)))]
          [positions (or/c (listof (or/c (list/c real? real?) (vector/c real? real?)))
                            (vectorof (or/c (list/c real? real?) (vector/c real? real?))))]
          [#:text text (or/c string? bytes? #f) #f]
          [#:clusters clusters (or/c (listof exact-nonnegative-integer?)
                                     (vectorof exact-nonnegative-integer?) #f) #f]) void?]{
Appends a run with an explicit two-dimensional origin for each glyph, relative
to the blob's origin. No additional run-origin translation is applied. Empty
lists or vectors create no run. The shared run-input and metadata rules apply.

@racketblock[
(with-skia ([font (make-font #:size 24)]
            [builder (make-text-blob-builder)])
  (define text "Aé")
  (define glyphs (font-text->glyphs font text))
  (text-blob-builder-add-positioned-run! builder font glyphs '((0 0) (40 0))
                                       #:text text #:clusters '(0 1))
  (with-skia ([blob (text-blob-builder-finish! builder)])
    (define run (vector-ref (text-blob-runs blob) 0))
    (list (text-run-info-utf8 run) (text-run-info-clusters run))))
]

The text occupies three UTF-8 bytes. Its glyph clusters start at byte offsets
0 and 1; a cluster at offset 2 would point into the encoding of the second
character and would be rejected.


@racketblock[
(with-skia ([surface (make-surface 280 110 #:background 'white)]
            [font (make-font #:size 34)]
            [builder (make-text-blob-builder)]
            [paint (make-paint #:color "#326DE6")])
  (define glyphs (font-text->glyphs font "WAVE"))
  (text-blob-builder-add-positioned-run!
   builder font glyphs '((15 65) (75 42) (135 70) (200 35)))
  (with-skia ([blob (text-blob-builder-finish! builder)])
    (draw-text-blob (surface-canvas surface) blob 0 0 paint)))
]
@reference-figure["blob-positioned-wave-stage8.png"
                  "The blue letters WAVE occupy explicit two-dimensional positions that rise and fall like a wave."]
}

@defproc[(text-blob-builder-add-transformed-run!
          [builder text-blob-builder?] [font font?]
          [glyphs (or/c (listof (integer-in 0 #xffff))
                        (vectorof (integer-in 0 #xffff)))]
          [transforms
           (or/c (listof (or/c atlas-transform? (list/c real? real? real? real?)
                               (vector/c real? real? real? real?)))
                 (vectorof (or/c atlas-transform? (list/c real? real? real? real?)
                                 (vector/c real? real? real? real?))))]
          [#:text text (or/c string? bytes? #f) #f]
          [#:clusters clusters (or/c (listof exact-nonnegative-integer?)
                                     (vectorof exact-nonnegative-integer?) #f) #f]) void?]{
Appends a run with an independent scaled rotation and translation for each
glyph. A transform is an @tech{atlas transform} or a four-element list or
vector containing @math{scos}, @math{ssin}, @math{tx}, and @math{ty}.
It maps the glyph's local point with coordinates @math{x} and @math{y} to
@math{(scos x - ssin y + tx, ssin x + scos y + ty)}. Font size, horizontal
scale, and skew already contribute to the glyph's local geometry.

These four coefficients are not an @tech{affine matrix}'s six coefficients. They do
not express independent x/y scaling, a general shear, or a reflection. A
zero-scale transform is accepted. Input coefficients and metadata are copied;
the shared run-input and metadata rules apply.

A blob containing any transformed run is rejected by
@racket[text-blob-intercepts], even when the other runs use ordinary positions.
Use @racket[make-atlas-transform] for placement by scale, angle, and anchor.

@racketblock[
(with-skia ([surface (make-surface 260 110 #:background 'white)]
            [font (make-font #:size 34)] [builder (make-text-blob-builder)]
            [paint (make-paint #:color "#20344E")])
  (define glyphs (font-text->glyphs font "ABC"))
  (text-blob-builder-add-transformed-run!
   builder font glyphs
   (list (make-atlas-transform 30 70 #:rotation -18)
         (make-atlas-transform 100 55 #:scale 1.2 #:rotation 8)
         (make-atlas-transform 185 75 #:scale 0.9 #:rotation 22)))
  (with-skia ([blob (text-blob-builder-finish! builder)])
    (draw-text-blob (surface-canvas surface) blob 0 0 paint)))
]
@reference-figure["transformed-text-run.png"
                  "The glyphs A, B, and C individually translated, scaled, and rotated within one transformed text run."]
}

@defproc[(text-blob-builder-add-shaped-run!
          [builder text-blob-builder?] [run shaped-run?]
          [#:origin origin (or/c (list/c real? real?) (vector/c real? real?)) '(0 0)]) void?]{
Appends the run's glyphs and positions, translated by @racket[origin], using
its originating shaper's font. The shaper must be open. Text is not shaped
again and no fallback font is selected.

The run's source text and cluster offsets are stored automatically as blob
metadata. An empty run follows the same validation and no-append rules as
the glyph-based append functions.

@racketblock[
(with-skia ([font (make-font #:size 24)]
            [shaper (make-shaper font)]
            [builder (make-text-blob-builder)])
  (define text "AB")
  (define run (shape-text shaper text #:direction 'ltr #:script 'latn))
  (text-blob-builder-add-shaped-run! builder run #:origin '(12 40) )
  (with-skia ([blob (text-blob-builder-finish! builder)])
    (skia-close! shaper)
    (text-run-info-positioning (vector-ref (text-blob-runs blob) 0))))
]

The result is @racket['positioned]. Closing the shaper after a successful
append does not invalidate the captured blob font.


@racketblock[
(with-skia ([surface (make-surface 280 100 #:background 'white)]
            [font (make-font #:size 34)]
            [shaper (make-shaper font)]
            [builder (make-text-blob-builder)]
            [paint (make-paint #:color "#20344E")])
  (define text "office")
  (define run (shape-text shaper text #:direction 'ltr #:script 'latn))
  (text-blob-builder-add-shaped-run! builder run
                                    #:origin '(25 62) )
  (with-skia ([blob (text-blob-builder-finish! builder)])
    (draw-text-blob (surface-canvas surface) blob 0 0 paint)))
]
@reference-figure["blob-shaped-run-stage8.png"
                  "The word office is drawn from a shaped run added to a text-blob builder."]
}

@subsection{Finishing the Blob}

@defproc[(text-blob-builder-finish! [builder text-blob-builder?]) (or/c text-blob? #f)]{
Creates an owned text blob containing the builder's runs in append order.
The builder must be open. When it has no nonempty runs, the result is @racket[#f].
Both outcomes close the builder. Native failure also closes it and raises an
exception; it does not return a partial blob. The predicate
@racket[text-blob-builder?] remains true, but further appends, count queries,
and finishing attempts require an open builder and therefore fail.

The finished blob owns its captured font resources independently. The caller's
font wrappers, shaper, and builder do not need to remain open. A builder already
listed in @racket[with-skia] may be finished inside that scope; closing it again
during scope cleanup is harmless.
}

@section[#:tag "skia-text-blob-runs"]{Inspecting Runs}

@(declare-exporting skia skia/text-blobs #:use-sources (skia/text-blobs))

Use these queries to inspect the placement and optional text metadata stored
in a blob. They do not reconstruct text that was not supplied when the blob was
built.

A @deftech{text run description} is an immutable Racket structure containing a
run's positioning mode, glyphs, coordinates, and optional text metadata.
Obtain an independently owned font separately with
@racket[text-blob-run-font].

@defproc[(text-blob-run-count [blob text-blob?]) exact-nonnegative-integer?]{
Returns the number of logical runs stored in an open blob. A blob created
by @racket[make-positioned-text-blob] has one run. A builder-produced blob counts
nonempty successful appends, even if native storage merges adjacent runs.
}

@defproc[(text-blob-runs [blob text-blob?]) (and/c (vectorof text-run-info?) immutable?)]{
Returns an immutable vector of run descriptions in append order.
The run descriptions and their nested data are immutable. A blob made with
@racket[make-positioned-text-blob] is described as one @racket['positioned] run
without text or cluster metadata. This query does not reconstruct the original
text, reshape glyphs, or expose native run-buffer addresses.
}

@defproc[(text-blob-run-font [blob text-blob?] [index exact-nonnegative-integer?]) font?]{
Copies the font settings captured by the selected run into a new font.

The returned font is mutable and independently owned.
The zero-based @racket[index] must be less than @racket[(text-blob-run-count blob)].
Mutating or closing this font does not change the blob. Closing the blob does
not close the returned font. Invalid indices and closed blobs raise exceptions.
}

@defproc[(text-run-info? [v any/c]) boolean?]{
Returns @racket[#t] for a text run description and @racket[#f] otherwise.
}

@defproc[(text-run-info-positioning [run text-run-info?])
          (or/c 'default 'horizontal 'positioned 'transformed)]{
Returns the positioning mode used to append the run. Shaped-run appends have
mode @racket['positioned]; text-on-path results have mode @racket['transformed].
The mode describes stored placement, not whether the glyphs were originally
obtained by shaping.
}

@defproc[(text-run-info-glyphs [run text-run-info?])
          (and/c (vectorof (integer-in 0 #xffff)) immutable?)]{
Returns the immutable vector of glyph IDs in stored order. Glyph IDs belong
to the captured typeface and are not Unicode character codes.
}

@defproc[(text-run-info-positions [run text-run-info?])
          (and/c (vectorof (and/c (vector/c real? real?) immutable?)) immutable?)]{
Returns immutable @racket[#(x y)] glyph-origin vectors in blob coordinates. Default runs contain
the positions computed from font advances; horizontal runs include the shared
y coordinate; positioned runs contain their explicit positions. A transformed
run returns an empty vector here and stores its placement in
@racket[text-run-info-transforms] instead.
}

@defproc[(text-run-info-transforms [run text-run-info?])
          (or/c (and/c (vectorof (and/c (vector/c real? real? real? real?) immutable?)) immutable?) #f)]{
Returns an immutable vector of immutable four-coefficient vectors for a transformed run,
or @racket[#f] for the other positioning modes. Coefficients use the order
@math{scos}, @math{ssin}, @math{tx}, and @math{ty}, even when the input
was supplied as atlas-transform values or vectors. The result is not a vector
of affine matrices or a borrowed native buffer.
}

@defproc[(text-run-info-utf8 [run text-run-info?]) (or/c (and/c bytes? immutable?) #f)]{
Returns the immutable UTF-8 bytes supplied as run metadata, or @racket[#f]
when metadata was omitted. Stored bytes describe the caller-supplied text;
they are not inferred from glyph IDs. A Racket string input is encoded as UTF-8.
}

@defproc[(text-run-info-clusters [run text-run-info?])
          (or/c (and/c (vectorof exact-nonnegative-integer?) immutable?) #f)]{
Returns the immutable vector of UTF-8 scalar-start byte offsets supplied as
metadata, or @racket[#f]. Each offset indexes @racket[(text-run-info-utf8 run)].
There is one offset per glyph when metadata is present. The offsets can repeat
or descend; they are not an index into the positions vector.
}

@section[#:tag "skia-text-blob-intercepts"]{Outlines and Intercepts}

Convert glyphs to paths to fill or stroke their outlines directly. Such paths
contain monochrome geometry, not the full appearance of bitmap-only or color
glyphs. All whole-text conversions use the same
@secref["skia-text-outline-policy"] rule.

@(declare-exporting skia)

@defproc[(text-blob->path [blob text-blob?]
          [#:missing-outline missing-outline (or/c 'error 'skip) 'error]) skia-path?]{
Converts the blob's glyph outlines to a path at their recorded positions.

The path contains monochrome outlines, without applying a paint or canvas
transform. It is an owned resource and remains usable after the blob is closed.

A glyph with visible bounds but no monochrome outline raises an exception by
default, regardless of how the blob was constructed. Use
@racket[#:missing-outline 'skip] to omit it. Spaces and other glyphs without
visible bounds do not cause that exception.
Use ordinary blob drawing when bitmap or color rendering is required; use a
raster surface when the output target would otherwise require outline conversion.

The builder can store multiple runs with independently captured font settings.
Here the left panel is the completed two-run blob; the right panel draws the
path returned by @racket[text-blob->path]. The source font changes size between
appends, so the large exclamation mark belongs to a separate run.

@racketblock[
(with-skia ([surface (make-surface 420 175 #:background 'white)]
            [font (make-font #:size 30)]
            [builder (make-text-blob-builder)]
            [source-paint (make-paint #:color "#326DE6")]
            [outline-paint (make-paint #:color "#EFA02B" #:style 'stroke #:stroke-width 2)]
            [label-font (make-font #:size 12)]
            [label-paint (make-paint #:color "#526070")])
  (text-blob-builder-add-run! builder font (font-text->glyphs font "small")
                             #:origin '(18 92))
  (font-set-size! font 52)
  (text-blob-builder-add-run! builder font (font-text->glyphs font "!")
                             #:origin '(130 92))
  (with-skia ([blob (text-blob-builder-finish! builder)]
              [outline (text-blob->path blob)])
    (define canvas (surface-canvas surface))
    (draw-simple-text canvas "completed blob: two runs" 18 24
                      label-font label-paint)
    (draw-text-blob canvas blob 0 0 source-paint)
    (draw-simple-text canvas "text-blob->path" 228 24 label-font label-paint)
    (with-canvas-state canvas
      (canvas-translate! canvas 210 0)
      (draw-path canvas outline outline-paint))))
]
@reference-figure["text-blob-multirun-outline.png"
                  "A filled blue two-run text blob with small and large glyphs is shown beside the orange stroked path returned by text-blob->path."]
}


@subsection{Positioned Glyph Outlines}

@(declare-exporting skia skia/text-blobs #:use-sources (skia/text-blobs))

@defproc[(positioned-glyphs->path
          [font font?]
          [glyphs (or/c (listof (integer-in 0 #xffff))
                        (vectorof (integer-in 0 #xffff)))]
          [positions (or/c (listof (or/c (list/c real? real?) (vector/c real? real?)))
                            (vectorof (or/c (list/c real? real?) (vector/c real? real?))))]
          [#:missing-outline missing-outline (or/c 'error 'skip) 'error])
          skia-path?]{
Returns an owned path containing the font's monochrome glyph outlines at the
supplied positions. Glyph and position counts must agree, and all IDs must belong
to the font's typeface. Empty inputs return an owned empty path after validating
the font.

The path is independent of the input lists or vectors and the font's lifetime. Font
size, scale, and skew are applied, but no paint, canvas transform, shaping, or
fallback is added. A visible glyph without an outline raises an exception unless
@racket[#:missing-outline 'skip] is supplied. See @secref["skia-text-outline-policy"]. The
copied input and resulting geometry are checked against the byte limit.


@racketblock[
(with-skia ([surface (make-surface 240 120 #:background 'white)]
            [font (make-font #:size 42)]
            [paint (make-paint #:color "#326DE6")])
  (define glyphs (font-text->glyphs font "PATH"))
  (with-skia ([path
               (positioned-glyphs->path
                font glyphs '((10 65) (60 65) (115 65) (170 65)))])
    (draw-path (surface-canvas surface) path paint)))
]
@reference-figure["glyphs-to-path-stage8.png"
                  "The word PATH is drawn as one filled blue vector path assembled from positioned glyph outlines."]
}

@subsection{Horizontal Intersections}

@(declare-exporting skia skia/text-blobs #:use-sources (skia/text-blobs))

Use intercepts to find where glyph outlines cross a horizontal band, for
example when placing a rule near text. This query reports outline intervals,
not rendered pixels.

@defproc[(text-blob-intercepts [blob text-blob?] [top real?] [bottom real?]
                              [#:paint paint (or/c paint? #f) #f])
          (and/c (vectorof (and/c (vector/c real? real?) immutable?)) immutable?)]{
Returns an immutable vector of horizontal intervals where glyph outlines
intersect the band between @racket[top] and @racket[bottom]. The value of
@racket[top] must be strictly less than @racket[bottom]. Each interval is an
immutable @racket[#(left right)] vector, with left no greater than
right. An empty vector means no intersections were reported.

Coordinates are relative to the blob's stored origin; a later draw translation,
canvas transform, and clip are not included. The optional open paint supplies
stroke and path-effect settings to the native query. The result is not a pixel
coverage readback or the output bounds of an image filter. Intervals are returned
in native order, not as a promised sorted, merged union.

The native backend omits transformed runs when computing intercepts. To avoid
returning incomplete results, this function rejects any blob containing a
transformed run. The result is subject to @racket[current-skia-byte-limit].

@racketblock[
(with-skia ([font (make-font #:size 24)]
            [blob
             (make-positioned-text-blob font (font-text->glyphs font "AB")
                                        '((0 30) (40 30)))])
  (text-blob-intercepts blob 20 25))
]

The exact intervals depend on the typeface; the two band coordinates and the
stored glyph positions share the same coordinate system.

@racketblock[
(with-skia ([surface (make-surface 240 100 #:background 'white)]
            [font (make-font #:size 42)]
            [blob (make-positioned-text-blob font (font-text->glyphs font "AB")
                                             '((0 55) (70 55)))]
            [text-paint (make-paint #:color "#20344E")])
  (draw-text-blob (surface-canvas surface) blob 20 10 text-paint)
  (text-blob-intercepts blob 35 45))
]
@reference-figure["text-blob-intercepts.png"
                  "Two large glyphs crossed by a highlighted horizontal band, with the reported intercept intervals marked within that band."]
}

@section[#:tag "skia-text-on-path"]{Placing Shaped Text on a Path}

@(declare-exporting skia skia/text-blobs #:use-sources (skia/text-blobs))

Use these operations to place a previously shaped run along a curve. They
rotate and position whole glyphs; they do not bend their outlines or fit an
overlong run to the path. Create a blob once for repeated drawing, or use
@racket[draw-shaped-run/on-path] for one drawing.

@defproc[(shaped-run->text-blob/on-path
          [run shaped-run?] [path skia-path?]
          [#:start-offset start real? 0]
          [#:normal-offset normal real? 0]
          [#:contour contour exact-nonnegative-integer? 0]
          [#:force-closed? closed? boolean? #f]) (or/c text-blob? #f)]{
Returns an owned blob that places the run's glyphs along the selected measured
contour. It uses the run's existing glyph positions and originating shaper's
captured font; it does not reshape text or bend individual glyph outlines.

The zero-based @racket[contour] selects by the same contour iteration used by
@racket[make-path-measure] and @racket[path-measure-next-contour!]. The
@racket[closed?] option affects measurement without modifying @racket[path].
For a glyph origin with coordinates @math{gx} and @math{gy}, its contour distance
is @math{start + gx}, and its
normal displacement is @math{normal + gy}.

At the sampled point @math{(px, py)}, let the unit tangent be @math{(tx, ty)}.
The normal points in direction @math{(-ty, tx)}. The resulting glyph transform
has coefficients @math{(tx, ty, px - ty (normal + gy), py + tx (normal + gy))}.
On a contour running to the right in downward-positive coordinates, a positive
normal offset places the baseline below the path.

Every glyph-origin distance must lie between zero and the selected contour's
length, inclusive. A nonempty run requires positive measurable length and a
valid tangent frame at every glyph origin. If an origin is outside the range
or the required length or tangent is unavailable for a nonempty run, the
function raises an exception before constructing the blob.
There is no fitting, clipping, or wraparound, even on a closed contour. This
check covers origins, not the full visible glyph extents. Glyphs may extend
beyond an endpoint.
Right-to-left and vertical runs are not reordered; stored x positions still
select distances and stored y positions still select normal offsets.

@bold{Conceptual diagram.} At arc-length @math{s=start+gx}, the unit tangent is
@math{(tx,ty)} and its downward-positive normal is @math{(-ty,tx)}. The glyph
origin is @math{P(s) + (normal+gy)(-ty,tx)}. On a contour travelling rightward,
a positive normal offset therefore points downward. The operation rotates whole
glyphs into this frame; it does not bend outlines or fit text to a contour.

@reference-figure["concept-text-path-frame.png"
                  "A rightward path marks contour direction, an arc-length bracket to sample distance s, tangent and normal arrows, and a glyph origin offset by the positive downward normal. The equation for the final glyph origin is printed below."]

The result contains a transformed run and therefore cannot be queried with
@racket[text-blob-intercepts]. It captures its own font state; closing the
source path or shaper afterward does not invalidate it.

The run's source text and cluster offsets are stored automatically.
An empty run returns @racket[#f], but still validates the path, originating
shaper, contour selection, and offsets. If Skia cannot construct the blob,
the function raises an exception without returning a partial blob.

@racketblock[
(with-skia ([surface (make-surface 330 100 #:background 'white)]
            [font (make-font #:size 24)]
            [shaper (make-shaper font)]
            [path (make-path '((move 10 40) (line 310 40)))]
            [guide-path (make-path '((move 10 40) (line 310 40)))]
            [guide (make-paint #:color "#BBBBBB" #:style 'stroke #:stroke-width 1)]
            [mark (make-paint #:color "#EFA02B" #:style 'stroke #:stroke-width 2)]
            [paint (make-paint #:color "#20344E")]
            [label-font (make-font #:size 12)]
            [label (make-paint #:color "#20344E")])
  (define text "AB")
  (define run (shape-text shaper text #:direction 'ltr #:script 'latn))
  (with-skia ([blob (shaped-run->text-blob/on-path run path
                                                 #:start-offset 20 #:normal-offset 5
                                                 )])
    (skia-close! path)
    (skia-close! shaper)
    (define canvas (surface-canvas surface))
    (draw-path canvas guide-path guide)
    (draw-text-blob canvas blob 0 0 paint)
    (draw-line canvas 30 40 30 45 mark)
    (draw-simple-text canvas "start +20; normal +5" 10 88 label-font label)
    (text-run-info-transforms (vector-ref (text-blob-runs blob) 0))))
]

@reference-figure["text-blob-path-snapshot.png"
                  "An AB text blob drawn after its source path and shaper close. A pale reconstructed straight guide marks the original path; the orange five-unit marker and caption identify the start offset 20 and normal offset 5."]

The guide is a separate path reconstructed for this drawing. The figure draws
@racket[blob] directly, rather than calling the on-path helper again after its
source resources have closed.

Each transform contains unit rotation coefficients for the horizontal path.
Its translation includes the start offset and the five-unit normal offset;
exact glyph positions also depend on shaping.
}

@defproc[(draw-shaped-run/on-path
          [canvas canvas?] [run shaped-run?]
          [path skia-path?] [paint paint?]
          [#:start-offset start real? 0]
          [#:normal-offset normal real? 0]
          [#:contour contour exact-nonnegative-integer? 0]
          [#:force-closed? closed? boolean? #f]) void?]{
Places and draws the run using the same contour and offset rules as
@racket[shaped-run->text-blob/on-path]. A temporary blob is drawn at origin
coordinates zero and zero, then released, including when drawing raises an
exception. The canvas transform and clip and the supplied paint apply.

The canvas and paint are validated even for an empty run; the path-placement
operation then validates the other inputs. An empty run draws nothing. The
operation does not close the caller's path, shaper, paint, or canvas owner.
For repeated drawing at the same placement, create a blob once with
@racket[shaped-run->text-blob/on-path] and reuse it with @racket[draw-text-blob].

@racketblock[
(with-skia ([surface (make-surface 330 120 #:background 'white)]
            [font (make-font #:size 24)]
            [shaper (make-shaper font)]
            [path (make-path '((move 15 80) (cubic 85 15 245 15 315 80)))]
            [guide (make-paint #:color "#BBBBBB" #:style 'stroke #:stroke-width 1)]
            [text-paint (make-paint #:color "#20344E")])
  (draw-path (surface-canvas surface) path guide)
  (define run (shape-text shaper "Text follows the curve"
                          #:direction 'ltr #:script 'latn #:language "en"))
  (draw-shaped-run/on-path (surface-canvas surface) run path text-paint
                           #:start-offset 10))
]

@reference-figure["text-on-path.png"
                  "Dark text follows a pale cubic curve from left to right."]


@racketblock[
(with-skia ([surface (make-surface 330 130 #:background 'white)]
            [font (make-font #:size 24)]
            [shaper (make-shaper font)]
            [path (make-path '((move 15 72) (line 315 72)))]
            [guide (make-paint #:color "#BBBBBB" #:style 'stroke)]
            [paint (make-paint #:color "#20344E")])
  (draw-path (surface-canvas surface) path guide)
  (define run (shape-text shaper "offset from the path"
                          #:direction 'ltr #:script 'latn))
  (draw-shaped-run/on-path (surface-canvas surface) run path paint
                           #:start-offset 25 #:normal-offset -14))
]
@reference-figure["text-path-offset-stage8.png"
                  "Dark text follows a pale horizontal path while a negative normal offset lifts its baseline above the guide."]
}
