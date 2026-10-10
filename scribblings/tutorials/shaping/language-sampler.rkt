#lang racket

(require skia)

(define width 900)
(define height 780)

(define paper-color "#F4F6F9")
(define ink-color "#20304C")
(define guide-color "#CBD5E1")
(define blue-color "#326DE6")
(define teal-color "#18A999")
(define orange-color "#F38C42")

(define font-manager (default-font-manager))
(define latin-face (make-typeface))
(define arabic-face
  (or (font-manager-match-character
       font-manager #\م
       #:languages '("ar"))
      (make-typeface)))
(define hebrew-face
  (or (font-manager-match-character
       font-manager #\ש
       #:languages '("he"))
      (make-typeface)))

(define latin-font (make-font latin-face #:size 48))
(define arabic-font (make-font arabic-face #:size 54))
(define hebrew-font (make-font hebrew-face #:size 50))

(define latin-shaper (make-shaper latin-font))
(define arabic-shaper (make-shaper arabic-font))
(define hebrew-shaper (make-shaper hebrew-font))

(define (right-aligned-run-x run right-edge)
  (define advance (shaped-run-advance-x run))
  (if (negative? advance)
      right-edge
      (- right-edge advance)))

(define (draw-rule canvas y)
  (define paint
    (make-paint #:color guide-color
                #:style 'stroke
                #:stroke-width 1))
  (draw-line canvas 54 y (- width 54) y paint))

(define (draw-label canvas text x y)
  (define font (make-font latin-face #:size 14))
  (define paint (make-paint #:color ink-color))
  (draw-simple-text canvas text x y font paint))

(define (draw-header canvas)
  (define kicker-font (make-font latin-face #:size 14))
  (define title-font (make-font latin-face #:size 52))
  (define ink (make-paint #:color ink-color))
  (define blue (make-paint #:color blue-color))
  (draw-simple-text canvas
                    "SKIA / SHAPING STUDY"
                    56 62
                    kicker-font blue)
  (draw-simple-text canvas
                    "Language sampler"
                    54 126
                    title-font ink)
  (draw-rule canvas 150))

(define (draw-latin-row canvas)
  (define paint (make-paint #:color blue-color))
  (define run
    (shape-text latin-shaper
                "office affinity"
                #:language "en"))
  (draw-label canvas "LATIN / DEFAULT FEATURES" 58 190)
  (draw-shaped-run canvas latin-shaper run
                   58 250 paint)
  (draw-label canvas
              (format "~a glyphs"
                      (shaped-run-glyph-count run))
              58 280))

(define (draw-arabic-row canvas)
  (define paint (make-paint #:color orange-color))
  (define run
    (shape-text arabic-shaper
                "مرحبا بالعالم"
                #:direction 'rtl
                #:script 'arab
                #:language "ar"))
  (define x
    (right-aligned-run-x run 842))
  (draw-label canvas "ARABIC / RTL" 58 330)
  (draw-shaped-run canvas arabic-shaper run
                   x 390 paint)
  (draw-label canvas
              (format "~a glyphs"
                      (shaped-run-glyph-count run))
              58 420))

(define (draw-hebrew-row canvas)
  (define paint (make-paint #:color teal-color))
  (define run
    (shape-text hebrew-shaper
                "שלום עולם"
                #:direction 'rtl
                #:script 'hebr
                #:language "he"))
  (define x
    (right-aligned-run-x run 842))
  (draw-label canvas "HEBREW / RTL" 58 470)
  (draw-shaped-run canvas hebrew-shaper run
                   x 530 paint)
  (draw-label canvas
              (format "~a glyphs"
                      (shaped-run-glyph-count run))
              58 560))

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
  (draw-label canvas "OPENTYPE FEATURE" 58 630)
  (draw-shaped-run canvas latin-shaper default-run
                   250 680 default-paint)
  (draw-shaped-run canvas latin-shaper no-liga-run
                   570 680 alternate-paint)
  (draw-label canvas "default" 250 714)
  (draw-label canvas "liga=0" 570 714))

(define (draw-sampler canvas)
  (draw-header canvas)
  (draw-latin-row canvas)
  (draw-arabic-row canvas)
  (draw-hebrew-row canvas)
  (draw-feature-row canvas))

(module+ main
  (define surface
    (make-surface width height
                  #:background paper-color))
  (draw-sampler (surface-canvas surface))
  (save-png surface
            "language-sampler.png"
            #:exists 'replace))
