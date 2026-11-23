#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia))

@title[#:tag "skia-shaping"]{Shaped Text}

@(declare-exporting skia)

Use shaped text when direct character-to-glyph mapping is insufficient, for
example for Arabic letter forms, combining marks, or ligatures. For a single
drawing, @racket[draw-shaped-text] performs shaping and drawing together.

The process of @deftech{shaping} maps text to glyphs and positions using a
@tech{typeface}'s layout rules. It can combine characters into ligatures, select
contextual forms, position marks, and apply kerning. A @deftech{shaper} uses
HarfBuzz with one captured @tech{font}. A @deftech{shaped run} is an immutable
Racket structure containing @tech{glyph IDs}, @tech{cluster offsets}, positions,
and @tech{advances}, together with its original text and resolved direction.
It also remembers the shaper that created it.

Shaping one run is not paragraph layout. It does not choose fallback fonts,
split mixed scripts into separate runs, or apply the Unicode bidirectional
algorithm to an entire paragraph. Use @racket[layout-mixed-text] for those tasks.

@local-table-of-contents[#:style 'immediate-only]

@section[#:tag "skia-shaper-construction"]{Shaper Construction}

@defproc[(shaper? [v any/c]) boolean?]{
Returns @racket[#t] for a shaper resource and @racket[#f] otherwise. A closed shaper still
satisfies it.
}

@defproc[(make-shaper [font font?]) shaper?]{
Creates an owned shaper using a snapshot of @racket[font] and its typeface
data. Later mutation or closure of the original font does not change the shaper.
The captured font is also used when turning shaped runs into @tech{text blobs}.

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
before drawing or to draw it more than once.

A run remembers its originating shaper; drawing and conversion do not take a
second shaper argument. That shaper must remain open for these operations,
including for an empty run. Closing it does not prevent inspection of the
run's immutable text and glyph data. To reuse drawing after closing the shaper,
convert the run to an independently owned @tech{text blob} first.

@defproc[(shape-text [shaper shaper?] [text string?]
                [#:direction direction (or/c 'auto 'ltr 'rtl 'ttb 'btt) 'auto]
                [#:script script (or/c symbol? string? #f) #f]
                [#:language language (or/c string? #f) #f]
                [#:features features (or/c (listof string?) (vectorof string?)) '()]) shaped-run?]{
Shapes @racket[text] with the captured font and returns a shaped run.
An empty string produces empty glyph, cluster, and position vectors and zero
advances. Glyph zero denotes a missing glyph; this operation does not invoke
@tech{font fallback}.

HarfBuzz guesses unset segment properties from the input. An explicit direction
selects left-to-right, right-to-left, top-to-bottom, or bottom-to-top shaping.
The script is parsed from a symbol or string such as @racket['latn] or
@racket['arab]. The language is a NUL-free language-tag string, not a request
to find another font. The feature strings use HarfBuzz syntax, for example
@racket["kern=0"] or @racket["liga=1"]. Malformed feature strings are rejected;
a syntactically accepted feature need not be implemented by the selected font.

The glyph, cluster, and position vectors have equal lengths and are in native
shaping order, which can differ from logical character order. Glyph count need
not equal character count. Returned glyph IDs must fit the unsigned 16-bit
Skia representation; an incompatible native result raises an exception.

The run records glyph positions, not bounds. For the meaning of its source-text
offsets, see @secref["skia-text-indices"].


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
    (draw-shaped-run canvas kerned 20 42 blue)
    (draw-shaped-run canvas unkerned 20 94 orange)))
]
@reference-figure["shaping-kern-stage10.png"
                  "AVATAR is shaped with normal kerning in blue and with kerning disabled in orange."]

@racketblock[
(with-skia ([surface (make-surface 300 110 #:background 'white)]
            [font (make-font #:size 34)] [shaper (make-shaper font)]
            [blue (make-paint #:color "#326DE6")]
            [orange (make-paint #:color "#EFA02B")])
  (define default-run (shape-text shaper "office" #:language "en"))
  (define no-liga-run (shape-text shaper "office" #:language "en"
                                  #:features '("liga=0")))
  (draw-shaped-run (surface-canvas surface) default-run 20 42 blue)
  (draw-shaped-run (surface-canvas surface) no-liga-run 20 92 orange))
]
@reference-figure["ligature-shaping.png"
                  "The word office shaped once with default features and once with standard ligatures disabled; the exact difference is font-dependent."]
}

@defproc[(draw-shaped-run [canvas canvas?] [run shaped-run?] [x real?] [y real?]
          [paint paint?]) void?]{
Draws the run with its origin translated by @racket[x] and @racket[y].
The canvas, paint, and run's originating shaper must be usable, even for
an empty run. The operation does not close its arguments.

An empty run draws nothing. When outline output is selected, drawing has the
limitations of @racket[shaped-run->path].

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
    (with-skia ([blob (shaped-run->text-blob run)])
      (define-values (left _top width _height) (vector->values (text-blob-bounds blob)))
      (draw-shaped-run (surface-canvas surface) run (- 230 (+ left width)) 58 paint))))
]
@reference-figure["rtl-shaping.png"
                  "The Hebrew word שלום is shaped with one verified Hebrew-capable face; the right edge of its blob bounds is aligned at x = 230 rather than treating the supplied baseline origin as a right-edge anchor."]

Right-to-left shaping does not make the drawing origin a right-edge anchor.
@racket[text-blob-bounds] returns x, y, width, and height; the right edge is
@racket[(+ left width)], not @racket[width] alone. Subtracting that edge from
230 places the right edge of the blob's bounds at x = 230. These bounds can be
conservative; they are not necessarily tight ink bounds.
}

@section[#:tag "skia-text-indices"]{Text Indices and Cluster Offsets}

A @deftech{cluster offset} is a UTF-8 byte offset that associates a glyph with
its source text. For @racket[shape-text], it indexes the string supplied to that
call. It is not a Racket character index.
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

The APIs in this chapter use different units and source strings for text
positions:

@tabular[#:sep @hspace[2]
 (list
  (list @bold{Source of the position} @bold{Unit and source text})
  (list @racket[shaped-run-clusters]
        @elem{UTF-8 byte offsets into the string passed to @racket[shape-text].})
  (list @racket[text-run-info-clusters]
        @elem{UTF-8 byte offsets into the optional text metadata for that blob run.})
  (list @racket[mixed-text-run-shaped-run]
        @elem{Cluster byte offsets within that run's text, not the full paragraph.})
  (list @tech{break provider}
        @elem{Racket character indices within the paragraph passed to the provider.}))]

Do not use a cluster offset directly with @racket[string-ref] or
@racket[substring], which expect character indices. A glyph's position is a
drawing coordinate, not either kind of text index. Layout source maps use
character ranges in the original input; see
@secref["skia-layout-inspection"].

@section[#:tag "skia-shaped-run-inspection"]{Inspecting Shaped Runs}

For drawing without inspecting glyph data, use @racket[draw-shaped-text] or
@racket[draw-shaped-run]. These accessors expose @tech{glyph IDs}, @tech{cluster offsets},
positions, and @tech{advances}. Glyph indices and UTF-8 byte offsets are not Racket
character indices.

@defproc[(shaped-run? [v any/c]) boolean?]{
Returns @racket[#t] for a shaped-run value and @racket[#f] otherwise.
}

@defproc[(shaped-run-text [run shaped-run?]) (and/c string? immutable?)]{
Returns the logical text used to shape this run. Cluster offsets index its UTF-8
encoding. For a justified layout run, display-only Arabic elongations are
mapped back to this logical text.
}

@defproc[(shaped-run-direction [run shaped-run?]) (or/c 'ltr 'rtl 'ttb 'btt)]{
Returns the resolved shaping direction, including when @racket['auto] was
requested. An empty automatically directed run uses @racket['ltr].
}

@defproc[(shaped-run-glyphs [run shaped-run?]) (and/c (vectorof (integer-in 0 #xffff)) immutable?)]{
Returns the glyph IDs in shaping order, including zero for missing glyphs.
}

@defproc[(shaped-run-clusters [run shaped-run?]) (and/c (vectorof exact-nonnegative-integer?) immutable?)]{
Returns UTF-8 byte offsets corresponding to the glyphs. For a run returned
by @racket[shape-text], these offsets refer to that call's input string, not an
entire paragraph containing the string.
}

@defproc[(shaped-run-positions [run shaped-run?]) (and/c (vectorof (and/c (vector/c real? real?) immutable?)) immutable?)]{
Returns glyph positions as immutable @racket[#(x y)] vectors relative to the run origin. Horizontal positions
accumulate advances and include HarfBuzz x offsets, scaled by font size and
horizontal scale. Vertical positions accumulate the signed y advances and
subtract the scaled y offsets. The operation does not apply a @tech{canvas transform}.

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
    (draw-shaped-run canvas run 20 62 text-paint)
    (for ([position (in-vector (shaped-run-positions run))])
      (draw-circle canvas (+ 20 (vector-ref position 0)) (+ 62 (vector-ref position 1)) 2.5 mark))))
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
    (draw-shaped-run canvas run 20 58 text-paint)
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

@section[#:tag "skia-shaped-run-conversion"]{Converting Shaped Runs}

Use @racket[draw-shaped-run] for direct drawing. Conversion is useful when a
caller needs a reusable @tech{text blob} or a @tech{path}. Each converted resource
has its own lifetime and must be released separately.

@defproc[(shaped-run->text-blob [run shaped-run?]) (or/c text-blob? #f)]{
Returns an owned text blob containing the run's glyphs, positions, source text,
and cluster offsets, using its originating shaper's font. An empty run returns
@racket[#f]. The originating shaper must be open.

The blob captures its own font state and remains usable after the shaper is closed.
}

@defproc[(shaped-run->path [run shaped-run?]
          [#:missing-outline missing-outline (or/c 'error 'skip) 'error]) skia-path?]{
Converts the run's monochrome glyph outlines to an owned path at their stored
positions. The originating shaper must be open. The run origin is zero;
empty runs yield an empty path.

A glyph with visible bounds but no monochrome outline raises an exception by
default. Use @racket[#:missing-outline 'skip] to omit such glyphs deliberately.
Spaces and other glyphs with no visible bounds contribute no contours.
See @secref["skia-text-outline-policy"] for the shared conversion rule.
The path remains usable after the shaper is closed and does not include paint settings.

@racketblock[
(with-skia ([surface (make-surface 240 110 #:background 'white)]
            [font (make-font #:size 60)] [shaper (make-shaper font)]
            [paint (make-paint #:color "#326DE6" #:style 'stroke #:stroke-width 2)])
  (define run (shape-text shaper "Skia" #:direction 'ltr #:script 'latn))
  (with-skia ([path (shaped-run->path run)])
    (with-canvas-state (surface-canvas surface)
      (canvas-translate! (surface-canvas surface) 20 78)
      (draw-path (surface-canvas surface) path paint))))
]
@reference-figure["shaped-outline.png"
                  "The shaped word Skia drawn as blue stroked glyph outlines rather than as native text."]
}
