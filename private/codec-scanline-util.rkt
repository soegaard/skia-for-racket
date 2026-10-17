#lang racket/base

;;;
;;; Scanline Decoder Results
;;;

;; Validates row requests and packages decoded scanline batches and failures.
;; Supplies detached results and state checks for the public scanline API.

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
;; Fields:
;;   result: symbolic codec result. native-code: corresponding native integer result. The inherited
;;   message and continuation marks retain the original failure context.

; raise-scanline-result : symbol? exact-integer? -> none/c
;;   Raises a structured start failure retaining the native result code and name.
(define (raise-scanline-result who code)
  (define name (codec-result-name code))
  (raise (exn:fail:codec-scanline
          (format "~a: native scanline start failed: ~a (~a); no decode fallback" who name code)
          (current-continuation-marks) name code)))

;; In-range pixel data is deliberately detached, including after session close.
;; The constructor is private. Bytes contain decoded rows ONLY, not Skia's fill.
(struct scanline-batch (info row-bytes first-row requested-count decoded-count bytes)
  #:transparent #:constructor-name make-scanline-batch)
;; Fields:
;;   info: detached image-info whose height equals decoded-count. row-bytes: positive byte stride
;;   of the copied rows. first-row: zero-based top-origin image row of the first copied row, or #f
;;   when decoded-count is zero; this is not the decoder's next scanline index.
;;   requested-count: positive row request. decoded-count: exact integer from zero through
;;   requested-count. bytes: immutable decoded rows in top-to-bottom order within this batch,
;;   including row padding, with length row-bytes * decoded-count. Native partial-read fill is
;;   excluded. Bottom-up batches arrive in reverse vertical order and must be placed by first-row.

; scanline-batch-complete? : scanline-batch? -> boolean?
;;   Returns whether decoded count equals requested count for this batch.
(define (scanline-batch-complete? batch)
  (unless (scanline-batch? batch)
    (raise-argument-error 'scanline-batch-complete? "scanline-batch?" batch))
  (= (scanline-batch-requested-count batch) (scanline-batch-decoded-count batch)))

; scanline-options : symbol? real? symbol? symbol? any/c -> (values inexact-real? image-info?)
;;   Checks scale and copies a detached format template before input or native allocation.
(define (scanline-options who scale color alpha space)
  (define requested (codec-query-scale who scale))
  ;; Validate/copy a detached descriptor before any native input or port I/O.
  (define template
    (make-image-info 1 1 #:color-type color #:alpha-type alpha #:color-space space))
  (values requested template))
; scanline-count : symbol? exact-integer? exact-nonnegative-integer? [#:zero? boolean?] ->
;   exact-nonnegative-integer?
;;   Bounds requested rows by remaining rows, optionally permitting zero.
(define (scanline-count who n remaining #:zero? [zero? #f])
  (unless (and (exact-integer? n) (<= (if zero? 0 1) n remaining))
    (raise-arguments-error who "row count is outside the remaining scanlines"
                           "count" n "remaining" remaining "zero allowed" zero?))
  n)
; scanline-index : symbol? exact-integer? exact-positive-integer? -> exact-nonnegative-integer?
;;   Requires a zero-based row strictly below the decoded height.
(define (scanline-index who n height)
  (unless (and (exact-integer? n) (<= 0 n) (< n height))
    (raise-arguments-error who "row index is outside the decoded image"
                           "row" n "height" height))
  n)
; scanline-order-name : symbol? exact-integer? -> symbol?
;;   Maps known native order codes to top-down or bottom-up.
(define (scanline-order-name who native)
  (case native [(0) 'top-down] [(1) 'bottom-up]
    [else (error who "unknown native scanline order: ~a" native)]))
; scanline-row : symbol? symbol? integer? integer? -> exact-nonnegative-integer?
;;   Maps decode-order position to the image's top-origin row.
(define (scanline-row who order height index)
  (scanline-index who index height)
  (case order [(top-down) index] [(bottom-up) (- height index 1)]
    [else (error who "unknown scanline order: ~a" order)]))

; scanline-batch-layout : symbol? symbol? integer? integer? integer? integer? -> (values integer?
;   any/c)
;;   Locates valid rows in a requested batch and their image origin, excluding native partial-read
;;   fill.
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
; scanline-read-state : integer? integer? integer? integer? -> symbol?
;;   Classifies a checked batch as incomplete, complete, or ready for another read.
(define (scanline-read-state height position requested decoded)
  (cond [(< decoded requested) 'incomplete]
        [(= (+ position requested) height) 'complete]
        [else 'ready]))
