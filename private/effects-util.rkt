#lang racket/base
;; Checks only: requiring this module does not load Skia or acquire a GPU.
(require racket/match "check.rkt" "filter-util.rkt" "types.rkt" "../matrix.rkt")
(provide effect-positive effect-nonnegative effect-matrix effect-table
         effect-clip effect-noise effect-path-size!)

(define (effect-positive who value)
  (define f (filter-float who value))
  (unless (> f 0) (raise-argument-error who "positive finite C float (after rounding)" value))
  f)
(define (effect-nonnegative who value)
  (define f (filter-float who value))
  (unless (>= f 0) (raise-argument-error who "nonnegative finite C float" value))
  f)
(define (effect-matrix who m)
  (unless (matrix? m) (raise-argument-error who "matrix? (2D affine)" m))
  (unless (matrix-invert m)
    (raise-arguments-error who "lattice matrix must have a representable inverse" "matrix" m))
  (make-sk-matrix (matrix-xx m) (matrix-xy m) (matrix-x0 m)
                  (matrix-yx m) (matrix-yy m) (matrix-y0 m) 0.0 0.0 1.0))
(define (effect-table who table)
  (unless (and (bytes? table) (= (bytes-length table) 256))
    (raise-argument-error who "bytes? containing exactly 256 coverage entries" table))
  (unless (<= 256 (current-skia-byte-limit))
    (error who "coverage table exceeds current-skia-byte-limit"))
  (bytes->immutable-bytes (bytes-copy table)))
(define (effect-clip who lo hi)
  (unless (and (byte? lo) (byte? hi) (< lo hi))
    (raise-arguments-error who "coverage thresholds must satisfy 0 <= min < max <= 255"
                           "min" lo "max" hi))
  (values lo hi))
(define (effect-noise who x y octaves seed tile)
  (define fx (effect-nonnegative who x))
  (define fy (effect-nonnegative who y))
  (unless (and (exact-integer? octaves) (<= 0 octaves 255))
    (raise-argument-error who "exact integer from 0 through 255" octaves))
  (define sd (filter-float who seed))
  (define ts
    (and tile
         (match (if (vector? tile) (vector->list tile) tile)
           [(list w h)
            ;; A tile size is a periodicity hint, not a pixel allocation.
            (for ([n (in-list (list w h))])
              (unless (and (exact-integer? n) (<= 1 n 32768))
                (raise-argument-error who "tile dimensions from 1 through 32768" tile)))
            (make-sk-isize w h)]
           [_ (raise-argument-error who "#f or a two-element tile-size list/vector" tile)])))
  (values fx fy octaves sd ts))
(define (effect-path-size! who points)
  (unless (positive? points)
    (raise-arguments-error who "stamp path must not be empty" "point count" points))
  ;; Bound the copied control-point payload; not a total native-heap promise.
  (unless (<= (* 8 points) (current-skia-byte-limit))
    (error who "stamp control points exceed current-skia-byte-limit")))
