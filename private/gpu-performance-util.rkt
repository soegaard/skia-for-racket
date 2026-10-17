#lang racket/base

;;;
;;; GPU Performance Options
;;;

;; Validates benchmark settings, measures completed work, and checks resource-use envelopes.
;; Shares native-free timing and stress-test evidence across the project's GPU performance probes.

(require racket/list)
(provide performance-config performance-clock measure-one measure-completed
         sample-statistics finite-nonnegative-real? check-resource-envelope!)
; performance-clock : parameter?
;;   Supplies an injectable monotonic millisecond clock for repeatable timing tests.
(define performance-clock (make-parameter current-inexact-monotonic-milliseconds))
; finite-nonnegative-real? : any/c -> any
;;   Rejects negative, infinite, and NaN measurements before computing performance statistics.
(define (finite-nonnegative-real? n) (and (real? n) (<= 0 n) (< n +inf.0)))
; bounded : exact-integer? any/c any/c any/c -> void?
;;   Checks one integer benchmark setting against its labeled minimum and maximum.
(define (bounded n lo hi label)
  (unless (and (exact-integer? n) (<= lo n hi))
    (raise-arguments-error 'gpu-performance "invalid benchmark configuration"
                           "setting" label "value" n "minimum" lo "maximum" hi)))
; performance-config : [#:samples exact-integer?] [#:warmup exact-integer?] [#:frames
;   exact-integer?] [#:cycles exact-integer?] [#:width exact-integer?] [#:height exact-integer?]
;   [#:sample-count exact-integer?] -> hash?
;;   Builds bounded benchmark settings with checkpoint intervals and explicit cache-growth
;;   allowances.
(define (performance-config #:samples [samples 12] #:warmup [warmup 3]
                            #:frames [frames 180] #:cycles [cycles 3]
                            #:width [width 640] #:height [height 400]
                            #:sample-count [sample-count 0])
  (bounded samples 3 500 'samples) (bounded warmup 1 100 'warmup)
  (bounded frames 60 9990 'frames) (bounded cycles 3 50 'cycles)
  (bounded width 128 4096 'width) (bounded height 128 4096 'height)
  (bounded sample-count 0 16 'sample-count)
  (when (> (* frames cycles) 30000)
    (error 'gpu-performance "frames times cycles must not exceed 30000; split larger runs"))
  (unless (zero? (modulo frames 30)) (error 'gpu-performance "frames must be a multiple of 30"))
  (hasheq 'samples samples 'warmup warmup 'frames frames 'cycles cycles
          'width width 'height height 'sample_count sample-count 'checkpoint_interval 30
          'cache_limit_bytes (* 32 1024 1024) 'cache_growth_allowance_bytes (* 16 1024 1024)
          'cache_growth_allowance_resources 64 'cpu_pressure_bytes (* 4 1024 1024)))
; stamp : -> any
;;   Reads the selected monotonic benchmark clock rather than wall-clock time.
(define (stamp) ((performance-clock)))
; delta : real? real? -> inexact-real?
;;   Checks finite monotonic endpoints before returning elapsed milliseconds.
(define (delta a b)
  (unless (and (real? a) (real? b) (< -inf.0 a +inf.0) (< -inf.0 b +inf.0) (<= a b))
    (error 'gpu-performance "clock readings must be finite and monotonic"))
  (exact->inexact (- b a)))
; measure-one : any/c -> (values any/c hash?)
;;   Returns a thunk's result together with wall, host-CPU, and GC timing measurements.
(define (measure-one thunk)
  (define cpu (current-process-milliseconds)) (define gc (current-gc-milliseconds))
  (define start (stamp)) (define result (thunk)) (define end (stamp))
  (values result (hasheq 'start_ms start 'end_ms end 'elapsed_ms (delta start end)
                         'host_cpu_ms (- (current-process-milliseconds) cpu)
                         'gc_cpu_ms (- (current-gc-milliseconds) gc))))
; measure-completed : procedure? procedure? procedure? procedure? -> hash?
;;   Measures draw, flush, submit, and explicit completion-wait phases separately.
(define (measure-completed draw flush submit wait)
  (define cpu (current-process-milliseconds)) (define gc (current-gc-milliseconds))
  (define t0 (stamp)) (draw) (define t1 (stamp))
  (flush) (define t2 (stamp)) (submit) (define t3 (stamp))
  (wait) (define t4 (stamp))
  (hasheq 'timepoints_ms (list t0 t1 t2 t3 t4)
          'draw_ms (delta t0 t1) 'flush_ms (delta t1 t2) 'submit_ms (delta t2 t3)
          'completion_wait_ms (delta t3 t4) 'completed_ms (delta t0 t4)
          'host_cpu_ms (- (current-process-milliseconds) cpu)
          'gc_cpu_ms (- (current-gc-milliseconds) gc)
          'completion "explicit CPU synchronization"))
; sample-statistics : any/c -> hash?
;;   Summarizes checked nonnegative samples with count, extrema, mean, median, and nearest-rank p95.
(define (sample-statistics numbers)
  (unless (and (list? numbers) (pair? numbers) (andmap finite-nonnegative-real? numbers))
    (raise-argument-error 'sample-statistics "nonempty finite nonnegative sample list" numbers))
  (define xs (sort numbers <)) (define n (length xs)) (define mid (quotient n 2))
  (hasheq 'count n 'min (car xs) 'max (last xs) 'mean (exact->inexact (/ (apply + xs) n))
          'median (exact->inexact (if (odd? n) (list-ref xs mid)
                                    (/ (+ (list-ref xs (sub1 mid)) (list-ref xs mid)) 2)))
          'p95 (list-ref xs (sub1 (inexact->exact (ceiling (* .95 n)))))))
; check-resource-envelope! : hash? hash? hash? hash? any/c -> void?
;;   Checks live-resource and post-purge cache counts against the recorded stress-test baseline.
(define (check-resource-envelope! info cache baseline config expected-live)
  (unless (and (equal? (hash-ref info 'state) "ready")
               (= (hash-ref info 'live_children) expected-live)
               (zero? (hash-ref info 'pending_releases)) (zero? (hash-ref info 'failed_releases))
               (not (hash-ref info 'shutdown_requested)))
    (error 'gpu-release-stress "resources did not return to the checkpoint baseline: ~a" info))
  (unless (and (<= (hash-ref cache 'budgeted_bytes)
                   (+ (hash-ref baseline 'budgeted_bytes) (hash-ref config
                     'cache_growth_allowance_bytes)))
               (<= (hash-ref cache 'budgeted_resources)
                   (+ (hash-ref baseline 'budgeted_resources) (hash-ref config
                     'cache_growth_allowance_resources))))
    (error 'gpu-release-stress "post-purge cache growth exceeds the recorded allowance"))
  (void))
