#lang racket/base
(require "check.rkt" "codec-util.rkt" "../image-info.rkt")
(provide incremental-options incremental-terminal? incremental-result-state
         incremental-progress? incremental-progress-state incremental-progress-result
         incremental-progress-initialized-rows make-incremental-progress
         incremental-snapshot? incremental-snapshot-info incremental-snapshot-row-bytes
         incremental-snapshot-bytes incremental-snapshot-progress make-incremental-snapshot)
(struct incremental-progress (state result initialized-rows)
  #:transparent #:constructor-name make-incremental-progress)
(struct incremental-snapshot (info row-bytes bytes progress)
  #:transparent #:constructor-name make-incremental-snapshot)
(define (incremental-terminal? status)
  (and (memq status '(complete incomplete failed cancelled closed)) #t))
(define (incremental-result-state code final?)
  (cond [(zero? code) 'complete]
        [(= code 1) (if final? 'incomplete 'needs-input)]
        [else 'failed]))
(define (incremental-options who color alpha space row-bytes limit)
  (unless (and (exact-positive-integer? limit)
               (<= limit (min #x7fffffff (current-skia-byte-limit))))
    (raise-argument-error who "positive byte limit <= min(2147483647, current-skia-byte-limit)" limit))
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
