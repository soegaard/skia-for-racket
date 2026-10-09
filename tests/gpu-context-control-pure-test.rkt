#lang racket/base
(require rackunit rackunit/text-ui racket/list
         "../gpu-context-options.rkt" (submod "../gpu-context-options.rkt" internals)
         "../private/gpu-domain.rkt" "../private/gpu-provider.rkt" "../private/gpu-context.rkt")
(provide gpu-context-control-pure-tests gpu-context-control-pure-test-count)
;; Native-free doubles exercise the actual domain state machine.
(define (mock-domain proc)
  (define log (box '()))
  (define current? (box #f))
  (define (note x) (set-box! log (append (unbox log) (list x))))
  (define p (make-gpu-provider #:name 'control-test #:backend 'opengl #:key (gensym)
              #:current? (lambda () (unbox current?))
              #:call-as-current
              (lambda (thunk)
                (dynamic-wind (lambda () (set-box! current? #t) (note 'activate))
                  thunk (lambda () (set-box! current? #f) (note 'deactivate))))))
  (define d (make-gpu-domain p
              (gpu-driver (lambda () 'native-context)
                          (lambda (_) (note 'unref)) (lambda (_) (note 'loss-abandon))
                          (lambda (_) (note 'reset)) (lambda (_) (hasheq 'double #t)))))
  (set-box! log '())
  (dynamic-wind void (lambda () (proc d log current? note))
    (lambda () (unless (memq (domain-state d) '(closed release-failed)) (domain-close! d)))))
(define gpu-context-control-pure-test-count 22)
(define gpu-context-control-pure-tests
  (test-suite "GPU context options and pure lifecycle"
    (test-case "six defaults"
      (check-equal? (gpu-context-options->jsexpr (make-gpu-context-options))
        (hasheq 'avoid_stencil_buffers #f 'runtime_program_cache_size 256
                'glyph_cache_texture_maximum_bytes 8388608 'allow_path_mask_caching #t
                'manual_mipmapping #f 'buffer_map_threshold -1)))
    (test-case "explicit fields"
      (define o (make-gpu-context-options #:avoid-stencil-buffers? #t #:runtime-program-cache-size 17
                  #:glyph-cache-texture-maximum-bytes 1048576 #:allow-path-mask-caching? #f
                  #:manual-mipmapping? #t #:buffer-map-threshold 4096))
      (check-equal? (gpu-context-options->jsexpr o)
        (hasheq 'avoid_stencil_buffers #t 'runtime_program_cache_size 17
                'glyph_cache_texture_maximum_bytes 1048576 'allow_path_mask_caching #f
                'manual_mipmapping #t 'buffer_map_threshold 4096)))
    (test-case "immutable value"
      (check-equal? (make-gpu-context-options) (make-gpu-context-options))
      (check-true (immutable? (gpu-context-options->jsexpr (make-gpu-context-options)))))
    (test-case "predicates"
      (check-true (gpu-context-options? (make-gpu-context-options)))
      (for ([v (in-list (list #f 0 'options (hasheq)))]) (check-false (gpu-context-options? v))))
    (test-case "boolean flags are not truthy values"
      (for ([v (in-list (list 0 1 'yes))])
        (check-exn exn:fail:contract? (lambda () (make-gpu-context-options #:avoid-stencil-buffers? v)))
        (check-exn exn:fail:contract? (lambda () (make-gpu-context-options #:allow-path-mask-caching? v)))
        (check-exn exn:fail:contract? (lambda () (make-gpu-context-options #:manual-mipmapping? v)))))
    (test-case "program cache bounds"
      (for ([v (in-list (list 0 -1 1.0 1/2 #t +nan.0 +inf.0 #x80000000))])
        (check-exn exn:fail:contract? (lambda () (make-gpu-context-options #:runtime-program-cache-size v)))))
    (test-case "glyph budget bounds"
      (for ([v (in-list (list 0 -1 1.0 #t +inf.0 #x10000000000000000))])
        (check-exn exn:fail:contract? (lambda () (make-gpu-context-options #:glyph-cache-texture-maximum-bytes v)))))
    (test-case "buffer mapping sentinel"
      (for ([v (in-list (list -2 0.0 #t +inf.0 #x80000000))])
        (check-exn exn:fail:contract? (lambda () (make-gpu-context-options #:buffer-map-threshold v))))
      (check-equal? (gpu-context-options-buffer-map-threshold (make-gpu-context-options #:buffer-map-threshold 0)) 0))
    (test-case "maximum exact integers"
      (define o (make-gpu-context-options #:runtime-program-cache-size #x7fffffff
                  #:glyph-cache-texture-maximum-bytes #xffffffffffffffff #:buffer-map-threshold #x7fffffff))
      (check-equal? (gpu-context-options-glyph-cache-texture-maximum-bytes o) #xffffffffffffffff))
    (test-case "optional options validation"
      (check-false (check-optional-context-options 'test #f))
      (check-exn exn:fail:contract? (lambda () (check-optional-context-options 'test 'wrong)))
      (check-exn exn:fail:contract? (lambda () (gpu-context-options->jsexpr #f))))
    (test-case "factory metadata is a requested value"
      (for ([backend '(opengl metal direct3d)]
            [factory '("gr_direct_context_make_gl" "gr_direct_context_make_metal" "gr_direct_context_make_direct3d")])
        (define d (context-options-diagnostics #f backend))
        (define e (context-options-diagnostics (make-gpu-context-options) backend))
        (check-equal? (hash-ref d 'context_factory) factory)
        (check-equal? (hash-ref e 'context_factory) (string-append factory "_with_options"))
        (check-true (immutable? (hash-ref e 'context_factory)))
        (check-false (hash-ref d 'context_options))
        (check-false (hash-ref e 'context_options_native_readback))))
    (test-case "unrelated metadata is preserved"
      (check-equal? (hash-ref (add-context-options-diagnostics (hasheq 'user_edit 17) #f 'metal) 'user_edit) 17)
      (check-exn exn:fail:contract? (lambda () (context-options-diagnostics #f 'vulkan))))
    (test-case "healthy release activates the provider"
      (mock-domain (lambda (d log current? note)
        (domain-release-and-abandon! d (lambda (_) (check-true (unbox current?)) (note 'native-release)))
        (check-equal? (unbox log) '(activate reset native-release deactivate))
        (check-eq? (domain-state d) 'abandoned))))
    (test-case "loss abandonment never activates the provider"
      (mock-domain (lambda (d log current? note)
        (domain-abandon! d) (check-equal? (unbox log) '(loss-abandon)))))
    (test-case "context unref remains a separate operation"
      (mock-domain (lambda (d log current? note)
        (domain-release-and-abandon! d void)
        (check-false (member 'unref (unbox log)))
        (domain-close! d) (check-eq? (domain-state d) 'closed)
        (check-equal? (count (lambda (x) (eq? x 'unref)) (unbox log)) 1))))
    (test-case "pending child releases precede native abandon"
      (mock-domain (lambda (d log current? note)
        (define h (domain-call d (lambda ()
          (domain-new-resource d 'image (lambda () 'image) (lambda (_) (note 'child-unref))))))
        (domain-resource-close! h) (set-box! log '())
        (domain-release-and-abandon! d (lambda (_) (note 'native-release)))
        (check-equal? (unbox log) '(activate reset child-unref native-release deactivate)))))
    (test-case "live children become unusable but remain owned"
      (mock-domain (lambda (d log current? note)
        (define h (domain-call d (lambda () (domain-new-resource d 'image (lambda () 'image) void))))
        (domain-release-and-abandon! d void)
        (check-false (domain-resource-closed? h))
        (check-exn exn:fail? (lambda () (resource-pointer h)))
        (check-exn exn:fail? (lambda () (domain-close! d)))
        (domain-resource-close! h) (domain-close! d))))
    (test-case "scope and owner rejection"
      (mock-domain (lambda (d log current? note)
        (domain-call d (lambda () (check-exn exn:fail? (lambda () (domain-release-and-abandon! d void)))))
        (define ch (make-channel))
        (thread (lambda () (with-handlers ([exn:fail? (lambda (e) (channel-put ch #t))])
          (domain-release-and-abandon! d void) (channel-put ch #f))))
        (check-true (channel-get ch)))))
    (test-case "closed repeated and requested shutdown are rejected"
      (mock-domain (lambda (d log current? note)
        (domain-release-and-abandon! d void)
        (check-exn exn:fail? (lambda () (domain-release-and-abandon! d void)))
        (domain-close! d)
        (check-exn exn:fail? (lambda () (domain-release-and-abandon! d void)))))
      (mock-domain (lambda (d log current? note)
        (domain-request-shutdown! d)
        (check-exn exn:fail? (lambda () (domain-release-and-abandon! d void)))
        (domain-abandon! d))))
    (test-case "indeterminate exception cannot be retried"
      (mock-domain (lambda (d log current? note)
        (check-exn #rx"native failure" (lambda () (domain-release-and-abandon! d (lambda (_) (error 'mock "native failure")))))
        (check-eq? (domain-state d) 'release-failed)
        (check-exn exn:fail? (lambda () (domain-abandon! d)))
        (check-exn exn:fail? (lambda () (domain-close! d)))
        (check-false (unbox current?)))))
    (test-case "raised false also quarantines"
      (mock-domain (lambda (d log current? note)
        (check-exn (lambda (e) (eq? e #f)) (lambda () (domain-release-and-abandon! d (lambda (_) (raise #f)))))
        (check-eq? (domain-state d) 'release-failed))))
    (test-case "native callback arity and reentry are guarded"
      (mock-domain (lambda (d log current? note)
        (check-exn exn:fail:contract? (lambda () (domain-release-and-abandon! d (lambda () (void)))))
        (check-equal? (unbox log) '())
        (domain-release-and-abandon! d (lambda (_)
          (check-exn exn:fail? (lambda () (domain-pointer d)))
          (check-exn exn:fail? (lambda () (domain-close! d))))))))))
(module+ main
  (define failures (run-tests gpu-context-control-pure-tests))
  (printf "gpu-context-control-pure: ~a cases, ~a failures\n" gpu-context-control-pure-test-count failures)
  (exit (if (zero? failures) 0 1)))
