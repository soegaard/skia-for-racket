#lang racket/base

;;;
;;; Global Cache Support
;;;

;; Provides shared inputs and drawing fixtures for global font/resource cache controls and bounded
;; memory statistics.
;; Regression suites and diagnostic programs import these fixtures to compare behavior using
;; consistent inputs.

;;;
;;; Imports and Exports
;;;
(require racket/list "../main.rkt" "typeface-fixtures.rkt")
(provide limit-settings restore-limits! with-restored-limits warm-cache! cache-test-pixels)

;;;
;;; Fixtures and Assertions
;;;

; limit-settings : -> vector?
;   Snapshots font bytes, font count, resource bytes, and single-allocation limits in that order.
(define (limit-settings)
  (vector (skia-font-cache-limit) (skia-font-cache-count-limit)
          (skia-resource-cache-limit) (skia-resource-cache-single-allocation-limit)))

; restore-limits! : vector? -> void?
;   Restores the four cache limits from the matching ordered snapshot.
(define (restore-limits! values)
  (skia-set-font-cache-limit! (vector-ref values 0))
  (skia-set-font-cache-count-limit! (vector-ref values 1))
  (skia-set-resource-cache-limit! (vector-ref values 2))
  (skia-set-resource-cache-single-allocation-limit! (vector-ref values 3))
  (void))

; with-restored-limits : (-> any) -> any
;   Restores process-global cache policy even if a cache test fails.
(define (with-restored-limits thunk)
  ;; Restores configuration, not the contents evicted by lowering a limit.
  (define saved (limit-settings))
  (dynamic-wind void thunk (lambda () (restore-limits! saved))))

; warm-cache! : -> bytes?
;   Renders deterministic fixture text to populate font caches and returns the capture.
(define (warm-cache!)
  (with-skia ([face (typeface-from-bytes (fixture-font-bytes))]
              [font (make-font face #:size 28)]
              [paint (make-paint #:color 'black)]
              [s (make-surface 80 48 #:background 'white)])
    (draw-simple-text (surface-canvas s) fixture-text 4 36 font paint)
    (surface->rgba-bytes s)))

; cache-test-pixels : -> bytes?
;   Renders a small solid rectangle to verify that cache operations preserve drawing results.
(define (cache-test-pixels)
  (with-skia ([paint (make-paint #:color 'red #:antialias? #f)]
              [surface (make-surface 8 6 #:background 'white)])
    (draw-rect (surface-canvas surface) 2 1 4 4 paint)
    (surface->rgba-bytes surface)))
