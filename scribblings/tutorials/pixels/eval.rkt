#lang racket/base

(require racket/runtime-path scribble/eval skia "pixel-lab.rkt" "../support/figures.rkt")
(provide pixels-interaction pixels-racketblock+eval pixel-study-pict source-pict processed-pict
         stamped-pict tiny-pixel-pict tiny-layout-pict)
(define-runtime-path program-source "pixel-lab.rkt")
(define-runtime-path program-directory ".")
(define pixels-eval (make-base-eval))
(pixels-eval `(current-directory ,(path->string program-directory)))
(pixels-eval '(require racket skia))
(pixels-eval `(require (file ,(path->string program-source))))
(define images (make-study-images))

(define (pixel-study-pict)
  (render-pict 780 360 (lambda (canvas) (draw-pixel-study canvas images)) #:scale 0.84))
(define (pixel-preview image #:region? [region? #f])
  (define width (* 2 pixel-width))
  (define height (* 2 pixel-height))
  (render-pict width height
               (lambda (canvas)
                 (draw-checker canvas 0 0 width height)
                 (draw-image-rect canvas image 0 0 width height #:sampling 'nearest)
                 (when region?
                   (define guide
                     (make-paint #:color "#C34B3B" #:style 'stroke #:stroke-width 1.5))
                   (draw-rect canvas (* 2 145) (* 2 100) (* 2 32) (* 2 20) guide)))))

(define (source-pict) (pixel-preview (car images)))
(define (processed-pict) (pixel-preview (cadr images)))
(define (stamped-pict) (pixel-preview (caddr images) #:region? #t))

(define (tiny-pixel-pict)
  (with-skia ([buffer (make-tiny-buffer)] [image (raster-buffer->image buffer)])
    (image-pict image 48)))

(define (tiny-layout-pict)
  (with-skia ([buffer (make-tiny-buffer)])
    (define storage (raster-buffer->storage-bytes buffer))
    (define stride (raster-buffer-row-bytes buffer))
    (render-pict 650 240
                 (lambda (canvas)
                   (define ink (make-paint #:color "#203653"))
                   (define active (make-paint #:color "#EDF5FB"))
                   (define padding (make-paint #:color "#F3E1B9"))
                   (define border
                     (make-paint #:color "#8C9CAD" #:style 'stroke #:stroke-width 1))
                   (define font (make-font #:size 12))
                   (define title (make-font #:size 16))
                   (draw-simple-text canvas (format "Storage: ~a bytes per row" stride)
                                     14 25 title ink)
                   (for ([label '("Pixel 0: RGBA" "Pixel 1: RGBA" "Pixel 2: RGBA" "Padding")]
                         [group (in-naturals)])
                     (draw-simple-text canvas label (+ 68 (* group 136)) 53 font ink))
                   (for ([row (in-range 2)])
                     (define y (+ 68 (* row 78)))
                     (draw-simple-text canvas (format "Row ~a" row) 14 (+ y 21) font ink)
                     (for ([column (in-range stride)])
                       (define x (+ 66 (* column 34)))
                       (define value (bytes-ref storage (+ (* row stride) column)))
                       (draw-rect canvas x y 34 32 (if (< column 12) active padding))
                       (draw-rect canvas x y 34 32 border)
                       (draw-simple-text canvas (number->string value) (+ x 5) (+ y 21) font ink))
                     (draw-simple-text canvas (format "Row starts at byte ~a" (* row stride))
                                       66 (+ y 52) font ink))
                   (draw-simple-text canvas "Padding is stored, but it is not a fourth pixel."
                                     14 228 font ink)))))

(define-syntax-rule (pixels-interaction expression ...)
  (interaction #:eval pixels-eval expression ...))
(define-syntax-rule (pixels-racketblock+eval expression ...)
  (racketblock+eval #:eval pixels-eval expression ...))
