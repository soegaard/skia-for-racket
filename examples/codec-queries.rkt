#lang racket/base
(require "../main.rkt")
;; JPEG suggestions describe native downscaling, not a new decoded image.
(with-skia ([surface (make-surface 16 12 #:background 'red)]
            [image (surface-snapshot surface)]
            [codec (codec-from-bytes (image->jpeg-bytes image))])
  (define-values (width height) (codec-scaled-dimensions codec 1/2))
  (printf "JPEG half-scale suggestion: ~a by ~a encoded pixels\n" width height)
  (printf "JPEG native subset: ~s\n" (codec-supported-subset codec 1 3 6 5)))
(with-skia ([surface (make-surface 16 12 #:background 'blue)]
            [image (surface-snapshot surface)]
            [codec (codec-from-bytes (image->webp-bytes image #:lossless? #t))])
  (printf "WebP request #(1 3 6 5), native suggestion: ~s\n"
          (codec-supported-subset codec 1 3 6 5)))
