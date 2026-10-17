#lang racket/base

;;;
;;; Incremental Decoder Results
;;;

;; Defines detached progress and snapshot records and validates incremental options.
;; Keeps public incremental-decoding results independent of native storage.

(require "check.rkt" "codec-util.rkt" "../image-info.rkt")
(provide incremental-options incremental-terminal? incremental-result-state
         incremental-progress? incremental-progress-state incremental-progress-result
         incremental-progress-initialized-rows make-incremental-progress
         incremental-snapshot? incremental-snapshot-info incremental-snapshot-row-bytes
         incremental-snapshot-bytes incremental-snapshot-progress make-incremental-snapshot)
(struct incremental-progress (state result initialized-rows)
  #:transparent #:constructor-name make-incremental-progress)
;; Fields:
;;   state: 'awaiting-input, 'needs-input, 'complete, 'incomplete, 'failed, or 'cancelled.
;;   result: latest codec result symbol (see codec-result-names), initially 'not-started, or
;;   'wrapper-error/'cancelled for wrapper outcomes. initialized-rows: nonnegative row count or #f
;;   when
;;   unavailable; success reports the full output height. A partial count is not a promise that
;;   those rows contain final pixels. This detached snapshot remains usable after session closure.

(struct incremental-snapshot (info row-bytes bytes progress)
  #:transparent #:constructor-name make-incremental-snapshot)
;; Fields:
;;   info: detached image-info for the full destination. row-bytes: positive four-byte-aligned
;;   stride, at least width * 4. bytes: immutable full destination copy, including row padding,
;;   of length row-bytes * height. Rows retain encoded orientation; no orientation is applied.
;;   progress: incremental-progress captured with the bytes. Partial samples are previews, not a
;;   guarantee of final decoded pixels; initialized-rows may be #f.

; incremental-terminal? : any/c -> boolean?
;;   Recognizes states that permit no further decoding, including sealed incomplete input.
(define (incremental-terminal? status)
  (and (memq status '(complete incomplete failed cancelled closed)) #t))
; incremental-result-state : exact-integer? boolean? -> symbol?
;;   Distinguishes temporary needs-input from terminal incomplete results using the final-input
;;   flag.
(define (incremental-result-state code final?)
  (cond [(zero? code) 'complete]
        [(= code 1) (if final? 'incomplete 'needs-input)]
        [else 'failed]))
; incremental-options : symbol? symbol? symbol? any/c any/c exact-positive-integer? -> image-info?
;;   Validates supported byte formats, alpha interpretation, aligned stride, and retained-input
;;   budget.
(define (incremental-options who color alpha space row-bytes limit)
  (unless (and (exact-positive-integer? limit)
               (<= limit (min #x7fffffff (current-skia-byte-limit))))
    (raise-argument-error
     who "positive byte limit <= min(2147483647, current-skia-byte-limit)" limit))
  ;; Restrict this first retained-destination API to byte RGBA/BGRA. Partially
  ;; initialized float samples and arbitrary conversions are not inferred safe
  ;; merely because a different one-shot decoder happens to accept them.
  (unless (memq color '(rgba-8888 bgra-8888))
    (raise-argument-error who "'rgba-8888 or 'bgra-8888" color))
  (unless (memq alpha '(premul unpremul))
    (raise-argument-error who "'premul or 'unpremul" alpha))
  (unless (or (not row-bytes)
              (and (exact-positive-integer? row-bytes) (<= row-bytes #x7fffffff)
                   (zero? (modulo row-bytes 4))))
    (raise-argument-error who "#f or positive 4-byte-aligned row stride" row-bytes))
  (make-image-info 1 1 #:color-type color #:alpha-type alpha #:color-space space))
