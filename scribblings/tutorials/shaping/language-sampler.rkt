#lang racket

;;;
;;; Language Sampler
;;;

;; Builds a multilingual specimen using suitable fonts and shaped runs.
;; This runnable tutorial example demonstrates public Skia APIs alongside the corresponding
;; manual.


;;;
;;; Imports and Exports
;;;

(require skia)

;;;
;;; Sampler Dimensions and Palette
;;;

; width : exact-integer?
;   Specifies width in the drawing's local coordinate units.
(define width 900)

; height : exact-integer?
;   Specifies height in the drawing's local coordinate units.
(define height 780)

; paper-color : string?
;   Specifies the paper color color used by this drawing.
(define paper-color "#F4F6F9")

; ink-color : string?
;   Specifies the ink color color used by this drawing.
(define ink-color "#20304C")

; guide-color : string?
;   Specifies the guide color color used by this drawing.
(define guide-color "#CBD5E1")

; blue-color : string?
;   Specifies the blue color color used by this drawing.
(define blue-color "#326DE6")

; teal-color : string?
;   Specifies the teal color color used by this drawing.
(define teal-color "#18A999")

; orange-color : string?
;   Specifies the orange color color used by this drawing.
(define orange-color "#F38C42")

;;;
;;; Script Font Selection and Shapers
;;;

; require-script-face : any/c any/c string? string? #:match [any/c] -> typeface?
;   Finds a font supporting the sample and reports a useful error when none is available.
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

; arabic-sample : string?
;   Supplies the Arabic phrase used to demonstrate right-to-left shaping.
(define arabic-sample "مرحبا بالعالم")

; hebrew-sample : string?
;   Supplies the Hebrew phrase used to demonstrate right-to-left shaping.
(define hebrew-sample "שלום עולם")

; font-manager : font-manager?
;   Queries installed faces to find real fonts supporting the tutorial samples.
(define font-manager (default-font-manager))

; latin-face : typeface?
;   Retains the latin face used by the specimen's fonts.
(define latin-face (make-typeface))

; arabic-face : typeface?
;   Retains the arabic face used by the specimen's fonts.
(define arabic-face
  (require-script-face font-manager #\م arabic-sample "ar"))

; hebrew-face : typeface?
;   Retains the hebrew face used by the specimen's fonts.
(define hebrew-face
  (require-script-face font-manager #\ש hebrew-sample "he"))

; latin-font : font?
;   Selects the latin font used by the scene.
(define latin-font (make-font latin-face #:size 48))

; arabic-font : font?
;   Selects the arabic font used by the scene.
(define arabic-font (make-font arabic-face #:size 54))

; hebrew-font : font?
;   Selects the hebrew font used by the scene.
(define hebrew-font (make-font hebrew-face #:size 50))

; latin-shaper : shaper?
;   Retains the latin shaper used to position the corresponding script.
(define latin-shaper (make-shaper latin-font))

; arabic-shaper : shaper?
;   Retains the arabic shaper used to position the corresponding script.
(define arabic-shaper (make-shaper arabic-font))

; hebrew-shaper : shaper?
;   Retains the hebrew shaper used to position the corresponding script.
(define hebrew-shaper (make-shaper hebrew-font))

;;;
;;; Labels and Alignment
;;;

; right-aligned-run-x : any/c real? -> real?
;   Computes the baseline origin that aligns a shaped run to the requested right edge.
(define (right-aligned-run-x run right-edge)
  (define advance (shaped-run-advance-x run))
  (if (negative? advance)
      right-edge
      (- right-edge advance)))

; draw-rule : canvas? real? -> void?
;   Draws the rule component in the current canvas coordinate system.
(define (draw-rule canvas y)
  (define paint
    (make-paint #:color guide-color
                #:style 'stroke
                #:stroke-width 1))
  (draw-line canvas 54 y (- width 54) y paint))

; draw-label : canvas? string? real? real? -> void?
;   Draws the label component in the current canvas coordinate system.
(define (draw-label canvas text x y)
  (define font (make-font latin-face #:size 14))
  (define paint (make-paint #:color ink-color))
  (draw-simple-text canvas text x y font paint))

; draw-header : canvas? -> void?
;   Draws the header component in the current canvas coordinate system.
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

;;;
;;; Script and Feature Rows
;;;

; draw-latin-row : canvas? -> void?
;   Draws the latin row component in the current canvas coordinate system.
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

; draw-arabic-row : canvas? -> void?
;   Draws the arabic row component in the current canvas coordinate system.
(define (draw-arabic-row canvas)
  (define paint (make-paint #:color orange-color))
  (define run
    (shape-text arabic-shaper
                arabic-sample
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

; draw-hebrew-row : canvas? -> void?
;   Draws the hebrew row component in the current canvas coordinate system.
(define (draw-hebrew-row canvas)
  (define paint (make-paint #:color teal-color))
  (define run
    (shape-text hebrew-shaper
                hebrew-sample
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

; draw-feature-row : canvas? -> void?
;   Draws the feature row component in the current canvas coordinate system.
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

;;;
;;; Sampler Assembly
;;;

; draw-sampler : canvas? -> void?
;   Draws the sampler component in the current canvas coordinate system.
(define (draw-sampler canvas)
  (draw-header canvas)
  (draw-latin-row canvas)
  (draw-arabic-row canvas)
  (draw-hebrew-row canvas)
  (draw-feature-row canvas))

;;;
;;; Command-Line Entry Point
;;;

(module+ main

  ; surface : surface?
  ;   Owns the raster drawing target used to produce the example's output.
  (define surface
    (make-surface width height
                  #:background paper-color))
  (draw-sampler (surface-canvas surface))
  (save-png surface
            "language-sampler.png"
            #:exists 'replace))

;;;
;;; Regression Checks
;;;

(module+ test
  (require rackunit)
  ;; Force a missing match without changing the host's installed fonts.

  ; missing-match : any/c any/c #:languages any/c -> #f
  ;   Models an unavailable font match so the diagnostic path can be tested.
  (define (missing-match _manager _representative #:languages _languages) #f)
  (check-exn
   #rx"Install a font"
   (lambda ()
     (require-script-face font-manager #\م arabic-sample "ar" #:match missing-match)))
  ;; These checks use the actual selected fonts and the complete strings being drawn.
  (for ([font (in-list (list arabic-font hebrew-font))]
        [sample (in-list (list arabic-sample hebrew-sample))])
    (check-true
     (for/and ([glyph (in-vector (font-text->glyphs font sample))])
       (positive? glyph)))))
