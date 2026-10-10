#lang scribble/manual

@title{Text and Typography — Make a Type Specimen}

@(require "eval.rkt"
          (for-label racket
                     skia))

This tutorial builds a small type specimen. The examples use Skia's simple
text API to draw a typeface at several sizes, place text from an origin on a
baseline, measure its advance, inspect its ink bounds, and use font metrics.

The tutorial assumes that you know the basics from
@italic{Quick: An Introduction to Skia with Pictures}.

The main idea is:

@centered{@bold{Simple text starts at an origin on a baseline. Advance, bounds,
and font metrics describe different parts of its geometry.}}

@section{Choose a Typeface and a Font}

A typeface identifies a font design. A font combines that design with a size
and rendering options.

The @racket[make-typeface] function selects the platform's default Skia
typeface:

@text-racketblock+eval[
(define face (make-typeface))
]

The exact family can differ between operating systems. You can inspect the
selected family:

@text-interaction[
(typeface-family-name face)
]

This tutorial uses that one typeface throughout. The visual details can
therefore vary from one machine to another, but the geometry concepts are the
same.

The @racket[make-font] function combines the typeface with a size:

@text-racketblock+eval[
(define sample-font
  (make-font face #:size 64))

(define ink
  (make-paint #:color "#25313D"))
]

You can also call @racket[make-font] without an explicit typeface. Using one
explicit @racket[face] here makes it easy to query the selected family and
reuse the same design at several sizes.

@section{The Text Origin Is on the Baseline}

The @racket[draw-simple-text] function takes an x coordinate and a y
coordinate. Together they form the text origin. The y coordinate is the
baseline, not the top or bottom of the letters.

The following drawing makes both the baseline and the origin visible:

@text-racketblock+eval[
(define (draw-baseline-demo canvas)
  (define font
    (make-font face #:size 72))
  (define text-paint
    (make-paint #:color "#25313D"))
  (define baseline-paint
    (make-paint #:color "#C8553D"
                #:style 'stroke
                #:stroke-width 2))
  (define origin-paint
    (make-paint #:color "#2D6CDF"))
  (define x 70)
  (define baseline 150)

  (draw-line canvas
             45 baseline
             675 baseline
             baseline-paint)
  (draw-circle canvas
               x baseline
               5
               origin-paint)
  (draw-simple-text canvas
                    "Baseline"
                    x baseline
                    font text-paint))
]

@text-image[
(text-render-pict 720 220 draw-baseline-demo)
]

The blue dot marks the text origin. The letters extend above and sometimes
below the red baseline. Changing the origin moves the whole run without
changing the font.

The x coordinate is also important later: text measurements are reported
relative to this origin.

@section{Change the Font Size}

The same typeface can be used at different sizes:

@text-racketblock+eval[
(define (draw-size-demo canvas)
  (define paint
    (make-paint #:color "#25313D"))
  (define label-font
    (make-font face #:size 13))
  (define label-paint
    (make-paint #:color "#C8553D"))

  (for ([size '(24 40 64)]
        [baseline '(58 130 230)])
    (define font
      (make-font face #:size size))
    (draw-simple-text canvas
                      (number->string size)
                      35 baseline
                      label-font label-paint)
    (draw-simple-text canvas
                      "Skia"
                      85 baseline
                      font paint)))
]

@text-image[
(text-render-pict 480 270 draw-size-demo)
]

The small labels show the requested font sizes. The typeface and paint stay
the same.

@section{Measure the Advance}

Drawing text does not return its width. The
@racket[measure-simple-text] function returns the advance of a simple text run.

The advance starts at the text origin and says where the next run would
normally begin. It is therefore useful for placement.

The next example uses the advance to center a line. It also draws the measured
span below the text:

@text-racketblock+eval[
(define (draw-centered-demo canvas)
  (define font
    (make-font face #:size 42))
  (define paint
    (make-paint #:color "#25313D"))
  (define measure-paint
    (make-paint #:color "#2D6CDF"
                #:style 'stroke
                #:stroke-width 2))
  (define marker
    (make-paint #:color "#2D6CDF"))
  (define center-guide
    (make-paint #:color "#AAB2BC"
                #:style 'stroke
                #:stroke-width 1))
  (define text "Measured, then centered")
  (define advance
    (measure-simple-text font text))
  (define x
    (/ (- 720 advance) 2))
  (define baseline 115)
  (define measure-y 150)

  (draw-line canvas
             360 32
             360 170
             center-guide)
  (draw-simple-text canvas
                    text
                    x baseline
                    font paint)
  (draw-line canvas
             x measure-y
             (+ x advance) measure-y
             measure-paint)
  (draw-circle canvas x measure-y 4 marker)
  (draw-circle canvas
               (+ x advance) measure-y
               4 marker))
]

@text-image[
(text-render-pict 720 190 draw-centered-demo)
]

The gray line marks the center of the available width. The blue line shows the
measured advance. Centering subtracts that advance from the available width and
places half of the remaining space on each side.

@section{Advance and Ink Bounds Are Different}

The advance answers a placement question: where does the run finish advancing?
It is not necessarily the same as the rectangle occupied by visible ink.

The @racket[simple-text-bounds] function returns four values: x offset,
y offset, width, and height. The offsets are relative to the text origin.

The next example shows the origin, baseline, advance, and bounds together:

@text-racketblock+eval[
(define (draw-bounds-demo canvas)
  (define font
    (make-font face #:size 72))
  (define ink
    (make-paint #:color "#25313D"))
  (define advance-paint
    (make-paint #:color "#2D6CDF"
                #:style 'stroke
                #:stroke-width 3))
  (define bounds-paint
    (make-paint #:color "#C8553D"
                #:style 'stroke
                #:stroke-width 2))
  (define baseline-paint
    (make-paint #:color "#AAB2BC"
                #:style 'stroke
                #:stroke-width 1))
  (define origin-paint
    (make-paint #:color "#2D6CDF"))
  (define text "Typography")
  (define x 70)
  (define baseline 150)
  (define advance
    (measure-simple-text font text))
  (define-values (bx by bw bh)
    (simple-text-bounds font text))

  (draw-line canvas
             45 baseline
             675 baseline
             baseline-paint)
  (draw-simple-text canvas
                    text x baseline
                    font ink)
  (draw-line canvas
             x baseline
             (+ x advance) baseline
             advance-paint)
  (draw-circle canvas
               x baseline
               5 origin-paint)
  (draw-rect canvas
             (+ x bx) (+ baseline by)
             bw bh
             bounds-paint))
]

@text-image[
(text-render-pict 720 230 draw-bounds-demo)
]

The blue dot is the origin. The blue segment ends at the advance position. The
red rectangle encloses the measured ink bounds.

The bounds are returned relative to the origin, so their x and y offsets can
move the rectangle away from @tt{(0, 0)}. Depending on the glyphs, visible ink
can start after the origin or extend beyond an advance edge.

Use the advance for laying out consecutive runs. Use the bounds when you need
to reason about the visible ink.

@section{Font Metrics Describe the Font}

Text bounds describe one particular string. Font metrics describe the font at
its current size.

The @racket[font-get-metrics] function returns an immutable Racket value
containing measurements such as ascent, descent, and spacing:

@text-racketblock+eval[
(define metrics-font
  (make-font face #:size 78))

(define metrics
  (font-get-metrics metrics-font))
]

With the usual downward-growing y axis, the ascent is normally negative and
the descent is normally positive. Adding those values to a baseline gives
guide positions:

@text-racketblock+eval[
(define (draw-metrics-demo canvas)
  (define font metrics-font)
  (define label-font
    (make-font face #:size 15))
  (define ink
    (make-paint #:color "#25313D"))
  (define accent
    (make-paint #:color "#C8553D"))
  (define guide
    (make-paint #:color "#AAB2BC"
                #:style 'stroke
                #:stroke-width 1))
  (define origin-paint
    (make-paint #:color "#2D6CDF"))
  (define x 80)
  (define baseline 160)
  (define ascent-y
    (+ baseline
       (font-metrics-ascent metrics)))
  (define descent-y
    (+ baseline
       (font-metrics-descent metrics)))

  (draw-simple-text canvas
                    "Ag"
                    x baseline
                    font accent)
  (draw-circle canvas
               x baseline
               4 origin-paint)

  (for ([y (list ascent-y baseline descent-y)]
        [label '("ascent" "baseline" "descent")])
    (draw-line canvas 55 y 665 y guide)
    (draw-simple-text canvas
                      label
                      550 (- y 6)
                      label-font ink)))
]

@text-image[
(text-render-pict 720 245 draw-metrics-demo)
]

The ascent and descent are properties of the font, not of the particular
letters in @racket["Ag"]. A particular string can occupy less vertical space
than the font-wide metrics suggest.

The @racket[font-metrics-spacing] function reports the native spacing value
for the font. This tutorial does not turn that value into paragraph layout.
Later tutorials will cover shaping, line breaking, and multi-line text.

@section{Simple Text Has Limits}

The functions in this tutorial deliberately have @italic{simple text} in their
names.

The simple text API maps and draws a single run through Skia's low-level font
API. It does not perform contextual shaping, bidirectional reordering, line
breaking, paragraph layout, or multi-font fallback.

Simple Latin examples such as the ones in this tutorial are appropriate.
Arabic, many Indic scripts, mixed-direction text, and other text that requires
contextual shaping need the shaping and layout APIs.

The next tutorial will introduce that layer.

@section{Build the Type Specimen}

The finished page combines the ideas from this tutorial. It shows the selected
family, a size scale, an alphabet sample, font metrics, and a centered measured
line.

First, define the page dimensions and colors:

@text-racketblock+eval[
(define width 800)
(define height 980)

(define paper-color "#F4F0E8")
(define ink-color "#25313D")
(define accent-color "#C8553D")
(define blue-color "#2D6CDF")
(define guide-color "#AAB2BC")
(define panel-color "#FBFAF7")

(define family-name
  (typeface-family-name face))
]

The finished drawing is divided into a few small functions:

@text-racketblock+eval[
(define (draw-rule canvas y)
  (define paint
    (make-paint #:color guide-color
                #:style 'stroke
                #:stroke-width 1))
  (draw-line canvas 56 y (- width 56) y paint))

(define (draw-header canvas)
  (define kicker-font
    (make-font face #:size 15))
  (define title-font
    (make-font face #:size 58))
  (define body-font
    (make-font face #:size 18))
  (define ink
    (make-paint #:color ink-color))
  (define accent
    (make-paint #:color accent-color))
  (draw-simple-text canvas
                    "SKIA / TYPE SPECIMEN"
                    58 64
                    kicker-font accent)
  (draw-simple-text canvas
                    "Simple text"
                    56 132
                    title-font ink)
  (draw-simple-text canvas
                    (format "Platform default: ~a"
                            family-name)
                    58 170
                    body-font ink)
  (draw-rule canvas 194))
]

@text-racketblock+eval[
(define (draw-size-scale canvas)
  (define paint
    (make-paint #:color ink-color))
  (define label-font
    (make-font face #:size 13))
  (define label-paint
    (make-paint #:color accent-color))
  (for ([size '(24 36 54 78)]
        [baseline '(250 304 376 470)])
    (define font
      (make-font face #:size size))
    (draw-simple-text canvas
                      (number->string size)
                      58 baseline
                      label-font label-paint)
    (draw-simple-text canvas
                      "Skia"
                      110 baseline
                      font paint)))

(define (draw-alphabet canvas)
  (define font
    (make-font face #:size 24))
  (define paint
    (make-paint #:color ink-color))
  (draw-rule canvas 510)
  (draw-simple-text canvas
                    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                    58 558
                    font paint)
  (draw-simple-text canvas
                    "abcdefghijklmnopqrstuvwxyz"
                    58 598
                    font paint)
  (draw-simple-text canvas
                    "0123456789  .,:;!?  ()[]{}"
                    58 638
                    font paint))
]

The metrics panel uses the same ascent and descent calculation from the
previous section:

@text-racketblock+eval[
(define (draw-metrics-panel canvas)
  (define font
    (make-font face #:size 78))
  (define label-font
    (make-font face #:size 15))
  (define text-paint
    (make-paint #:color ink-color))
  (define accent
    (make-paint #:color accent-color))
  (define guide
    (make-paint #:color guide-color
                #:style 'stroke
                #:stroke-width 1))
  (define origin-paint
    (make-paint #:color blue-color))
  (define panel
    (make-paint #:color panel-color))
  (define metrics
    (font-get-metrics font))
  (define x 92)
  (define baseline 790)
  (define ascent-y
    (+ baseline
       (font-metrics-ascent metrics)))
  (define descent-y
    (+ baseline
       (font-metrics-descent metrics)))

  (draw-rounded-rect canvas
                     52 682 696 164
                     18 18 panel)
  (draw-simple-text canvas
                    "Ag"
                    x baseline
                    font accent)
  (draw-circle canvas
               x baseline
               4 origin-paint)

  (for ([y (list ascent-y baseline descent-y)]
        [label '("ascent" "baseline" "descent")])
    (draw-line canvas 76 y 720 y guide)
    (draw-simple-text canvas
                      label
                      610 (- y 7)
                      label-font text-paint)))
]

The last line uses its advance to center itself:

@text-racketblock+eval[
(define (draw-centered-line canvas)
  (define font
    (make-font face #:size 28))
  (define paint
    (make-paint #:color blue-color))
  (define text "MEASURED, THEN CENTERED")
  (define advance
    (measure-simple-text font text))
  (define x
    (/ (- width advance) 2))
  (draw-simple-text canvas
                    text x 910
                    font paint))

(define (draw-footer canvas)
  (define font
    (make-font face #:size 14))
  (define paint
    (make-paint #:color ink-color))
  (draw-simple-text canvas
                    "Origin / baseline / advance / bounds / metrics"
                    58 952
                    font paint))
]

The complete drawing function only assembles those pieces:

@text-racketblock+eval[
(define (draw-specimen canvas)
  (draw-header canvas)
  (draw-size-scale canvas)
  (draw-alphabet canvas)
  (draw-metrics-panel canvas)
  (draw-centered-line canvas)
  (draw-footer canvas))
]

@text-image[
(text-render-pict
 width height
 draw-specimen
 #:background paper-color
 #:scale 0.56)
]

@section{Save the Result}

The finished specimen is an ordinary raster drawing:

@racketblock[
(define surface
  (make-surface width height
                #:background paper-color))

(draw-specimen (surface-canvas surface))

(save-png surface
          "type-specimen.png"
          #:exists 'replace)
]

@section{Try It}

Try changing the font sizes in @racket[draw-size-scale]. Keep the baselines
fixed and observe how the glyphs grow around them.

Try centering a different string with @racket[measure-simple-text]. Compare its
advance with its ink bounds.

Try replacing @racket["Typography"] in the bounds example with @racket["jazz"].
Look for glyphs whose ink extends differently around the text origin.

Try moving the metrics baseline while leaving the ascent and descent formulas
unchanged. The three guides should move together.

Try replacing @racket[make-typeface] with @racket[typeface-from-family] for a
family installed on your machine. Use @racket[typeface-family-name] to inspect
the face that Skia selected.

@section{Where to Go From Here}

This tutorial used typefaces, fonts, text origins, baselines, font sizes,
advance measurement, simple-text bounds, and font metrics.

The next tutorial will use HarfBuzz shaping for ligatures, script-sensitive
glyph selection, bidirectional text, and multilingual runs. Paragraph layout
will follow after that.

The complete @filepath{type-specimen.rkt} example contains the finished program
from this tutorial.
