#lang racket/base
(require ffi/unsafe "../main.rkt" "../private/types.rkt")
(provide filter-graph-doctor!)
(define (filter-graph-doctor!)
  (unless (and (= (ctype-sizeof _sk-isize) 8) (= (ctype-sizeof _sk-ipoint) 8)
               (= (ctype-sizeof _sk-point3) 12))
    (error 'doctor "filter structure layout mismatch"))
  (define shifted (make-offset-image-filter 6 0))
  (with-skia ([filter (make-merge-image-filter (list #f shifted) #:crop '(4 4 18 8))]
              [s (make-surface 32 20)]
              [p (make-paint #:color 'blue #:antialias? #f #:image-filter filter)])
    (skia-close! shifted)
    (draw-rect (surface-canvas s) 4 4 8 8 p)
    (unless (and (equal? (surface-pixel s 5 6) (rgb 0 0 255))
                 (equal? (surface-pixel s 16 6) (rgb 0 0 255))
                 (zero? (rgba-alpha (surface-pixel s 24 6))))
      (error 'doctor "merge/source-slot/retention/crop regression")))
  (with-skia ([s (make-surface 20 20)]
              [f (make-matrix-convolution-image-filter 3 3 '(0 0 0 0 1 0 0 0 0))]
              [p (make-paint #:color 'red #:antialias? #f #:image-filter f)])
    (draw-rect (surface-canvas s) 4 4 8 8 p)
    (unless (equal? (surface-pixel s 8 8) (rgb 255 0 0))
      (error 'doctor "convolution layout regression")))
  (printf "Advanced filters passed: merge/source slots, closed-child retention, crop, convolution; isize=8 ipoint=8 point3=12\n"))
