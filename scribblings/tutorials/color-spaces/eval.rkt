#lang racket/base

(require racket/runtime-path scribble/eval skia "color-study.rkt" "../support/figures.rkt")
(provide colors-interaction colors-racketblock+eval color-study-pict gray-pair-pict ramp-pair-pict)
(define-runtime-path program-source "color-study.rkt")
(define-runtime-path program-directory ".")
(define colors-eval (make-base-eval))
(colors-eval `(current-directory ,(path->string program-directory)))
(colors-eval '(require racket skia))
(colors-eval `(require (file ,(path->string program-source))))
(define srgb (make-srgb-color-space))
(define images (make-color-study))

(define (color-study-pict)
  (render-pict 740 490 (lambda (canvas) (draw-color-study canvas images))
               #:color-space srgb #:scale 0.87))

(define (gray-pair-pict)
  (figure-row
   (captioned-pict "sRGB samples: 128" (image-pict (car images) 140))
   (captioned-pict
    (format "Converted samples: ~a" (bytes-ref (image->rgba-bytes (cadr images)) 0))
    (image-pict (cadr images) 140))))

(define (ramp-pair-pict)
  (render-pict 560 166
               (lambda (canvas)
                 (define font (make-font #:size 13))
                 (define ink (make-paint #:color "#263751"))
                 (draw-image-rect canvas (caddr images) 0 0 560 42 #:sampling 'nearest)
                 (draw-simple-text canvas "Equal encoded steps" 0 64 font ink)
                 (draw-image-rect canvas (cadddr images) 0 88 560 42 #:sampling 'nearest)
                 (draw-simple-text canvas "Equal linear-light steps, converted for display"
                                   0 154 font ink))
               #:color-space srgb))

(define-syntax-rule (colors-interaction expression ...)
  (interaction #:eval colors-eval expression ...))
(define-syntax-rule (colors-racketblock+eval expression ...)
  (racketblock+eval #:eval colors-eval expression ...))
