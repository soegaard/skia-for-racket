#lang scribble/manual

@(require "support/figures.rkt"
          (for-label racket/base racket/contract skia))

@title[#:tag "skia-text-layout"]{Text Layout}

@(declare-exporting skia)

A @deftech{text layout} arranges @tech{shaped runs} into horizontal lines. The layout
origin is the upper-left corner of its layout box, not the @tech{baseline} origin
used by @racket[draw-simple-text] and @racket[draw-shaped-text]. The line records
supply baseline positions relative to that box.

For the baseline-relative @tech{font metrics} that determine a layout's first baseline
and reported height, see @secref["skia-font-metrics"].

Layout values and their line records are ordinary Racket values, not resources
to close with @racket[skia-close!]. A layout keeps its required shaper and, for
mixed text, its font manager reachable. Both must remain open when the layout
is drawn. Retaining a reference does not prevent explicit closure.

@local-table-of-contents[#:style 'immediate-only]

Use @racket[layout-text] and @racket[draw-text-layout] for a single-font layout.
Use @racket[layout-mixed-text] and @racket[draw-mixed-text-layout] when text needs
mixed-direction paragraph layout or font fallback.

@section{Single-Font Layout}

@defproc[(layout-text [shaper shaper?] [text string?]
                [#:width width (or/c (and/c real? (>/c 0)) #f) #f]
                [#:align align (or/c 'start 'center 'end 'left 'right 'justify 'justify-all) 'start]
                [#:direction direction (or/c 'auto 'ltr 'rtl) 'auto]
                [#:script script (or/c symbol? string? #f) #f]
                [#:language language (or/c string? #f) #f]
                [#:features features (or/c (listof string?) (vectorof string?)) '()]
                [#:break-provider break-provider
                 (or/c #f (-> string? (or/c string? #f)
                              (listof (or/c exact-nonnegative-integer?
                                            layout-break-opportunity?)))) #f]
                [#:line-height line-height (or/c (and/c real? (>/c 0)) #f) #f]) text-layout?]{
Returns a layout using one shaper and the rules in
@secref["skia-layout-options"]. Width and line height, when supplied, must be
positive drawing scalars. Script, language, and features are interpreted as
in @racket[shape-text]. A language string must not contain NUL.

For justification, an explicit @racket[#:script] affects shaping but does not
enable the script-specific CJK or Arabic expansion opportunities. Those
opportunities can be detected through script inference when @racket[#:script]
is @racket[#f].

Each line is shaped as a single run. This does not provide font fallback or
full mixed-direction paragraph layout. With automatic direction, the line's
alignment direction is inferred from descending cluster offsets; empty and
one-glyph runs default to LTR. Supply an explicit direction when that ambiguity
matters, or use @racket[layout-mixed-text] for paragraph bidi resolution.

The layout keeps the shaper, not the original font supplied to @racket[make-shaper].
It is not an independent native text blob. Drawing it after closing the shaper
raises an exception, including for an empty line.

@racketblock[
(with-skia ([surface (make-surface 320 90 #:background 'white)]
            [font (make-font #:size 24)]
            [shaper (make-shaper font)]
            [paint (make-paint #:color "#20344E")]
            [guide (make-paint #:color "#EFA02B" #:style 'stroke #:stroke-width 1)])
  (define text "unbreakable")
  (define natural (abs (shaped-run-advance-x (shape-text shaper text))))
  (define requested (max 1 (/ natural 2)))
  (define layout (layout-text shaper text #:width requested))
  (define canvas (surface-canvas surface))
  (draw-line canvas (+ 20 requested) 18 (+ 20 requested) 72 guide)
  (draw-text-layout canvas layout 20 25 paint)
  (list (text-layout-line-count layout) (text-layout-width layout)))
]

@reference-figure["layout-unbreakable-overflow.png"
                  "The actual one-line layout for the unbreakable word, with an orange vertical guide at the requested half-natural width. The word visibly extends beyond the guide without being clipped."]

The guide marks the requested layout width, not a canvas clip. The whole word
stays visible on one line, even though its advance exceeds the requested width.


@racketblock[
(with-skia ([surface (make-surface 300 100 #:background 'white)]
            [manager (make-font-manager)])
  (define hebrew "אבג דהו זחט")
  (define face (font-manager-match-character manager #\א #:languages '("he")))
  (unless face (error 'hebrew-layout "no Hebrew-capable typeface is available"))
  (with-skia ([hebrew-face face]
              [font (make-font hebrew-face #:size 22)]
              [shaper (make-shaper font)]
              [paint (make-paint #:color "#20344E")])
    (unless (for/and ([char (in-string hebrew)] #:unless (char-whitespace? char))
              (positive? (font-char->glyph font char)))
      (error 'hebrew-layout "the selected typeface does not cover the displayed text"))
    (define layout
      (layout-text shaper hebrew #:width 260 #:direction 'rtl #:align 'start))
    (draw-text-layout (surface-canvas surface) layout 20 18 paint)))
]
@reference-figure["layout-rtl-stage8.png"
                  "A Hebrew line rendered with one verified Hebrew-capable face uses right-to-left start alignment at the right side of its layout box."]

The selected face must cover every displayed non-space character; it is not a request for
per-character fallback.

@racketblock[
(with-skia ([surface (make-surface 360 90 #:background 'white)]
            [font (make-font #:size 18)]
            [shaper (make-shaper font)]
            [paint (make-paint #:color "#20344E")])
  (define layout
    (layout-text shaper "Wrapping is disabled for this long single line."
                 #:width #f))
  (draw-text-layout (surface-canvas surface) layout 10 20 paint))
]
@reference-figure["layout-nowrap-stage8.png"
                  "A long sentence stays on one line because wrapping is disabled with a false width."]
}

@defproc[(draw-text-layout [canvas canvas?] [layout text-layout?] [x real?] [y real?] [paint
          paint?]) void?]{
Draws the layout box with origin at the drawing scalars @racket[x] and
@racket[y], using each line's stored x offset and baseline. The canvas transform
and existing clip apply; this operation does not clip to the box or reflow text.
The layout's shaper must remain open. Temporary blobs or paths are released by
the underlying shaped-run drawing operations.

@racketblock[
(with-skia ([surface (make-surface 260 150 #:background 'white)]
            [font (make-font #:size 20)]
            [shaper (make-shaper font)]
            [paint (make-paint #:color 'black)])
  (define layout (layout-text shaper "A short paragraph with several words."
                              #:width 220 #:line-height 28))
  (draw-text-layout (surface-canvas surface) layout 20 16 paint)
  (save-png surface "text-layout.png" #:exists 'replace))
]

@reference-figure["text-layout.png"
                  "A short black paragraph wrapped into several lines inside a 220-unit layout width."]

@racketblock[
(with-skia ([surface (make-surface 320 125 #:background 'white)]
            [font (make-font #:size 18)]
            [shaper (make-shaper font)]
            [paint (make-paint #:color "#20344E")])
  (define layout
    (layout-text shaper
                 "Skia makes drawing fast, portable, and expressive."
                 #:width 280 #:align 'justify-all #:line-height 28))
  (draw-text-layout (surface-canvas surface) layout 20 15 paint))
]

@reference-figure["justified-text.png"
                  "A short paragraph whose lines are expanded to fill a 280-unit justified layout width."]
}

@section[#:tag "skia-mixed-layout"]{Mixed Scripts and Directions}

Mixed-text layout resolves bidirectional embedding levels for each whole
paragraph before wrapping, then applies line-dependent reordering. It groups
compatible script, direction, and font choices into shaped runs. Explicit bidi
controls affect this resolution rather than becoming ordinary drawn glyphs.

With @deftech{font fallback}, the supplied @tech{font manager} selects alternative
typefaces for grapheme clusters that need them.
A selected face is not guaranteed to cover every character of a cluster; a
missing fallback can still leave glyph zero. Matching may depend on language
and the machine's font configuration. This is not a promise that every Unicode
string has a complete installed font.

@defproc[(layout-mixed-text [shaper shaper?] [manager font-manager?] [text string?]
                [#:width width (or/c (and/c real? (>/c 0)) #f) #f]
                [#:align align (or/c 'start 'center 'end 'left 'right 'justify 'justify-all) 'start]
                [#:direction direction (or/c 'auto 'ltr 'rtl) 'auto]
                [#:language language (or/c string? #f) #f]
                [#:features features (or/c (listof string?) (vectorof string?)) '()]
                [#:break-provider break-provider
                 (or/c #f (-> string? (or/c string? #f)
                              (listof (or/c exact-nonnegative-integer?
                                            layout-break-opportunity?)))) #f]
                [#:line-height line-height (or/c (and/c real? (>/c 0)) #f) #f]) mixed-text-layout?]{
Returns a mixed-script, mixed-direction layout with font fallback. The
base shaper supplies the primary font and metrics; the manager supplies fallback
families. Wrapping, alignment, feature strings, language, break-provider behavior,
and line-height rules follow @secref["skia-layout-options"]. Vertical directions
are not accepted, and there is no single forced-script keyword.

Automatic direction resolves each paragraph's base direction from its text.
Run records are in visual order within each line. Their cluster offsets are
relative to individual run text, not global paragraph positions.

The result keeps the base shaper and font manager reachable. Fallback families
and styles are recorded for later lookup; it does not own a permanent native
font for every fallback run. Both the shaper and manager must remain open when
drawing. Changes in available fonts can affect later drawing or make a recorded
fallback family unavailable.

@racketblock[
(with-skia ([font (make-font #:size 20)]
            [shaper (make-shaper font)]
            [manager (make-font-manager)])
  (define layout (layout-mixed-text shaper manager "ABC אבג 123" #:width 240))
  (for/list ([line (in-list (mixed-text-layout-lines layout))])
    (map mixed-text-run-direction (mixed-text-line-runs line))))
]

The run directions expose reordering independently of whether the chosen fonts
contain every glyph.
}

@defproc[(draw-mixed-text-layout [canvas canvas?] [layout mixed-text-layout?] [x real?] [y real?]
          [paint paint?]) void?]{
Draws the stored layout at its upper-left box origin. The coordinates must
be drawing scalars. The base shaper and font manager must be open, even for an
empty line. The canvas transform and existing clip apply without an added box
clip or automatic reflow.

Fallback fonts and shapers are created as needed during this call and released
on return or exceptional exit. Failure to recover a recorded fallback family
raises an exception. Drawing is not transactional: earlier runs may already
have changed the canvas before a later failure.

@racketblock[
(with-skia ([surface (make-surface 300 90 #:background 'white)]
            [font (make-font #:size 22)]
            [shaper (make-shaper font)]
            [manager (make-font-manager)]
            [paint (make-paint #:color 'black)])
  (define layout
    (layout-mixed-text shaper manager "ABC אבג 123" #:width 260))
  (draw-mixed-text-layout (surface-canvas surface) layout 20 20 paint))
]

@reference-figure["mixed-text-layout.png"
                  "A single mixed-direction line containing Latin ABC, Hebrew letters, and the digits 123 in their resolved visual order."]
}

@section[#:tag "skia-layout-options"]{Wrapping and Alignment}

A positive @racket[#:width] enables greedy wrapping at Unicode line-break
opportunities. An optional @tech{break provider} can add more opportunities.
An unbreakable span stays on one line even when it exceeds the requested width.
The reported box width is the greater of the requested width and the largest
line advance; it is not a clipping boundary.
The drawing operations do not add a clip around the layout box.

Hard line separators delimit paragraphs and are not drawn. Empty paragraphs
and trailing hard breaks retain empty lines. With wrapping disabled by
@racket[#:width #f], leading and trailing whitespace is preserved. With wrapping
enabled, breakable whitespace at selected boundaries is trimmed; no-break spaces
remain part of the text. A break provider is not invoked when wrapping is disabled.

The alignment choices are:

@tabular[#:sep @hspace[2]
 (list
  (list @bold{Alignment} @bold{Placement})
  (list @indexed-racket['left] "Place every line at the left of the box.")
  (list @indexed-racket['right] "Place every line at the right of the box.")
  (list @indexed-racket['center] "Center each line's advance interval.")
  (list @indexed-racket['start] "Use the left for LTR lines and the right for RTL lines.")
  (list @indexed-racket['end] "Use the right for LTR lines and the left for RTL lines.")
  (list @indexed-racket['justify] "Expand eligible lines except the last line of each paragraph.")
  (list @indexed-racket['justify-all] "Expand eligible lines including paragraph-final lines."))]

The @deftech{justification} modes expand eligible lines toward the requested
width. Both require a positive width. They do not shrink lines
that are already too wide. Lines without expandable opportunities keep their
natural @tech{advance} and use start alignment. Alignment concerns advances, not tight
ink bounds; glyph overhang can extend beyond the nominal box.

Justification can expand ordinary U+0020 spaces. Script-specific processing can
also expand boundaries between adjacent CJK grapheme clusters and elongate
Arabic joining positions by shaping inserted tatweel characters. Common CJK
punctuation is not itself an expansion point. Arabic insertions are display-only;
@tech{cluster offsets} are remapped to the logical line text. This does not replace
that text with a string containing the inserted elongations.

For @racket[layout-text], CJK and Arabic opportunity detection uses script
inference when @racket[#:script] is @racket[#f]. An explicit script is passed
to shaping but does not enable these script-specific justification opportunities.
Mixed-text layout instead determines scripts for its individual runs.

The baseline step is @racket[#:line-height] when supplied. Otherwise it uses a
positive native font spacing, or a fallback of at least one drawing unit based
on @tech{ascent}, @tech{descent}, and nonnegative @tech{leading}. An explicitly small positive line
height is allowed and can make lines overlap. The first baseline is at
@math{max(0, -ascent)}. For @math{n} lines, the reported height is
@math{max(0, -ascent) + (n - 1) line-height + max(0, descent)}.
These metrics come from the base font, not a union of every fallback glyph's ink.

@bold{Conceptual diagram.} A layout is drawn from its box origin, not from a
text baseline. The top panel separates the first baseline, baseline-to-baseline
step, and reported metric height. The lower panel shows that requested wrapping
width is not a canvas clip: an unbreakable word can make the reported layout box
wider and remains fully drawable.

@reference-figure["concept-layout-box.png"
                  "An annotated three-line layout box marks its upper-left origin, first baseline, baseline-to-baseline line height, and reported height. A second panel shows an unbreakable word continuing past a requested-width guide without clipping."]

@section[#:tag "skia-layout-inspection"]{Inspecting Layouts}

Use @racket[draw-text-layout] or @racket[draw-mixed-text-layout] to draw a complete
layout. These accessors expose its dimensions, lines, and runs for callers that
need to inspect placement. Inspection does not reflow text or keep the required
shaper and font manager open.

@subsection{Single-Font Layout Records}

@defproc[(text-layout? [v any/c]) boolean?]{
Returns @racket[#t] for a single-font text-layout value and @racket[#f] otherwise.
}

@defproc[(text-layout-lines [layout text-layout?]) (listof text-layout-line?)]{
Returns the line records in top-to-bottom order.
}

@defproc[(text-layout-width [layout text-layout?]) real?]{
Returns the layout-box width, which can exceed the requested wrapping width.
}

@defproc[(text-layout-height [layout text-layout?]) real?]{
Returns the metric-based layout-box height, not a tight ink bound.
}

@defproc[(text-layout-line-height [layout text-layout?]) real?]{
Returns the chosen baseline-to-baseline step.
}

@defproc[(text-layout-line-count [layout text-layout?]) exact-nonnegative-integer?]{
Returns the number of line records, including retained empty lines.
}

@defproc[(text-layout-line? [v any/c]) boolean?]{
Returns @racket[#t] for a single-font line record and @racket[#f] otherwise.
}

@defproc[(text-layout-line-text [line text-layout-line?]) string?]{
Returns the selected line text, including a break-provider insertion when that break is used.
Wrapping may remove boundary whitespace; this is not necessarily a verbatim input slice.
}

@defproc[(text-layout-line-run [line text-layout-line?]) shaped-run?]{
Returns the positioned run for the line, including any justification adjustments.
}

@defproc[(text-layout-line-origin-x [line text-layout-line?]) real?]{
Returns the line's horizontal offset from the layout-box origin.
}

@defproc[(text-layout-line-baseline [line text-layout-line?]) real?]{
Returns the baseline y coordinate relative to the layout-box origin.
}

@defproc[(text-layout-line-width [line text-layout-line?]) real?]{
Returns the line's horizontal advance measure after @tech{justification}, not its tight ink width.
}

@defproc[(text-layout-line-direction [line text-layout-line?]) (or/c 'ltr 'rtl)]{
Returns the direction used for start/end alignment of this line.
}

@subsection{Mixed-Text Layout Records}

@defproc[(mixed-text-layout? [v any/c]) boolean?]{
Returns @racket[#t] for a mixed-text-layout value and @racket[#f] otherwise.
}

@defproc[(mixed-text-layout-lines [layout mixed-text-layout?]) (listof mixed-text-line?)]{
Returns the line records in top-to-bottom order.
}

@defproc[(mixed-text-layout-width [layout mixed-text-layout?]) real?]{
Returns the layout-box width based on line advances and the requested width.
}

@defproc[(mixed-text-layout-height [layout mixed-text-layout?]) real?]{
Returns the box height computed from base-font metrics and the chosen line step.
}

@defproc[(mixed-text-layout-line-height [layout mixed-text-layout?]) real?]{
Returns the baseline-to-baseline step.
}

@defproc[(mixed-text-layout-line-count [layout mixed-text-layout?]) exact-nonnegative-integer?]{
Returns the number of lines, including retained empty lines.
}

@defproc[(mixed-text-line? [v any/c]) boolean?]{
Returns @racket[#t] for a mixed-text line record and @racket[#f] otherwise.
}

@defproc[(mixed-text-line-text [line mixed-text-line?]) string?]{
Returns the selected logical line text, including any selected break insertion.
It is not reordered into visual character order.
}

@defproc[(mixed-text-line-runs [line mixed-text-line?]) (listof mixed-text-run?)]{
Returns the line's shaped runs in visual order.
}

@defproc[(mixed-text-line-origin-x [line mixed-text-line?]) real?]{
Returns the line's horizontal offset from the layout-box origin.
}

@defproc[(mixed-text-line-baseline [line mixed-text-line?]) real?]{
Returns the baseline y coordinate relative to the layout-box origin.
}

@defproc[(mixed-text-line-width [line mixed-text-line?]) real?]{
Returns the line's advance measure after justification.
}

@defproc[(mixed-text-line-direction [line mixed-text-line?]) (or/c 'ltr 'rtl)]{
Returns the line's resolved paragraph direction for alignment.
}

@defproc[(mixed-text-run? [v any/c]) boolean?]{
Returns @racket[#t] for a mixed-text run record and @racket[#f] otherwise.
}

@defproc[(mixed-text-run-text [run mixed-text-run?]) string?]{
Returns the logical text shaped for this run. Bidi formatting controls may
have been removed; the text is not a source-position map.
}

@defproc[(mixed-text-run-shaped-run [run mixed-text-run?]) shaped-run?]{
Returns the copied glyphs, cluster offsets, positions, and advances. Cluster
offsets refer to this run's text, not the original complete paragraph.
}

@defproc[(mixed-text-run-origin-x [run mixed-text-run?]) real?]{
Returns the run's x offset within its line, before adding the line and layout origins.
}

@defproc[(mixed-text-run-width [run mixed-text-run?]) real?]{
Returns the run's horizontal advance measure after any justification adjustments.
}

@defproc[(mixed-text-run-direction [run mixed-text-run?]) (or/c 'ltr 'rtl)]{
Returns the direction used to shape the run.
}

@defproc[(mixed-text-run-level [run mixed-text-run?]) exact-nonnegative-integer?]{
Returns the resolved bidi embedding level. Odd levels indicate right-to-left runs.
}

@defproc[(mixed-text-run-script [run mixed-text-run?]) (or/c symbol? #f)]{
Returns the inferred script tag, or @racket[#f] when no specific script is selected.
}

@defproc[(mixed-text-run-family [run mixed-text-run?]) (or/c string? #f)]{
Returns the recorded fallback family name, or @racket[#f] when the base shaper
is used. A false result is not itself proof of complete glyph coverage.
}

@section{Additional Break Opportunities}

Use @racket[layout-text] or @racket[layout-mixed-text] with @racket[#:width] for
ordinary Unicode line breaking. Supply a @racket[#:break-provider] only when
additional break positions or display insertions are needed. The provider
must return valid paragraph-relative positions, as described in this section.

A @deftech{break provider} supplements Unicode line breaking; it does not replace it.
The provider receives a hard-break-delimited paragraph string and the requested
language, and returns a list of integer positions or @tech{break opportunity} values.
Positions are Racket character indices within that paragraph, not UTF-8 offsets
and not indices in the whole multi-paragraph input.

Each position must be strictly inside the paragraph and at a default grapheme
boundary. Duplicate positions with the same insertion are accepted; conflicting
insertions at the same position are rejected. Returned order does not matter.
An insertion is rendered only when that break is selected and is included when
measuring the candidate line. It does not modify the caller's input string.
The provider may be invoked while measuring layout candidates; it should return
consistent results without depending on an exact invocation count.

@defproc[(layout-break-opportunity? [v any/c]) boolean?]{
Returns @racket[#t] for a break-opportunity value and @racket[#f] otherwise.
}

@defproc[(make-layout-break-opportunity [index exact-nonnegative-integer?] [insert string? ""])
          layout-break-opportunity?]{
Returns an ordinary break-opportunity value. The insertion must contain
neither a hard line separator nor a bidi formatting control. Construction checks
the index's type but cannot establish that it is inside a particular paragraph;
layout validates paragraph bounds and grapheme boundaries later.

A @deftech{break opportunity} pairs a paragraph-relative character index with
text to insert for display when a line breaks at that index.

@racketblock[
(define break (make-layout-break-opportunity 4 "-"))
(list (layout-break-opportunity-index break) (layout-break-opportunity-insert break))
]

The result is @racket['(4 "-")]. The value owns no native resource.
}

@subsection{A Selected Break Changes the Display Only}

This provider offers one paragraph-relative character boundary: index four in
@racket["longword"].  The wide layout leaves the input on one line, so the
insertion is absent. The narrower layout selects that opportunity and draws a
hyphen, while the caller's logical text remains @racket["longword"].

@racketblock[
(with-skia ([surface (make-surface 420 175 #:background 'white)]
            [font (make-font #:size 28)]
            [shaper (make-shaper font)]
            [text-paint (make-paint #:color "#20344E")]
            [guide (make-paint #:color "#C9D2DF" #:style 'stroke)]
            [label-font (make-font #:size 11)]
            [label-paint (make-paint #:color "#526070")])
  (define text "longword")
  (define opportunity (make-layout-break-opportunity 4 "-"))
  (define (provider paragraph language) (list opportunity))
  (define wide (layout-text shaper text #:width 170 #:break-provider provider))
  (define narrow (layout-text shaper text #:width 90 #:break-provider provider))
  (define canvas (surface-canvas surface))
  (draw-rect canvas 18 40 170 82 guide)
  (draw-rect canvas 228 40 90 82 guide)
  (draw-simple-text canvas "wide: no break selected" 18 25 label-font label-paint)
  (draw-text-layout canvas wide 18 48 text-paint)
  (draw-simple-text canvas "narrow: selected break inserts -" 228 25
                    label-font label-paint)
  (draw-text-layout canvas narrow 228 48 text-paint)
  (draw-simple-text canvas "logical input stays: longword" 18 148
                    label-font label-paint)
  (list (map text-layout-line-text (text-layout-lines wide))
        (map text-layout-line-text (text-layout-lines narrow))))
]
@reference-figure["layout-break-provider-insertion.png"
                  "The logical word longword fits in a wide layout without a hyphen; in a narrow layout the provider's character-index-four break is selected and the visible first line becomes long-."]

The opportunity index is a Racket character index in its paragraph, not a
UTF-8 byte offset or a shaped-glyph cluster index. The two displayed line-text
lists are @racket['("longword")] and @racket['("long-" "word")].

@defproc[(layout-break-opportunity-index [opportunity layout-break-opportunity?])
          exact-nonnegative-integer?]{
Returns the paragraph-relative Racket character index of the break.
}

@defproc[(layout-break-opportunity-insert [opportunity layout-break-opportunity?]) string?]{
Returns the display insertion associated with the break.
}

@section{Additional Visual Examples}

@racketblock[
(with-skia ([surface (make-surface 300 120 #:background 'white)]
            [font (make-font #:size 20)] [shaper (make-shaper font)]
            [paint (make-paint #:color "#20344E")])
  (define layout (layout-text shaper "Centered lines wrap inside a fixed width."
                              #:width 260 #:align 'center #:line-height 30))
  (draw-text-layout (surface-canvas surface) layout 20 15 paint))
]
@reference-figure["layout-center.png"
                  "A wrapped paragraph whose line advances are centered within a fixed-width layout box."]

@racketblock[
(with-skia ([surface (make-surface 300 100 #:background 'white)]
            [font (make-font #:size 22)] [shaper (make-shaper font)]
            [paint (make-paint #:color "#20344E")])
  (define layout (layout-text shaper "End aligned" #:width 250 #:align 'end))
  (draw-text-layout (surface-canvas surface) layout 20 20 paint))
]
@reference-figure["layout-end.png"
                  "A short left-to-right line positioned at the end, or right side, of its layout box."]

@racketblock[
(with-skia ([surface (make-surface 320 160 #:background 'white)]
            [font (make-font #:size 18)] [shaper (make-shaper font)]
            [blue (make-paint #:color "#326DE6")]
            [orange (make-paint #:color "#EFA02B")])
  (define text "One two three four five six seven eight.")
  (draw-text-layout (surface-canvas surface)
                    (layout-text shaper text #:width 130 #:line-height 20)
                    10 10 blue)
  (draw-text-layout (surface-canvas surface)
                    (layout-text shaper text #:width 130 #:line-height 34)
                    175 10 orange))
]
@reference-figure["layout-line-height.png"
                  "The same wrapped paragraph shown with tight blue line spacing and looser orange line spacing."]
