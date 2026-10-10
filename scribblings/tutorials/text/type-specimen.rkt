#lang racket

(require skia)

(define width 800)
(define height 980)

(define paper-color "#F4F0E8")
(define ink-color "#25313D")
(define accent-color "#C8553D")
(define blue-color "#2D6CDF")
(define guide-color "#AAB2BC")
(define panel-color "#FBFAF7")

(define face (make-typeface))
(define family-name (typeface-family-name face))

(define (draw-rule canvas y)
  (define paint
    (make-paint #:color guide-color
                #:style 'stroke
                #:stroke-width 1))
  (draw-line canvas 56 y (- width 56) y paint))

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

(define (draw-centered-line canvas)
  (define font (make-font face #:size 28))
  (define paint (make-paint #:color blue-color))
  (define text "MEASURED, THEN CENTERED")
  (define advance (measure-simple-text font text))
  (define x (/ (- width advance) 2))
  (draw-simple-text canvas text x 910 font paint))

(define (draw-footer canvas)
  (define font (make-font face #:size 14))
  (define paint (make-paint #:color ink-color))
  (draw-simple-text canvas
                    "Origin / baseline / advance / bounds / metrics"
                    58 952
                    font paint))

(define (draw-specimen canvas)
  (draw-header canvas)
  (draw-size-scale canvas)
  (draw-alphabet canvas)
  (draw-metrics-panel canvas)
  (draw-centered-line canvas)
  (draw-footer canvas))

(module+ main
  (define surface
    (make-surface width height #:background paper-color))
  (draw-specimen (surface-canvas surface))
  (save-png surface "type-specimen.png" #:exists 'replace))
