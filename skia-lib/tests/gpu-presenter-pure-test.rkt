#lang racket/base

;;;
;;; GPU Presenter Pure Test
;;;

;; Covers presentation lifecycle and scheduling with synthetic adapters.
;; This source-only regression layer checks contracts and lifecycle rules before native rendering
;; is involved.

;;;
;;; Imports and Exports
;;;

(require rackunit racket/list ffi/unsafe/atomic
         "../private/gpu-presenter.rkt"
         (submod "../private/gpu-presenter.rkt" adapter-internals)
         "../private/gpu-metal-handles.rkt" "../private/gpu-presentation-cleanup.rkt"
         "../private/gpu-presenter-timing.rkt"
         "../tools/gc-trace.rkt"
         (submod "../tools/gc-trace.rkt" test-support)
         "../private/gpu-cocoa-trace.rkt"
         (submod "../private/gpu-cocoa-trace.rkt" test-support)
         "../private/gpu-native-scope.rkt"
         (submod "../private/gpu-presenter-timing.rkt" test-support)
         (submod "../private/gpu-metal-layer.rkt" test-support)
         "../private/gpu-domain.rkt" "gpu-fixtures.rkt")
(provide gpu-presenter-pure-tests)

(struct gui-event (start end name) #:prefab)
;; Fields:
;;   start/end: epoch milliseconds. name: phase symbol. This independent declaration verifies
;;   compatibility with existing Racket GUI trace consumers, without importing the producer's type.

;;;
;;; Fixtures and Assertions
;;;

; make-mock-presenter : [procedure? symbol?] -> (values gpu-presenter? box? box? box? box?)
;   Builds a synthetic presenter with mutable metrics, queued callbacks, and injected failure
;   state.
(define (make-mock-presenter [render void] [backend 'metal])
  (define metrics (box (presentation-metrics 100 80 50 40)))
  (define log (box '())) (define queued (box '())) (define fail (box #f))
  (define (emit x) (set-box! log (cons x (unbox log))))
  (define adapter
    (presentation-adapter backend (gensym 'context)
      (lambda () (when (eq? (unbox fail) 'measure) (error 'mock "measure")) (unbox metrics))
      (lambda (m receive)
        (emit 'acquire)
        (cond
          [(eq? (unbox fail) 'no-drawable) #f]
          [(eq? (unbox fail) 'acquire) (error 'mock "acquire")]
          [else
           (dynamic-wind void
             (lambda ()
               (receive 'fake-canvas
                        (hasheq 'backend
                                (if (eq? (unbox fail) 'backend) "wrong" (symbol->string backend))
                                'target_identity "mock-target")
                        (lambda () (emit 'present)
                          (when (eq? (unbox fail) 'present) (error 'mock "present")))))
             (lambda () (emit 'release)))]))
      (lambda (f)
        (when (eq? (unbox fail) 'post) (error 'mock "post"))
        (set-box! queued (append (unbox queued) (list f))))
      (lambda () (when (eq? (unbox fail) 'close) (error 'mock "live application children"))
        (emit 'close))
      (lambda () (hasheq 'synthetic #t))))
  (values (make-presenter adapter render (lambda (e) (emit 'reported-error)))
          metrics log queued fail))

; event-count* : box? any/c -> exact-nonnegative-integer?
;   Counts a selected lifecycle event in the presenter's recorded log.
(define (event-count* log e) (count (lambda (v) (eq? v e)) (unbox log)))

; dispatch! : box? -> void?
;   Runs queued redraw callbacks with a finite budget that detects runaway rescheduling.
(define (dispatch! queue)
  (let loop ([fuel 50])
    (when (pair? (unbox queue))
      (when (zero? fuel) (error 'dispatch "unbounded redraw loop"))
      (define f (car (unbox queue))) (set-box! queue (cdr (unbox queue)))
      (f) (loop (sub1 fuel)))))

; with-presenter : procedure? [procedure?] -> any
;   Scopes a synthetic presenter and disables injected failures before guaranteed cleanup.
(define (with-presenter proc [render void])
  (define-values (p m log queue fail) (make-mock-presenter render))
  (dynamic-wind void (lambda () (proc p m log queue fail))
    (lambda () (set-box! fail #f) (gpu-presenter-close! p))))

;;;
;;; Regression Suite
;;;

; gpu-presenter-pure-tests : test-suite?
;   Collects the regression cases for presentation lifecycle and scheduling with synthetic
;   adapters.
(define gpu-presenter-pure-tests
  (test-suite
   "Presentation lifecycle and scheduling with synthetic adapters"

   ;;;
   ;;; Optional Metal Diagnostics
   ;;;

   (test-case "GC collection and parsing require explicit opt-in"
     (parameterize ([current-gc-trace-enabled #f])
       (check-false (gc-trace-enabled?))
       (check-false (make-gc-trace-receiver))
       (check-false (gc-log-message->record (vector 'debug "GC" 'invalid 'GC)))))

   (test-case "GC records preserve payload times, CPU time, and memory for each mode"
     (parameterize ([current-gc-trace-enabled #t])
       (for ([mode '(minor major incremental)])
         (define payload (make-prefab-struct 'gc-info mode 1000 2000 100 700 1800 50 54 10 16))
         (define record (gc-log-message->record (vector 'debug "not parsed" payload 'GC)))
         (check-equal? (hash-ref record 'mode) (symbol->string mode))
         (for ([key '(pre_bytes pre_admin_bytes code_bytes post_bytes post_admin_bytes
                               cpu_start cpu_end cpu_ms start end wall_ms)]
               [expected '(1000 2000 100 700 1800 50 54 4 10 16 6)])
           (check-equal? (hash-ref record key) expected))
         ;; An old payload is still dated by its own clock, not by delayed log delivery.
         (check-true (> (hash-ref record 'received_at) (hash-ref record 'end))))))

   (test-case "GC receiver and parser exclude duplicate major and unrelated messages"
     (parameterize ([current-gc-trace-enabled #t] [current-logger (make-logger #f #f)])
       (define receiver (make-gc-trace-receiver))
       (define payload (make-prefab-struct 'gc-info 'major 1000 2000 100 700 1800 50 54 10 16))
       (for ([topic '(GC GC:major other)])
         (log-message (current-logger) 'debug topic "collection" payload #f))
       (check-equal? (hash-ref (gc-log-message->record (sync/timeout 0 receiver)) 'type) "gc")
       (check-false (sync/timeout 0 receiver))
       (for ([topic '(GC:major other #f)])
         (check-false (gc-log-message->record (vector 'debug "collection" payload topic))))))

   (test-case "GC records accept future trailing fields and report unsupported payloads"
     (parameterize ([current-gc-trace-enabled #t])
       (define payload
         (make-prefab-struct 'gc-info 'minor 1000 2000 100 700 1800 50 54 10 16 'future))
       (check-equal? (hash-ref (gc-log-message->record (vector 'debug "" payload 'GC)) 'type)
                     "gc")
       (for ([bad (list #f 'invalid (make-prefab-struct 'gc-info 'minor)
                        (make-prefab-struct 'gc-info 'minor 1 2 3 4 5 54 50 10 16))])
         (check-equal? (hash-ref (gc-log-message->record (vector 'debug "" bad 'GC)) 'type)
                       "gc-error"))))

   (test-case "GC tracing reads an actual runtime collection without a GUI or presenter"
     (parameterize ([current-gc-trace-enabled #t])
       (define receiver (make-gc-trace-receiver))
       (define before (current-inexact-milliseconds))
       ;; Only this test requests a collection. The collector never requests or schedules one.
       (collect-garbage 'major)
       (define after (current-inexact-milliseconds))
       (define record
         (let loop ()
           (define message (sync/timeout 5 receiver))
           (unless message (error 'gc-test "runtime did not report the requested collection"))
           (define value (gc-log-message->record message))
           (if (equal? (hash-ref value 'mode #f) "major") value (loop))))
       ;; GC timestamps can be rounded to whole milliseconds by the runtime.
       (check-true (<= (- before 1) (hash-ref record 'start) (hash-ref record 'end) (+ after 1)))
       (check-true (>= (hash-ref record 'cpu_ms) 0))
       (check-true (>= (hash-ref record 'wall_ms) 0))))

   (test-case "Cocoa tracing needs opt-in and a receiver before installing anything"
     (define (unexpected) (error 'install "must not install"))
     (parameterize ([current-logger (make-logger #f #f)]
                    [current-metal-cocoa-trace-enabled #t])
       (check-false (make-cocoa-presenter-trace "test" unexpected)))
     (parameterize ([current-logger (make-logger #f #f)]
                    [current-metal-cocoa-trace-enabled #f])
       (define receiver (make-log-receiver (current-logger) 'debug 'skia-metal-presenter-cocoa))
       (check-false (make-cocoa-presenter-trace "test" unexpected))
       (check-false (sync/timeout 0 receiver)))
     (record-cocoa-presenter-trace! #f 'before #f)
     (close-cocoa-presenter-trace! #f))

   (test-case "Cocoa tracing copies live state and closes its observer exactly once"
     (parameterize ([current-logger (make-logger #f #f)]
                    [current-metal-cocoa-trace-enabled #t])
       (define receiver (make-log-receiver (current-logger) 'debug 'skia-metal-presenter-cocoa))
       (define reads 0)
       (define closes 0)
       (define trace
         (make-cocoa-presenter-trace "test"
           (lambda ()
             (values (lambda (window)
                       (check-eq? window 'window)
                       (set! reads (add1 reads))
                       (hasheq 'run_loop_events reads))
                     (lambda () (set! closes (add1 closes)))))))
       (for ([phase '(before-next-drawable after-next-drawable)] [n '(1 2)])
         (record-cocoa-presenter-trace! trace phase 'window)
         (define datum (vector-ref (sync/timeout 0 receiver) 2))
         (check-eq? (prefab-struct-key datum) 'metal-presenter-cocoa-state)
         (define v (struct->vector datum))
         (check-equal? (vector-ref v 2) "test")
         (check-eq? (vector-ref v 3) phase)
         (check-equal? (hash-ref (vector-ref v 4) 'run_loop_events) n)
         (check-true (>= (hash-ref (vector-ref v 4) 'observation_ms) 0)))
       (parameterize ([current-metal-cocoa-trace-enabled #f])
         (close-cocoa-presenter-trace! trace))
       (close-cocoa-presenter-trace! trace)
       (record-cocoa-presenter-trace! trace 'after-close 'window)
       (check-equal? reads 2)
       (check-equal? closes 1)
       (check-false (sync/timeout 0 receiver))))

   (test-case "Cocoa installation and read failures are diagnostic errors, not false state"
     (parameterize ([current-logger (make-logger #f #f)]
                    [current-metal-cocoa-trace-enabled #t])
       (define receiver (make-log-receiver (current-logger) 'debug 'skia-metal-presenter-cocoa))
       (for ([install (list (lambda () (error 'install "unsupported"))
                            (lambda () (values (lambda (w) (error 'read "missing")) void)))]
             [key '(installation_error observation_error)])
         (define trace (make-cocoa-presenter-trace "test" install))
         (record-cocoa-presenter-trace! trace 'before-next-drawable #f)
         (define fields (vector-ref (struct->vector (vector-ref (sync/timeout 0 receiver) 2)) 4))
         (check-true (string? (hash-ref fields key)))
         (check-false (hash-has-key? fields 'flush_suspended))
         (close-cocoa-presenter-trace! trace))))

   (test-case "empty layer transactions are skipped only with both opt-ins and equal values"
     (for* ([setters? '(#f #t)] [transactions? '(#f #t)]
            #:unless (and setters? transactions?))
       (parameterize ([current-metal-skip-unchanged-layer-setters setters?]
                      [current-metal-skip-empty-layer-transactions transactions?])
         (check-equal? (call-with-metal-layer-update
                        (lambda () (error 'preflight "must not run"))
                        (lambda () 'updated)) 'updated)))
     (parameterize ([current-metal-skip-unchanged-layer-setters #t]
                    [current-metal-skip-empty-layer-transactions #t])
       (define updates 0)
       (define reads 0)
       (define same? #t)
       (define (unchanged?) (set! reads (add1 reads)) same?)
       (define (update) (set! updates (add1 updates)) 'updated)
       (check-true (void? (call-with-metal-layer-update unchanged? update)))
       (check-equal? updates 0)
       (set! same? #f)
       (check-equal? (call-with-metal-layer-update unchanged? update) 'updated)
       (check-equal? updates 1)
       (set! same? #t)
       (check-true (void? (call-with-metal-layer-update unchanged? update)))
       (check-equal? updates 1)
       (check-equal? reads 3)
       (check-exn #rx"preflight failure"
                  (lambda () (call-with-metal-layer-update
                               (lambda () (error "preflight failure")) update)))
       (check-equal? updates 1)))

   (test-case "layer setter experiment checks current values only when explicitly enabled"
     (parameterize ([current-metal-skip-unchanged-layer-setters #f])
       (check-true (metal-layer-setter-needed? (lambda () (error 'read "must not run")))))
     (parameterize ([current-metal-skip-unchanged-layer-setters #t])
       (define reads 0)
       (define same? #t)
       (define (unchanged?) (set! reads (add1 reads)) same?)
       (check-false (metal-layer-setter-needed? unchanged?))
       (set! same? #f)
       (check-true (metal-layer-setter-needed? unchanged?))
       (set! same? #t)
       (check-false (metal-layer-setter-needed? unchanged?))
       (check-equal? reads 3)
       (check-exn #rx"read failure"
                  (lambda () (metal-layer-setter-needed? (lambda () (error "read failure")))))))

   (test-case "disabled timing preserves results and emits nothing even with a receiver"
     (parameterize ([current-logger (make-logger #f #f)]
                    [current-metal-presenter-timing-enabled #f])
       (define receiver (make-log-receiver (current-logger) 'debug 'skia-metal-presenter))
       (check-false (start-metal-presenter-timing 'disabled))
       (check-equal? (call-with-values
                     (lambda () (with-metal-presenter-timing 'disabled (values 1 2))) list)
                     '(1 2))
       (define states (make-log-receiver (current-logger) 'debug 'skia-metal-presenter-state))
       (record-metal-presenter-state! "test" 'disabled
                                     (lambda () (error 'observer "must not run")))
       (check-false (sync/timeout 0 states))
       (check-false (sync/timeout 0 receiver))))
   (test-case "enabled timing does not start without a matching debug receiver"
     (parameterize ([current-logger (make-logger #f #f)]
                    [current-metal-presenter-timing-enabled #t])
       (define receiver (make-log-receiver (current-logger) 'info 'skia-metal-presenter))
       (check-false (start-metal-presenter-timing 'ignored))
       (check-equal? (with-metal-presenter-timing 'ignored 'result) 'result)
       (record-metal-presenter-state! "test" 'ignored
                                     (lambda () (error 'observer "must not run")))
       (check-false (sync/timeout 0 receiver))))
   (test-case "timing uses compatible GUI events and preserves multiple and zero values"
     (parameterize ([current-logger (make-logger #f #f)]
                    [current-metal-presenter-timing-enabled #t])
       (define receiver (make-log-receiver (current-logger) 'debug 'skia-metal-presenter))
       (define before (current-inexact-milliseconds))
       (check-equal? (call-with-values
                     (lambda () (with-metal-presenter-timing 'phase (values 'a 'b))) list)
                     '(a b))
       (define message (sync/timeout 0 receiver))
       (check-eq? (vector-ref message 0) 'debug)
       (check-eq? (vector-ref message 3) 'skia-metal-presenter)
       (define event (vector-ref message 2))
       (check-true (gui-event? event))
       (check-eq? (gui-event-name event) 'phase)
       (check-true (<= before (gui-event-start event) (gui-event-end event)))
       (check-equal? (call-with-values
                     (lambda () (with-metal-presenter-timing 'zero (values))) list) '())
       (check-eq? (gui-event-name (vector-ref (sync/timeout 0 receiver) 2)) 'zero)
       (define states (make-log-receiver (current-logger) 'debug 'skia-metal-presenter-state))
       (record-metal-presenter-state! "test" 'before-update
                                     (lambda () (hasheq 'frame '(0.0 0.0 100.0 80.0))))
       (define state (vector-ref (sync/timeout 0 states) 2))
       (check-eq? (prefab-struct-key state) 'metal-presenter-state)
       (define fields (struct->vector state))
       (check-true (<= before (vector-ref fields 1)))
       (check-equal? (vector-ref fields 2) "test")
       (check-eq? (vector-ref fields 3) 'before-update)
       (check-equal? (hash-ref (vector-ref fields 4) 'frame) '(0.0 0.0 100.0 80.0))
       (check-true (>= (hash-ref (vector-ref fields 4) 'observation_ms) 0))
       (check-false (sync/timeout 0 receiver))
       (record-metal-presenter-state! "test" 'failed-read
                                     (lambda () (error 'observer "diagnostic failure")))
       (define failed (struct->vector (vector-ref (sync/timeout 0 states) 2)))
       (check-regexp-match #rx"diagnostic failure"
                           (hash-ref (vector-ref failed 4) 'observation_error))))
   (test-case "timing records nested spans in completion order"
     (parameterize ([current-logger (make-logger #f #f)]
                    [current-metal-presenter-timing-enabled #t])
       (define receiver (make-log-receiver (current-logger) 'debug 'skia-metal-presenter))
       (with-metal-presenter-timing 'outer (with-metal-presenter-timing 'inner (void)))
       (define inner (vector-ref (sync/timeout 0 receiver) 2))
       (define outer (vector-ref (sync/timeout 0 receiver) 2))
       (check-equal? (list (gui-event-name inner) (gui-event-name outer)) '(inner outer))
       (check-true (<= (gui-event-start outer) (gui-event-start inner)))
       (check-false (sync/timeout 0 receiver))))
   (test-case "timing preserves raised values and does not swallow failures"
     (for ([enabled? '(#f #t)])
       (parameterize ([current-logger (make-logger #f #f)]
                      [current-metal-presenter-timing-enabled enabled?])
         (define receiver (make-log-receiver (current-logger) 'debug 'skia-metal-presenter))
         (define failure (exn:fail "deliberate" (current-continuation-marks)))
         (for ([raised (list failure 'non-exception)])
           (check-eq? (with-handlers ([(lambda (_) #t) values])
                        (with-metal-presenter-timing 'failure (raise raised))) raised)
           (define message (sync/timeout 0 receiver))
           (if enabled?
               (check-eq? (gui-event-name (vector-ref message 2)) 'failure)
               (check-false message))))))
   (test-case "timing records escapes without changing cleanup order"
     (parameterize ([current-logger (make-logger #f #f)]
                    [current-metal-presenter-timing-enabled #t])
       (define receiver (make-log-receiver (current-logger) 'debug 'skia-metal-presenter))
       (define cleaned? #f)
       (check-eq? (let/ec escape
                    (with-metal-presenter-timing 'escape
                      (dynamic-wind void (lambda () (escape 'escaped))
                                    (lambda () (set! cleaned? #t))))) 'escaped)
       (check-true cleaned?)
       (check-eq? (gui-event-name (vector-ref (sync/timeout 0 receiver) 2)) 'escape)))
   (test-case "an explicit timing boundary and its cleanup emit only one event"
     (parameterize ([current-logger (make-logger #f #f)]
                    [current-metal-presenter-timing-enabled #t])
       (define receiver (make-log-receiver (current-logger) 'debug 'skia-metal-presenter))
       (define span (start-metal-presenter-timing 'context-entry))
       (finish-metal-presenter-timing! span)
       (finish-metal-presenter-timing! span)
       (finish-metal-presenter-timing! #f)
       (check-eq? (gui-event-name (vector-ref (sync/timeout 0 receiver) 2)) 'context-entry)
       (check-false (sync/timeout 0 receiver))))
   (test-case "timing starts a fresh span on continuation reentry"
     (parameterize ([current-logger (make-logger #f #f)]
                    [current-metal-presenter-timing-enabled #t])
       (define receiver (make-log-receiver (current-logger) 'debug 'skia-metal-presenter))
       (define tag (make-continuation-prompt-tag))
       (define saved #f)
       (check-eq?
        (call-with-continuation-prompt
         (lambda ()
           (with-metal-presenter-timing 'reentry
             (call-with-current-continuation (lambda (k) (set! saved k) 'first) tag))) tag)
        'first)
       (check-eq? (gui-event-name (vector-ref (sync/timeout 0 receiver) 2)) 'reentry)
       (check-eq? (call-with-continuation-prompt (lambda () (saved 'again)) tag) 'again)
       (check-eq? (gui-event-name (vector-ref (sync/timeout 0 receiver) 2)) 'reentry)
       (check-false (sync/timeout 0 receiver))))
   (test-case "timing inside a native scope preserves atomicity and pool cleanup"
     (parameterize ([current-logger (make-logger #f #f)]
                    [current-metal-presenter-timing-enabled #t])
       (define receiver (make-log-receiver (current-logger) 'debug 'skia-metal-presenter))
       (define actions '())
       (define scope
         (make-gpu-native-scope
          (lambda () (set! actions (cons 'enter actions)) 'pool)
          (lambda (pool) (check-eq? pool 'pool) (set! actions (cons 'leave actions)))))
       (parameterize ([current-gpu-native-scope scope])
         (check-exn #rx"native-failure"
          (lambda ()
            (call-with-gpu-native-scope
             (lambda ()
               (with-metal-presenter-timing 'native
                 (check-true (in-atomic-mode?))
                 (set! actions (cons 'body actions))
                 (error 'native-failure "deliberate")))))))
       (check-equal? (reverse actions) '(enter body leave))
       (check-eq? (gui-event-name (vector-ref (sync/timeout 0 receiver) 2)) 'native)))

   ;;;
   ;;; Geometry and Drawable Availability
   ;;;

   (test-case "positive geometry records logical/pixel scale"
     (define m (presentation-metrics 600 300 300 150))
     (check-equal? (hash-ref m 'scale_x) 2.0) (check-true (hash-ref m 'drawable)))
   (test-case "zero pixel size is not drawable"
     (check-false (hash-ref (presentation-metrics 0 20 10 10) 'drawable)))
   (test-case "zero logical size is not drawable"
     (check-false (hash-ref (presentation-metrics 20 20 0 0) 'drawable)))
   (test-case "hidden positive geometry is not drawable"
     (check-false (hash-ref (presentation-metrics 20 20 10 10 #:visible? #f) 'drawable)))
   (test-case "negative, fractional and oversized pixel extents reject"
     (for ([n (list -1 0.5 +inf.0 #x80000000)])
       (check-exn exn:fail? (lambda () (presentation-metrics n 1 1 1)))))
   (test-case "invalid logical geometry rejects"
     (for ([n (list -1 +nan.0 +inf.0)])
       (check-exn exn:fail? (lambda () (presentation-metrics 1 1 n 1)))))
   (test-case "visibility is explicitly Boolean"
     (check-exn exn:fail? (lambda () (presentation-metrics 1 1 1 1 #:visible? 'yes))))

   ;;;
   ;;; Frame Acquisition, Expiration, and Target Generation
   ;;;

   (test-case "initial presenter contains no fabricated presentation result"
     (with-presenter (lambda (p m log q fail)
       (check-eq? (gpu-presenter-state p) 'ready)
       (check-equal? (hash-ref (gpu-presenter-info p) 'presents_requested) 0)
       (check-false (hash-ref (gpu-presenter-info p) 'visible_pixels_verified)))))
   (test-case "render acquires, presents and releases once"
     (with-presenter (lambda (p m log q fail)
       (check-eq? (gpu-presenter-render! p) 'present-requested)
       (check-equal? (reverse (unbox log)) '(acquire present release)))))
   (test-case "frame metadata survives expiration but canvas does not"
     (define saved #f)
     (with-presenter (lambda (p m log q fail)
       (gpu-presenter-render! p)
       (check-true (gpu-frame-expired? saved))
       (check-equal? (gpu-frame-width saved) 100)
       (check-equal? (gpu-frame-logical-width saved) 50)
       (check-exn #rx"expired" (lambda () (gpu-frame-canvas saved))))
       (lambda (f) (set! saved f) (check-false (gpu-frame-expired? f))
         (check-eq? (gpu-frame-canvas f) 'fake-canvas))))
   (test-case "frame context access has the same expiration rule"
     (define saved #f)
     (with-presenter (lambda (p m log q fail)
       (gpu-presenter-render! p)
       (check-exn #rx"expired" (lambda () (gpu-frame-context saved))))
       (lambda (f) (set! saved f) (check-not-false (gpu-frame-context f)))))
   (test-case "next frame does not revive an old frame"
     (define old #f)
     (with-presenter (lambda (p m log q fail)
       (gpu-presenter-render! p) (gpu-presenter-render! p))
       (lambda (f)
         (when old (check-true (gpu-frame-expired? old))) (set! old f))))
   (test-case "unchanged geometry preserves target generation"
     (with-presenter (lambda (p m log q fail)
       (gpu-presenter-render! p) (gpu-presenter-render! p)
       (check-equal? (hash-ref (gpu-presenter-info p) 'target_generation) 1)
       (check-equal? (hash-ref (gpu-presenter-info p) 'frames_acquired) 2))))
   (test-case "resize advances target generation"
     (with-presenter (lambda (p m log q fail)
       (gpu-presenter-render! p) (set-box! m (presentation-metrics 120 80 60 40))
       (gpu-presenter-render! p)
       (check-equal? (hash-ref (gpu-presenter-info p) 'target_generation) 2))))
   (test-case "backing scale change advances target generation"
     (with-presenter (lambda (p m log q fail)
       (gpu-presenter-render! p) (set-box! m (presentation-metrics 50 40 50 40))
       (gpu-presenter-render! p)
       (check-equal? (hash-ref (gpu-presenter-info p) 'target_generation) 2))))
   (test-case "hidden frames do not acquire a native target"
     (with-presenter (lambda (p m log q fail)
       (set-box! m (presentation-metrics 100 80 50 40 #:visible? #f))
       (check-eq? (gpu-presenter-render! p) 'skipped) (check-equal? (unbox log) '()))))
   (test-case "nil drawable is an explicit skip, not a successful present"
     (with-presenter (lambda (p m log q fail)
       (set-box! fail 'no-drawable)
       (check-eq? (gpu-presenter-render! p) 'skipped)
       (check-equal? (event-count* log 'present) 0))))
   (test-case "showing again resumes drawing"
     (with-presenter (lambda (p m log q fail)
       (set-box! fail 'no-drawable) (gpu-presenter-render! p)
       (set-box! fail #f) (check-eq? (gpu-presenter-render! p) 'present-requested))))

   ;;;
   ;;; Redraw Scheduling and Callback Failures
   ;;;

   (test-case "burst redraw requests coalesce"
     (with-presenter (lambda (p m log q fail)
       (for ([i (in-range 12)]) (gpu-presenter-request-render! p))
       (check-equal? (length (unbox q)) 1) (dispatch! q)
       (check-equal? (event-count* log 'present) 1))))
   (test-case "direct render invalidates an already queued request"
     (with-presenter (lambda (p m log q fail)
       (gpu-presenter-request-render! p) (gpu-presenter-render! p) (dispatch! q)
       (check-equal? (event-count* log 'present) 1))))
   (test-case "redraw requested inside callback runs later, not recursively"
     (define target #f) (define n 0)
     (with-presenter (lambda (p m log q fail)
       (set! target p) (gpu-presenter-render! p)
       (check-equal? n 1) (dispatch! q) (check-equal? n 2))
       (lambda (f) (set! n (add1 n)) (when (= n 1) (gpu-presenter-request-render! target)))))
   (test-case "reentrant direct presentation rejects"
     (define target #f)
     (with-presenter (lambda (p m log q fail) (set! target p) (gpu-presenter-render! p))
       (lambda (f) (check-exn #rx"nested" (lambda () (gpu-presenter-render! target))))))
   (test-case "callback exception prevents present and still releases"
     (with-presenter (lambda (p m log q fail)
       (check-exn #rx"callback" (lambda () (gpu-presenter-render! p)))
       (check-equal? (reverse (unbox log)) '(acquire release))
       (check-eq? (gpu-presenter-state p) 'ready))
       (lambda (f) (error 'callback "deliberate"))))
   (test-case "queued callback errors reach the selected handler"
     (with-presenter (lambda (p m log q fail)
       (gpu-presenter-request-render! p) (dispatch! q)
       (check-equal? (event-count* log 'reported-error) 1))
       (lambda (f) (raise 'callback-failure))))
   (test-case "replacement callback used on next render"
     (define n 0)
     (with-presenter (lambda (p m log q fail)
       (gpu-presenter-set-render! p (lambda (f) (set! n (add1 n))))
       (dispatch! q) (check-equal? n 1))))
   (test-case "invalid callback rejected before queueing"
     (with-presenter (lambda (p m log q fail)
       (check-exn exn:fail? (lambda () (gpu-presenter-set-render! p 4)))
       (check-equal? (unbox q) '()))))

   ;;;
   ;;; Closure, Thread Affinity, and Deferred Cleanup
   ;;;

   (test-case "close invalidates pending redraw and is idempotent"
     (with-presenter (lambda (p m log q fail)
       (check-eq? (presenter-close-state p) 'open)
       (gpu-presenter-request-render! p) (gpu-presenter-close! p) (gpu-presenter-close! p)
       (check-eq? (presenter-close-state p) 'closed)
       (dispatch! q) (check-equal? (event-count* log 'present) 0)
       (check-equal? (event-count* log 'close) 1))))
   (test-case "closed presenter rejects drawing and new requests"
     (with-presenter (lambda (p m log q fail)
       (gpu-presenter-close! p)
       (check-exn exn:fail? (lambda () (gpu-presenter-render! p)))
       (check-exn exn:fail? (lambda () (gpu-presenter-request-render! p))))))
   (test-case "close during rendering is deferred until target release"
     (for ([fail-close? '(#f #t)])
       (define target #f)
       (with-presenter (lambda (p m log q fail)
         (set! target p)
         (when fail-close? (set-box! fail 'close))
         (if fail-close?
             (begin
               (check-exn #rx"live application children" (lambda () (gpu-presenter-render! p)))
               (check-eq? (presenter-close-state p) 'close-failed)
               (check-equal? (hash-ref (gpu-presenter-info p) 'close_state) "close-failed")
               (check-equal? (reverse (unbox log)) '(acquire release))
               (set-box! fail #f)
               (gpu-presenter-close! p))
             (check-eq? (gpu-presenter-render! p) 'cancelled))
         (check-eq? (presenter-close-state p) 'closed)
         (check-equal? (reverse (unbox log)) '(acquire release close)))
         (lambda (f)
           (gpu-presenter-close! target)
           (check-eq? (presenter-close-state target) 'closing)))))
   (test-case "resize during drawing cancels rather than showing stale extent"
     (define sizes #f) (define changed? #f)
     (with-presenter (lambda (p m log q fail)
       (set! sizes m) (check-eq? (gpu-presenter-render! p) 'cancelled)
       (check-equal? (event-count* log 'present) 0) (dispatch! q)
       (check-equal? (event-count* log 'present) 1))
       (lambda (f) (unless changed? (set! changed? #t)
                    (set-box! sizes (presentation-metrics 200 80 100 40))))))
   (test-case "foreign-thread calls reject without acquiring"
     (with-presenter (lambda (p m log q fail)
       (check-true (exn:fail? (in-worker (lambda () (gpu-presenter-render! p)))))
       (check-true (exn:fail? (in-worker (lambda () (gpu-presenter-close! p)))))
       (check-equal? (unbox log) '()))))
   (test-case "frame canvas rejects access from an inherited thread"
     (with-presenter (lambda (p m log q fail) (gpu-presenter-render! p))
       (lambda (f) (check-true (exn:fail? (in-worker (lambda () (gpu-frame-canvas f))))))))
   (test-case "native present failure marks failed but still retires target"
     (with-presenter (lambda (p m log q fail)
       (set-box! fail 'present) (check-exn exn:fail? (lambda () (gpu-presenter-render! p)))
       (check-eq? (gpu-presenter-state p) 'failed)
       (check-equal? (event-count* log 'release) 1))))
   (test-case "wrong native backend rejected before callback"
     (with-presenter (lambda (p m log q fail)
       (set-box! fail 'backend) (check-exn exn:fail? (lambda () (gpu-presenter-render! p)))
       (check-equal? (event-count* log 'present) 0) (check-equal? (event-count* log 'release) 1))))
   (test-case "close blocked by children stays retryable"
     (with-presenter (lambda (p m log q fail)
       (set-box! fail 'close) (check-exn exn:fail? (lambda () (gpu-presenter-close! p)))
       (check-eq? (presenter-close-state p) 'close-failed)
       (check-eq? (gpu-presenter-state p) 'closing)
       (set-box! fail #f) (gpu-presenter-close! p) (check-eq? (gpu-presenter-state p) 'closed))))
   (test-case "queue failure resets coalescing latch"
     (with-presenter (lambda (p m log q fail)
       (set-box! fail 'post) (check-exn exn:fail? (lambda () (gpu-presenter-request-render! p)))
       (set-box! fail #f) (gpu-presenter-request-render! p) (dispatch! q)
       (check-equal? (event-count* log 'present) 1))))
   (test-case "existing GPU execution scopes cannot host a presenter render"
     (with-presenter (lambda (p m log q fail)
       (call-with-mock (lambda (d provider driver events abandoned?)
         (domain-call d (lambda () (check-exn #rx"nested" (lambda () (gpu-presenter-render! p)))))))
       (check-equal? (unbox log) '()))))
   (test-case "borrowed Metal queue registration does not own or release pointers"
     (define key (gensym 'context))
     (register-metal-handles! key 'device 'queue)
     (check-equal? (call-with-metal-handles key list) '(device queue))
     (forget-metal-handles! key)
     (check-exn exn:fail? (lambda () (call-with-metal-handles key list))))
   (test-case "borrowed Metal handles reject a foreign owner"
     (define key (gensym 'context))
     (register-metal-handles! key 'device 'queue)
     (check-true (exn:fail? (in-worker (lambda () (call-with-metal-handles key list)))))
     (forget-metal-handles! key))
   (test-case "GC enqueues owner cleanup without running the adapter destructor"
     (define-values (log queue)
       (let-values ([(p m log q fail) (make-mock-presenter)]) (values log q)))
     (check-true (collect-until (lambda () (pair? (unbox queue)))))
     (check-equal? (event-count* log 'close) 0)
     (dispatch! queue)
     (check-equal? (event-count* log 'close) 1))
   (test-case "custodian requests cleanup; owner dispatch performs it"
     (define cust (make-custodian))
     (define-values (p m log q fail)
       (parameterize ([current-custodian cust]) (make-mock-presenter)))
     (custodian-shutdown-all cust)
     (check-equal? (event-count* log 'close) 0)
     (dispatch! q)
     (check-equal? (event-count* log 'close) 1))
   (test-case "queued redraw waits until an ordinary GPU scope has unwound"
     (with-presenter (lambda (p m log q fail)
       (call-with-mock (lambda (d provider driver events abandoned?)
         (domain-call d (lambda ()
           (gpu-presenter-request-render! p) (dispatch! q)
           (check-equal? (event-count* log 'present) 0)))))
       (dispatch! q) (check-equal? (event-count* log 'present) 1))))
   (test-case "a second window dispatched during drawing is deferred without spinning"
     (with-presenter (lambda (a am al aq af)
       (with-presenter (lambda (b bm bl bq bf)
         (gpu-presenter-set-render! a
           (lambda (f) (gpu-presenter-request-render! b) (dispatch! bq)
             (check-equal? (event-count* bl 'present) 0)))
         (gpu-presenter-render! a) (dispatch! bq)
         (check-equal? (event-count* bl 'present) 1))))))
   (test-case "closing a second window inside a frame is owner-deferred"
     (with-presenter (lambda (a am al aq af)
       (with-presenter (lambda (b bm bl bq bf)
         (gpu-presenter-set-render! a (lambda (f)
           (gpu-presenter-close! b) (dispatch! bq)
           (check-equal? (event-count* bl 'close) 0)))
         (gpu-presenter-render! a) (dispatch! bq)
         (check-equal? (event-count* bl 'close) 1))))))
   (test-case "an escape retires the frame without presenting or leaking a lease"
     (define saved #f)
     (with-presenter (lambda (p m log q fail)
       (let/ec escape
         (gpu-presenter-set-render! p (lambda (f) (set! saved f) (escape 'escaped)))
         (gpu-presenter-render! p))
       (check-true (gpu-frame-expired? saved))
       (check-equal? (reverse (unbox log)) '(acquire release))
       (check-eq? (gpu-presenter-state p) 'ready))))
   (test-case "close dispatched inside a plain GPU scope waits for domain idle"
     (with-presenter (lambda (p m log q fail)
       (call-with-mock (lambda (d provider driver events abandoned?)
         (domain-call d (lambda ()
           (gpu-presenter-close! p) (dispatch! q)
           (check-equal? (event-count* log 'close) 0)))))
       (dispatch! q) (check-equal? (event-count* log 'close) 1))))
   (test-case "duplicate borrowed registry keys cannot replace the original queue"
     (define key (gensym 'context))
     (dynamic-wind void
       (lambda ()
         (register-metal-handles! key 'device 'queue)
         (check-exn #rx"duplicate" (lambda () (register-metal-handles! key 'foreign 'foreign)))
         (check-equal? (call-with-metal-handles key list) '(device queue)))
       (lambda () (forget-metal-handles! key))))

   ;;;
   ;;; Presentation Completion and Quarantine
   ;;;

   (test-case "presented target cleanup never invokes the abort wait"
     (define log '())
     (call-with-presentation-cleanup
       (lambda (mark!) (set! log (cons 'draw log)) (mark!))
       (lambda () (set! log (cons 'abort log)))
       (lambda () (set! log (cons 'release log)))
       (lambda (e) (set! log (cons 'quarantine log))))
     (check-equal? (reverse log) '(draw release)))
   (test-case "cancelled target completes outstanding work before release"
     (define log '())
     (call-with-presentation-cleanup void
       (lambda () (set! log (cons 'abort log)))
       (lambda () (set! log (cons 'release log))) void)
     (check-equal? (reverse log) '(abort release)))
   (test-case "callback failure still completes cancelled target before release"
     (define log '())
     (check-exn #rx"callback"
       (lambda () (call-with-presentation-cleanup (lambda (mark!) (error 'callback "deliberate"))
         (lambda () (set! log (cons 'abort log)))
         (lambda () (set! log (cons 'release log))) void)))
     (check-equal? (reverse log) '(abort release)))
   (test-case "failed abort quarantines rather than releasing an in-flight drawable"
     (define log '())
     (check-exn #rx"abort"
       (lambda () (call-with-presentation-cleanup void
         (lambda () (error 'abort "indeterminate completion"))
         (lambda () (set! log (cons 'release log)))
         (lambda (e) (set! log (cons 'quarantine log))))))
     (check-equal? log '(quarantine)))
   (test-case "indeterminate destruction is quarantined and never retried"
     (define releases 0) (define quarantines 0)
     (check-exn #rx"release"
       (lambda () (call-with-presentation-cleanup (lambda (mark!) (mark!)) void
         (lambda () (set! releases (add1 releases)) (error 'release "indeterminate"))
         (lambda (e) (set! quarantines (add1 quarantines))))))
     (check-equal? releases 1) (check-equal? quarantines 1))
   (test-case "retired or duplicate presentation marks are rejected"
     (define saved #f)
     (call-with-presentation-cleanup
       (lambda (mark!) (set! saved mark!) (mark!)
         (check-exn exn:fail? mark!)) void void void)
     (check-exn exn:fail? saved))
))
