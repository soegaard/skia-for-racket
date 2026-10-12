#lang racket/base

(require racket/runtime-path scribble/eval skia "color-study.rkt" "../support/figures.rkt")
(provide colors-interaction colors-racketblock+eval color-study-pict gray-pair-pict ramp-pair-pict
         conversion-pict)
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
   (captioned-pict
    (format "sRGB samples: ~a" (bytes-ref (image->rgba-bytes (car images)) 0))
    (image-pict (car images) 140 #:color-space srgb))
   (captioned-pict
    (format "Converted samples: ~a" (bytes-ref (image->rgba-bytes (cadr images)) 0))
    (image-pict (cadr images) 140 #:color-space srgb))))

(define (conversion-pict)
  (with-skia ([linear (make-linear-srgb-color-space)]
              [source (make-gray-sample linear)]
              [converted (image-convert-color-space source srgb)]
              [wrong-tag (rgba-bytes->image 1 1 (image->rgba-bytes source) #:color-space srgb)])
    (define (one image)
      (render-pict 172 100
                   (lambda (canvas) (draw-image-rect canvas image 0 0 172 100 #:sampling 'nearest))
                   #:color-space srgb))
    (define (panel title space image)
      (define value (bytes-ref (image->rgba-bytes image) 0))
      (captioned-pict (format "Source: ~a / RGB ~a" space value)
                      (captioned-pict title (one image))))
    (figure-row (panel "Automatic conversion" "linear" source)
                (panel "Explicit conversion" "sRGB" converted)
                (panel "Wrong tag, same bytes" "sRGB" wrong-tag))))

(define (ramp-pair-pict)
  (render-pict 560 226
               (lambda (canvas)
                 (define font (make-font #:size 13))
                 (define ink (make-paint #:color "#263751"))
                 (define tick
                   (make-paint #:color "#B95136" #:style 'stroke #:stroke-width 2))
                 ;; Put the tick at the center of source pixel 128's displayed interval.
                 (define x (* 560 (/ 128.5 256)))
                 (for ([image (in-list (list (caddr images) (cadddr images)))]
                       [y '(20 132)]
                       [label '("Equal encoded steps" "Equal linear-light steps")])
                   (define midpoint (bytes-ref (image->rgba-bytes image) (* 4 128)))
                   (draw-image-rect canvas image 0 y 560 42 #:sampling 'nearest)
                   (draw-line canvas x (- y 9) x y tick)
                   (draw-line canvas x (+ y 42) x (+ y 51) tick)
                   (draw-simple-text canvas label 0 (+ y 66) font ink)
                   (draw-simple-text canvas (format "Input 128 -> sRGB output ~a" midpoint)
                                     284 (+ y 66) font ink)))
               #:color-space srgb))

(define-syntax-rule (colors-interaction expression ...)
  (interaction #:eval colors-eval expression ...))
(define-syntax-rule (colors-racketblock+eval expression ...)
  (racketblock+eval #:eval colors-eval expression ...))
