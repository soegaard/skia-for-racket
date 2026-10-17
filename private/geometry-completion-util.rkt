#lang racket/base

;;;
;;; Extended Geometry Validation
;;;

;; Checks geometry matrices, conic subdivision, path-operation lists, and span bounds.
;; Supplies shared validation for the extended path and region APIs.

;; Pure checks shared by the geometry APIs and their native-free tests.
(require racket/list racket/vector "check.rkt" "filter-util.rkt" "types.rkt"
         "geometry-util.rkt" "../matrix.rkt")
(provide geometry-float geometry-positive geometry-nonnegative geometry-matrix
         geometry-start-index geometry-point-list geometry-conic-parameters
         geometry-span-range current-path-operation-limit geometry-operation-list)

;;;
;;; Coordinates, Transforms, and Conic Inputs
;;;

; geometry-float : symbol? real? -> inexact-real?
;   Shares the filter helper's checked binary32 conversion for geometric coordinates.
(define geometry-float filter-float)

; geometry-positive : symbol? real? -> inexact-real?
;   Requires strict positivity after native binary32 rounding.
(define (geometry-positive who v)
  (define f (geometry-float who v))
  (unless (> f 0) (raise-argument-error who "positive finite C float after rounding" v))
  f)

; geometry-nonnegative : symbol? real? -> inexact-real?
;   Requires a nonnegative finite binary32 geometric parameter.
(define (geometry-nonnegative who v)
  (define f (geometry-float who v))
  (unless (>= f 0) (raise-argument-error who "nonnegative finite C float" v))
  f)

; geometry-matrix : symbol? matrix? -> sk-matrix?
;   Converts affine coefficients to native layout, preserving meaningful singular path transforms.
(define (geometry-matrix who m)
  (unless (matrix? m) (raise-argument-error who "matrix? (2D affine)" m))
  ;; Singular affine matrices are meaningful for paths. RRect transform itself
  ;; reports whether its more restrictive representation can hold the result.
  (apply make-sk-matrix
         (map (lambda (v) (geometry-float who v))
              (list (matrix-xx m) (matrix-xy m) (matrix-x0 m)
                    (matrix-yx m) (matrix-yy m) (matrix-y0 m) 0 0 1))))

; geometry-start-index : symbol? exact-integer? exact-positive-integer? -> exact-nonnegative-integer?
;   Checks a shape's zero-based starting vertex against its vertex count.
(define (geometry-start-index who index size)
  (unless (and (exact-integer? index) (<= 0 index) (< index size))
    (raise-arguments-error who "start index outside shape's vertex range"
                           "index" index "vertex count" size))
  index)

; geometry-point-list : symbol? any/c [any/c] -> list?
;   Checks point count, storage budget, and binary32 x/y pairs in source order.
(define (geometry-point-list who points [expected #f])
  (define xs (geometry-list who points))
  (geometry-budget who (length xs) (* 8 (length xs)))
  (when (and expected (not (= (length xs) expected)))
    (raise-arguments-error who "wrong point count" "expected" expected "given" (length xs)))
  (for/list ([p (in-list xs)])
    (define xy (geometry-list who p))
    (unless (= 2 (length xy)) (raise-argument-error who "two-element point" p))
    (map (lambda (v) (geometry-float who v)) xy)))

; geometry-conic-parameters : symbol? any/c any/c any/c real? integer? -> (values list? real?
;   integer?)
;   Checks a rational conic and bounded subdivision power, returning its required output-point
;   capacity.
(define (geometry-conic-parameters who p0 p1 p2 weight power)
  ;; Deliberately limit subdivision powers to 0..5; bound the buffer before FFI.
  (unless (and (exact-integer? power) (<= 0 power 5))
    (raise-argument-error who "exact integer from 0 through 5" power))
  (define points (geometry-point-list who (list p0 p1 p2) 3))
  (define w (geometry-positive who weight))
  (define capacity (add1 (* 2 (arithmetic-shift 1 power))))
  (geometry-budget who capacity (* 8 capacity))
  (values points w capacity))

;;;
;;; Bounded Path Operations and Spans
;;;

; current-path-operation-limit : (parameter/c exact-positive-integer?)
;   Limits ordered path-operation batches; defaults to 4096 operations.
(define current-path-operation-limit
  (make-parameter 4096
    (lambda (v)
      (unless (and (exact-integer? v) (<= 1 v #x7fffffff))
        (raise-argument-error 'current-path-operation-limit "positive int32 operation count" v))
      v)))

; geometry-operation-list : symbol? any/c -> list?
;   Checks bounded ordered operation/path pairs before executing a native path-operation batch.
(define (geometry-operation-list who operations)
  (define xs (geometry-list who operations))
  (unless (<= (length xs) (current-path-operation-limit))
    (raise-arguments-error who "too many path operations"
                           "count" (length xs) "limit" (current-path-operation-limit)))
  (geometry-budget who (length xs) (* 16 (length xs)))
  (for/list ([entry (in-list xs)])
    (define pair (geometry-list who entry))
    (unless (= 2 (length pair))
      (raise-argument-error who "(operation path) pairs" entry))
    (choice who (car pair) path-op-values)
    pair))

; geometry-span-range : symbol? integer? integer? integer? -> (values integer? integer? integer?)
;   Checks a scanline y and ordered left/right region coordinates.
(define (geometry-span-range who y left right)
  (define iy (geometry-int who y))
  (define il (geometry-int who left))
  (define ir (geometry-int who right))
  (unless (<= il ir)
    (raise-arguments-error who "left must not exceed right" "left" left "right" right))
  (values iy il ir))
