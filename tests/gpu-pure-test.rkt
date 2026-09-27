#lang racket/base
(require rackunit racket/list ffi/unsafe
         "gpu-fixtures.rkt" "../gpu.rkt"
         "../private/gpu-context.rkt" "../private/gpu-domain.rkt"
         "../private/gpu-provider.rkt" "../private/gpu-types.rkt"
         "../private/gpu-diagnostics.rkt" "../private/native-platform.rkt")
(provide gpu-pure-tests)
(define (provider activate current? [key (gensym 'host)])
  (make-gpu-provider #:name 'test #:backend 'opengl #:key key
                     #:call-as-current activate #:current? current?))
(define gpu-pure-tests
  (test-suite
   "GPU foundation: pure mock-provider, ownership, lifecycle, and ABI tests"
   (test-case "provider construction does not run callbacks"
     (define calls 0)
     (define p (provider (lambda (_) (set! calls (add1 calls))) (lambda () #f)))
     (check-true (gpu-provider? p)) (check-equal? calls 0))
   (test-case "provider callback arity is checked"
     (check-exn exn:fail:contract? (lambda () (provider 12 void)))
     (check-exn exn:fail:contract? (lambda () (provider void 12))))
   (test-case "provider key must be stable"
     (check-exn exn:fail:contract? (lambda () (provider void void (box 1)))))
   (test-case "provider backend is explicit"
     (check-exn exn:fail:contract?
                (lambda () (make-gpu-provider #:name 'test #:backend 'auto #:key 'key
                             #:call-as-current void #:current? void))))
   (test-case "provider preserves multiple values"
     (check-equal? (call-with-values
                    (lambda () (provider-call (provider (lambda (f) (f)) (lambda () #t))
                                               (lambda () (values 10 20)))) list) '(10 20)))
   (test-case "provider cannot replace callback return values"
     (check-equal?
      (call-with-values
       (lambda () (provider-call (provider (lambda (f) (f) 'ignored) (lambda () #t))
                                  (lambda () (values 3 4)))) list)
      '(3 4)))
   (test-case "provider cannot swallow a callback failure"
     (define p (provider (lambda (f) (with-handlers ([exn:fail? (lambda (_) 'swallowed)]) (f)))
                         (lambda () #t)))
     (check-exn #rx"original failure" (lambda () (provider-call p (lambda () (error 'test "original failure"))))))
   (test-case "provider must invoke its callback"
     (check-exn exn:fail? (lambda () (provider-call (provider (lambda (_) 10) (lambda () #t)) void))))
   (test-case "provider must not invoke twice"
     (check-exn exn:fail? (lambda () (provider-call (provider (lambda (f) (f) (f)) (lambda () #t)) void))))
   (test-case "late provider callback is retired"
     (define saved #f)
     (provider-call (provider (lambda (f) (set! saved f) (f)) (lambda () #t)) void)
     (check-exn exn:fail? saved))
   (test-case "provider must make native context current"
     (check-exn exn:fail? (lambda () (provider-call (provider (lambda (f) (f)) (lambda () #f)) void))))
   (test-case "provider rejects another thread before acquisition"
     (define calls 0)
     (define p (provider (lambda (f) (set! calls (add1 calls)) (f)) (lambda () #t)))
     (check-true (exn:fail? (in-worker (lambda () (provider-call p void)))))
     (check-equal? calls 0))
   (test-case "provider rejects callback execution on another thread"
     (define p (provider (lambda (f) (define result (in-worker f)) (when (exn? result) (raise result)))
                         (lambda () #t)))
     (check-exn exn:fail? (lambda () (provider-call p void))))
   (test-case "diagnostics are copied and immutable"
     (define text (string-copy "renderer"))
     (define copy (freeze-gpu-details (hash 'name text 'data (list text))))
     (string-set! text 0 #\X)
     (check-true (immutable? copy))
     (check-equal? (hash-ref copy 'name) "renderer")
     (check-true (immutable? (hash-ref copy 'name))))
   (test-case "diagnostics reject pointers and nonfinite data"
     (check-exn exn:fail? (lambda () (freeze-gpu-details (hasheq 'pointer (malloc 8 'atomic)))))
     (check-exn exn:fail? (lambda () (freeze-gpu-details +nan.0))))
   (test-case "domain initializes and closes under its provider"
     (define-values (p driver log abandoned?) (make-mock))
     (define d (make-gpu-domain p driver))
     (check-eq? (domain-state d) 'ready)
     (domain-close! d)
     (check-eq? (domain-state d) 'closed)
     (check-equal? (events log) '(activate create describe deactivate activate release-context deactivate)))
   (test-case "same host cannot have two live Ganesh domains"
     (call-with-mock
      (lambda (d p driver log a)
        (check-exn exn:fail? (lambda () (make-gpu-domain p driver)))
        (check-equal? (event-count log 'create) 1))))
   (test-case "duplicate host identity is rejected across provider wrappers"
     (define-values (p driver log a) (make-mock #:key 'shared-gpu-test-host))
     (define-values (q other other-log b) (make-mock #:key 'shared-gpu-test-host))
     (define d (make-gpu-domain p driver))
     (check-exn exn:fail? (lambda () (make-gpu-domain q other)))
     (domain-close! d))
   (test-case "null construction releases the host claim"
     (define-values (p driver log a) (make-mock #:create (lambda () #f)))
     (check-exn exn:fail:gpu:unavailable? (lambda () (make-gpu-domain p driver)))
     (define replacement (struct-copy gpu-driver driver [create (lambda () 'pointer)]))
     (define d (make-gpu-domain p replacement))
     (domain-close! d))
   (test-case "failed diagnostic construction releases the native context"
     (define-values (p driver log a) (make-mock #:describe (lambda () (error 'mock "describe failed"))))
     (check-exn exn:fail? (lambda () (make-gpu-domain p driver)))
     (check-equal? (event-count log 'release-context) 1))
   (test-case "mutable diagnostic snapshots reject with cleanup"
     (define-values (p driver log a) (make-mock #:describe (lambda () (make-hash))))
     (check-exn exn:fail? (lambda () (make-gpu-domain p driver)))
     (check-equal? (event-count log 'release-context) 1))
   (test-case "scope preserves values and has a checked native pointer"
     (call-with-mock
      (lambda (d p driver log a)
        (check-equal? (domain-call d (lambda () (+ 2 3))) 5)
        (check-equal? (call-with-values (lambda () (domain-call d (lambda () (values 1 2 3)))) list) '(1 2 3))
        (check-not-false (domain-call d (lambda () (domain-pointer d)))))))
   (test-case "native pointer cannot be obtained outside a scope"
     (call-with-mock (lambda (d p driver log a) (check-exn exn:fail? (lambda () (domain-pointer d))))))
   (test-case "wrong-thread domain use never activates"
     (call-with-mock
      (lambda (d p driver log a)
        (define before (events log))
        (check-true (exn:fail? (in-worker (lambda () (domain-call d void)))))
        (check-equal? (events log) before))))
   (test-case "same-domain nested scopes restore the outer lease"
     (call-with-mock
      (lambda (d p driver log a)
        (domain-call d (lambda () (domain-call d void) (check-not-false (domain-pointer d))))
        (check-equal? (event-count log 'reset) 1))))
   (test-case "foreign nested domains are rejected without switching"
     (call-with-mock
      (lambda (d p driver log a)
        (call-with-mock
         (lambda (e q other log2 b)
           (check-exn exn:fail? (lambda () (domain-call d (lambda () (domain-call e void)))))
           (check-equal? (event-count log2 'reset) 0))))))
   (test-case "exceptions retire the activation and allow a later scope"
     (call-with-mock
      (lambda (d p driver log a)
        (check-exn exn:fail? (lambda () (domain-call d (lambda () (error 'test "escape")))))
        (check-exn exn:fail? (lambda () (domain-pointer d)))
        (check-equal? (domain-call d (lambda () 'again)) 'again))))
   (test-case "continuation escape retires scope"
     (call-with-mock
      (lambda (d p driver log a)
        (check-equal? (let/ec escape (domain-call d (lambda () (escape 17)))) 17)
        (check-exn exn:fail? (lambda () (domain-pointer d)))
        (domain-call d void))))
   (test-case "captured continuation cannot reenter a retired scope"
     (call-with-mock
      (lambda (d p driver log a)
        (define saved #f)
        (domain-call d (lambda () (call/cc (lambda (k) (set! saved k) 'first))))
        (check-exn exn:fail? (lambda () (saved 'again))))))
   (test-case "failed driver reset retires the lease and permits teardown"
     (define-values (p driver log a) (make-mock))
     (define d (make-gpu-domain p (struct-copy gpu-driver driver
                                   [reset (lambda (_) (error 'mock "reset failed"))])))
     (check-exn exn:fail? (lambda () (domain-call d void)))
     (domain-close! d)
     (check-eq? (domain-state d) 'closed))
   (test-case "native context changed in callback is rejected and scope retired"
     (call-with-mock
      (lambda (d p driver log a)
        (check-exn exn:fail?
                   (lambda () (domain-call d (lambda () (current-mock 'wrong-host)))))
        (check-exn exn:fail? (lambda () (domain-pointer d)))
        (domain-call d void))))
   (test-case "shutdown request inside scope prevents further resource creation"
     (call-with-mock
      (lambda (d p driver log a)
        (domain-call d
          (lambda ()
            (domain-request-shutdown! d)
            (check-exn exn:fail? (lambda () (mock-resource d log a)))))
        (check-equal? (domain-live-count d) 0))))
   (test-case "normal close and abandon reject active scopes"
     (call-with-mock
      (lambda (d p driver log a)
        (domain-call d
         (lambda ()
           (check-exn exn:fail? (lambda () (domain-close! d)))
           (check-exn exn:fail? (lambda () (domain-abandon! d)))
           (check-exn exn:fail? (lambda () (drain-pending-domains!))))))))
   (test-case "close is idempotent"
     (call-with-mock
      (lambda (d p driver log a)
        (domain-close! d) (domain-close! d)
        (check-equal? (event-count log 'release-context) 1)
        (check-exn exn:fail? (lambda () (domain-call d void))))))
   (test-case "recreated domain has a new generation"
     (call-with-mock
      (lambda (d p driver log a)
        (define generation (domain-generation d))
        (domain-close! d)
        (define next (make-gpu-domain p driver))
        (check-true (> (domain-generation next) generation))
        (domain-close! next))))
   (test-case "child construction requires a current scope"
     (call-with-mock
      (lambda (d p driver log a)
        (check-exn exn:fail? (lambda () (mock-resource d log a))))))
   (test-case "child creation failure does not increment live count"
     (call-with-mock
      (lambda (d p driver log a)
        (domain-call d (lambda () (check-exn exn:fail? (lambda () (domain-new-resource d 'failed (lambda () #f) void)))))
        (check-equal? (domain-live-count d) 0))))
   (test-case "explicit child close queues without activating or releasing"
     (call-with-mock
      (lambda (d p driver log a)
        (define h (domain-call d (lambda () (mock-resource d log a))))
        (define before (events log))
        (domain-resource-close! h)
        (check-equal? (events log) before)
        (check-true (domain-resource-closed? h))
        (check-equal? (domain-live-count d) 0)
        (check-equal? (domain-pending-count d) 1))))
   (test-case "next activation drains queued native destruction"
     (call-with-mock
      (lambda (d p driver log a)
        (define h (domain-call d (lambda () (mock-resource d log a))))
        (domain-resource-close! h)
        (domain-call d (lambda () (check-equal? (event-count log 'child) 1)))
        (check-equal? (domain-pending-count d) 0))))
   (test-case "double child close releases exactly once"
     (call-with-mock
      (lambda (d p driver log a)
        (define h (domain-call d (lambda () (mock-resource d log a))))
        (domain-resource-close! h) (domain-resource-close! h)
        (domain-call d void)
        (check-equal? (event-count log 'child) 1))))
   (test-case "closed child rejects access even in a valid scope"
     (call-with-mock
      (lambda (d p driver log a)
        (define h (domain-call d (lambda () (mock-resource d log a))))
        (domain-resource-close! h)
        (domain-call d (lambda () (check-exn exn:fail? (lambda () (resource-pointer h))))))))
   (test-case "foreign active context does not authorize a child"
     (call-with-mock
      (lambda (d p driver log a)
        (define h (domain-call d (lambda () (mock-resource d log a))))
        (call-with-mock
         (lambda (other q driver2 log2 b)
           (domain-call other (lambda () (check-exn exn:fail? (lambda () (resource-pointer h)))))))
        (domain-resource-close! h))))
   (test-case "wrong-thread child close rejects before enqueue"
     (call-with-mock
      (lambda (d p driver log a)
        (define h (domain-call d (lambda () (mock-resource d log a))))
        (check-true (exn:fail? (in-worker (lambda () (domain-resource-close! h)))))
        (check-equal? (domain-live-count d) 1)
        (domain-resource-close! h))))
   (test-case "normal context close rejects live children"
     (call-with-mock
      (lambda (d p driver log a)
        (define h (domain-call d (lambda () (mock-resource d log a))))
        (check-exn exn:fail? (lambda () (domain-close! d)))
        (check-eq? (domain-state d) 'ready)
        (domain-resource-close! h))))
   (test-case "children are destroyed before their native context"
     (call-with-mock
      (lambda (d p driver log a)
        (define h (domain-call d (lambda () (mock-resource d log a))))
        (domain-resource-close! h) (domain-close! d)
        (check-true (< (index-of (events log) 'child) (index-of (events log) 'release-context))))))
   (test-case "newly enqueued work during drain is not lost at close"
     (call-with-mock
      (lambda (d p driver log a)
        (define second #f)
        (define first
          (domain-call d
           (lambda ()
             (set! second (mock-resource d log a 'second))
             (domain-new-resource d 'first (lambda () 'first)
               (lambda (_) (domain-resource-close! second))))))
        (domain-resource-close! first)
        (domain-close! d)
        (check-equal? (event-count log 'second) 1)
        (check-equal? (domain-pending-count d) 0))))
   (test-case "GC queues child destruction without provider acquisition"
     (call-with-mock
      (lambda (d p driver log a)
        (define weak (domain-call d (lambda () (make-weak-box (mock-resource d log a)))))
        (define before (event-count log 'activate))
        (check-true (collect-until (lambda () (= (domain-pending-count d) 1))))
        ;; A finalizer receives the value while it is about to be collected.
        ;; Its side effect can therefore become visible one GC cycle before a
        ;; separate weak box is cleared. Wait for collection independently.
        (check-true (collect-until (lambda () (not (weak-box-value weak)))))
        (check-false (weak-box-value weak))
        (check-equal? (event-count log 'activate) before)
        (check-equal? (event-count log 'child) 0)
        (domain-call d void)
        (check-equal? (event-count log 'child) 1))))
   (test-case "abandon invalidates children without making GL current"
     (call-with-mock
      (lambda (d p driver log a)
        (define h (domain-call d (lambda () (mock-resource d log a))))
        (define before (event-count log 'activate))
        (domain-abandon! d)
        (check-eq? (domain-state d) 'abandoned)
        (check-equal? (event-count log 'activate) before)
        (check-exn exn:fail? (lambda () (domain-call d void)))
        (domain-resource-close! h)
        (domain-drain! d)
        (check-equal? (event-count log 'child) 1))))
   (test-case "abandon is idempotent and does not silently close live children"
     (call-with-mock
      (lambda (d p driver log a)
        (define h (domain-call d (lambda () (mock-resource d log a))))
        (domain-abandon! d) (domain-abandon! d)
        (check-equal? (event-count log 'abandon) 1)
        (check-exn exn:fail? (lambda () (domain-close! d)))
        (domain-resource-close! h))))
   (test-case "shutdown requests from other threads only enqueue"
     (call-with-mock
      (lambda (d p driver log a)
        (define before (events log))
        (check-eq? (in-worker (lambda () (domain-request-shutdown! d))) 'returned)
        (check-equal? (events log) before)
        (check-exn exn:fail? (lambda () (domain-call d void)))
        (drain-pending-domains!)
        (check-eq? (domain-state d) 'closed))))
   (test-case "custodian callback requests shutdown without backend work"
     (call-with-mock
      (lambda (d p driver log a)
        (define custodian (make-custodian))
        (define context (parameterize ([current-custodian custodian]) (wrap-gpu-domain d)))
        (define before (events log))
        (custodian-shutdown-all custodian)
        (check-equal? (events log) before)
        (check-true (hash-ref (domain-info d) 'shutdown_requested))
        (drain-pending-domains!)
        (check-eq? (domain-state d) 'closed)
        (gpu-context-close! context))))
   (test-case "dead custodian construction closes the new domain"
     (call-with-mock
      (lambda (d p driver log a)
        (define custodian (make-custodian))
        (custodian-shutdown-all custodian)
        (check-exn exn:fail?
                   (lambda () (parameterize ([current-custodian custodian]) (wrap-gpu-domain d))))
        (check-eq? (domain-state d) 'closed))))
   (test-case "public context GC requests owner-side cleanup"
     (call-with-mock
      (lambda (d p driver log a)
        (define weak (make-weak-box (wrap-gpu-domain d)))
        (define before (event-count log 'activate))
        (check-true (collect-until (lambda () (hash-ref (domain-info d) 'shutdown_requested))))
        ;; register-finalizer-and-custodian-shutdown likewise calls the
        ;; callback while the context is still the finalizer argument.
        (check-true (collect-until (lambda () (not (weak-box-value weak)))))
        (check-false (weak-box-value weak))
        (check-equal? (event-count log 'activate) before)
        (drain-pending-domains!)
        (check-eq? (domain-state d) 'closed))))
   (test-case "public context explicit close cancels later custodian work"
     (call-with-mock
      (lambda (d p driver log a)
        (define custodian (make-custodian))
        (define context (parameterize ([current-custodian custodian]) (wrap-gpu-domain d)))
        (gpu-context-close! context)
        (define before (events log))
        (custodian-shutdown-all custodian)
        (check-equal? (events log) before)
        (check-true (gpu-context? context)))))
   (test-case "public API rejects invalid contexts without native loading"
     (check-exn exn:fail:contract? (lambda () (call-with-gpu-context #f void)))
     (check-exn exn:fail:contract? (lambda () (make-gpu-context #f))))
   (test-case "public Metal rendering request is explicit unavailability"
     (define p (make-gpu-provider #:name 'test #:backend 'metal #:key 'unimplemented
                                  #:call-as-current void #:current? void))
     (check-exn exn:fail:gpu:unavailable? (lambda () (make-gpu-context p))))
   (test-case "software renderer names override vendor hardware hints"
     (check-equal? (renderer-class "Intel" "Mesa llvmpipe") "software")
     (check-equal? (renderer-class "Google" "SwiftShader") "software")
     (check-equal? (renderer-class "Microsoft" "GDI Generic") "software"))
   (test-case "hardware strings and unknown strings stay distinct"
     (check-equal? (renderer-class "Apple" "Apple M3 Pro") "hardware-reported")
     (check-equal? (renderer-class "NVIDIA Corporation" "GeForce") "hardware-reported")
     (check-equal? (renderer-class "unknown" "unknown") "unclassified"))
   (test-case "pixel checker rejects missing and blank output"
     (check-exn exn:fail? (lambda () (verify-smoke-pixels #"")))
     (check-exn exn:fail? (lambda () (verify-smoke-pixels (make-bytes 256)))))
   (test-case "pixel checker accepts complete asymmetric RGBA pattern"
     (define data
       (apply bytes
         (append*
           (for*/list ([y (in-range 8)] [x (in-range 8)])
             (cond [(= x 3) '(0 0 0 0)]
                   [(< y 4) (if (< x 3) '(255 0 0 255) '(0 255 0 255))]
                   [else (if (< x 3) '(0 0 255 255) '(255 255 0 255))])))))
     (check-true (verify-smoke-pixels data))
     (bytes-set! data 0 0)
     (check-exn exn:fail? (lambda () (verify-smoke-pixels data))))
   (test-case "GL descriptor ABI sizes and offsets"
     (check-equal? (ctype-sizeof _gr-gl-framebuffer-info) 12)
     (check-equal? (ctype-sizeof _gr-gl-texture-info) 16)
     (define info (make-gr-gl-texture-info 1 2 3 #t))
     (check-equal? (for/list ([i (in-range 3)]) (ptr-ref info _uint32 i)) '(1 2 3))
     (check-equal? (ptr-ref info _uint8 12) 1))
   (test-case "Metal descriptor ABI and enum discriminants"
     (check-equal? (ctype-sizeof _gr-mtl-texture-info) (ctype-sizeof _pointer))
     (check-equal? (list gr-opengl gr-metal gr-top-left gr-bottom-left) '(0 2 0 1)))
   (test-case "Windows x64 loading selection does not change CPU platforms"
     (check-equal? (native-rid 'windows 'x86_64) "win-x64")
     (check-equal? (native-rid 'macosx 'aarch64) "osx")
     (check-equal? (native-rid 'unix 'x86_64) "linux-x64")
     (check-equal? (native-rid 'unix 'aarch64) "linux-arm64")
     (check-false (native-rid 'windows 'aarch64)))
   (test-case "Windows DLL names are selected for both native libraries"
     (check-equal? (native-library-name 'skia 'windows) "libSkiaSharp.dll")
     (check-equal? (native-library-name 'harfbuzz 'windows) "libHarfBuzzSharp.dll")
     (check-equal? (native-library-name 'skia 'macosx) "libSkiaSharp.dylib")
     (check-equal? (native-library-name 'harfbuzz 'unix) "libHarfBuzzSharp.so"))))
