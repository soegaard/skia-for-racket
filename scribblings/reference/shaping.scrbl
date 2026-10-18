#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia))

@title[#:tag "skia-shaping"]{Shaped Text}

@(declare-exporting skia)

The process of @deftech{shaping} maps text to glyphs and positions using a
@tech{typeface}'s layout rules. It can combine characters into ligatures, select
contextual forms, position marks, and apply kerning. A @deftech{shaper} uses
HarfBuzz with one captured @tech{font}. A @deftech{shaped run} is an immutable
Racket structure containing @tech{glyph IDs}, @tech{cluster offsets}, positions,
and @tech{advances}. Drawing a run also requires its shaper.

Shaping one run is not paragraph layout. It does not choose fallback fonts,
split mixed scripts into separate runs, or apply the Unicode bidirectional
algorithm to an entire paragraph. Use @racket[layout-mixed-text] for those tasks.

@local-table-of-contents[#:style 'immediate-only]

@section[#:tag "Shapers_and_Shaped_Runs"]{Shaper Construction}

@defproc[(shaper? [v any/c]) boolean?]{
Returns @racket[#t] for a shaper resource and @racket[#f] otherwise. A closed shaper still
satisfies it.
}

@defproc[(make-shaper [font font?]) shaper?]{
Creates an owned shaper using a snapshot of @racket[font] and its typeface
data. Later mutation or closure of the original font does not change the shaper.
The captured font is also used when turning shaped runs into text blobs.

Construction requires native Skia, HarfBuzz, and usable font data. Copying the
font data is subject to @racket[current-skia-byte-limit]. An unsupported font
stream or native failure raises an exception; no substitute font is silently
installed. Closing the shaper releases its native shaping resources and private
font snapshot.

@racketblock[
(with-skia ([font (make-font #:size 24)]
            [shaper (make-shaper font)])
  (define before (shaped-run-advance-x (shape-text shaper "AB")))
  (font-set-size! font 48)
  (= before (shaped-run-advance-x (shape-text shaper "AB"))))
]

The result is @racket[#t]; changing the original font does not resize the shaper.
}

@section[#:tag "skia-shaped-text-drawing"]{Drawing Shaped Text}

@defproc[(draw-shaped-text [canvas canvas?] [shaper shaper?] [text string?] [x real?] [y real?]
          [paint paint?]
                [#:direction direction (or/c 'auto 'ltr 'rtl 'ttb 'btt) 'auto]
                [#:script script (or/c symbol? string? #f) #f]
                [#:language language (or/c string? #f) #f]
                [#:features features (or/c (listof string?) (vectorof string?)) '()]) shaped-run?]{
Shapes @racket[text] with @racket[shape-text], draws it with
@racket[draw-shaped-run], and returns the shaped run. All shaping options have
the same meaning as in @racket[shape-text].

@racketblock[
(with-skia ([surface (make-surface 240 80 #:background 'white)]
            [font (make-font #:size 28)]
            [shaper (make-shaper font)]
            [paint (make-paint #:color 'black)])
  (define run
    (draw-shaped-text (surface-canvas surface) shaper "office" 16 48 paint
                      #:direction 'ltr #:script 'latn #:language "en"))
  (save-png surface "shaped-text.png" #:exists 'replace)
  (shaped-run-glyph-count run))
]

@reference-figure["shaped-text.png"
                  "The word office drawn in black on a white background after Latin text shaping."]

The glyph count depends on the typeface and its shaping features.
}

@section[#:tag "skia-shaped-run-reuse"]{Shaping and Reusing Runs}

Use @racket[draw-shaped-text] to shape and draw text in one call. Use
@racket[shape-text] and @racket[draw-shaped-run] separately to inspect a run
before drawing or to draw it more than once. The shaper used for drawing must
match the font used to shape the run.

@defproc[(shape-text [shaper shaper?] [text string?]
                [#:direction direction (or/c 'auto 'ltr 'rtl 'ttb 'btt) 'auto]
                [#:script script (or/c symbol? string? #f) #f]
                [#:language language (or/c string? #f) #f]
                [#:features features (or/c (listof string?) (vectorof string?)) '()]) shaped-run?]{
Shapes @racket[text] with the captured font and returns a shaped run.
An empty string produces empty glyph, cluster, and position lists and zero
advances. Glyph zero denotes a missing glyph; this operation does not invoke
@tech{font fallback}.

HarfBuzz guesses unset segment properties from the input. An explicit direction
selects left-to-right, right-to-left, top-to-bottom, or bottom-to-top shaping.
The script is parsed from a symbol or string such as @racket['latn] or
@racket['arab]. The language is a NUL-free language-tag string, not a request
to find another font. The feature strings use HarfBuzz syntax, for example
@racket["kern=0"] or @racket["liga=1"]. Malformed feature strings are rejected;
a syntactically accepted feature need not be implemented by the selected font.

The glyph, cluster, and position lists have equal lengths and are in native
shaping order, which can differ from logical character order. Glyph count need
not equal character count. Returned glyph IDs must fit the unsigned 16-bit
Skia representation; an incompatible native result raises an exception.

A @deftech{cluster offset} is a UTF-8 byte offset into @racket[text] that associates
a glyph with its source text. It is not a Racket character index.
Multiple glyphs can share a cluster offset, and cluster offsets can descend in
right-to-left output. They are not a complete caret-position or selection map.

@racketblock[
(with-skia ([font (make-font #:size 24)]
            [shaper (make-shaper font)])
  (define text "éA")
  (define run (shape-text shaper text #:direction 'ltr #:script 'latn))
  (list (string-length text)
        (bytes-length (string->bytes/utf-8 text))
        (shaped-run-clusters run)))
]

The string has two Racket characters and three UTF-8 bytes. The cluster offset for the
second character starts at byte offset 2, not character index 1.

@bold{Conceptual diagram.} Characters, UTF-8 byte offsets, glyph IDs, and
stored glyph origins are distinct data. The first table shows @racket["éA"]:
character starts 0 and 1 correspond to byte starts 0 and 2.
A ligature can map multiple characters to one glyph only when the selected font
actually forms it; cluster starts are not a full caret map, and RTL starts can
descend.

@reference-figure["concept-text-clusters.png"
                  "A table aligns e-acute and A character entries with UTF-8 byte starts zero through one and two, glyph IDs, and cluster starts. A second row illustrates several characters mapping to one shaped glyph only for a verified ligature font."]

The run records glyph positions, not bounds. It contains no typeface identity
check that would make its glyph IDs portable to an unrelated shaper.


@racketblock[
(with-skia ([surface (make-surface 320 110 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([font (make-font #:size 38)]
              [shaper (make-shaper font)]
              [blue (make-paint #:color "#326DE6")]
              [orange (make-paint #:color "#EFA02B")])
    (define kerned (shape-text shaper "AVATAR" #:direction 'ltr #:script 'latn))
    (define unkerned (shape-text shaper "AVATAR" #:direction 'ltr #:script 'latn
                                 #:features '("kern=0")))
    (draw-shaped-run canvas shaper kerned 20 42 blue)
    (draw-shaped-run canvas shaper unkerned 20 94 orange)))
]
@reference-figure["shaping-kern-stage10.png"
                  "AVATAR is shaped with normal kerning in blue and with kerning disabled in orange."]
}

@defproc[(draw-shaped-run [canvas canvas?] [shaper shaper?] [run shaped-run?] [x real?] [y real?]
          [paint paint?]) void?]{
Draws the run with its origin translated by @racket[x] and @racket[y].
For a nonempty run, the canvas, shaper, and paint must satisfy their native-use
lifetime rules. The caller is responsible for matching the run to its shaping
font. The operation does not
close its arguments.

An empty run draws nothing. When outline output is selected, drawing has the
limitations of @racket[shaped-run->path].
}

@section[#:tag "skia-shaped-run-inspection"]{Inspecting Shaped Runs}

For drawing without inspecting glyph data, use @racket[draw-shaped-text] or
@racket[draw-shaped-run]. These accessors expose glyph IDs, cluster offsets,
positions, and advances. Glyph indices and UTF-8 byte offsets are not Racket
character indices.

@defproc[(shaped-run? [v any/c]) boolean?]{
Returns @racket[#t] for a shaped-run value and @racket[#f] otherwise.
}

@defproc[(shaped-run-glyphs [run shaped-run?]) (listof (integer-in 0 #xffff))]{
Returns the copied glyph IDs in shaping order, including zero for missing glyphs.
}

@defproc[(shaped-run-clusters [run shaped-run?]) (listof exact-nonnegative-integer?)]{
Returns UTF-8 byte offsets corresponding to the glyphs. For a run returned
by @racket[shape-text], these offsets refer to that call's input string, not an
entire paragraph containing the string.
}

@defproc[(shaped-run-positions [run shaped-run?]) (listof (list/c real? real?))]{
Returns glyph positions relative to the run origin. Horizontal positions
accumulate advances and include HarfBuzz x offsets, scaled by font size and
horizontal scale. Vertical positions accumulate the signed y advances and
subtract the scaled y offsets. The operation does not apply a canvas transform.

Vertical directions preserve the native signed advance convention; this API
does not automatically lay out vertical paragraphs in downward-positive canvas
coordinates. The paragraph-layout operations support horizontal text only.


@racketblock[
(with-skia ([surface (make-surface 320 110 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([font (make-font #:size 38)]
              [shaper (make-shaper font)]
              [text-paint (make-paint #:color "#20344E")]
              [mark (make-paint #:color "#E94F37")])
    (define run (shape-text shaper "office" #:direction 'ltr #:script 'latn))
    (draw-shaped-run canvas shaper run 20 62 text-paint)
    (for ([position (in-list (shaped-run-positions run))])
      (draw-circle canvas (+ 20 (car position)) (+ 62 (cadr position)) 2.5 mark))))
]
@reference-figure["shaped-positions-stage10.png"
                  "Small red dots mark the stored glyph origins beneath the shaped word office."]
}

@defproc[(shaped-run-advance-x [run shaped-run?]) real?]{
Returns the accumulated horizontal advance in drawing units. It is a
spacing quantity, not a tight ink width. Horizontal layouts use its absolute
value as the run's measure.

See the advance-versus-ink-bounds explanation in @secref["skia-font-metrics"].


@racketblock[
(with-skia ([surface (make-surface 320 100 #:background 'white)])
  (define canvas (surface-canvas surface))
  (with-skia ([font (make-font #:size 38)]
              [shaper (make-shaper font)]
              [text-paint (make-paint #:color "#20344E")]
              [rule (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 2)])
    (define run (shape-text shaper "Skia" #:direction 'ltr #:script 'latn))
    (define advance (abs (shaped-run-advance-x run)))
    (draw-shaped-run canvas shaper run 20 58 text-paint)
    (draw-line canvas 20 75 (+ 20 advance) 75 rule)))
]
@reference-figure["shaped-advance-stage10.png"
                  "A blue rule below the shaped word Skia visualizes the run horizontal advance."]
}

@defproc[(shaped-run-advance-y [run shaped-run?]) real?]{
Returns the accumulated native y advance, scaled by the captured font size.
The sign is retained, rather than automatically negated for a canvas with y
increasing downward. Ordinary horizontal runs generally have zero y advance.
}

@defproc[(shaped-run-glyph-count [run shaped-run?]) exact-nonnegative-integer?]{
Returns the number of glyph IDs in the run, not the number of characters or clusters.
}

@section[#:tag "Drawing_and_Converting_Shaped_Runs"]{Converting Shaped Runs}

Use @racket[draw-shaped-run] for direct drawing. Conversion is useful when a
caller needs a reusable @tech{text blob} or a @tech{path}. Each converted resource
has its own lifetime and must be released separately.

@defproc[(shaped-run->text-blob [shaper shaper?] [run shaped-run?]) text-blob?]{
Returns an owned text blob containing the run's glyphs and positions,
using the shaper's captured font. An empty run is rejected. The blob captures
its own font state and remains usable after the shaper is closed.

The caller must supply the shaper whose font gives meaning to the run's glyph
IDs; the run does not record enough information to verify that relationship.
}

@defproc[(shaped-run->path [shaper shaper?] [run shaped-run?]) skia-path?]{
Returns an owned path assembled from the run's available monochrome glyph
outlines at their stored positions. The run origin is zero. The shaper must
match the run's glyph IDs. Empty runs yield an empty path.

Glyphs without monochrome outlines are omitted; bitmap-only and color glyph
appearance is not preserved by this conversion. The path remains usable after
the shaper is closed and does not include paint settings.
}

@section{Additional Visual Examples}

@racketblock[
(with-skia ([surface (make-surface 300 110 #:background 'white)]
            [font (make-font #:size 34)] [shaper (make-shaper font)]
            [blue (make-paint #:color "#326DE6")]
            [orange (make-paint #:color "#EFA02B")])
  (define default-run (shape-text shaper "office" #:language "en"))
  (define no-liga-run (shape-text shaper "office" #:language "en"
                                  #:features '("liga=0")))
  (draw-shaped-run (surface-canvas surface) shaper default-run 20 42 blue)
  (draw-shaped-run (surface-canvas surface) shaper no-liga-run 20 92 orange))
]
@reference-figure["ligature-shaping.png"
                  "The word office shaped once with default features and once with standard ligatures disabled; the exact difference is font-dependent."]

The following example selects one Hebrew-capable face, verifies every non-space glyph before
shaping, and keeps that one face for the whole run. It does not use mixed-text fallback.

@racketblock[
(with-skia ([surface (make-surface 260 90 #:background 'white)]
            [manager (make-font-manager)])
  (define hebrew "שלום")
  (define face (font-manager-match-character manager #\ש #:languages '("he")))
  (unless face (error 'hebrew-example "no Hebrew-capable typeface is available"))
  (with-skia ([hebrew-face face]
              [font (make-font hebrew-face #:size 36)] [shaper (make-shaper font)]
              [paint (make-paint #:color "#20344E")])
    (unless (for/and ([char (in-string hebrew)]) (positive? (font-char->glyph font char)))
      (error 'hebrew-example "the selected typeface does not cover the displayed text"))
    (define run (shape-text shaper hebrew #:direction 'rtl #:script 'hebr))
    (with-skia ([blob (shaped-run->text-blob shaper run)])
      (define-values (_left _top right _bottom) (text-blob-bounds blob))
      (draw-shaped-run (surface-canvas surface) shaper run (- 230 right) 58 paint))))
]
@reference-figure["rtl-shaping.png"
                  "The Hebrew word שלום is shaped with one verified Hebrew-capable face; its right ink edge is aligned to the guide position rather than treating the supplied baseline origin as a right-edge anchor."]

The x coordinate is calculated from the run's actual bounds, so right-to-left shaping alone is
not mistaken for right-edge anchoring. Regeneration records the selected face and native versions.

@racketblock[
(with-skia ([surface (make-surface 240 110 #:background 'white)]
            [font (make-font #:size 60)] [shaper (make-shaper font)]
            [paint (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 2)])
  (define run (shape-text shaper "Skia" #:direction 'ltr #:script 'latn))
  (with-skia ([path (shaped-run->path shaper run)])
    (with-canvas-state (surface-canvas surface)
      (canvas-translate! (surface-canvas surface) 20 78)
      (draw-path (surface-canvas surface) path paint))))
]
@reference-figure["shaped-outline.png"
                  "The shaped word Skia drawn as blue stroked glyph outlines rather than as native text."]
