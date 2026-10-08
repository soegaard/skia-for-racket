#lang racket/base
;; Pure argument and result rules; no native allocation or file/port I/O.
(require "check.rkt" "codec-query-util.rkt" "codec-util.rkt" "../image-info.rkt")
(provide scanline-options scanline-count scanline-index scanline-order-name
         scanline-row scanline-batch-layout scanline-read-state
         exn:fail:codec-scanline? exn:fail:codec-scanline-result
         exn:fail:codec-scanline-native-code raise-scanline-result
         scanline-batch? scanline-batch-info scanline-batch-row-bytes
         scanline-batch-first-row scanline-batch-requested-count
         scanline-batch-decoded-count scanline-batch-bytes scanline-batch-complete?
         make-scanline-batch)

(struct exn:fail:codec-scanline exn:fail (result native-code) #:transparent)
(define (raise-scanline-result who code)
  (define name (codec-result-name code))
  (raise (exn:fail:codec-scanline
          (format "~a: native scanline start failed: ~a (~a); no decode fallback" who name code)
          (current-continuation-marks) name code)))

;; In-range pixel data is deliberately detached, including after session close.
;; The constructor is private. Bytes contain decoded rows ONLY, not Skia's fill.
(struct scanline-batch (info row-bytes first-row requested-count decoded-count bytes)
  #:transparent #:constructor-name make-scanline-batch)
(define (scanline-batch-complete? batch)
  (unless (scanline-batch? batch)
    (raise-argument-error 'scanline-batch-complete? "scanline-batch?" batch))
  (= (scanline-batch-requested-count batch) (scanline-batch-decoded-count batch)))

(define (scanline-options who scale color alpha space)
  (define requested (codec-query-scale who scale))
  ;; Validate/copy a detached descriptor before any native input or port I/O.
  (define template
    (make-image-info 1 1 #:color-type color #:alpha-type alpha #:color-space space))
  (values requested template))
(define (scanline-count who n remaining #:zero? [zero? #f])
  (unless (and (exact-integer? n) (<= (if zero? 0 1) n remaining))
    (raise-arguments-error who "row count is outside the remaining scanlines"
                           "count" n "remaining" remaining "zero allowed" zero?))
  n)
(define (scanline-index who n height)
  (unless (and (exact-integer? n) (<= 0 n) (< n height))
    (raise-arguments-error who "row index is outside the decoded image"
                           "row" n "height" height))
  n)
(define (scanline-order-name who native)
  (case native [(0) 'top-down] [(1) 'bottom-up]
    [else (error who "unknown native scanline order: ~a" native)]))
(define (scanline-row who order height index)
  (scanline-index who index height)
  (case order [(top-down) index] [(bottom-up) (- height index 1)]
    [else (error who "unknown scanline order: ~a" order)]))

(define (scanline-batch-layout who order height position requested decoded)
  (scanline-index who position height)
  (scanline-count who requested (- height position))
  (unless (and (exact-integer? decoded) (<= 0 decoded requested))
    (error who "native decoder returned an invalid decoded-row count: ~a" decoded))
  ;; Bottom-up decoders reverse each REQUESTED batch, not just the complete
  ;; image. A short native read fills the low-address rows; successfully decoded
  ;; rows are therefore at the END of that allocation. Never publish the fill.
  (case order
    [(top-down) (values 0 (and (positive? decoded) position))]
    [(bottom-up) (values (- requested decoded)
                        (and (positive? decoded) (- height position decoded)))]
    [else (error who "unknown scanline order: ~a" order)]))
(define (scanline-read-state height position requested decoded)
  (cond [(< decoded requested) 'incomplete]
        [(= (+ position requested) height) 'complete]
        [else 'ready]))
