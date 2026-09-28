#lang racket/base
(require rackunit racket/list
         "../private/gpu-presenter.rkt"
         (submod "../private/gpu-presenter.rkt" adapter-internals)
         "../private/gpu-metal-handles.rkt" "../private/gpu-presentation-cleanup.rkt"
         "../private/gpu-domain.rkt" "gpu-fixtures.rkt")
(provide gpu-presenter-pure-tests)
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
                        (hasheq 'backend (if (eq? (unbox fail) 'backend) "wrong" (symbol->string backend))
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
  (values (make-presenter adapter render (lambda (e) (emit 'reported-error))) metrics log queued fail))
(define (event-count* log e) (count (lambda (v) (eq? v e)) (unbox log)))
(define (dispatch! queue)
  (let loop ([fuel 50])
    (when (pair? (unbox queue))
      (when (zero? fuel) (error 'dispatch "unbounded redraw loop"))
      (define f (car (unbox queue))) (set-box! queue (cdr (unbox queue)))
      (f) (loop (sub1 fuel)))))
(define (with-presenter proc [render void])
  (define-values (p m log queue fail) (make-mock-presenter render))
  (dynamic-wind void (lambda () (proc p m log queue fail))
    (lambda () (set-box! fail #f) (gpu-presenter-close! p))))
(define gpu-presenter-pure-tests
  (test-suite
   "Presentation lifecycle and scheduling with synthetic adapters"
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
   (test-case "close invalidates pending redraw and is idempotent"
     (with-presenter (lambda (p m log q fail)
       (gpu-presenter-request-render! p) (gpu-presenter-close! p) (gpu-presenter-close! p)
       (dispatch! q) (check-equal? (event-count* log 'present) 0)
       (check-equal? (event-count* log 'close) 1))))
   (test-case "closed presenter rejects drawing and new requests"
     (with-presenter (lambda (p m log q fail)
       (gpu-presenter-close! p)
       (check-exn exn:fail? (lambda () (gpu-presenter-render! p)))
       (check-exn exn:fail? (lambda () (gpu-presenter-request-render! p))))))
   (test-case "close during rendering is deferred until target release"
     (define target #f)
     (with-presenter (lambda (p m log q fail)
       (set! target p) (check-eq? (gpu-presenter-render! p) 'cancelled)
       (check-equal? (reverse (unbox log)) '(acquire release close)))
       (lambda (f) (gpu-presenter-close! target))))
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
