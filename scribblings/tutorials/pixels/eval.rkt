#lang racket/base

(require racket/runtime-path scribble/eval skia "pixel-lab.rkt" "../support/figures.rkt")
(provide pixels-interaction pixels-racketblock+eval pixel-study-pict source-pict processed-pict
         stamped-pict tiny-pixel-pict)
(define-runtime-path program-source "pixel-lab.rkt")
(define-runtime-path program-directory ".")
(define pixels-eval (make-base-eval))
(pixels-eval `(current-directory ,(path->string program-directory)))
(pixels-eval '(require racket skia))
(pixels-eval `(require (file ,(path->string program-source))))
(define images (make-study-images))

(define (pixel-study-pict)
  (render-pict 780 360 (lambda (canvas) (draw-pixel-study canvas images)) #:scale 0.84))
(define (source-pict) (image-pict (car images) 2))
(define (processed-pict) (image-pict (cadr images) 2))
(define (stamped-pict) (image-pict (caddr images) 2))

(define (tiny-pixel-pict)
  (with-skia ([buffer (make-raster-buffer 3 2 #:row-bytes 16)])
    (raster-buffer-write-rgba!
     buffer (bytes 255 0 0 255  0 255 0 255  0 0 255 255
                   255 255 0 255  0 255 255 255  255 0 255 255))
    (with-skia ([image (raster-buffer->image buffer)])
      (image-pict image 48))))

(define-syntax-rule (pixels-interaction expression ...)
  (interaction #:eval pixels-eval expression ...))
(define-syntax-rule (pixels-racketblock+eval expression ...)
  (racketblock+eval #:eval pixels-eval expression ...))
