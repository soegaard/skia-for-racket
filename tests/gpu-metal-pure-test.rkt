#lang racket/base
(require rackunit racket/list ffi/unsafe/atomic
         "../gpu.rkt" "../private/gpu-domain.rkt" "../private/gpu-types.rkt"
         "../private/gpu-provider.rkt" "../private/gpu-native-scope.rkt"
         "gpu-fixtures.rkt" "gpu-metal-fixtures.rkt")
(provide gpu-metal-pure-tests)
(define (failed-construction fail)
  (define f (make-metal-fixture fail))
  (check-exn exn:fail? (lambda () (make-gpu-domain (metal-fixture-provider f) (metal-fixture-driver f))))
  (check-equal? (metal-live-refs f) '(0 0 0))
  (check-equal? (metal-event-count f 'pool-enter) (metal-event-count f 'pool-leave))
  f)
(define gpu-metal-pure-tests
  (test-suite
   "Metal ownership and native-call scopes: pure mocked operations"
   (test-case "constructor without a host needs an explicit backend"
     (check-exn exn:fail:contract? (lambda () (make-gpu-context))))
   (test-case "unsupported backend rejects before native initialization"
     (check-exn exn:fail:contract? (lambda () (make-gpu-context #:backend 'auto))))
   (test-case "OpenGL still requires its host"
     (check-exn exn:fail:contract? (lambda () (make-gpu-context #:backend 'opengl))))
   (test-case "invalid provider is rejected before native initialization"
     (check-exn exn:fail:contract? (lambda () (make-gpu-context 'invalid #:backend 'metal))))
   (test-case "a supplied host cannot silently change backend"
     (define-values (p driver log a) (make-mock))
     (check-exn exn:fail:contract? (lambda () (make-gpu-context p #:backend 'metal)))
     (check-equal? (events log) '()))
   (test-case "unimplemented external Metal providers fail explicitly"
     (define f (make-metal-fixture))
     (check-exn exn:fail:gpu:unavailable? (lambda () (make-gpu-context (metal-fixture-provider f))))
     (check-equal? (metal-events f) '()))
   (test-case "native backend IDs are explicit and distinct"
     (check-equal? (map gpu-backend-native-id '(opengl metal)) '(0 2))
     (check-exn exn:fail:contract? (lambda () (gpu-backend-native-id 'cpu))))
   (test-case "default native scope preserves multiple values"
     (check-equal? (call-with-values (lambda () (call-with-gpu-native-scope (lambda () (values 1 2)))) list) '(1 2)))
   (test-case "native scope rejects invalid callbacks"
     (check-exn exn:fail:contract? (lambda () (make-gpu-native-scope 1 void)))
     (check-exn exn:fail:contract? (lambda () (make-gpu-native-scope void 1))))
   (test-case "native-call scope enters and leaves exactly once"
     (define f (make-metal-fixture))
     (parameterize ([current-gpu-native-scope (metal-fixture-scope f)])
       (check-true (call-with-gpu-native-scope in-atomic-mode?)))
     (check-equal? (metal-events f) '(pool-enter pool-leave)))
   (test-case "nested FFI wrappers share their immediate pool"
     (define f (make-metal-fixture))
     (parameterize ([current-gpu-native-scope (metal-fixture-scope f)])
       (call-with-gpu-native-scope (lambda () (call-with-gpu-native-scope void))))
     (check-equal? (metal-events f) '(pool-enter pool-leave)))
   (test-case "native failure closes its pool before propagating"
     (define f (make-metal-fixture))
     (parameterize ([current-gpu-native-scope (metal-fixture-scope f)])
       (check-exn exn:fail? (lambda () (call-with-gpu-native-scope (lambda () (error 'test "failure"))))))
     (check-false (unbox (metal-fixture-in-pool f)))
     (check-equal? (metal-events f) '(pool-enter pool-leave)))
   (test-case "failed pool entry is not popped"
     (define popped? #f)
     (define s (make-gpu-native-scope (lambda () (error 'test "enter")) (lambda (_) (set! popped? #t))))
     (parameterize ([current-gpu-native-scope s])
       (check-exn exn:fail? (lambda () (call-with-gpu-native-scope void))))
     (check-false popped?))
   (test-case "expired native continuation cannot reopen a pool"
     (define f (make-metal-fixture)) (define saved #f)
     (parameterize ([current-gpu-native-scope (metal-fixture-scope f)])
       (call-with-gpu-native-scope (lambda () (call/cc (lambda (k) (set! saved k))))))
     (check-exn exn:fail? (lambda () (saved 'again)))
     (check-equal? (metal-events f) '(pool-enter pool-leave)))
   (test-case "inherited parameters do not expose a parent's pool in another thread"
     (define f (make-metal-fixture))
     (parameterize ([current-gpu-native-scope (metal-fixture-scope f)])
       (check-eq? (in-worker (lambda () (call-with-gpu-native-scope void))) 'returned))
     (check-equal? (metal-events f) '()))
   (test-case "deferred release remembers its native scope"
     (define f (make-metal-fixture))
     (define release
       (parameterize ([current-gpu-native-scope (metal-fixture-scope f)])
         (capture-gpu-native-release (lambda (p) (check-true (unbox (metal-fixture-in-pool f)))))))
     (release 'pointer)
     (check-equal? (metal-events f) '(pool-enter pool-leave)))
   (test-case "successful constructor balances caller Create and new references"
     (define f (make-metal-fixture))
     (define d (make-gpu-domain (metal-fixture-provider f) (metal-fixture-driver f)))
     (check-equal? (metal-live-refs f) '(1 1 1))
     (check-equal? (metal-event-count f 'release-queue) 1)
     (check-equal? (metal-event-count f 'release-device) 1)
     (domain-close! d)
     (check-equal? (metal-live-refs f) '(0 0 0)))
   (test-case "null device creates no queue"
     (define f (failed-construction 'device-null))
     (check-equal? (metal-event-count f 'queue) 0))
   (test-case "raised device creation balances its pool"
     (void (failed-construction 'device-raise)))
   (test-case "null queue releases the device"
     (define f (failed-construction 'queue-null))
     (check-equal? (metal-event-count f 'release-device) 1))
   (test-case "raised queue creation releases the device"
     (void (failed-construction 'queue-raise)))
   (test-case "device description failure releases both caller references"
     (void (failed-construction 'device-info)))
   (test-case "null Ganesh creation releases both caller references"
     (void (failed-construction 'context-null)))
   (test-case "raised Ganesh creation releases both caller references"
     (void (failed-construction 'context-raise)))
   (test-case "post-creation context description failure releases Ganesh once"
     (define f (failed-construction 'context-info))
     (check-equal? (metal-event-count f 'release-context) 1))
   (test-case "a failed construction does not leave the provider claim behind"
     (define f (failed-construction 'queue-null))
     (set-box! (metal-fixture-failure f) #f)
     (define d (make-gpu-domain (metal-fixture-provider f) (metal-fixture-driver f)))
     (domain-close! d)
     (check-equal? (metal-live-refs f) '(0 0 0)))
   (test-case "independent owned queues have distinct domains"
     (with-metal-fixture
      (lambda (f d)
        (with-metal-fixture
         (lambda (g e)
           (check-false (eq? (gpu-provider-key (metal-fixture-provider f)) (gpu-provider-key (metal-fixture-provider g))))
           (check-false (= (domain-generation d) (domain-generation e))))))))
   (test-case "application scope has no open autorelease pool"
     (with-metal-fixture
      (lambda (f d)
        (domain-call d (lambda () (check-false (unbox (metal-fixture-in-pool f))))))))
   (test-case "same-domain nested scope does not disturb outer ownership"
     (with-metal-fixture
      (lambda (f d)
        (domain-call d
          (lambda ()
            (define lease (domain-capture-lease d))
            (domain-call d void)
            (domain-check-lease! 'test lease)
            (check-false (unbox (metal-fixture-in-pool f)))))
        (check-equal? (metal-event-count f 'reset) 1))))
   (test-case "foreign nested Metal domains fail before switching"
     (with-metal-fixture
      (lambda (f d)
        (with-metal-fixture
         (lambda (g e)
           (check-exn exn:fail? (lambda () (domain-call d (lambda () (domain-call e void)))))
           (check-equal? (metal-event-count g 'reset) 0))))))
   (test-case "wrong-thread Metal ownership is rejected"
     (with-metal-fixture
      (lambda (f d) (check-true (exn:fail? (in-worker (lambda () (domain-call d void))))))))
   (test-case "explicit child release queues outside activation and drains under a pool"
     (with-metal-fixture
      (lambda (f d)
        (define released? #f)
        (define h (domain-call d
                    (lambda () (domain-new-resource d 'child (lambda () 'native)
                      (lambda (_) (set! released? (unbox (metal-fixture-in-pool f))))))))
        (domain-resource-close! h)
        (check-false released?)
        (domain-call d void)
        (check-true released?))))
   (test-case "abandon and release work without a provider activation"
     (define f (make-metal-fixture))
     (define d (make-gpu-domain (metal-fixture-provider f) (metal-fixture-driver f)))
     (define released? #f)
     (define h (domain-call d (lambda () (domain-new-resource d 'child (lambda () 'native)
                   (lambda (_) (set! released? (unbox (metal-fixture-in-pool f))))))))
     (domain-abandon! d) (domain-resource-close! h) (domain-close! d)
     (check-true released?) (check-equal? (metal-live-refs f) '(0 0 0)))
   (test-case "GC only queues; the finalizer never opens a Metal pool"
     (with-metal-fixture
      (lambda (f d)
        (define released? #f)
        (define weak
          (domain-call d
            (lambda () (make-weak-box
              (domain-new-resource d 'child (lambda () 'native)
                (lambda (_) (set! released? (unbox (metal-fixture-in-pool f)))))))))
        (define before (metal-event-count f 'pool-enter))
        (check-true (collect-until (lambda () (= (domain-pending-count d) 1))))
        (check-equal? before (metal-event-count f 'pool-enter))
        (check-false released?)
        (domain-call d void)
        (check-true released?)
        (check-true (collect-until (lambda () (not (weak-box-value weak)))))))))
)
