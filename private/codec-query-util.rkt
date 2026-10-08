#lang racket/base
;; Pure argument/result validation. No native library or pixel allocation.
(require "check.rkt")
(provide codec-query-scale codec-query-rect codec-query-check-bounds
         codec-query-source-size codec-query-scaled-result codec-query-subset-result)
(define int32-max #x7fffffff)

(define (codec-query-scale who value)
  ;; Validate AFTER rounding to the actual C float. A positive Racket number
  ;; may otherwise become zero at the ABI boundary and violate SkCodec's contract.
  (define rounded
    (floating-point-bytes->real (real->floating-point-bytes (scalar who value) 4)))
  (unless (> rounded 0)
    (raise-argument-error who "positive finite scale representable as a nonzero C float" value))
  rounded)

(define (codec-query-rect who x y width height)
  (for ([v (in-list (list x y))])
    (unless (and (exact-integer? v) (<= 0 v int32-max))
      (raise-argument-error who "nonnegative signed-32-bit integer coordinate" v)))
  (for ([v (in-list (list width height))])
    (unless (and (exact-integer? v) (<= 1 v int32-max))
      (raise-argument-error who "positive signed-32-bit integer extent" v)))
  (define right (+ x width))
  (define bottom (+ y height))
  (unless (and (<= right int32-max) (<= bottom int32-max))
    (raise-arguments-error who "subset endpoint exceeds signed 32-bit range"
                           "subset" (list x y width height)))
  (vector-immutable x y right bottom))

(define (codec-query-source-size who width height)
  ;; Dimension metadata is not a request to allocate width*height pixels.
  (unless (and (exact-integer? width) (<= 1 width int32-max)
               (exact-integer? height) (<= 1 height int32-max))
    (error who "native codec returned invalid source dimensions: ~a by ~a" width height))
  (values width height))

(define (codec-query-check-bounds who rect width height)
  (unless (and (<= (vector-ref rect 2) width) (<= (vector-ref rect 3) height))
    (raise-arguments-error who "subset must be nonempty and inside the encoded image bounds"
                           "subset (left top right bottom)" rect
                           "encoded dimensions" (list width height)))
  (void))

(define (codec-query-scaled-result who source-width source-height width height)
  (codec-query-source-size who width height)
  (unless (and (<= width source-width) (<= height source-height))
    (error who "native scaled dimensions exceed the encoded image bounds"))
  (values width height))

(define (codec-query-subset-result who width height left top right bottom)
  (unless (and (exact-integer? left) (exact-integer? top)
               (exact-integer? right) (exact-integer? bottom)
               (<= 0 left) (< left right) (<= right width)
               (<= 0 top) (< top bottom) (<= bottom height))
    (error who "native subset negotiation returned an invalid rectangle"))
  ;; Do not assume containment of the requested rectangle for every codec.
  ;; The public result is the actual suggested subset, not the input request.
  (vector-immutable left top (- right left) (- bottom top)))
