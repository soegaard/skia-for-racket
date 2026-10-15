#lang scribble/manual

@(require (for-label racket/base racket/contract skia skia/text-blobs))

@title[#:tag "skia-text-blobs"]{Text Blobs}

@(declare-exporting skia)

A @deftech{text blob} is an owned native object containing glyphs and their
placement. It retains the font information needed to draw them. A blob does
not contain a paint, perform paragraph wrapping, or turn glyph IDs into a
portable character string.

The single-run constructor and the multi-run builder below produce blobs that
can be drawn repeatedly with different paints or canvas transforms. Native
operations require open resources on their owning thread. Drawing also follows
the canvas's and paint's GPU-context conditions when applicable.

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


@local-table-of-contents[#:style 'immediate-only]

@section[#:tag "skia-text-blob-builders"]{Building Multiple Runs}

@defmodule[skia/text-blobs #:no-declare]
@(declare-exporting skia skia/text-blobs #:use-sources (skia/text-blobs))

A @deftech{text-blob builder} collects glyph runs into one text blob. Each run
has a positioning mode and captures its font's settings when appended. Different
runs may use different fonts. Successful appends copy their inputs; later input
mutation, font mutation, or closure of the original font does not change them.
The builder and finished blob retain their own font information.

Finishing consumes the builder. A finished blob is independent of the builder's
lifetime and can use the drawing, bounds, and outline operations above. Closing
an unfinished builder discards its runs and releases its retained resources.
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
still consumed.
}

@defproc[(text-blob-builder-run-count [builder text-blob-builder?])
          exact-nonnegative-integer?]{
Returns the number of nonempty runs successfully appended to an open builder.
Appending an empty glyph sequence does not increase the count. This counts
logical appends, not any merging of adjacent runs performed by native storage.
}

@subsection[#:tag "skia-text-run-inputs"]{Run Inputs and Failure Behavior}

Glyph inputs are lists or vectors of unsigned 16-bit glyph IDs. Each ID must
also be less than the glyph count of the selected font's typeface; zero is
permitted. These operations do not map characters, shape text, or select a
fallback typeface. Coordinates and transform coefficients must be
@tech{drawing scalar}s. Position and transform sequences must match the glyph
count. A point may be a two-element list or vector.

Input counts must fit a signed 32-bit integer. Copied inputs and accumulated
run data are checked against @racket[current-skia-byte-limit]. The limit bounds
the wrapper's charged payload and bookkeeping, not all native font caches or
allocator overhead. Exceeding a limit raises an exception.

An empty append still validates its options and resources, but creates no run
and captures no font. Invalid arguments detected before native run allocation
leave the builder available. A failure after native run allocation begins
closes the builder because the partial append cannot be rolled back. After an
append exception, check @racket[skia-closed?] before attempting to reuse it.
Finishing a closed builder, or using one from the wrong thread, raises an
exception rather than producing another blob.

@subsection[#:tag "skia-text-run-metadata"]{Optional Text and Clusters}

The four glyph-based append procedures accept @racket[#:text] and
@racket[#:clusters]. Both must be @racket[#f], or both must be supplied. Text
may be a Racket string or a byte string containing valid UTF-8; malformed byte
sequences are rejected. Supplied text is retained as immutable UTF-8 bytes.

The cluster sequence contains one exact nonnegative integer per glyph. Each
integer is a byte offset inside the supplied UTF-8 text, at the beginning of a
Unicode scalar value. It is not a Racket character index or necessarily a
grapheme boundary. Repeated and descending offsets are permitted, so clusters
can describe ligatures, combining marks, and right-to-left glyph order.

Nonempty glyphs require nonempty text when metadata is supplied. An empty run
can have empty text and an empty cluster sequence, but cannot retain nonempty
text that would otherwise be discarded. Supplying metadata does not reshape,
reorder, or reposition glyphs. The caller is responsible for making the text,
glyphs, and cluster associations agree; the library checks their representation
and ranges, not that semantic correspondence.

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
@racket[text-blob-builder-add-shaped-run!] to retain an already shaped result.
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
Appends a run with one absolute x coordinate per glyph and a shared baseline
coordinate @racket[y], all relative to the blob's origin. The x values are not
advances to be accumulated. Their order is preserved; no sorting or shaping
is performed. The shared run-input and metadata rules apply.
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
to the blob's origin. No additional run-origin translation is applied. Unlike
@racket[make-positioned-text-blob], this procedure accepts empty sequences as
an append that creates no run. The shared run-input and metadata rules apply.

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

These four coefficients are not an affine matrix's six coefficients. They do
not express independent x/y scaling, a general shear, or a reflection. A
zero-scale transform is accepted. Input coefficients and metadata are copied;
the shared run-input and metadata rules apply.

A blob containing any transformed run is rejected by
@racket[text-blob-intercepts], even when the other runs use ordinary positions.
Use @racket[make-atlas-transform] for placement by scale, angle, and anchor.
}

@defproc[(text-blob-builder-add-shaped-run!
          [builder text-blob-builder?] [shaper shaper?] [run shaped-run?]
          [#:origin origin (or/c (list/c real? real?) (vector/c real? real?)) '(0 0)]
          [#:text text (or/c string? bytes? #f) #f]) void?]{
Appends a positioned run using the glyphs and positions already stored in
@racket[run], translated by @racket[origin]. The font is copied from the open
@racket[shaper]; text is not shaped again. The caller must use a shaper whose
captured font agrees with the one used to create the run. There is no automatic
font-provenance check or fallback selection.

When @racket[text] is supplied, the run's clusters supply its UTF-8 byte offsets
and are checked against that text according to @secref["skia-text-run-metadata"].
The original string cannot be reconstructed from the shaped run alone. With
@racket[#f], neither text nor clusters are retained as blob metadata. The run's
glyphs and positions are still used. An empty run follows the same validation
and no-append rules as the glyph-based append procedures.

@racketblock[
(with-skia ([font (make-font #:size 24)]
            [shaper (make-shaper font)]
            [builder (make-text-blob-builder)])
  (define text "AB")
  (define run (shape-text shaper text #:direction 'ltr #:script 'latn))
  (text-blob-builder-add-shaped-run! builder shaper run #:origin '(12 40) #:text text)
  (with-skia ([blob (text-blob-builder-finish! builder)])
    (skia-close! shaper)
    (text-run-info-positioning (vector-ref (text-blob-runs blob) 0))))
]

The result is @racket['positioned]. Closing the shaper after a successful
append does not invalidate the captured blob font.
}

@defproc[(text-blob-builder-finish! [builder text-blob-builder?]) (or/c text-blob? #f)]{
Consumes an open builder and returns an owned blob containing its runs, in
append order. When the builder has no nonempty runs, the result is @racket[#f].
Both outcomes close the builder. Native failure also closes it and raises an
exception; it does not return a partial blob. The predicate
@racket[text-blob-builder?] remains true, but further appends, count queries,
and finishing attempts require an open builder and therefore fail.

The finished blob owns its captured font resources independently. It does not
retain the caller's font wrappers, shaper, or builder as resources that must
remain open. A builder already listed in @racket[with-skia] may be finished
inside that scope; closing it again during scope cleanup is harmless.
}

@section[#:tag "skia-text-blob-runs"]{Inspecting Runs}

@(declare-exporting skia skia/text-blobs #:use-sources (skia/text-blobs))

A @deftech{text run description} is a detached immutable value containing a
run's positioning mode, glyphs, coordinates, and optional text metadata. It
contains no borrowed font or native pointer and remains usable after the blob
closes. Obtain an independently owned font separately with
@racket[text-blob-run-font].

@defproc[(text-blob-run-count [blob text-blob?]) exact-nonnegative-integer?]{
Returns the number of logical runs retained by an open blob. A blob created
by @racket[make-positioned-text-blob] has one run. A builder-produced blob counts
nonempty successful appends, even if native storage merges adjacent runs.
}

@defproc[(text-blob-runs [blob text-blob?]) (vectorof text-run-info?)]{
Returns an immutable vector of detached run descriptions in append order.
The run descriptions and their nested data are immutable. A blob made with
@racket[make-positioned-text-blob] is described as one @racket['positioned] run
without text or cluster metadata. This query does not reconstruct the original
text, reshape glyphs, or expose native run-buffer addresses.
}

@defproc[(text-blob-run-font [blob text-blob?] [index exact-nonnegative-integer?]) font?]{
Returns a new owned mutable font copied from the selected run's captured font.
The zero-based @racket[index] must be less than @racket[(text-blob-run-count blob)].
Mutating or closing this font does not change the blob. Closing the blob does
not close the returned font. Invalid indices and closed blobs raise exceptions.
}

@defproc[(text-run-info? [v any/c]) boolean?]{
Returns @racket[#t] for a text run description and @racket[#f] otherwise. A run
description is a detached value, not a resource requiring explicit closure.
}

@defproc[(text-run-info-positioning [run text-run-info?])
          (or/c 'default 'horizontal 'positioned 'transformed)]{
Returns the positioning mode used to append the run. Shaped-run appends have
mode @racket['positioned]; text-on-path results have mode @racket['transformed].
The mode describes stored placement, not whether the glyphs were originally
obtained by shaping.
}

@defproc[(text-run-info-glyphs [run text-run-info?]) (vectorof (integer-in 0 #xffff))]{
Returns the immutable vector of glyph IDs in stored order. Glyph IDs belong
to the captured typeface and are not Unicode character codes.
}

@defproc[(text-run-info-positions [run text-run-info?]) (vectorof (list/c real? real?))]{
Returns immutable glyph-origin pairs in blob coordinates. Default runs contain
the positions computed from font advances; horizontal runs include the shared
y coordinate; positioned runs contain their explicit positions. A transformed
run returns an empty vector here and stores its placement in
@racket[text-run-info-transforms] instead.
}

@defproc[(text-run-info-transforms [run text-run-info?])
          (or/c (vectorof (list/c real? real? real? real?)) #f)]{
Returns an immutable vector of four-coefficient lists for a transformed run,
or @racket[#f] for the other positioning modes. Coefficients use the order
@math{scos}, @math{ssin}, @math{tx}, and @math{ty}, even when the input
was supplied as atlas-transform values or vectors. The result is not a vector
of affine matrices or a borrowed native buffer.
}

@defproc[(text-run-info-utf8 [run text-run-info?]) (or/c bytes? #f)]{
Returns the immutable UTF-8 bytes supplied as run metadata, or @racket[#f]
when metadata was omitted. Stored bytes describe the caller-supplied text;
they are not inferred from glyph IDs. A Racket string input is encoded as UTF-8.
}

@defproc[(text-run-info-clusters [run text-run-info?])
          (or/c (vectorof exact-nonnegative-integer?) #f)]{
Returns the immutable vector of UTF-8 scalar-start byte offsets supplied as
metadata, or @racket[#f]. Each offset indexes @racket[(text-run-info-utf8 run)].
There is one offset per glyph when metadata is present. The offsets can repeat
or descend; they are not an index into the positions vector.
}

@section[#:tag "skia-text-blob-intercepts"]{Intercepts and Outlines}

@(declare-exporting skia skia/text-blobs #:use-sources (skia/text-blobs))

@defproc[(text-blob-intercepts [blob text-blob?] [top real?] [bottom real?]
                              [#:paint paint (or/c paint? #f) #f])
          (vectorof (list/c real? real?))]{
Returns an immutable vector of horizontal intervals where glyph outlines
intersect the band between @racket[top] and @racket[bottom]. Both bounds must
be drawing scalars with @racket[top] strictly less than @racket[bottom]. Each
interval is a list of its left and right endpoints, with left no greater than
right. An empty vector means no intersections were reported.

Coordinates are relative to the blob's stored origin; a later draw translation,
canvas transform, and clip are not included. The optional open paint supplies
stroke and path-effect settings to the native query. The result is not a pixel
coverage readback or the output bounds of an image filter. Intervals are returned
in native order, not as a promised sorted, merged union.

The native backend omits transformed runs when computing intercepts. To avoid
returning incomplete results, this procedure rejects any blob containing a
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
}

@defproc[(positioned-glyphs->path
          [font font?]
          [glyphs (or/c (listof (integer-in 0 #xffff))
                        (vectorof (integer-in 0 #xffff)))]
          [positions (or/c (listof (or/c (list/c real? real?) (vector/c real? real?)))
                            (vectorof (or/c (list/c real? real?) (vector/c real? real?))))])
          skia-path?]{
Returns an owned path containing the font's monochrome glyph outlines at the
supplied positions. Glyph and position counts must agree, all IDs must belong
to the font's typeface, and coordinates must be drawing scalars. Empty inputs
return an owned empty path after validating the font.

The path is independent of the input sequences and the font's lifetime. Font
size, scale, and skew are applied, but no paint, canvas transform, shaping, or
fallback is added. Glyphs without monochrome outlines contribute no contour;
this is not a general conversion of bitmap or color glyphs to vectors. The
copied input and resulting geometry are checked against the byte limit.
}

@section[#:tag "skia-text-on-path"]{Placing Shaped Text on a Path}

@(declare-exporting skia skia/text-blobs #:use-sources (skia/text-blobs))

@defproc[(shaped-run->text-blob/on-path
          [shaper shaper?] [run shaped-run?] [path skia-path?]
          [#:start-offset start real? 0]
          [#:normal-offset normal real? 0]
          [#:contour contour exact-nonnegative-integer? 0]
          [#:force-closed? closed? boolean? #f]
          [#:text text (or/c string? bytes? #f) #f]) (or/c text-blob? #f)]{
Returns an owned blob that places the run's glyphs along the selected measured
contour. It uses the run's existing glyph positions and the shaper's captured
font; it does not reshape text or bend individual glyph outlines.

The zero-based @racket[contour] selects by the same contour iteration used by
@racket[make-path-measure] and @racket[path-measure-next-contour!]. The
@racket[closed?] option affects measurement without modifying @racket[path].
Offsets must be drawing scalars. For a glyph origin with coordinates
@math{gx} and @math{gy}, its contour distance is @math{start + gx}, and its
normal displacement is @math{normal + gy}.

At the sampled point @math{(px, py)}, let the unit tangent be @math{(tx, ty)}.
The normal points in direction @math{(-ty, tx)}. The resulting glyph transform
has coefficients @math{(tx, ty, px - ty (normal + gy), py + tx (normal + gy))}.
On a contour running to the right in downward-positive coordinates, a positive
normal offset places the baseline below the path.

Every glyph-origin distance must lie between zero and the selected contour's
length, inclusive. A nonempty run requires positive measurable length and a
valid tangent frame. Origins outside the range raise an exception: there is
no fitting, clipping, or wraparound, even on a closed contour. This check covers
origins, not the full visible glyph extents. Glyphs may extend beyond an endpoint.
Right-to-left and vertical runs are not reordered; stored x positions still
select distances and stored y positions still select normal offsets.

The result contains a transformed run and therefore cannot be queried with
@racket[text-blob-intercepts]. It captures its own font state; closing the
source path or shaper afterward does not invalidate it. The caller must supply
a shaper whose captured font agrees with the shaped run.

An empty run returns @racket[#f], but still validates the path, shaper, contour
selection, offsets, and metadata. With @racket[text], the run's clusters are
validated against the supplied UTF-8 text; with @racket[#f], both text and
clusters are absent from the resulting blob metadata. The rules in
@secref["skia-text-run-metadata"] apply. Failure returns no partial blob.

@racketblock[
(with-skia ([font (make-font #:size 24)]
            [shaper (make-shaper font)]
            [path (make-path '((move 10 40) (line 310 40)))])
  (define text "AB")
  (define run (shape-text shaper text #:direction 'ltr #:script 'latn))
  (with-skia ([blob (shaped-run->text-blob/on-path shaper run path
                                                 #:start-offset 20 #:normal-offset 5
                                                 #:text text)])
    (skia-close! path)
    (skia-close! shaper)
    (text-run-info-transforms (vector-ref (text-blob-runs blob) 0))))
]

Each transform contains unit rotation coefficients for the horizontal path.
Its translation includes the start offset and the five-unit normal offset;
exact glyph positions also depend on shaping.
}

@defproc[(draw-shaped-run/on-path
          [canvas canvas?] [shaper shaper?] [run shaped-run?]
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
Use a retained blob instead when repeatedly drawing the same placement.
}
