#lang racket/base

;;;
;;; Figures
;;;

;; Converts actual tutorial drawings and images into presentation-sized picts.
;; This module supports documentation assembly and shared examples rather than the public Skia
;; API.


;; Presentation helpers only. Each caller supplies the real tutorial drawing.
;;;
;;; Imports and Exports
;;;

(require skia
         (prefix-in draw: racket/draw)
         (prefix-in pict: pict))

(provide render-pict image-pict captioned-pict figure-row)

;;;
;;; Documentation Data and Helpers
;;;

; render-pict : real? real? procedure? #:scale [real?] #:background [any/c] #:color-space [(or/c
; color-space? #f)] -> pict?
;;   Draws onto a temporary surface and returns a presentation-scaled pict.
(define (render-pict width height draw
                     #:scale [scale 1]
                     #:background [background 'white]
                     #:color-space [color-space #f])
  (with-skia ([surface (make-surface width height
                                     #:background background
                                     #:color-space color-space)])
    (draw (surface-canvas surface))
    (pict:scale
     (pict:bitmap
      (draw:read-bitmap (open-input-bytes (surface->png-bytes surface)) 'png/alpha))
     scale)))

;; Magnification happens in Skia, not in the HTML/CSS image scaler.
; image-pict : image? real? #:sampling [symbol?] #:color-space [(or/c color-space? #f)] -> pict?
;;   Renders an image at the requested enlargement with explicit sampling.
(define (image-pict image factor #:sampling [sampling 'nearest]
                    #:color-space [color-space #f])
  (define width (* factor (image-width image)))
  (define height (* factor (image-height image)))
  (render-pict width height
               (lambda (canvas)
                 (draw-image-rect canvas image 0 0 width height #:sampling sampling))
               #:color-space color-space))

; captioned-pict : string? pict? -> pict?
;;   Places a textual caption beneath the supplied pict.
(define (captioned-pict caption picture)
  (pict:vc-append 8 picture (pict:text caption)))

; figure-row : any/c ... -> pict?
;;   Builds the figure row illustration from the tutorial's actual drawing.
(define (figure-row . pictures)
  (apply pict:ht-append 16 pictures))
