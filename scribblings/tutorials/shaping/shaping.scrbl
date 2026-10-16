#lang scribble/manual

@(require "../support/reader.rkt"
          "../support/accessible-figures.rkt")

@title{Shaping and Multilingual Text — Make a Language Sampler}
@(tutorial-navigation "shaping")

@(require "eval.rkt"
          (for-label racket
                     skia))

@(define-values (finished-preview finish-figure) (make-figure-preview))

@section[#:tag "finished-result"]{The Finished Language Sampler}

@|finished-preview|

The sampler combines Latin, Arabic, and Hebrew text. You will select suitable
fonts, shape individual runs, inspect their glyph positions, and compare an
OpenType feature.

Shaping turns a string into positioned glyphs. Drawing places that shaped run
on the canvas. Mixed-direction paragraphs are a separate step in
@tutorial-link["paragraph"].

@tutorial-entry["shaping"]

@section{Create a Shaper}

A shaper is built from a font:

@shaping-racketblock+eval[
(define latin-face (make-typeface))
(define latin-font
  (make-font latin-face #:size 48))
(define latin-shaper
  (make-shaper latin-font))
]

The shaper snapshots the font state it needs. The important conceptual change
is that text now passes through an explicit shaping step before drawing.

@section{Shape, Then Draw}

The @racket[shape-text] function returns a shaped run. The
@racket[shaped-run?] predicate recognizes these values:

@shaping-racketblock+eval[
(define office-run
  (shape-text latin-shaper
              "office"
              #:language "en"))
]

A shaped run is not another string. It contains selected glyph IDs, cluster
information, glyph positions, and final advances.

The run can be drawn with @racket[draw-shaped-run]:

@shaping-racketblock+eval[
(define (draw-office canvas)
  (define paint
    (make-paint #:color "#326DE6"))
  (draw-shaped-run canvas
                   latin-shaper
                   office-run
                   60 110
                   paint))
]

@(tutorial-figure
 (string-append
   "The shaped word office is placed at an origin on its baseline; glyph selection "
   "depends on the font."
)
 (shaping-image
(shaping-render-pict 420 160 draw-office)
))

The x and y arguments give the origin for the shaped run. The glyph positions
stored inside the run are relative to that origin.

@section{Look Inside a Shaped Run}

The number of input characters and the number of output glyphs do not have to
be the same.

The following queries inspect the run:

@shaping-interaction[
(shaped-run-glyph-count office-run)
(shaped-run-advance-x office-run)
]

The exact values depend on the selected typeface. Glyph IDs and metrics are
font-specific.

The positions are also available as ordinary Racket data:

@shaping-racketblock+eval[
(define skia-run
  (shape-text latin-shaper
              "Skia"
              #:language "en"))
]

The next drawing marks every glyph origin with a small red dot and shows the
final advance as a blue line:

@shaping-racketblock+eval[
(define (draw-position-demo canvas)
  (define paint
    (make-paint #:color "#20304C"))
  (define marker
    (make-paint #:color "#C8553D"))
  (define advance-paint
    (make-paint #:color "#326DE6"
                #:style 'stroke
                #:stroke-width 2))
  (define x 70)
  (define baseline 125)

  (draw-shaped-run canvas
                   latin-shaper
                   skia-run
                   x baseline
                   paint)

  (for ([position
         (in-list
          (shaped-run-positions skia-run))])
    (draw-circle canvas
                 (+ x (first position))
                 (+ baseline (second position))
                 4
                 marker))

  (draw-line canvas
             x 155
             (+ x
                (shaped-run-advance-x skia-run))
             155
             advance-paint))
]

@(tutorial-figure
 (string-append
   "Each glyph in Skia has a marked origin; a separate horizontal segment shows "
   "the total advance."
)
 (shaping-image
(shaping-render-pict 520 190 draw-position-demo)
))

The dots are glyph origins, not character positions. HarfBuzz can change both
the number of glyphs and their positions.

@section{OpenType Features Affect Shaping}

OpenType features can change glyph selection and positioning.

The word @racket["office"] is a useful example because many fonts contain a
standard ligature for part of the word. The exact result remains font-dependent.

The following code shapes the same string twice:

@shaping-racketblock+eval[
(define liga-on
  (shape-text latin-shaper
              "office"
              #:language "en"))

(define liga-off
  (shape-text latin-shaper
              "office"
              #:language "en"
              #:features '("liga=0")))
]

The @racket["liga=0"] feature disables standard ligatures.

@shaping-racketblock+eval[
(define (draw-feature-demo canvas)
  (define default-paint
    (make-paint #:color "#326DE6"))
  (define off-paint
    (make-paint #:color "#F38C42"))
  (define label-font
    (make-font latin-face #:size 14))
  (define label-paint
    (make-paint #:color "#20304C"))

  (draw-shaped-run canvas
                   latin-shaper
                   liga-on
                   70 95
                   default-paint)
  (draw-simple-text canvas
                    "default"
                    70 130
                    label-font label-paint)

  (draw-shaped-run canvas
                   latin-shaper
                   liga-off
                   340 95
                   off-paint)
  (draw-simple-text canvas
                    "liga=0"
                    340 130
                    label-font label-paint))
]

@(tutorial-figure
 (string-append
   "The word office is shaped with default features and with liga=0; the visible "
   "difference is font-specific."
)
 (shaping-image
(shaping-render-pict 620 165 draw-feature-demo)
))

Some fonts will show a clear ligature difference. A font without that feature
can legitimately produce the same visible result for both runs.

@section{Choose a Face Before Shaping}

The @racket[shape-text] function shapes one font run. It does not search other
fonts when the selected typeface lacks a character.

For multilingual text, font selection is therefore a separate step.

A font manager can find a typeface containing a representative character.
The result can be false, and matching one character does not prove that the
font covers the complete sample. This helper checks both conditions before
shaping. A missing font produces a message asking you to install a suitable
font, rather than silently using an unrelated default face:

@shaping-racketblock+eval[
(define (require-script-face manager representative sample language
                             #:match [match font-manager-match-character])
  (define face (match manager representative #:languages (list language)))
  (unless face
    (error 'require-script-face
           "No font found for language ~a. Install a font covering ~s and restart."
           language sample))
  (define font (make-font face))
  (unless (for/and ([glyph (in-vector (font-text->glyphs font sample))])
            (positive? glyph))
    (error 'require-script-face
           "The selected font lacks characters in ~s. Install a font for language ~a and restart."
           sample language))
  face)
]

@shaping-racketblock+eval[
(define font-manager
  (default-font-manager))

(define arabic-sample "مرحبا بالعالم")
(define arabic-face
  (require-script-face font-manager #\م arabic-sample "ar"))

(define arabic-font
  (make-font arabic-face #:size 54))

(define arabic-shaper
  (make-shaper arabic-font))
]

The font manager result can vary by platform. The shaping API does not require
a particular family name; it requires a font that can represent the run.

@section{Shape Right-to-Left Text}

Arabic joining forms depend on neighboring characters. This is exactly the
kind of work that belongs in shaping.

For a short standalone sample, we can state the direction, script, and
language explicitly:

@shaping-racketblock+eval[
(define arabic-run
  (shape-text arabic-shaper
              "مرحبا"
              #:direction 'rtl
              #:script 'arab
              #:language "ar"))
]

Right-to-left does not by itself tell us the sign of the x advance. HarfBuzz
runs can use either sign here, depending on the shaped run. The portable rule
is to inspect @racket[shaped-run-advance-x].

The following helper places the right endpoint of the run's advance interval
at a chosen edge. That interval lies between the drawing origin @racket[x] and
@racket[(+ x advance)]. It is not the rectangle occupied by visible ink:

@shaping-racketblock+eval[
(define (right-aligned-run-x run right-edge)
  (define advance
    (shaped-run-advance-x run))
  (if (negative? advance)
      right-edge
      (- right-edge advance)))
]

When the advance is negative, the origin is the interval's right endpoint;
@racket[(+ x advance)] lies to its left. When the advance is positive, the
origin is the left endpoint, so subtracting the advance places the other
endpoint at the requested right edge. A zero advance gives a zero-width interval.

The Arabic example can therefore align its advance interval without assuming
the sign of the advance:

@shaping-racketblock+eval[
(define (draw-arabic-demo canvas)
  (define paint
    (make-paint #:color "#F38C42"))
  (define guide
    (make-paint #:color "#CBD5E1"
                #:style 'stroke
                #:stroke-width 1))
  (define origin
    (make-paint #:color "#326DE6"))
  (define right-edge 570)
  (define x
    (right-aligned-run-x
     arabic-run right-edge))
  (define baseline 120)

  (draw-line canvas
             45 baseline
             right-edge baseline
             guide)
  (draw-circle canvas
               x baseline
               5 origin)
  (draw-shaped-run canvas
                   arabic-shaper
                   arabic-run
                   x baseline
                   paint))
]

@(tutorial-figure
 "An Arabic run has a marked baseline origin and a right-aligned advance interval."
 (shaping-image
(shaping-render-pict 640 175 draw-arabic-demo)
))

The dot marks the drawing origin. The larger of @racket[x] and
@racket[(+ x advance)] is the chosen right edge. Glyphs can overhang either
endpoint, so this is advance alignment, not ink alignment or a clipping rule.
The canvas keeps its ordinary coordinate system; the shaped glyph order and
positions carry the right-to-left behavior.

@section{Add Another Right-to-Left Script}

Hebrew uses a different script but the same single-run shaping pattern.

First select a suitable face and create a shaper:

@shaping-racketblock+eval[
(define hebrew-sample "שלום עולם")
(define hebrew-face
  (require-script-face font-manager #\ש hebrew-sample "he"))

(define hebrew-font
  (make-font hebrew-face #:size 50))

(define hebrew-shaper
  (make-shaper hebrew-font))

(define hebrew-run
  (shape-text hebrew-shaper
              "שלום"
              #:direction 'rtl
              #:script 'hebr
              #:language "he"))
]

@shaping-racketblock+eval[
(define (draw-hebrew-demo canvas)
  (define paint
    (make-paint #:color "#18A999"))
  (define x
    (right-aligned-run-x
     hebrew-run 570))
  (draw-shaped-run canvas
                   hebrew-shaper
                   hebrew-run
                   x 110
                   paint))
]

@(tutorial-figure
 "A Hebrew run is shaped right-to-left and placed using its measured advance."
 (shaping-image
(shaping-render-pict 640 155 draw-hebrew-demo)
))

The explicit script and direction apply to this run only.

@section{Run Direction Is Not Paragraph Bidi}

The @racket[#:direction 'rtl] option does not turn
@racket[shape-text] into a paragraph bidi engine. It also does not provide a
right-alignment policy. Direction controls shaping; placement still uses the
run's measured positions and advance.

A sentence containing Latin, Arabic, Hebrew, numbers, and punctuation can need
several directional and font runs. Paragraph-level bidi resolution,
multi-font fallback, and line alignment belong to the mixed-text layout layer.

This tutorial stays with single shaped runs so the shaping step remains
visible.

@section{Build the Language Sampler}

The final page uses three typefaces and three shapers:

@shaping-racketblock+eval[
(define width 900)
(define height 780)

(define paper-color "#F4F6F9")
(define ink-color "#20304C")
(define guide-color "#CBD5E1")
(define blue-color "#326DE6")
(define teal-color "#18A999")
(define orange-color "#F38C42")
]

The shared helpers draw labels, rules, and the page header:

@shaping-racketblock+eval[
(define (draw-rule canvas y)
  (define paint
    (make-paint #:color guide-color
                #:style 'stroke
                #:stroke-width 1))
  (draw-line canvas
             54 y
             (- width 54) y
             paint))

(define (draw-label canvas text x y)
  (define font
    (make-font latin-face #:size 14))
  (define paint
    (make-paint #:color ink-color))
  (draw-simple-text canvas
                    text x y
                    font paint))

(define (draw-header canvas)
  (define kicker-font
    (make-font latin-face #:size 14))
  (define title-font
    (make-font latin-face #:size 52))
  (define ink
    (make-paint #:color ink-color))
  (define blue
    (make-paint #:color blue-color))
  (draw-simple-text canvas
                    "SKIA / SHAPING STUDY"
                    56 62
                    kicker-font blue)
  (draw-simple-text canvas
                    "Language sampler"
                    54 126
                    title-font ink)
  (draw-rule canvas 150))
]

The right-to-left rows reuse the alignment helper from above:

@shaping-racketblock+eval[
(define (right-aligned-run-x run right-edge)
  (define advance
    (shaped-run-advance-x run))
  (if (negative? advance)
      right-edge
      (- right-edge advance)))
]

Each language row shapes its own run:

@shaping-racketblock+eval[
(define (draw-latin-row canvas)
  (define paint
    (make-paint #:color blue-color))
  (define run
    (shape-text latin-shaper
                "office affinity"
                #:language "en"))
  (draw-label canvas
              "LATIN / DEFAULT FEATURES"
              58 190)
  (draw-shaped-run canvas
                   latin-shaper run
                   58 250 paint)
  (draw-label canvas
              (format "~a glyphs"
                      (shaped-run-glyph-count run))
              58 280))

(define (draw-arabic-row canvas)
  (define paint
    (make-paint #:color orange-color))
  (define run
    (shape-text arabic-shaper
                arabic-sample
                #:direction 'rtl
                #:script 'arab
                #:language "ar"))
  (define x
    (right-aligned-run-x run 842))
  (draw-label canvas "ARABIC / RTL" 58 330)
  (draw-shaped-run canvas
                   arabic-shaper run
                   x 390 paint)
  (draw-label canvas
              (format "~a glyphs"
                      (shaped-run-glyph-count run))
              58 420))
]

@shaping-racketblock+eval[
(define (draw-hebrew-row canvas)
  (define paint
    (make-paint #:color teal-color))
  (define run
    (shape-text hebrew-shaper
                hebrew-sample
                #:direction 'rtl
                #:script 'hebr
                #:language "he"))
  (define x
    (right-aligned-run-x run 842))
  (draw-label canvas "HEBREW / RTL" 58 470)
  (draw-shaped-run canvas
                   hebrew-shaper run
                   x 530 paint)
  (draw-label canvas
              (format "~a glyphs"
                      (shaped-run-glyph-count run))
              58 560))
]

The final row compares an OpenType feature:

@shaping-racketblock+eval[
(define (draw-feature-row canvas)
  (define default-paint
    (make-paint #:color blue-color))
  (define alternate-paint
    (make-paint #:color orange-color))
  (define default-run
    (shape-text latin-shaper
                "office"
                #:language "en"))
  (define no-liga-run
    (shape-text latin-shaper
                "office"
                #:language "en"
                #:features '("liga=0")))
  (draw-rule canvas 590)
  (draw-label canvas
              "OPENTYPE FEATURE"
              58 630)
  (draw-shaped-run canvas
                   latin-shaper default-run
                   250 680 default-paint)
  (draw-shaped-run canvas
                   latin-shaper no-liga-run
                   570 680 alternate-paint)
  (draw-label canvas "default" 250 714)
  (draw-label canvas "liga=0" 570 714))
]

The page is assembled in drawing order:

@shaping-racketblock+eval[
(define (draw-sampler canvas)
  (draw-header canvas)
  (draw-latin-row canvas)
  (draw-arabic-row canvas)
  (draw-hebrew-row canvas)
  (draw-feature-row canvas))
]

@(finish-figure
 (tutorial-figure
 (string-append
   "A finished language sampler has Latin, Arabic, and Hebrew rows and a "
   "standard-ligature comparison."
)
 (shaping-image
(shaping-render-pict
 width height
 draw-sampler
 #:background paper-color
 #:scale 0.60)
)))

@section{Save the Result}

The sampler is an ordinary raster drawing:

@racketblock[
(define surface
  (make-surface width height
                #:background paper-color))

(draw-sampler (surface-canvas surface))

(save-png surface
          "language-sampler.png"
          #:exists 'replace)
]

@section[#:tag "try-it"]{Try It}

Try changing @racket["liga=0"] to @racket["liga=1"]. Compare the glyph count
and visible result for the selected typeface.

Try changing the Latin sample from @racket["office"] to another word containing
@racket["fi"] or @racket["ff"]. Remember that ligature availability is
font-dependent.

Try changing the Arabic @racket[right-edge] value. Compare the origin with the
origin plus the advance: the larger coordinate should equal the chosen edge.
Look separately for ink that extends beyond that advance interval.

Try inspecting @racket[shaped-run-clusters] for one of the runs. Cluster values
are UTF-8 byte offsets into the original input, not Racket character indices.

Try asking @racket[font-manager-match-character] for another script installed on
your system, then create a font and shaper from the returned typeface.

@section[#:tag "next-steps"]{Where to Go From Here}

You can now choose a script font and draw a shaped run. A mixed-direction paragraph
needs paragraph layout, not just a right-to-left setting on one shaper.

@tutorial-next["shaping"]

@section[#:tag "example-source"]{The Complete Example}

@tutorial-sources["shaping"]
