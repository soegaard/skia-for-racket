#lang racket/base
(require racket/list "../main.rkt" "typeface-fixtures.rkt")
(provide limit-settings restore-limits! with-restored-limits warm-cache! cache-test-pixels)
(define (limit-settings)
  (vector (skia-font-cache-limit) (skia-font-cache-count-limit)
          (skia-resource-cache-limit) (skia-resource-cache-single-allocation-limit)))
(define (restore-limits! values)
  (skia-set-font-cache-limit! (vector-ref values 0))
  (skia-set-font-cache-count-limit! (vector-ref values 1))
  (skia-set-resource-cache-limit! (vector-ref values 2))
  (skia-set-resource-cache-single-allocation-limit! (vector-ref values 3))
  (void))
(define (with-restored-limits thunk)
  ;; Restores configuration, not the contents evicted by lowering a limit.
  (define saved (limit-settings))
  (dynamic-wind void thunk (lambda () (restore-limits! saved))))
(define (warm-cache!)
  (with-skia ([face (typeface-from-bytes (fixture-font-bytes))]
              [font (make-font face #:size 28)]
              [paint (make-paint #:color 'black)]
              [s (make-surface 80 48 #:background 'white)])
    (draw-simple-text (surface-canvas s) fixture-text 4 36 font paint)
    (surface->rgba-bytes s)))
(define (cache-test-pixels)
  (with-skia ([paint (make-paint #:color 'red #:antialias? #f)]
              [surface (make-surface 8 6 #:background 'white)])
    (draw-rect (surface-canvas surface) 2 1 4 4 paint)
    (surface->rgba-bytes surface)))
