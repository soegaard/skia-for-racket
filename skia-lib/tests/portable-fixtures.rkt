#lang racket/base

;;;
;;; Portable Fixtures
;;;

;; Provides shared inputs and drawing fixtures for portable image drawing and bounded
;; vector-output alternatives.
;; Regression suites and diagnostic programs import these fixtures to compare behavior using
;; consistent inputs.

;;;
;;; Imports and Exports
;;;
(require "../main.rkt")
(provide make-portable-test-image)

;;;
;;; Fixtures and Assertions
;;;

; make-portable-test-image : -> image?
;   Creates a deterministic border/center image for portable drawing and tiling comparisons.
(define (make-portable-test-image)
  ;; Nine solid, distinct 3x3 blocks. Nearest-neighbor reference comparisons
  ;; avoid renderer-specific edge sampling while still exposing wrong cells.
  (define palette (vector (rgb 255 0 0) (rgb 0 128 0) (rgb 0 0 255)
                          (rgb 255 255 0) (rgb 0 255 255) (rgb 255 0 255)
                          (rgb 128 64 0) (rgb 64 128 192) (rgb 255 255 255)))
  (define pixels (make-bytes (* 9 9 4)))
  (for* ([y (in-range 9)] [x (in-range 9)])
    (define color (vector-ref palette (+ (quotient x 3) (* 3 (quotient y 3)))))
    (define i (* 4 (+ x (* y 9))))
    (bytes-set! pixels i (rgba-red color))
    (bytes-set! pixels (+ i 1) (rgba-green color))
    (bytes-set! pixels (+ i 2) (rgba-blue color))
    (bytes-set! pixels (+ i 3) 255))
  (rgba-bytes->image 9 9 pixels))
