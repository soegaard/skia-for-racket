#lang racket/base

;;;
;;; Codec Query Fixtures
;;;

;; Provides shared inputs and drawing fixtures for native codec scaling and subset negotiation.
;; Regression suites and diagnostic programs import these fixtures to compare behavior using
;; consistent inputs.

;;;
;;; Imports and Exports
;;;
;; Original pixels; native encoders create their own small format fixtures.
(require racket/list "../main.rkt")
(provide query-fixture-bytes query-fixture-pixels query-fixture-width query-fixture-height)

;;;
;;; Fixtures and Assertions
;;;

; query-fixture-width : exact-positive-integer?
;;   Sets the default encoded-query image width in pixels.
(define query-fixture-width 16)

; query-fixture-height : exact-positive-integer?
;;   Sets the default encoded-query image height in pixels.
(define query-fixture-height 12)

; query-fixture-pixels : [exact-positive-integer? exact-positive-integer?] -> bytes?
;;   Generates an opaque coordinate pattern for decode-size and subset checks.
(define (query-fixture-pixels [width query-fixture-width] [height query-fixture-height])
  (apply bytes-append
    (for*/list ([y (in-range height)] [x (in-range width)])
      (bytes (modulo (* x 13) 256) (modulo (* y 19) 256)
             (modulo (+ (* x 7) (* y 11)) 256) 255))))

; query-fixture-bytes : symbol? [exact-positive-integer? exact-positive-integer?] -> bytes?
;;   Encodes the query pattern as PNG, full-quality JPEG, or lossless WebP.
(define (query-fixture-bytes format [width query-fixture-width] [height query-fixture-height])
  (with-skia ([image (rgba-bytes->image width height (query-fixture-pixels width height))])
    (case format
      [(png) (image->png-bytes image)]
      [(jpeg) (image->jpeg-bytes image #:quality 100 #:downsample 'yuv-444)]
      [(webp) (image->webp-bytes image #:lossless? #t)]
      [else (raise-argument-error 'query-fixture-bytes "'png, 'jpeg, or 'webp" format)])))
