#lang racket

(require skia)

(provide card-image-width
         card-image-height
         background-color
         draw-flat-card
         draw-shadowed-card
         draw-soft-accents
         draw-ring-motif
         draw-card-with-rings
         draw-card-labels
         draw-card)

(define card-image-width 960)
(define card-image-height 640)
(define background-color "#EEF3F8")
(define ink-color "#243850")
(define muted-color "#64778B")
(define blue-color "#326DE6")
(define teal-color "#1AA6AD")

(define card-x 80)
(define card-y 74)
(define card-width 800)
(define card-height 478)

(define (draw-flat-card canvas)
  (define white (make-paint #:color 'white))
  (draw-rounded-rect canvas
                     card-x card-y card-width card-height
                     28 28 white))

(define (draw-shadowed-card canvas)
  (define shadow
    (make-drop-shadow-image-filter
     0 14 14 14 (rgba 27 47 70 90)))
  (define white
    (make-paint #:color 'white
                #:image-filter shadow))
  (draw-rounded-rect canvas
                     card-x card-y card-width card-height
                     28 28 white))

(define (draw-soft-accents canvas)
  (define blur (make-blur-image-filter 22 22))
  (define teal
    (make-paint #:color (rgba 46 184 192 150)
                #:image-filter blur))
  (define apricot
    (make-paint #:color (rgba 245 154 108 165)
                #:image-filter blur))
  (draw-circle canvas 665 288 78 teal)
  (draw-circle canvas 744 373 58 apricot))

(define (draw-ring-motif canvas)
  (define ring
    (make-paint #:color ink-color
                #:style 'stroke
                #:stroke-width 2.4))
  (define light-ring
    (make-paint #:color "#7A97B0"
                #:style 'stroke
                #:stroke-width 1.2))
  (define blue (make-paint #:color blue-color))
  (define teal (make-paint #:color teal-color))
  (draw-circle canvas 703 319 101 ring)
  (draw-circle canvas 703 319 72 light-ring)
  (draw-line canvas 595 319 811 319 light-ring)
  (draw-line canvas 703 210 703 428 light-ring)
  (draw-circle canvas 703 319 9 blue)
  (draw-circle canvas 703 218 5 teal)
  (draw-circle canvas 804 319 5 teal))

(define (draw-card-with-rings canvas)
  (draw-shadowed-card canvas)
  (draw-soft-accents canvas)
  (draw-ring-motif canvas))

(define (draw-card-labels canvas)
  (define face (make-typeface))
  (define kicker-font (make-font face #:size 17))
  (define title-font (make-font face #:size 53))
  (define subtitle-font (make-font face #:size 22))
  (define caption-font (make-font face #:size 15))
  (define ink (make-paint #:color ink-color))
  (define muted (make-paint #:color muted-color))
  (define blue (make-paint #:color blue-color))
  (define rule
    (make-paint #:color "#D5DFE9"
                #:style 'stroke
                #:stroke-width 2))
  (draw-simple-text canvas "SKIA / LIGHT STUDY" 132 137 kicker-font blue)
  (draw-simple-text canvas "Light and depth" 129 225 title-font ink)
  (draw-simple-text canvas "A few filters change the mood." 132 270
                    subtitle-font muted)
  (draw-line canvas 132 318 516 318 rule)
  (draw-simple-text canvas "SOFT SHADOW" 132 367 caption-font blue)
  (draw-simple-text canvas "BLURRED COLOR" 132 405 caption-font blue)
  (draw-simple-text canvas "SHARP DETAILS" 132 443 caption-font blue)
  (draw-simple-text canvas "GEOMETRY  /  COLOR  /  LIGHT" 132 514 caption-font muted)
  (draw-simple-text canvas "10" 829 514 caption-font muted))

(define (draw-card canvas)
  (draw-card-with-rings canvas)
  (draw-card-labels canvas))

(module+ main
  (define surface
    (make-surface card-image-width card-image-height
                  #:background background-color))
  (draw-card (surface-canvas surface))
  (save-png surface "card-with-shadows.png" #:exists 'replace))
