#lang racket/base
(provide cache-size cache-age cache-boolean cache-snapshot)
;; These guards load no native library. Zero is a valid cache budget/request.
(define (cache-size who n)
  (unless (and (exact-nonnegative-integer? n) (< n (expt 2 (system-type 'word))))
    (raise-argument-error who "exact nonnegative integer fitting size_t" n)) n)
(define (cache-age who n)
  ;; Bound ages before native milliseconds -> steady-clock conversion.
  (unless (and (exact-nonnegative-integer? n) (<= n #x7fffffff))
    (raise-argument-error who "exact milliseconds from 0 through 2147483647" n)) n)
(define (cache-boolean who v)
  (unless (boolean? v) (raise-argument-error who "boolean?" v)) v)
(define (cache-snapshot backend generation limit count bytes)
  (unless (memq backend '(opengl metal)) (error 'gpu-cache-info "invalid backend"))
  (unless (exact-positive-integer? generation) (error 'gpu-cache-info "invalid generation"))
  (cache-size 'gpu-cache-info limit) (cache-size 'gpu-cache-info bytes)
  (unless (exact-nonnegative-integer? count) (error 'gpu-cache-info "invalid native resource count"))
  ;; Verified against m119 GrDirectContext.cpp: usage is BUDGETED, not total.
  (hasheq 'backend (symbol->string backend) 'context_generation generation
          'limit_bytes limit 'budgeted_resources count 'budgeted_bytes bytes
          'purgeable_bytes #f 'total_gpu_bytes #f 'limit_is_hard_allocation_cap #f
          'scope "Ganesh budgeted resource cache; not total VRAM or process RSS"))
