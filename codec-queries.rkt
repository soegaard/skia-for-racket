#lang racket/base

;;;
;;; Codec Dimension Queries
;;;

;; Queries decoder-supported scaled dimensions and subset rectangles.
;; This public layer validates requested geometry before applications allocate decoder output or
;; begin native decoding.

;;;
;;; Imports and Exports
;;;

;; 0.76a: native negotiation only; no scaled/subset decode or resampling fallback.
(require "private/native.rkt" "private/types.rkt" "private/lifetime.rkt"
         "private/codec-query-util.rkt"
         (submod "private/core.rkt" codec-query-internals))
(provide codec-scaled-dimensions codec-supported-subset)

;;;
;;; Scaled Dimensions and Supported Subsets
;;;

; source-size : symbol? cpointer? -> (values exact-positive-integer? exact-positive-integer?)
;   Reads and validates the codec's source width and height.
(define (source-size who ptr)
  (define info (make-sk-image-info #f 0 0 0 0))
  (sk_codec_get_info ptr info)
  (codec-query-source-size who (sk-image-info-width info) (sk-image-info-height info)))

; codec-scaled-dimensions : codec? (and/c real? (>/c 0)) -> (values exact-positive-integer?
;   exact-positive-integer?)
;   Returns the native decoder's proposed pixel dimensions for scale.
(define (codec-scaled-dimensions codec scale)
  (define who 'codec-scaled-dimensions)
  (define handle (codec-h who codec))
  (define requested (codec-query-scale who scale))
  (call-with-owned who (list handle)
    (lambda (ptr)
      (define-values (width height) (source-size who ptr))
      (define size (make-sk-isize 0 0))
      (sk_codec_get_scaled_dimensions ptr requested size)
      (codec-query-scaled-result who width height (sk-isize-width size) (sk-isize-height size)))))

; codec-supported-subset : codec? (integer-in 0 2147483647) (integer-in 0 2147483647) (integer-in 1
;   2147483647) (integer-in 1 2147483647) -> (or/c #f (and/c (vector/c exact-integer? exact-integer?
;   exact-positive-integer? exact-positive-integer?) immutable?))
;   Returns the native decoder's proposed subset as an immutable x, y, width, height vector, or #f
;   when subset decoding is unsupported.
(define (codec-supported-subset codec x y width height)
  (define who 'codec-supported-subset)
  (define handle (codec-h who codec))
  (define requested (codec-query-rect who x y width height))
  (call-with-owned who (list handle)
    (lambda (ptr)
      (define-values (source-width source-height) (source-size who ptr))
      (codec-query-check-bounds who requested source-width source-height)
      (define rect (make-sk-irect (vector-ref requested 0) (vector-ref requested 1)
                                 (vector-ref requested 2) (vector-ref requested 3)))
      ;; On false, the ABI explicitly leaves rect undefined: NEVER read it.
      (and (sk_codec_get_valid_subset ptr rect)
           (codec-query-subset-result who source-width source-height
             (sk-irect-left rect) (sk-irect-top rect)
             (sk-irect-right rect) (sk-irect-bottom rect))))))
