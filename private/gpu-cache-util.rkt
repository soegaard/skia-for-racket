#lang racket/base

;;;
;;; GPU Cache Validation
;;;

;; Validates GPU cache limits, purge sizes, and age thresholds.
;; Keeps public cache-control arguments within the native API's ranges.

(require "gpu-backends.rkt")
(provide cache-size cache-age cache-boolean cache-snapshot)
;; These guards load no native library. Zero is a valid cache budget/request.
; cache-size : symbol? exact-nonnegative-integer? -> exact-nonnegative-integer?
;;   Checks a nonnegative cache byte value against the host size_t range.
(define (cache-size who n)
  (unless (and (exact-nonnegative-integer? n) (< n (expt 2 (system-type 'word))))
    (raise-argument-error who "exact nonnegative integer fitting size_t" n)) n)
; cache-age : symbol? exact-nonnegative-integer? -> exact-nonnegative-integer?
;;   Bounds milliseconds before conversion to the native cache-cleanup clock representation.
(define (cache-age who n)
  ;; Bound ages before native milliseconds -> steady-clock conversion.
  (unless (and (exact-nonnegative-integer? n) (<= n #x7fffffff))
    (raise-argument-error who "exact milliseconds from 0 through 2147483647" n)) n)
; cache-boolean : symbol? boolean? -> boolean?
;;   Requires an actual boolean rather than coercing arbitrary truthy cache options.
(define (cache-boolean who v)
  (unless (boolean? v) (raise-argument-error who "boolean?" v)) v)
; cache-snapshot : symbol? exact-positive-integer? exact-nonnegative-integer?
;   exact-nonnegative-integer? exact-nonnegative-integer? -> hash?
;;   Labels native cache usage as budgeted resources, explicitly distinguishing it from total VRAM
;;   or a hard allocation cap.
(define (cache-snapshot backend generation limit count bytes)
  (check-gpu-backend! 'gpu-cache-info backend)
  (unless (exact-positive-integer? generation) (error 'gpu-cache-info "invalid generation"))
  (cache-size 'gpu-cache-info limit) (cache-size 'gpu-cache-info bytes)
  (unless (exact-nonnegative-integer? count) (error 'gpu-cache-info "invalid native resource count"))
  ;; Verified against m119 GrDirectContext.cpp: usage is BUDGETED, not total.
  (hasheq 'backend (symbol->string backend) 'context_generation generation
          'limit_bytes limit 'budgeted_resources count 'budgeted_bytes bytes
          'purgeable_bytes #f 'total_gpu_bytes #f 'limit_is_hard_allocation_cap #f
          'scope "Ganesh budgeted resource cache; not total VRAM or process RSS"))
