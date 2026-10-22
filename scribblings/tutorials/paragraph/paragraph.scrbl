#lang scribble/manual

@(require "../support/reader.rkt"
          "../support/accessible-figures.rkt")

@title[#:style (tutorial-feedback-style)]{Paragraph Layout — Make a Multilingual Article Card}
@(tutorial-navigation "paragraph")

@(require "eval.rkt"
          (for-label racket
                     skia))

@(define-values (finished-preview finish-figure) (make-figure-preview))

@section[#:tag "finished-result"]{The Finished Article Card}

@|finished-preview|

The article card combines a wrapped introduction, a mixed-script paragraph,
and a right-to-left callout. You will give text an available width and draw
each layout from the upper-left corner of its box.

Mixed layout also resolves directional runs and selects fallback fonts.

@tutorial-entry["paragraph"]

@section{Start with One Long Line}

A shaper still supplies the font and its shaping behavior. Begin with the
platform's default typeface:

@paragraph-racketblock+eval[
(define face (make-typeface))
(define font (make-font face #:size 28))
(define shaper (make-shaper font))
(define text-paint (make-paint #:color "#20304C"))

(define sample-text
  "A page gives words a width. Paragraph layout chooses the lines and their baselines.")

(define unwrapped
  (layout-text shaper sample-text))
]

Without a width, this sample occupies one line. The @racket[draw-text-layout]
function positions the upper-left corner of the layout box, rather than a text
baseline:

@paragraph-racketblock+eval[
(define (draw-unwrapped canvas)
  (draw-text-layout canvas unwrapped 40 32 text-paint))
]

@(tutorial-figure
 "The sample sentence occupies one long line when no wrapping width is supplied."
 (paragraph-image
(paragraph-render-pict 1180 100 draw-unwrapped #:scale 0.64)
))

The typeface family and the exact text measurements can differ across
platforms. This tutorial relies on layout measurements instead of assuming
fixed glyph widths.

@section{Give the Paragraph a Width}

Now give the same text a width of 380 pixels:

@paragraph-racketblock+eval[
(define wrapped
  (layout-text shaper sample-text #:width 380))
]

Skia finds legal Unicode line-break opportunities and shapes each selected
line. The layout contains both the positioned lines and their measurements.

The @racket[text-layout-line-count] function reports the number of lines:

@paragraph-interaction[
(text-layout-line-count wrapped)
(text-layout-width wrapped)
(text-layout-height wrapped)
]

The requested width is not a clipping rectangle. If a word or another
unbreakable span is wider than the requested measure, the layout reports the
larger occupied width instead of splitting the span arbitrarily.

Draw the wrapped layout on a smaller surface:

@paragraph-racketblock+eval[
(define (draw-wrapped-plain canvas)
  (draw-text-layout canvas wrapped 44 32 text-paint))
]

@(tutorial-figure
 "The same sentence wraps into several lines at a requested width of 380."
 (paragraph-image
(paragraph-render-pict 500 165 draw-wrapped-plain #:scale 0.9)
))

The original sentence now occupies several baselines without any manual line
splitting or separate drawing call for each line.

@section{See the Layout Box and Baselines}

Each line has a baseline relative to the top of the layout box. We can use
those actual measurements to draw guides behind the paragraph:

@paragraph-racketblock+eval[
(define frame-paint
  (make-paint #:color "#C7D2E3"
              #:style 'stroke
              #:stroke-width 1))
(define baseline-paint
  (make-paint #:color "#A5B7D2"
              #:style 'stroke
              #:stroke-width 1))

(define (draw-layout-guides canvas layout x y)
  (define box-width (text-layout-width layout))
  (define box-height (text-layout-height layout))
  (draw-rect canvas x y box-width box-height frame-paint)
  (for ([line (in-list (text-layout-lines layout))])
    (define baseline (+ y (text-layout-line-baseline line)))
    (draw-line canvas x baseline (+ x box-width) baseline baseline-paint)))

(define (draw-wrapped canvas)
  (draw-layout-guides canvas wrapped 44 32)
  (draw-wrapped-plain canvas))
]

@(tutorial-figure
 "A rectangle marks the layout box and horizontal rules mark its line-baseline offsets."
 (paragraph-image
(paragraph-render-pict 500 165 draw-wrapped #:scale 0.9)
))

The outer rectangle uses the reported layout width and height. The horizontal
rules use @racket[text-layout-line-baseline], so they track the chosen font's
metrics. The text is drawn over those rules at the layout box origin.

The two drawing APIs use different origins. The @racket[draw-simple-text]
function positions an origin on the text baseline. The @racket[draw-text-layout]
function positions the layout box's upper-left corner. Each line's baseline is
an offset below that corner, so its canvas y coordinate is the box y coordinate
plus @racket[text-layout-line-baseline].

@section{Align Lines Inside the Width}

Some lines end before the right edge of the available width. Alignment
decides where those shorter lines sit inside the box.

Use the same width and text with three alignments:

@paragraph-racketblock+eval[
(define alignment-text
  "A line can end earlier than its box.")
(define label-font (make-font face #:size 17))
(define label-paint (make-paint #:color "#326DE6"))

(define (draw-alignments canvas)
  (for ([alignment '(start center end)]
        [x '(44 362 680)])
    (define layout
      (layout-text shaper alignment-text
                   #:width 264
                   #:align alignment))
    (draw-simple-text canvas (symbol->string alignment)
                      x 42 label-font label-paint)
    (draw-layout-guides canvas layout x 66)
    (draw-text-layout canvas layout x 66 text-paint)))
]

@(tutorial-figure
 "The same text uses start, center, and end alignment in three equal-width boxes."
 (paragraph-image
(paragraph-render-pict 990 170 draw-alignments #:scale 0.78)
))

For a left-to-right paragraph, @racket['start] aligns at the left edge,
@racket['center] centers each line, and @racket['end] aligns at the right edge.
For a right-to-left paragraph, logical start and end exchange sides. The
@racket['left] and @racket['right] alignments instead name physical edges.

@section{Move from One Run to Mixed Text}

A single run is not enough for a sentence that mixes scripts and writing
directions. The @racket[layout-text] function wraps and shapes one font run
per line, but does not resolve a mixed-direction paragraph or select fallback
fonts for individual scripts.

The @racket[layout-mixed-text] function accepts a font manager as well as a
shaper. It resolves the paragraph direction, segments runs, and asks the font
manager for fallback typefaces when the base font lacks characters.

@paragraph-racketblock+eval[
(define font-manager (default-font-manager))
(define mixed-text
  "Skia places English beside العربية and עברית, even when a sentence includes 2026.")

(define mixed-layout
  (layout-mixed-text shaper font-manager mixed-text
                     #:width 650
                     #:direction 'ltr))

(define mixed-frame
  (make-paint #:color "#C7D2E3"
              #:style 'stroke
              #:stroke-width 1))

(define (draw-mixed-example canvas)
  (draw-rect canvas 48 38
             (mixed-text-layout-width mixed-layout)
             (mixed-text-layout-height mixed-layout)
             mixed-frame)
  (draw-mixed-text-layout canvas mixed-layout 48 38 text-paint))
]

@(tutorial-figure
 (string-append
   "English, Arabic, Hebrew, and a number share a paragraph with left-to-right "
   "base direction."
)
 (paragraph-image
(paragraph-render-pict 770 140 draw-mixed-example #:scale 0.83)
))

The text now contains Latin, Arabic, and Hebrew runs. An explicit
@racket[#:direction 'ltr] chooses the left-to-right paragraph base direction.
It does not force each embedded Arabic or Hebrew run to be left-to-right.

@section{Inspect the Runs and Font Choices}

The mixed layout exposes lines, and each line exposes its shaped runs.
There may be many short runs, including spaces. To focus on the new scripts,
inspect only the right-to-left runs:

@paragraph-interaction[
(for*/list ([line (in-list (mixed-text-layout-lines mixed-layout))]
            [run (in-list (mixed-text-line-runs line))]
            #:when (eq? (mixed-text-run-direction run) 'rtl))
  (list (mixed-text-run-text run)
        (mixed-text-run-direction run)
        (mixed-text-run-family run)))
]

The @racket[mixed-text-run-family] function returns @racket[#f] when a run
uses the base shaper. Otherwise, it names a selected fallback family. Which
families appear depends on the fonts installed on the computer. A default
font that already covers a script may need no fallback for that script.

The caller's shaper and font manager must remain open while the mixed layout
is drawn. The layout retains references to them; it does not permanently own
the temporary fallback fonts used during shaping.

@section{Let the Paragraph Choose Its Direction}

A mixed paragraph can also begin in a right-to-left script. Use a
Hebrew-first sentence that contains Arabic, English, and a number:

@paragraph-racketblock+eval[
(define right-to-left-text
  "שלום 2026, Skia! مرحبا بالعالم and English.")

(define right-to-left-layout
  (layout-mixed-text shaper font-manager right-to-left-text
                     #:width 650
                     #:direction 'auto
                     #:align 'start))

(define (draw-right-to-left canvas)
  (draw-rect canvas 48 38
             (mixed-text-layout-width right-to-left-layout)
             (mixed-text-layout-height right-to-left-layout)
             mixed-frame)
  (draw-mixed-text-layout canvas right-to-left-layout 48 38 text-paint))
]

@(tutorial-figure
 (string-append
   "A Hebrew-first paragraph starts at the right; embedded Latin text and numbers "
   "keep their directions."
)
 (paragraph-image
(paragraph-render-pict 770 135 draw-right-to-left #:scale 0.83)
))

With @racket[#:direction 'auto], the first strong directional character
selects the paragraph's base direction. Here, the initial Hebrew text makes
logical @racket['start] the right edge. The embedded left-to-right text and
number still keep their resolved directional behavior.

The final period appears at the left of the displayed line even though it
comes last in the source string. Bidirectional layout determines the visual
order; the program does not reverse the string.

This is paragraph-level bidirectional layout. The @racket[shape-text]
function from @tutorial-link["shaping"] only shapes a run with a direction; it
does not reorder a mixed-direction paragraph.

@section{Build the Article Card}

The finished card uses three paragraphs. Its introduction uses
@racket[layout-text]. Its mixed-script sentence and Hebrew-first callout use
@racket[layout-mixed-text]. Each paragraph is drawn from the upper-left
corner of its own layout box.

Inside @racket[draw-article-card], a 26-unit body font supplies the shaper for
all three layouts. The @racket[introduction] uses @racket[layout-text] with a
width of 744. The @racket[multilingual-text] layout also has width 744, with a
left-to-right base direction. The @racket[right-to-left-text] layout has width
690, automatic base direction, and start alignment.

The following excerpt places those layouts below the heading and inside the
callout. The canvas, paint, and layouts are local bindings of the complete
function. Here @racket[right-to-left-text] names a layout, not the earlier
sample string:

@racketblock[
(draw-text-layout canvas introduction 88 222 ink)
(draw-mixed-text-layout canvas multilingual-text 88 376 ink)
(draw-mixed-text-layout canvas right-to-left-text 108 562 ink)
]

These coordinates place layout-box corners, not baselines. The heading and
separators are drawn around the first two paragraphs. A rounded background and
a label frame the right-to-left callout. The
@seclink["example-source"]{complete example} includes that decoration and the
three layout constructors.

@(finish-figure
 (tutorial-figure
 (string-append
   "A finished article card has a heading, wrapped introduction, mixed-script "
   "paragraph, and right-to-left callout."
)
 (paragraph-article-pict)))

@section{Save the Card}

The runnable example creates a raster surface, draws the card, and saves a PNG
file:

@racketblock[
(define surface
  (make-surface card-width card-height
                #:background paper-color))
(draw-article-card (surface-canvas surface))
(save-png surface "article-card.png" #:exists 'replace)
]

Run @filepath{article-card.rkt} with Racket to write @filepath{article-card.png}
in the current directory. The surface is an ordinary owned CPU resource; no
special cleanup form is required when prompt release is unimportant.

@section[#:tag "try-it"]{Try It}

Try reducing the introduction width in @filepath{article-card.rkt}. Watch how
the line count and total height change. Keep the other elements far enough
below the paragraph to accommodate the extra lines.

Try replacing @racket['start] with @racket['end] in the Hebrew-first callout.
Predict which edge the paragraph will use before rendering it.

Try changing the default typeface, or inspecting
@racket[mixed-text-run-family] on another computer. Compare the actual font
choices rather than expecting identical fallback families.

@section[#:tag "next-steps"]{Where to Go From Here}

You can now wrap text into measured lines and use mixed layout for directional and font runs.

@tutorial-next["paragraph"]

@section[#:tag "example-source"]{The Complete Example}

@tutorial-sources["paragraph"]
