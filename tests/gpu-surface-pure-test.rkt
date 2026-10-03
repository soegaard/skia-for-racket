#lang racket/base
(require rackunit racket/list
         "gpu-fixtures.rkt"
         "../private/gpu-domain.rkt" "../private/gpu-context.rkt"
         "../private/gpu-surface-util.rkt" "../private/lifetime.rkt"
         "../private/core.rkt" (submod "../private/core.rkt" gpu-surface-internals))
(provide gpu-surface-pure-tests)
(define (options #:w [w 8] #:h [h 8] #:samples [samples 0]
                 #:opaque? [opaque? #f] #:budgeted? [budgeted? #t] #:alpha [alpha 0])
  (gpu-surface-options 'test w h samples opaque? budgeted? alpha))
(define (fake-surface d log abandoned?)
  (make-gpu-surface-record (mock-resource d log abandoned? 'surface) 8 8 '()
                          'mock-context d #f (options)))
(define gpu-surface-pure-tests
  (test-suite
   "GPU surfaces: pure options, generic handles, and activation leases"
   (test-case "dimensions validated before native allocation"
     (for ([v '(0 -1 1.0 32769)])
       (check-exn exn:fail? (lambda () (options #:w v)))))
   (test-case "height validated before native allocation"
     (for ([v '(0 -2 2.0 32769)])
       (check-exn exn:fail? (lambda () (options #:h v)))))
   (test-case "pixel allocation bound is still enforced"
     (parameterize ([current-skia-byte-limit 16])
       (check-exn exn:fail? options)))
   (test-case "sample request has an integer bound"
     (for ([v '(-1 1.0 65 #f)])
       (check-exn exn:fail? (lambda () (options #:samples v)))))
   (test-case "single sample and native rounding are not invented"
     (check-false (hash-ref (options #:samples 3) 'actual_sample_count))
     (check-equal? (hash-ref (options #:samples 3) 'requested_sample_count) 3))
   (test-case "opaque creation rejects translucent clear"
     (check-exn exn:fail? (lambda () (options #:opaque? #t #:alpha 128))))
   (test-case "opaque creation accepts opaque clear"
     (check-equal? (hash-ref (options #:opaque? #t #:alpha 255) 'alpha_type) "opaque"))
   (test-case "boolean options do not coerce truthy values"
     (check-exn exn:fail? (lambda () (options #:opaque? 'yes)))
     (check-exn exn:fail? (lambda () (options #:budgeted? 1))))
   (test-case "option metadata is immutable and explicit"
     (define v (options))
     (check-true (immutable? v))
     (check-equal? (hash-ref v 'origin) "top-left")
     (check-equal? (hash-ref v 'storage) "gpu"))
   (test-case "readback dimensions must match exactly"
     (check-not-exn (lambda () (gpu-transfer-shape! 'test 8 9 8 9)))
     (check-exn exn:fail? (lambda () (gpu-transfer-shape! 'test 8 9 9 8))))
   (test-case "RGBA8 framebuffer format from actual encoding"
     (check-equal? (gpu-presentation-format 8 8 8 8 #x2601 #x8C17) #x8058)
     (check-equal? (gpu-presentation-format 8 8 8 8 #x8C40 #x8C17) #x8C43)
     (check-false (gpu-presentation-srgb? #x2601))
     (check-true (gpu-presentation-srgb? #x8C40)))
   (test-case "RGB8 framebuffer has an opaque format"
     (check-equal? (gpu-presentation-format 8 8 8 0 #x2601 #x8C17) #x8051)
     ;; Pinned Skia's GLWindowContext describes framebuffer 0 as RGBA8.
     (check-equal? (gpu-window-wrap-format 0 #x8051) #x8058)
     (check-equal? (gpu-window-wrap-format 7 #x8051) #x8051))
   (test-case "HDR and unsupported host layouts reject"
     (check-exn exn:fail? (lambda () (gpu-presentation-format 10 10 10 2 #x2601 #x8C17)))
     (check-exn exn:fail? (lambda () (gpu-presentation-format 8 8 8 8 #x2601 #x1406))))
   (test-case "unknown host encoding rejects"
     (check-exn exn:fail? (lambda () (gpu-presentation-format 8 8 8 8 0 #x8C17)))
     (check-exn exn:fail? (lambda () (gpu-presentation-srgb? 0))))
   (test-case "lease requires an active scope"
     (call-with-mock
      (lambda (d p driver log a)
        (check-exn exn:fail? (lambda () (domain-capture-lease d))))))
   (test-case "lease is live only in its activation"
     (call-with-mock
      (lambda (d p driver log a)
        (define lease #f)
        (domain-call d (lambda () (set! lease (domain-capture-lease d))
                        (check-false (domain-lease-expired? lease))
                        (domain-check-lease! 'test lease)))
        (check-true (domain-lease-expired? lease)))))
   (test-case "reentering the same context cannot resurrect a lease"
     (call-with-mock
      (lambda (d p driver log a)
        (define lease (domain-call d (lambda () (domain-capture-lease d))))
        (domain-call d (lambda () (check-exn exn:fail? (lambda () (domain-check-lease! 'test lease))))))))
   (test-case "nested activation retires only the inner lease"
     (call-with-mock
      (lambda (d p driver log a)
        (domain-call d
          (lambda ()
            (define outer (domain-capture-lease d))
            (define inner (domain-call d (lambda () (domain-check-lease! 'test outer)
                                          (domain-capture-lease d))))
            (check-true (domain-lease-expired? inner))
            (check-false (domain-lease-expired? outer))
            (domain-check-lease! 'test outer))))))
   (test-case "exception retires the canvas lease"
     (call-with-mock
      (lambda (d p driver log a)
        (define lease #f)
        (check-exn exn:fail? (lambda () (domain-call d (lambda () (set! lease (domain-capture-lease d))
                                                                 (error 'test "escape")))))
        (check-true (domain-lease-expired? lease)))))
   (test-case "continuation escape retires the lease"
     (call-with-mock
      (lambda (d p driver log a)
        (define lease #f)
        (let/ec out
          (domain-call d (lambda () (set! lease (domain-capture-lease d)) (out 'escaped))))
        (check-true (domain-lease-expired? lease)))))
   (test-case "worker thread cannot use a live lease"
     (call-with-mock
      (lambda (d p driver log a)
        (domain-call d
          (lambda ()
            (define lease (domain-capture-lease d))
            (check-true (exn:fail? (in-worker (lambda () (domain-check-lease! 'test lease))))))))))
   (test-case "changed native identity rejects a live lease"
     (call-with-mock
      (lambda (d p driver log a)
        (domain-call d
          (lambda ()
            (define lease (domain-capture-lease d))
            (parameterize ([current-mock 'other])
              (check-exn exn:fail? (lambda () (domain-check-lease! 'test lease)))))))))
   (test-case "generic lifetime access checks the GPU domain"
     (call-with-mock
      (lambda (d p driver log a)
        (define h (domain-call d (lambda () (mock-resource d log a))))
        (check-exn exn:fail? (lambda () (call-with-owned 'test (list h) values)))
        (domain-call d (lambda () (check-not-false (call-with-owned 'test (list h) values))))
        (owned-close! 'test h))))
   (test-case "generic close queues rather than calling GPU destruction"
     (call-with-mock
      (lambda (d p driver log a)
        (define h (domain-call d (lambda () (mock-resource d log a))))
        (define before (events log))
        (owned-close! 'test h)
        (check-equal? (events log) before)
        (check-true (owned-closed? h))
        (check-equal? (domain-pending-count d) 1))))
   (test-case "surface uses the existing resource and surface predicates"
     (call-with-mock
      (lambda (d p driver log a)
        (define s (domain-call d (lambda () (fake-surface d log a))))
        (check-true (surface? s)) (check-true (gpu-surface? s)) (check-true (skia-resource? s))
        (check-eq? (surface-backend s) 'opengl)
        (check-equal? (list (surface-width s) (surface-height s)) '(8 8))
        (skia-close! s))))
   (test-case "surface canvas is ordinary and expires with activation"
     (call-with-mock
      (lambda (d p driver log a)
        (define s (domain-call d (lambda () (fake-surface d log a))))
        (define c (domain-call d (lambda () (surface-canvas s))))
        (check-true (canvas? c)) (check-true (skia-closed? c))
        (domain-call d (lambda () (check-exn exn:fail? (lambda () (canvas-owner 'test c)))))
        (skia-close! s))))
   (test-case "GPU surface requires a scope even to borrow a canvas"
     (call-with-mock
      (lambda (d p driver log a)
        (define s (domain-call d (lambda () (fake-surface d log a))))
        (check-exn exn:fail? (lambda () (surface-canvas s)))
        (skia-close! s))))
   (test-case "with-skia closes a GPU handle without native context activation"
     (call-with-mock
      (lambda (d p driver log a)
        (define s (domain-call d (lambda () (fake-surface d log a))))
        (with-skia ([target s]) (check-false (skia-closed? target)))
        (check-true (skia-closed? s)) (check-equal? (domain-pending-count d) 1))))
   (test-case "GPU child blocks normal context teardown"
     (call-with-mock
      (lambda (d p driver log a)
        (define s (domain-call d (lambda () (fake-surface d log a))))
        (check-exn exn:fail? (lambda () (domain-close! d)))
        (skia-close! s))))
   (test-case "CPU transfer entry points reject before any foreign call"
     (call-with-mock
      (lambda (d p driver log a)
        (define s (domain-call d (lambda () (fake-surface d log a))))
        (for ([op (list surface-snapshot surface->rgba-bytes (lambda (v) (surface-pixel v 0 0)))])
          (check-exn #rx"GPU transfers are explicit" (lambda () (op s))))
        (skia-close! s))))
   (test-case "closed surface cannot create a new lease"
     (call-with-mock
      (lambda (d p driver log a)
        (define s (domain-call d (lambda () (fake-surface d log a))))
        (skia-close! s)
        (domain-call d (lambda () (check-exn exn:fail? (lambda () (surface-canvas s))))))))
   (test-case "surface explicit close is idempotent"
     (call-with-mock
      (lambda (d p driver log a)
        (define s (domain-call d (lambda () (fake-surface d log a))))
        (skia-close! s) (skia-close! s)
        (domain-call d void)
        (check-equal? (event-count log 'surface) 1))))
   (test-case "scope retirement does not close a reusable surface"
     (call-with-mock
      (lambda (d p driver log a)
        (define s (domain-call d (lambda () (fake-surface d log a))))
        (domain-call d (lambda () (surface-canvas s)))
        (check-false (skia-closed? s))
        (domain-call d (lambda () (check-true (canvas? (surface-canvas s)))))
        (skia-close! s))))
   (test-case "generic GPU resource close rejects another thread"
     (call-with-mock
      (lambda (d p driver log a)
        (define s (domain-call d (lambda () (fake-surface d log a))))
        (check-true (exn:fail? (in-worker (lambda () (skia-close! s)))))
        (check-false (skia-closed? s)) (skia-close! s))))
   (test-case "source surface cannot be borrowed in a foreign active domain"
     (call-with-mock
      (lambda (d p driver log a)
        (define s (domain-call d (lambda () (fake-surface d log a))))
        (call-with-mock
         (lambda (other q driver2 log2 b)
           (domain-call other (lambda () (check-exn exn:fail? (lambda () (surface-canvas s)))))))
        (skia-close! s))))))
