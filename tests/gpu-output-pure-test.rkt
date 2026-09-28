#lang racket/base
(require rackunit racket/list json
         "../private/output-executor.rkt" "../private/gpu-provider.rkt"
         "../private/audit-trace.rkt" "../output-policy.rkt")
(provide gpu-output-pure-tests)
(define (plan c p)
  (output-raster-plan 'metal 17 #f (lambda (w h cs replay consume) (void))))
(define (unavailable) (gpu-unavailable 'test-device "synthetic unavailable device"))
(define (lazy proc #:create [create (lambda () 'context)] #:check [check void]
              #:plan [make-plan plan] #:close [close void] #:policy [policy 'error])
  (call-with-lazy-output-raster-executor create check make-plan close proc #:on-unavailable policy))
(define (drawing-event handle backend)
  (audit-on-canvas 'probe 'owner backend handle '()
    (lambda () (audit-native-call 'sk_canvas_draw_rect '() void))))
(define (geometry-events thunk)
  (define-values (_ report)
    (call-with-audit-collector 'svg 'report #f 1
      (lambda () (call-with-audit-raster 'svg 4 4 (hasheq) thunk))))
  (filter (lambda (e) (eq? (output-audit-event-feature e) 'geometry))
          (output-audit-report-events report)))

(define gpu-output-pure-tests
  (test-suite
   "GPU document execution: pure protocol, lazy ownership and scoped audit"
   (test-case "CPU plan is explicitly CPU and has no renderer"
     (define p (prepare-output-raster 'cpu 'picture))
     (check-eq? (output-raster-plan-backend p) 'raster)
     (check-false (output-raster-plan-render p)))
   (test-case "invalid executors reject before preparation"
     (check-exn exn:fail:contract? (lambda () (check-output-raster-executor! 'test 'auto))))
   (test-case "executor constructor validates callback arity"
     (check-exn exn:fail:contract? (lambda () (make-output-raster-executor void (lambda () 1)))))
   (test-case "required keywords are not accepted as optional callback arguments"
     (check-exn exn:fail:contract?
       (lambda () (make-output-raster-executor (lambda (#:required n) n) values))))
   (test-case "invalid plan backend is rejected"
     (define e (make-output-raster-executor void (lambda (_) (output-raster-plan 'vulkan 1 #f void))))
     (check-exn exn:fail? (lambda () (prepare-output-raster e 'picture))))
   (test-case "GPU plans need a positive generation"
     (define e (make-output-raster-executor void (lambda (_) (output-raster-plan 'metal #f #f void))))
     (check-exn exn:fail? (lambda () (prepare-output-raster e 'picture))))
   (test-case "GPU plan renderer arity is checked"
     (define e (make-output-raster-executor void (lambda (_) (output-raster-plan 'opengl 1 #f (lambda () 1)))))
     (check-exn exn:fail? (lambda () (prepare-output-raster e 'picture))))
   (test-case "checking an unused lazy executor does not create a context"
     (define creates 0) (define closes 0)
     (lazy (lambda (e) (check-output-raster-executor! 'test e))
           #:create (lambda () (set! creates (add1 creates)) 'context)
           #:close (lambda (_) (set! closes (add1 closes))))
     (check-equal? creates 0) (check-equal? closes 0))
   (test-case "lazy scope preserves multiple values"
     (check-equal? (call-with-values (lambda () (lazy (lambda (_) (values 1 2 3)))) list) '(1 2 3)))
   (test-case "first raster prepares once and reuses the context"
     (define creates 0) (define closes 0)
     (lazy (lambda (e) (prepare-output-raster e 'a) (prepare-output-raster e 'b))
           #:create (lambda () (set! creates (add1 creates)) 'context)
           #:close (lambda (_) (set! closes (add1 closes))))
     (check-equal? creates 1) (check-equal? closes 1))
   (test-case "owned context closes after callback, not between groups"
     (define events '())
     (lazy (lambda (e) (prepare-output-raster e 'a) (set! events (cons 'body events)))
           #:close (lambda (_) (set! events (cons 'close events))))
     (check-equal? (reverse events) '(body close)))
   (test-case "owned context closes on an exception"
     (define closed? #f)
     (check-exn #rx"deliberate"
       (lambda () (lazy (lambda (e) (prepare-output-raster e 'a) (error 'test "deliberate"))
                        #:close (lambda (_) (set! closed? #t)))))
     (check-true closed?))
   (test-case "owned context closes on arbitrary raised values"
     (define closed? #f)
     (define got (with-handlers ([(lambda (_) #t) values])
                   (lazy (lambda (e) (prepare-output-raster e 'a) (raise 'marker))
                         #:close (lambda (_) (set! closed? #t)))))
     (check-eq? got 'marker) (check-true closed?))
   (test-case "escape retires a lazy executor and releases its context"
     (define saved #f) (define closes 0)
     (define result
       (let/ec exit
         (lazy (lambda (e) (set! saved e) (prepare-output-raster e 'a) (exit 'escaped))
               #:close (lambda (_) (set! closes (add1 closes))))))
     (check-eq? result 'escaped) (check-equal? closes 1)
     (check-exn #rx"expired" (lambda () (prepare-output-raster saved 'a))))
   (test-case "even unused executors expire at scope exit"
     (define e (lazy values))
     (check-exn #rx"expired" (lambda () (check-output-raster-executor! 'test e))))
   (test-case "wrong-thread checking never invokes the factory"
     (define creates 0)
     (lazy (lambda (e)
             (define ch (make-channel))
             (thread (lambda ()
                       (channel-put ch (with-handlers ([exn:fail? (lambda (_) #t)])
                                         (prepare-output-raster e 'a) #f))))
             (check-true (channel-get ch)))
           #:create (lambda () (set! creates (add1 creates)) 'c))
     (check-equal? creates 0))
   (test-case "unavailability is an error by default"
     (check-exn exn:fail:gpu:unavailable?
       (lambda () (lazy (lambda (e) (prepare-output-raster e 'a)) #:create unavailable))))
   (test-case "explicit unavailable policy selects CPU and records a reason"
     (define p (lazy (lambda (e) (prepare-output-raster e 'a)) #:create unavailable #:policy 'cpu))
     (check-eq? (output-raster-plan-backend p) 'raster)
     (check-equal? (hash-ref (output-raster-plan-fallback p) 'step) "test-device")
     (check-false (output-raster-plan-generation p)))
   (test-case "unavailable factory result is memoized without retry"
     (define attempts 0)
     (lazy (lambda (e) (prepare-output-raster e 'a) (prepare-output-raster e 'b))
           #:create (lambda () (set! attempts (add1 attempts)) (unavailable)) #:policy 'cpu)
     (check-equal? attempts 1))
   (test-case "CPU fallback does not close an uncreated context"
     (define closes 0)
     (lazy (lambda (e) (prepare-output-raster e 'a)) #:create unavailable #:policy 'cpu
           #:close (lambda (_) (set! closes (add1 closes))))
     (check-equal? closes 0))
   (test-case "ordinary factory exceptions are not CPU fallbacks"
     (check-exn #rx"programming error"
       (lambda () (lazy (lambda (e) (prepare-output-raster e 'a)) #:policy 'cpu
                        #:create (lambda () (error 'factory "programming error"))))))
   (test-case "validation unavailability is not factory unavailability"
     (define closed? #f)
     (check-exn exn:fail:gpu:unavailable?
       (lambda () (lazy (lambda (e) (prepare-output-raster e 'a)) #:policy 'cpu
                        #:check (lambda (_) (unavailable)) #:close (lambda (_) (set! closed? #t)))))
     (check-true closed?))
   (test-case "plan errors are not CPU fallbacks"
     (check-exn exn:fail:gpu:unavailable?
       (lambda () (lazy (lambda (e) (prepare-output-raster e 'a)) #:policy 'cpu
                        #:plan (lambda (c p) (unavailable))))))
   (test-case "failed factory is not retried after caller catches its exception"
     (define attempts 0)
     (lazy (lambda (e)
             (for ([i (in-range 2)])
               (check-exn exn:fail? (lambda () (prepare-output-raster e 'a)))))
           #:create (lambda () (set! attempts (add1 attempts)) (error 'factory "failed")))
     (check-equal? attempts 1))
   (test-case "recursive lazy initialization is rejected"
     (define e #f)
     (check-exn #rx"recursive"
       (lambda () (lazy (lambda (v) (set! e v) (prepare-output-raster v 'a))
                        #:create (lambda () (prepare-output-raster e 'a))))))
   (test-case "bad unavailable policy is rejected before callback"
     (check-exn exn:fail:contract? (lambda () (lazy values #:policy 'fallback))))
   (test-case "failed close cannot leave a reusable executor"
     (define saved #f) (define closes 0)
     (check-exn #rx"close failed"
       (lambda () (lazy (lambda (e) (set! saved e) (prepare-output-raster e 'a))
                        #:close (lambda (_) (set! closes (add1 closes)) (error 'test "close failed")))))
     (check-exn #rx"expired" (lambda () (prepare-output-raster saved 'a)))
     (check-equal? closes 1))
   (test-case "planned execution does not claim a readback"
     (define p (plan 'c 'p))
     (define d (output-execution-details 'gpu 'planned 'metal #:plan p))
     (check-equal? (hash-ref d 'readback_count) 0) (check-equal? (hash-ref d 'transfer) "none"))
   (test-case "completed GPU report separates execution from transfer"
     (define d (output-execution-details 'gpu 'completed 'metal #:plan (plan 'c 'p)))
     (check-equal? (hash-ref d 'readback_count) 1)
     (check-equal? (hash-ref d 'context_generation) 17)
     (check-equal? (hash-ref d 'image_storage) "cpu-owned")
     (check-not-exn (lambda () (jsexpr->string d))))
   (test-case "CPU fallback does not claim GPU transfer"
     (define p (lazy (lambda (e) (prepare-output-raster e 'a)) #:create unavailable #:policy 'cpu))
     (define d (output-execution-details 'gpu 'completed 'raster #:plan p))
     (check-equal? (hash-ref d 'readback_count) 0) (check-equal? (hash-ref d 'requested) "gpu"))
   (test-case "exact GPU target receives raster representation audit"
     (define h (gensym))
     (define events (geometry-events (lambda () (call-with-audit-gpu-raster h (lambda () (drawing-event h 'gpu))))))
     (check-equal? (length events) 1)
     (check-eq? (output-audit-event-status (car events)) 'rasterized))
   (test-case "unrelated GPU target cannot inherit raster audit scope"
     (define events (geometry-events (lambda () (call-with-audit-gpu-raster 'a (lambda () (drawing-event 'b 'gpu))))))
     (check-equal? events '()))
   (test-case "GPU audit authority expires on scope exit"
     (define saved #f)
     (call-with-audit-gpu-raster 'h
       (lambda ()
         (set! saved (current-parameterization))))
     (check-exn #rx"expired"
       (lambda () (call-with-parameterization saved (lambda () (drawing-event 'h 'gpu))))))
   (test-case "inherited thread cannot use GPU audit authority"
     (define ch (make-channel))
     (call-with-audit-gpu-raster 'h
       (lambda ()
         (thread (lambda ()
                   (channel-put ch (with-handlers ([exn:fail? (lambda (_) #t)])
                                     (drawing-event 'h 'gpu) #f))))
         (check-true (channel-get ch)))))
   (test-case "strict audit rejects a raster decision before preparation"
     (define prepared? #f)
     (check-exn exn:fail:output-audit?
       (lambda ()
         (call-with-audit-collector 'svg 'vector-only #f 1
           (lambda () (audit-output-group! 'svg #t (hasheq)) (set! prepared? #t)))))
     (check-false prepared?))))
