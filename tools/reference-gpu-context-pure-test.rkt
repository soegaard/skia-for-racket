#lang racket/base

;;;
;;; Reference GPU Context Pure Test
;;;

;; Checks activation, thread affinity, child leases, shutdown, and release quarantine using fake
;; drivers.
;; These acceptance checks keep the Reference's documented contracts aligned with the public
;; implementation.

;;;
;;; Imports and Exports
;;;

;; No native graphics calls. Private fake drivers exercise the actual state
;; machine and public context wrappers; they are not GPU acceptance evidence.
(require rackunit racket/list skia/gpu skia/gpu-context-options
         (only-in "../private/gpu-context.rkt" wrap-gpu-domain)
         (prefix-in p: "../private/gpu-provider.rkt")
         (prefix-in d: "../private/gpu-domain.rkt")
         (prefix-in control: (submod "../private/gpu-context-control.rkt" testing)))


;;;
;;; Diagnostic Operations
;;;

; fake-context : [any/c] -> (values gpu-context? any/c box?)
;;   Builds a fake provider and driver with an event log for native-free context lifecycle checks.
(define (fake-context [key (gensym 'reference-host)])
  (define events (box '()))
  (define active? (make-parameter #f))
  (define (record kind) (set-box! events (cons kind (unbox events))))
  (define provider
    (make-gpu-provider
     #:name 'reference-test #:backend 'opengl #:key key
     #:current? (lambda () (active?))
     #:call-as-current
     (lambda (thunk)
       (record 'activate)
       (parameterize ([active? #t]) (thunk)))))
  (define driver
    (d:gpu-driver (lambda () (record 'create) 'fake-context-pointer)
                  (lambda (_) (record 'release))
                  (lambda (_) (record 'abandon))
                  (lambda (_) (record 'reset))
                  (lambda (_) (hasheq 'scope "fake-driver"))))
  (define domain (d:make-gpu-domain provider driver))
  (values (wrap-gpu-domain domain) domain events))


; with-fake : procedure? -> any
;;   Scopes a fake context, leaving release-failed state intact so tests can inspect failed cleanup.
(define (with-fake proc)
  (define-values (context domain events) (fake-context))
  (dynamic-wind void
    (lambda () (proc context domain events))
    (lambda ()
      ;; An intentionally indeterminate fake release is never retried. No native
      ;; pointer exists in this test; the actual quarantine rules are preserved.
      (unless (eq? (gpu-context-state context) 'release-failed)
        (gpu-context-close! context)))))


; other-thread-result : procedure? -> list?
;;   Runs one operation on a worker thread and returns a tagged result or raised value for affinity
;;   checks.
(define (other-thread-result proc)
  (define result (box #f))
  (define worker
    (thread
     (lambda ()
       (set-box! result
         (with-handlers ([(lambda (_) #t) (lambda (e) (list 'raised e))])
           (list 'returned (proc)))))))
  (thread-wait worker)
  (unbox result))


; provider-for : procedure? [procedure?] -> gpu-provider?
;;   Builds a uniquely keyed fake OpenGL provider using supplied activation and current-context
;;   checks.
(define (provider-for activate [current? (lambda () #t)])
  (make-gpu-provider #:name 'reference-test #:backend 'opengl #:key (gensym)
                     #:call-as-current activate #:current? current?))

(module+ test
  (test-case "backend declarations do not claim runtime availability"
    (check-equal? (gpu-backends) '(opengl metal direct3d))
    (check-false (gpu-backend? 'vulkan))
    (check-false (gpu-backend? "metal"))
    (for ([backend (in-list (gpu-backends))])
      (define info (gpu-backend-capabilities backend))
      (check-true (immutable? info))
      (check-true (immutable? (hash-ref info 'features)))
      (check-equal? (hash-ref info 'scope) "wrapper-declarations")
      (check-equal? (hash-ref info 'runtime_availability) "not-probed")
      (check-false (hash-ref info 'native_probe_performed))
      (check-false (hash-ref info 'hardware_acceleration_verified))))

  (test-case "options preserve all six defaults"
    (define options (make-gpu-context-options))
    (check-true (gpu-context-options? options))
    (check-equal? (gpu-context-options->jsexpr options)
      (hasheq 'avoid_stencil_buffers #f 'runtime_program_cache_size 256
              'glyph_cache_texture_maximum_bytes 8388608 'allow_path_mask_caching #t
              'manual_mipmapping #f 'buffer_map_threshold -1))
    (check-false (gpu-context-options? #f)))

  (test-case "option limits are exact entry counts and a uint64 byte budget"
    (define options
      (make-gpu-context-options #:runtime-program-cache-size #x7fffffff
        #:glyph-cache-texture-maximum-bytes #xffffffffffffffff
        #:buffer-map-threshold #x7fffffff))
    (check-equal? (gpu-context-options-runtime-program-cache-size options) #x7fffffff)
    (check-equal? (gpu-context-options-glyph-cache-texture-maximum-bytes options)
                  #xffffffffffffffff)
    (for ([bad (in-list '(0 1.0 2147483648))])
      (check-exn exn:fail:contract?
        (lambda () (make-gpu-context-options #:runtime-program-cache-size bad))))
    (check-exn exn:fail:contract?
      (lambda () (make-gpu-context-options #:glyph-cache-texture-maximum-bytes (expt 2 64))))
    (check-exn exn:fail:contract?
      (lambda () (make-gpu-context-options #:buffer-map-threshold -2))))

  (test-case "options are reusable data and serialization is immutable"
    (define a (make-gpu-context-options))
    (define b (make-gpu-context-options #:avoid-stencil-buffers? #t
               #:allow-path-mask-caching? #f #:manual-mipmapping? #t
               #:buffer-map-threshold 0))
    (check-false (gpu-context-options-avoid-stencil-buffers? a))
    (check-true (gpu-context-options-avoid-stencil-buffers? b))
    (check-false (gpu-context-options-allow-path-mask-caching? b))
    (check-true (gpu-context-options-manual-mipmapping? b))
    (check-true (immutable? (gpu-context-options->jsexpr b)))
    (check-equal? (other-thread-result (lambda () (gpu-context-options->jsexpr b)))
                  (list 'returned (gpu-context-options->jsexpr b)))
    (check-exn exn:fail:contract?
      (lambda () (make-gpu-context-options #:manual-mipmapping? 1))))

  (test-case "provider construction retains callbacks without invoking them"
    (define calls 0)
    (define (called . _) (set! calls (add1 calls)) #f)
    (define provider
      (make-gpu-provider #:name 'test-host #:backend 'opengl #:key 37
        #:call-as-current called #:current? called #:describe called
        #:get-proc-address called))
    (check-equal? calls 0)
    (check-true (gpu-provider? provider))
    (check-equal? (gpu-provider-name provider) 'test-host)
    (check-equal? (other-thread-result (lambda () (gpu-provider-backend provider)))
                  '(returned opengl)))

  (test-case "provider construction rejects invalid identities and callback arities"
    (for ([key (in-list '(0 -1 "host" #f))])
      (check-exn exn:fail:contract?
        (lambda () (make-gpu-provider #:name 'test #:backend 'opengl #:key key
                      #:call-as-current void #:current? void))))
    (check-exn exn:fail:contract?
      (lambda () (provider-for (lambda () (void)))))
    (check-exn exn:fail:contract?
      (lambda () (provider-for void (lambda (_) #t)))))

  (test-case "activation must invoke its callback exactly once while current"
    (check-exn exn:fail? (lambda () (p:provider-call (provider-for void) void)))
    (check-exn exn:fail?
      (lambda () (p:provider-call (provider-for (lambda (thunk) (thunk) (thunk))) void)))
    (check-exn exn:fail?
      (lambda () (p:provider-call (provider-for (lambda (thunk) (thunk))
                                              (lambda () #f)) void))))

  (test-case "retained activation callbacks expire after provider return"
    (define saved #f)
    (define provider (provider-for (lambda (thunk) (set! saved thunk) (thunk))))
    (check-equal? (p:provider-call provider (lambda () 17)) 17)
    (check-exn exn:fail? saved))

  (test-case "provider activation cannot replace callback values or suppress failure"
    (define provider (provider-for (lambda (thunk) (thunk) 'discarded)))
    (check-equal? (call-with-values (lambda () (p:provider-call provider
                                   (lambda () (values 1 2)))) list) '(1 2))
    (define suppressor
      (provider-for (lambda (thunk) (with-handlers ([(lambda (_) #t) void]) (thunk)))))
    (check-exn (lambda (e) (eq? e 'sentinel))
      (lambda () (p:provider-call suppressor (lambda () (raise 'sentinel))))))

  (test-case "provider callbacks cannot migrate to a different Racket thread"
    (define provider
      (provider-for (lambda (thunk) (other-thread-result thunk) (void))))
    (check-exn exn:fail? (lambda () (p:provider-call provider void))))

  (test-case "provider diagnostics are detached and reject unsupported values"
    (define text (string-copy "host"))
    (define frozen (p:freeze-gpu-details (hasheq 'name text 'nested (hasheq 'value '(1 #f)))))
    (string-set! text 0 #\X)
    (check-equal? (hash-ref frozen 'name) "host")
    (check-true (immutable? (hash-ref frozen 'name)))
    (for ([value (in-list (list (hasheq 'bad 'symbol) (hash "bad" 1)
                               (hasheq 'bad #(1)) (hasheq 'bad +inf.0)))])
      (check-exn exn:fail? (lambda () (p:freeze-gpu-details value)))))

  (test-case "invalid public context choices fail without a native constructor"
    (check-exn exn:fail? (lambda () (make-gpu-context)))
    (check-exn exn:fail? (lambda () (make-gpu-context #:backend 'opengl)))
    (check-exn exn:fail:contract? (lambda () (make-gpu-context #:backend 'vulkan)))
    (check-exn exn:fail:contract?
      (lambda () (make-gpu-context #:backend 'metal #:options 'invalid)))
    (check-exn exn:fail:contract?
      (lambda () (make-gpu-context #:backend 'metal #:gl-interface 'gles)))
    (check-exn exn:fail:contract?
      (lambda () (make-gpu-context #:backend 'metal #:adapter 'hardware)))
    (define external-metal
      (make-gpu-provider #:name 'test #:backend 'metal #:key (gensym)
                        #:call-as-current void #:current? void))
    (check-exn
      (lambda (e) (and (exn:fail:gpu:unavailable? e)
                       (eq? (exn:fail:gpu:unavailable-step e) 'metal-provider)))
      (lambda () (make-gpu-context external-metal))))

  (test-case "same-context nesting preserves values without reactivating the host"
    (with-fake
      (lambda (context domain events)
        (set-box! events '())
        (check-equal?
          (call-with-values
            (lambda () (call-with-gpu-context context
              (lambda () (call-with-gpu-context context (lambda () (values 3 4)))))) list)
          '(3 4))
        (check-equal? (reverse (unbox events)) '(activate reset))
        (check-equal? (gpu-context-state context) 'ready))))

  (test-case "foreign nesting and teardown inside an activation are rejected"
    (with-fake
      (lambda (first _domain _events)
        (with-fake
          (lambda (second _other _log)
            (call-with-gpu-context first
              (lambda ()
                (check-exn exn:fail? (lambda () (call-with-gpu-context second void)))
                (check-exn exn:fail? (lambda () (gpu-context-close! second)))
                (check-exn exn:fail? (lambda () (gpu-context-abandon! first))))))))))

  (test-case "activation failure retires a lease and permits a fresh activation"
    (with-fake
      (lambda (context domain _events)
        (define lease #f)
        (check-exn exn:fail?
          (lambda () (call-with-gpu-context context
            (lambda () (set! lease (d:domain-capture-lease domain))
                       (error 'callback "failure")))))
        (check-true (d:domain-lease-expired? lease))
        (call-with-gpu-context context
          (lambda () (check-exn exn:fail? (lambda () (d:domain-check-lease! 'test lease)))))
        (check-equal? (gpu-context-state context) 'ready))))

  (test-case "metadata queries distinguish stored identity from owner-only reports"
    (with-fake
      (lambda (context _domain _events)
        (check-equal? (other-thread-result (lambda () (gpu-context-state context)))
                      '(returned ready))
        (check-equal? (other-thread-result (lambda () (gpu-context-generation context)))
                      (list 'returned (gpu-context-generation context)))
        (check-equal? (car (other-thread-result (lambda () (gpu-context-info context)))) 'raised)
        (check-equal? (car (other-thread-result
                           (lambda () (call-with-gpu-context context void)))) 'raised)
        (gpu-context-close! context)
        (check-true (gpu-context? context))
        (check-equal? (hash-ref (gpu-context-info context) 'state) "closed"))))

  (test-case "cross-thread shutdown request is a flag and prevents further entry"
    (with-fake
      (lambda (context _domain events)
        (define before (unbox events))
        (check-equal? (car (other-thread-result
                           (lambda () (gpu-context-request-shutdown! context)))) 'returned)
        (check-equal? (unbox events) before)
        (check-equal? (gpu-context-state context) 'ready)
        (check-true (hash-ref (gpu-context-info context) 'shutdown_requested))
        (check-exn exn:fail? (lambda () (call-with-gpu-context context void))))))

  (test-case "live children block close and queued releases are counted separately"
    (with-fake
      (lambda (context domain events)
        (define child
          (call-with-gpu-context context
            (lambda () (d:domain-new-resource domain 'fake (lambda () 'fake-child)
                         (lambda (_) (set-box! events (cons 'child-release (unbox events))))))))
        (check-exn exn:fail? (lambda () (gpu-context-close! context)))
        (d:domain-resource-close! child)
        (check-equal? (hash-ref (gpu-context-info context) 'live_children) 0)
        (check-equal? (hash-ref (gpu-context-info context) 'pending_releases) 1)
        (check-exn exn:fail? (lambda () (gpu-drain-releases! context)))
        (call-with-gpu-context context
          (lambda () (check-equal? (gpu-drain-releases! context) 0)))
        (check-equal? (count (lambda (e) (eq? e 'child-release)) (unbox events)) 1))))

  (test-case "abandonment does not activate the host or retire live children"
    (with-fake
      (lambda (context domain events)
        (define child (call-with-gpu-context context
                        (lambda () (d:domain-new-resource domain 'fake
                                     (lambda () 'fake-child) void))))
        (set-box! events '())
        (gpu-context-abandon! context)
        (check-equal? (unbox events) '(abandon))
        (check-exn exn:fail? (lambda () (gpu-context-close! context)))
        (d:domain-resource-close! child)
        (check-equal? (gpu-drain-releases! context) 1)
        (gpu-context-close! context)
        (check-false (and (memq 'activate (unbox events)) #t)))))

  (test-case "pending shutdown reports failures instead of claiming every context closed"
    (with-fake
      (lambda (context domain _events)
        (define child (call-with-gpu-context context
                        (lambda () (d:domain-new-resource domain 'fake
                                     (lambda () 'fake-child) void))))
        (gpu-context-request-shutdown! context)
        (define report (gpu-drain-pending-contexts!))
        (define mine (findf (lambda (row) (= (hash-ref row 'generation)
                                            (gpu-context-generation context))) report))
        (check-true (hash-has-key? mine 'shutdown_error))
        (check-equal? (gpu-context-state context) 'ready)
        (d:domain-resource-close! child)
        (gpu-drain-pending-contexts!)
        (check-equal? (gpu-context-state context) 'closed))))

  (test-case "healthy release activates its provider and keeps context ownership until close"
    (with-fake
      (lambda (context _domain events)
        (define abandoned? #f)
        (parameterize ([control:current-context-control-dispatch
                         (lambda (operation . _)
                           (case operation
                             [(release-and-abandon) (set! abandoned? #t)]
                             [(abandoned?) abandoned?]
                             [else (error 'fake-dispatch "unexpected operation")]))])
          (gpu-context-release-and-abandon! context))
        (check-equal? (gpu-context-state context) 'abandoned)
        (check-false (and (memq 'release (unbox events)) #t))
        (gpu-context-close! context)
        (check-equal? (gpu-context-state context) 'closed))))

  (test-case "failed healthy release is quarantined rather than retried"
    (with-fake
      (lambda (context _domain _events)
        (define calls 0)
        (parameterize ([control:current-context-control-dispatch
                         (lambda (operation . _)
                           (case operation
                             [(release-and-abandon) (set! calls (add1 calls))]
                             [(abandoned?) #f]))])
          (check-exn exn:fail? (lambda () (gpu-context-release-and-abandon! context))))
        (check-equal? (gpu-context-state context) 'release-failed)
        (check-true (hash-ref (gpu-context-info context) 'shutdown_requested))
        (check-exn exn:fail? (lambda () (gpu-context-release-and-abandon! context)))
        (check-exn exn:fail? (lambda () (gpu-context-abandon! context)))
        (check-exn exn:fail? (lambda () (gpu-context-close! context)))
        (check-equal? calls 1)))))
