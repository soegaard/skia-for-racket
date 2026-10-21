#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia skia/typefaces))

@title[#:tag "skia-typefaces"]{Font Managers and Typefaces}

@(declare-exporting skia)

A @deftech{typeface} identifies a font face, including its glyphs and design
metrics. It does not select a drawing size. A @tech{font} combines a typeface
with size and rendering settings. A @deftech{font manager} finds typefaces
available through a platform font system or a supplied collection.

Font managers, typefaces, and @tech{font-style sets} are @tech{owned resource}s.
Their native operations require an open resource on its owning thread.
Predicates identify their wrappers even after closure. Font availability,
family order, and matching results depend on the machine; a family name is
not a portable font-file identifier.

@local-table-of-contents[#:style 'immediate-only]

@section{Font Managers}

@defproc[(font-manager? [v any/c]) boolean?]{
Returns @racket[#t] for a font-manager resource and @racket[#f] otherwise.
}

@defproc[(make-font-manager) font-manager?]{
Creates an owned manager using the platform's default font sources.
A native allocation or initialization failure raises an exception. The manager
need not contain any families on a machine without configured fonts.
}

@defproc[(default-font-manager) font-manager?]{
Returns an owned reference to the native default font manager. The wrapper
has its own lifetime; closing it releases that reference, not every reference
to the native manager. This operation does not return a borrowed singleton.
}

@defproc[(font-manager-family-count [manager font-manager?]) exact-nonnegative-integer?]{
Returns the number of families enumerated by @racket[manager].
}

@defproc[(font-manager-family-name [manager font-manager?] [index exact-nonnegative-integer?])
          string?]{
Returns the family name at the zero-based @racket[index]. The index must be
less than @racket[(font-manager-family-count manager)].
}

@defproc[(font-manager-families [manager font-manager?]) (listof string?)]{
Returns the family names in the manager's enumeration order. The list is
not guaranteed to be sorted or identical on different platforms.

@racketblock[
(with-skia ([manager (make-font-manager)])
  (= (length (font-manager-families manager))
     (font-manager-family-count manager)))
]
}

@defproc[(font-manager-match-family [manager font-manager?] [family string?]
                [#:weight weight (or/c (integer-in 0 1000) 'invisible 'thin 'extra-light 'light
                'normal
                         'medium 'semi-bold 'bold 'extra-bold 'black 'extra-black) 'normal]
                [#:width width (or/c (integer-in 1 9) 'ultra-condensed 'extra-condensed 'condensed
                        'semi-condensed 'normal 'semi-expanded 'expanded
                        'extra-expanded 'ultra-expanded) 'normal]
                [#:slant slant (or/c 'upright 'italic 'oblique) 'upright]) (or/c typeface? #f)]{
Returns an owned typeface selected by @racket[manager] for the requested
family and style, or @racket[#f] if no face is found. The family string must
not contain NUL. Matching can substitute a family or style; inspect the returned
face instead of assuming an exact match. The result has its own native reference
and remains usable after the manager is closed.

The accepted weight, width, and slant values are described in
@secref["skia-font-styles"]. Width here selects a condensed or expanded design;
it is not a width in drawing units.
}

@subsection{Selecting and Inspecting Actual Faces}

The requested style is a preference, not a portable promise. This comparison
starts from a face selected for a displayed character, asks the same manager
for regular, bold, and italic variants of that face's actual family, and labels
each result with the family and style that the manager returned.

@racketblock[
(with-skia ([surface (make-surface 420 180 #:background 'white)]
            [manager (make-font-manager)]
            [label-font (make-font #:size 11)]
            [label-paint (make-paint #:color "#526070")])
  (define initial
    (or (font-manager-match-character manager #\g)
        (error 'face-comparison "no face covers the displayed character")))
  (define family (typeface-family-name initial))
  (with-skia ([regular initial]
              [bold (or (font-manager-match-family manager family #:weight 'bold)
                        (error 'face-comparison "no bold face was selected"))]
              [italic (or (font-manager-match-family manager family #:slant 'italic)
                          (error 'face-comparison "no italic face was selected"))])
    (define canvas (surface-canvas surface))
    (for ([face (in-list (list regular bold italic))]
          [x '(18 154 290)])
      (with-skia ([font (make-font face #:size 37)]
                  [paint (make-paint #:color "#20344E")])
        (draw-simple-text canvas "Style" x 78 font paint)
        (draw-simple-text canvas (typeface-family-name face) x 132
                          label-font label-paint)
        (draw-simple-text canvas
                          (format "weight ~a; ~a"
                                  (typeface-weight face) (typeface-slant face))
                          x 150 label-font label-paint)))))
]
@reference-figure["font-manager-style-selection.png"
                  "Three panels show Style in manager-selected regular, bold, and italic faces; each panel identifies the actual returned family, numeric weight, and slant."]

@defproc[(font-manager-match-character [manager font-manager?] [character (or/c char? (integer-in
          0 #xd7ff) (integer-in #xe000 #x10ffff))]
                [#:family family (or/c string? #f) #f]
                [#:weight weight (or/c (integer-in 0 1000) 'invisible 'thin 'extra-light 'light
                'normal
                         'medium 'semi-bold 'bold 'extra-bold 'black 'extra-black) 'normal]
                [#:width width (or/c (integer-in 1 9) 'ultra-condensed 'extra-condensed 'condensed
                        'semi-condensed 'normal 'semi-expanded 'expanded
                        'extra-expanded 'ultra-expanded) 'normal]
                [#:slant slant (or/c 'upright 'italic 'oblique) 'upright]
                [#:languages languages (listof string?) '()]) (or/c typeface? #f)]{
Returns an owned typeface selected for @racket[character], or @racket[#f]
if none is found. A character may be supplied as a Racket character or a Unicode
scalar integer; surrogate integers are rejected. Family and language strings
must not contain NUL. The language tags guide the platform's fallback search.

Finding a face for one character does not establish that it supports an entire
string, cluster, or script. This operation neither shapes text nor installs a
fallback policy in an existing font.
}

@section{Constructing and Inspecting Typefaces}

@defproc[(typeface? [v any/c]) boolean?]{
Returns @racket[#t] for a typeface resource and @racket[#f] otherwise.
}

@defproc[(make-typeface) typeface?]{
Creates an owned default typeface. The selected family is platform-dependent.
Failure to obtain a native typeface raises an exception, not @racket[#f].
}

@defproc[(typeface-from-family [family string?]
                [#:weight weight (or/c (integer-in 0 1000) 'invisible 'thin 'extra-light 'light
                'normal
                         'medium 'semi-bold 'bold 'extra-bold 'black 'extra-black) 'normal]
                [#:width width (or/c (integer-in 1 9) 'ultra-condensed 'extra-condensed 'condensed
                        'semi-condensed 'normal 'semi-expanded 'expanded
                        'extra-expanded 'ultra-expanded) 'normal]
                [#:slant slant (or/c 'upright 'italic 'oblique) 'upright]) typeface?]{
Creates an owned typeface using the default font system and the requested
family and style. The family string must not contain NUL. Native matching may
substitute a family or style; this function does not verify exact family-name
agreement. Native failure raises an exception. Use
@racket[font-manager-match-family] to select through a particular manager.
}

@defproc[(typeface-from-file [filename path-string?] [#:index index exact-nonnegative-integer? 0])
          typeface?]{
Loads an owned typeface from an existing file. The zero-based @racket[index]
selects a face within a collection and must fit the native signed-integer index.
A path containing NUL, missing file, unsupported font, or native failure raises
an exception. This loader uses the platform's native file-loading behavior;
@racket[typeface-from-bytes] provides copied-byte loading with explicit
collection-member selection.
}

@defproc[(typeface-family-name [face typeface?]) string?]{
Returns a copied family-name string for the actual selected face, which can
differ from a requested family name.
}

@defproc[(typeface-weight [face typeface?]) exact-integer?]{
Returns the face's numeric weight, rather than a weight symbol. The standard
scale uses 400 for normal and 700 for bold.
}

@defproc[(typeface-width [face typeface?]) exact-integer?]{
Returns the face's numeric width class, rather than a width in pixels.
The standard classes run from 1 (ultra-condensed) to 9 (ultra-expanded).
}

@defproc[(typeface-slant [face typeface?]) (or/c 'upright 'italic 'oblique)]{
Returns the face's declared slant: upright, italic, or oblique.
}

@section[#:tag "skia-font-styles"]{Font Styles and Style Sets}

@defmodule[skia/typefaces #:no-declare]
@(declare-exporting skia skia/typefaces #:use-sources (skia/typefaces))

To choose a face within a family, obtain its available styles with
@racket[font-manager-style-set]. Create a style request with
@racket[make-font-style] and pass it to @racket[font-style-set-match]. A style
request selects among available faces; it does not change an existing
typeface's design.

The font-style, style-set, copied-data, and metadata bindings are also provided
by @racketmodname[skia/typefaces]. A @deftech{font style} is an immutable Racket
structure describing weight, width, and slant, not a typeface.

A @deftech{font-style set} is an owned collection of the styles available for a
font family. It keeps its own native reference to the style collection, so
closing the font manager's wrapper does not prevent inspecting styles or
obtaining their typefaces.

The weight names denote the following integers: @racket['invisible] is 0,
@racket['thin] is 100, @racket['extra-light] is 200, @racket['light] is 300,
@racket['normal] is 400, @racket['medium] is 500, @racket['semi-bold] is 600,
@racket['bold] is 700, @racket['extra-bold] is 800, @racket['black] is 900,
and @racket['extra-black] is 1000. Any exact integer from 0 through 1000 is
also accepted; naming a weight does not guarantee that a matching design exists.

The width names denote classes 1 through 9 in this order:
@racket['ultra-condensed], @racket['extra-condensed], @racket['condensed],
@racket['semi-condensed], @racket['normal], @racket['semi-expanded],
@racket['expanded], @racket['extra-expanded], and @racket['ultra-expanded].
The slants are @racket['upright], @racket['italic], and @racket['oblique].

@defproc[(font-style? [v any/c]) boolean?]{
Returns @racket[#t] for a font-style value and @racket[#f] otherwise.
}

@defproc[(make-font-style [#:weight weight (or/c (integer-in 0 1000) 'invisible 'thin 'extra-light
          'light 'normal
                         'medium 'semi-bold 'bold 'extra-bold 'black 'extra-black) 'normal]
                [#:width width (or/c (integer-in 1 9) 'ultra-condensed 'extra-condensed 'condensed
                        'semi-condensed 'normal 'semi-expanded 'expanded
                        'extra-expanded 'ultra-expanded) 'normal]
                [#:slant slant (or/c 'upright 'italic 'oblique) 'upright]) font-style?]{
Returns a @tech{font style} value, normalizing named weights and widths to their
numeric classes. This operation performs no font lookup or native allocation.

@racketblock[
(define style (make-font-style #:weight 'bold #:width 'condensed))
(list (font-style-weight style) (font-style-width style) (font-style-slant style))
]

The result is @racket['(700 3 upright)].
}

@defproc[(font-style-weight [style font-style?]) (integer-in 0 1000)]{
Returns the normalized numeric weight.
}

@defproc[(font-style-width [style font-style?]) (integer-in 1 9)]{
Returns the normalized numeric width class.
}

@defproc[(font-style-slant [style font-style?]) (or/c 'upright 'italic 'oblique)]{
Returns the slant symbol.
}

@defproc[(font-style-set? [v any/c]) boolean?]{
Returns @racket[#t] for an owned font-style-set resource and @racket[#f] otherwise.
}

@defproc[(make-empty-font-style-set) font-style-set?]{
Creates an owned style set with no entries. It still requires native Skia.
}

@defproc[(font-manager-style-set [manager font-manager?] [family string?]) font-style-set?]{
Returns an owned set of styles for @racket[family] in @racket[manager].
An unavailable family yields an empty set, not @racket[#f]. The NUL-free family
name, including its encoded terminator, must fit @racket[current-skia-byte-limit].
The set retains its own native reference and does not borrow the manager's lifetime.
}

@defproc[(font-manager-style-set-ref [manager font-manager?] [index (integer-in 0 #x7fffffff)])
          font-style-set?]{
Returns an owned style set for the zero-based family index in
@racket[manager]. An index outside the manager's enumeration raises an exception.
}

@defproc[(font-style-set-count [styles font-style-set?]) exact-nonnegative-integer?]{
Returns the number of entries in the open style set.
}

@defproc[(font-style-set-ref [styles font-style-set?] [index (integer-in 0 #x7fffffff)])
          font-style-entry?]{
Returns an immutable structure describing the indexed style, including its
immutable name string. The index must be less than
@racket[(font-style-set-count styles)].
}

@defproc[(font-style-set-styles [styles font-style-set?]) (vectorof font-style-entry?)]{
Returns an immutable vector of all style descriptions in enumeration order.
The copied descriptions and UTF-8 name bytes count toward
@racket[current-skia-byte-limit]; this is not an exact Racket heap-size estimate.
}

@defproc[(font-style-entry? [v any/c]) boolean?]{
Returns @racket[#t] for a style-entry description and @racket[#f] otherwise.
}

@defproc[(font-style-entry-index [entry font-style-entry?]) exact-nonnegative-integer?]{
Returns the entry's zero-based index in its originating style set.
}

@defproc[(font-style-entry-name [entry font-style-entry?]) (and/c string? immutable?)]{
Returns the copied style name. The name can be empty.
}

@defproc[(font-style-entry-style [entry font-style-entry?]) font-style?]{
Returns the weight, width, and slant description.
}

@defproc[(font-style-set-typeface [styles font-style-set?] [index (integer-in 0 #x7fffffff)])
          typeface?]{
Returns an owned typeface for the indexed style. An invalid index or
native creation failure raises an exception. The returned face is independent
of the set's wrapper lifetime.
}

@defproc[(font-style-set-match [styles font-style-set?] [pattern font-style? (make-font-style)])
          (or/c typeface? #f)]{
Returns an owned typeface matching @racket[pattern] in the set. An empty
set yields @racket[#f]. Native failure for a nonempty set raises an exception.
Matching selects an available style; it does not synthesize every requested style.
}

@defproc[(typeface-style [face typeface?]) font-style?]{
Returns a style description for the actual face.
}

@section{Copied Font Data and Metadata}

@(declare-exporting skia skia/typefaces #:use-sources (skia/typefaces))

@defproc[(typeface-from-bytes [data bytes?] [#:index index (integer-in 0 #x7fffffff) 0]) typeface?]{
Creates an owned typeface from copied font data. The input must be nonempty
and fit @racket[current-skia-byte-limit]. Later mutation or reclamation of
@racket[data] does not change the face. The index is zero-based within a font
collection. Invalid or unsupported font data and native failures raise exceptions.

For a TrueType collection, @racket[index] selects the requested member, including
on macOS. The operation does not silently substitute a different face.
}

@defproc[(font-manager-typeface-from-bytes [manager font-manager?] [data bytes?] [#:index index
          (integer-in 0 #x7fffffff) 0]) typeface?]{
Like @racket[typeface-from-bytes], but loads through @racket[manager]. The
manager is required and must be open; @racket[#f] does not select a default.
The result owns a native reference rather than borrowing the manager or input bytes.
}

@defproc[(typeface-postscript-name [face typeface?]) (or/c (and/c string? immutable?) #f)]{
Returns a copied PostScript name, or @racket[#f] when the native name is unavailable or empty.
}

@defproc[(typeface-fixed-pitch? [face typeface?]) boolean?]{
Reports the face's fixed-pitch property. This does not make shaped strings equally wide.
}

@defproc[(typeface-glyph-count [face typeface?]) exact-nonnegative-integer?]{
Returns the number of glyphs in the face, not the number of supported Unicode characters.
}

@defproc[(typeface-units-per-em [face typeface?]) (or/c exact-positive-integer? #f)]{
Returns the font's design units per em, or @racket[#f] when the native value is zero.
}

@defproc[(font-table-tag [tag (or/c (integer-in 0 #xffffffff) bytes? string?)]) (integer-in 0
          #xffffffff)]{
Returns a packed four-byte table tag. A byte string must contain exactly
four bytes. A string must contain exactly four Latin-1 characters; symbols are not accepted.
Packing uses the first byte as the most significant byte. Case and spaces
are significant; this operation does not check that a table exists.
}

@defproc[(font-table-tag->bytes [tag (integer-in 0 #xffffffff)]) (and/c bytes? immutable?)]{
Returns the immutable four-byte representation of the packed integer @racket[tag].
Unlike @racket[font-table-tag], this function accepts only an integer.

@racketblock[
(= (font-table-tag "head") #x68656164)
(bytes=? (font-table-tag->bytes (font-table-tag "OS/2")) #"OS/2")
]
}

@defproc[(typeface-table-tags [face typeface?]) (vectorof (integer-in 0 #xffffffff))]{
Returns an immutable vector of available table tags. The native order is
preserved; callers must not assume alphabetic ordering. A duplicate native tag
or inconsistent count raises an exception.
}

@defproc[(typeface-table-size [face typeface?] [tag (or/c (integer-in 0 #xffffffff) bytes?
          string?)]) (or/c exact-nonnegative-integer? #f)]{
Returns the byte length of the selected table, or @racket[#f] when absent.
An existing zero-length table returns 0, which is distinct from absence. The
tag has the representation accepted by @racket[font-table-tag].
}

@defproc[(typeface-table-bytes [face typeface?]
                [tag (or/c (integer-in 0 #xffffffff) bytes? string?)]
                [#:start start exact-nonnegative-integer? 0]
                [#:end end (or/c exact-nonnegative-integer? #f) #f]) (or/c (and/c bytes?
                immutable?) #f)]{
Returns a copied immutable byte string from @racket[start] inclusive to
@racket[end] exclusive, or @racket[#f] for an absent table. An omitted end uses
the table size. For an existing table the slice must satisfy
@math{0 <= start <= end <= size}, where size is the table's byte length.
An empty slice returns an empty byte string, not @racket[#f].

The requested slice must fit @racket[current-skia-byte-limit]. Invalid index
types or an explicit end before start are rejected even for an absent table.
A short native read raises an exception instead of returning partial data.
}

@defproc[(typeface-kerning-pair-adjustments [face typeface?] [glyphs (or/c (listof (integer-in 0
          #xffff)) (vectorof (integer-in 0 #xffff)))]) (or/c (vectorof exact-integer?) #f)]{
Returns an immutable vector of adjustments for successive glyph pairs,
measured in font design units, or @racket[#f] when native pair adjustments are
unavailable. With fewer than two glyphs the result is an empty vector. Every
glyph must be below the face's glyph count, including in a one-glyph input.

For @math{n} glyphs the nonempty result has @math{n - 1} entries.
This query is not a replacement for OpenType @tech{shaping} or contextual positioning;
use @racket[shape-text] for those operations.
}

@defproc[(typeface->font-bytes [face typeface?]) (values (and/c bytes? immutable?) (integer-in 0
          #x7fffffff))]{
Returns copied font data and its collection index as two values. The
native stream is closed before return. The byte string is independent of the
face's lifetime and is bounded by @racket[current-skia-byte-limit]. A face that
cannot expose usable font data raises an exception; the result is not promised
to reproduce the original file byte for byte.
}
