#lang racket/base
;; Original pixels; native encoders create their own small format fixtures.
(require racket/list "../main.rkt")
(provide query-fixture-bytes query-fixture-pixels query-fixture-width query-fixture-height)
(define query-fixture-width 16)
(define query-fixture-height 12)
(define (query-fixture-pixels [width query-fixture-width] [height query-fixture-height])
  (apply bytes-append
    (for*/list ([y (in-range height)] [x (in-range width)])
      (bytes (modulo (* x 13) 256) (modulo (* y 19) 256)
             (modulo (+ (* x 7) (* y 11)) 256) 255))))
(define (query-fixture-bytes format [width query-fixture-width] [height query-fixture-height])
  (with-skia ([image (rgba-bytes->image width height (query-fixture-pixels width height))])
    (case format
      [(png) (image->png-bytes image)]
      [(jpeg) (image->jpeg-bytes image #:quality 100 #:downsample 'yuv-444)]
      [(webp) (image->webp-bytes image #:lossless? #t)]
      [else (raise-argument-error 'query-fixture-bytes "'png, 'jpeg, or 'webp" format)])))
