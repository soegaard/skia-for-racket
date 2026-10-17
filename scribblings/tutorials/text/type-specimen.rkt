#lang racket

;;;
;;; Type Specimen
;;;

;; Builds a type specimen that makes baseline, advance, and font metrics visible.
;; This runnable tutorial example demonstrates public Skia APIs alongside the corresponding
;; manual.


;;;
;;; Imports and Exports
;;;

(require skia)

;;;
;;; Drawing Data and Helpers
;;;

; width : exact-integer?
;;   Specifies width in the drawing's local coordinate units.
(define width 800)
; height : exact-integer?
;;   Specifies height in the drawing's local coordinate units.
(define height 980)

; paper-color : string?
;;   Specifies the paper color color used by this drawing.
(define paper-color "#F4F0E8")
; ink-color : string?
;;   Specifies the ink color color used by this drawing.
(define ink-color "#25313D")
; accent-color : string?
;;   Specifies the accent color color used by this drawing.
(define accent-color "#C8553D")
; blue-color : string?
;;   Specifies the blue color color used by this drawing.
(define blue-color "#2D6CDF")
; guide-color : string?
;;   Specifies the guide color color used by this drawing.
(define guide-color "#AAB2BC")
; panel-color : string?
;;   Specifies the panel color color used by this drawing.
(define panel-color "#FBFAF7")

; face : typeface?
;;   Retains the face used by the specimen's fonts.
(define face (make-typeface))
; family-name : string?
;;   Records the actual typeface family so the specimen identifies its font.
(define family-name (typeface-family-name face))

; draw-rule : canvas? real? -> void?
;;   Draws the rule component in the current canvas coordinate system.
(define (draw-rule canvas y)
  (define paint
    (make-paint #:color guide-color
                #:style 'stroke
                #:stroke-width 1))
  (draw-line canvas 56 y (- width 56) y paint))

; draw-header : canvas? -> void?
;;   Draws the header component in the current canvas coordinate system.
(define (draw-header canvas)
  (define kicker-font (make-font face #:size 15))
  (define title-font (make-font face #:size 58))
  (define body-font (make-font face #:size 18))
  (define ink (make-paint #:color ink-color))
  (define accent (make-paint #:color accent-color))
  (draw-simple-text canvas
                    "SKIA / TYPE SPECIMEN"
                    58 64
                    kicker-font accent)
  (draw-simple-text canvas
                    "Simple text"
                    56 132
                    title-font ink)
  (draw-simple-text canvas
                    (format "Platform default: ~a" family-name)
                    58 170
                    body-font ink)
  (draw-rule canvas 194))

; draw-size-scale : canvas? -> void?
;;   Draws the size scale component in the current canvas coordinate system.
(define (draw-size-scale canvas)
  (define paint (make-paint #:color ink-color))
  (define label-font (make-font face #:size 13))
  (define label-paint (make-paint #:color accent-color))
  (for ([size '(24 36 54 78)]
        [baseline '(250 304 376 470)])
    (define font (make-font face #:size size))
    (draw-simple-text canvas
                      (number->string size)
                      58 baseline
                      label-font label-paint)
    (draw-simple-text canvas
                      "Skia"
                      110 baseline
                      font paint)))

; draw-alphabet : canvas? -> void?
;;   Draws the alphabet component in the current canvas coordinate system.
(define (draw-alphabet canvas)
  (define font (make-font face #:size 24))
  (define paint (make-paint #:color ink-color))
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

; draw-metrics-panel : canvas? -> void?
;;   Draws the metrics panel component in the current canvas coordinate system.
(define (draw-metrics-panel canvas)
  (define font (make-font face #:size 78))
  (define label-font (make-font face #:size 15))
  (define text-paint (make-paint #:color ink-color))
  (define accent (make-paint #:color accent-color))
  (define guide
    (make-paint #:color guide-color
                #:style 'stroke
                #:stroke-width 1))
  (define origin-paint (make-paint #:color blue-color))
  (define panel (make-paint #:color panel-color))
  (define metrics (font-get-metrics font))
  (define x 92)
  (define baseline 790)
  (define ascent-y (+ baseline (font-metrics-ascent metrics)))
  (define descent-y (+ baseline (font-metrics-descent metrics)))

  (draw-rounded-rect canvas 52 682 696 164 18 18 panel)
  (draw-simple-text canvas "Ag" x baseline font accent)
  (draw-circle canvas x baseline 4 origin-paint)

  (for ([y (list ascent-y baseline descent-y)]
        [label '("ascent" "baseline" "descent")])
    (draw-line canvas 76 y 720 y guide)
    (draw-simple-text canvas label 610 (- y 7) label-font text-paint)))

; draw-centered-line : canvas? -> void?
;;   Draws the centered line component in the current canvas coordinate system.
(define (draw-centered-line canvas)
  (define font (make-font face #:size 28))
  (define paint (make-paint #:color blue-color))
  (define text "MEASURED, THEN CENTERED")
  (define advance (measure-simple-text font text))
  (define x (/ (- width advance) 2))
  (draw-simple-text canvas text x 910 font paint))

; draw-footer : canvas? -> void?
;;   Draws the footer component in the current canvas coordinate system.
(define (draw-footer canvas)
  (define font (make-font face #:size 14))
  (define paint (make-paint #:color ink-color))
  (draw-simple-text canvas
                    "Origin / baseline / advance / bounds / metrics"
                    58 952
                    font paint))

; draw-specimen : canvas? -> void?
;;   Draws the specimen component in the current canvas coordinate system.
(define (draw-specimen canvas)
  (draw-header canvas)
  (draw-size-scale canvas)
  (draw-alphabet canvas)
  (draw-metrics-panel canvas)
  (draw-centered-line canvas)
  (draw-footer canvas))

;;;
;;; Command-Line Entry Point
;;;

(module+ main
  ; surface : surface?
  ;;   Owns the raster drawing target used to produce the example's output.
  (define surface
    (make-surface width height #:background paper-color))
  (draw-specimen (surface-canvas surface))
  (save-png surface "type-specimen.png" #:exists 'replace))
