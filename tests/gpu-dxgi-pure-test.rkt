#lang racket/base
(require rackunit
         "../private/gpu-dxgi-util.rkt" "../private/gpu-dxgi-types.rkt"
         "../private/gpu-presenter.rkt"
         (submod "../private/gpu-presenter.rkt" adapter-internals))
(provide gpu-dxgi-pure-tests)
(define (fixture proc [render void])
  (define outcome (box 'occluded))
  (define metrics (box (presentation-metrics 120 80 60 40)))
  (define acquired (box 0)) (define retired (box 0)) (define posted (box '()))
  (define p
    (make-presenter
      (presentation-adapter 'direct3d 'synthetic-context
        (lambda () (unbox metrics))
        (lambda (_m receive)
          (set-box! acquired (add1 (unbox acquired)))
          (dynamic-wind void
            (lambda () (receive 'synthetic-canvas
                                 (hasheq 'backend "direct3d" 'target_identity "synthetic-dxgi")
                                 (lambda () (unbox outcome))))
            (lambda () (set-box! retired (add1 (unbox retired))))))
        (lambda (thunk) (set-box! posted (append (unbox posted) (list thunk))))
        void (lambda () (hasheq 'synthetic #t)))
      render raise))
  (dynamic-wind void (lambda () (proc p outcome metrics acquired retired posted))
    (lambda () (gpu-presenter-close! p))))
(define gpu-dxgi-pure-tests
  (test-suite
   "DXGI policy and shared presenter semantics; no Windows/Skia calls"
   (test-case "immediate interval is explicit" (check-equal? (dxgi-sync-interval! 0) 0))
   (test-case "vsync interval is explicit" (check-equal? (dxgi-sync-interval! 1) 1))
   (test-case "other intervals are rejected"
     (for ([x '(#f #t -1 2 1.0 immediate)])
       (check-exn exn:fail? (lambda () (dxgi-sync-interval! x)))))
   (test-case "minimum drawable size" (check-not-exn (lambda () (dxgi-extent! 1 1))))
   (test-case "bounded maximum size" (check-not-exn (lambda () (dxgi-extent! 16384 16384))))
   (test-case "zero is a skip, not a swap-chain extent"
     (check-exn exn:fail? (lambda () (dxgi-extent! 0 1))))
   (test-case "invalid drawable extents reject before FFI"
     (for ([x (list -1 16385 #f 1.5 +inf.0 +nan.0)])
       (check-exn exn:fail? (lambda () (dxgi-extent! x 1)))
       (check-exn exn:fail? (lambda () (dxgi-extent! 1 x)))))
   (test-case "readback pitch alignment"
     (check-equal? (map dxgi-row-pitch '(1 63 64 65 320 321)) '(256 256 256 512 1280 1536)))
   (test-case "S_OK is submitted" (check-eq? (dxgi-present-result 0) 'submitted))
   (test-case "occlusion is distinct from submitted"
     (check-eq? (dxgi-present-result #x087a0001) 'occluded))
   (test-case "HRESULT failures do not become skips"
     (check-exn exn:fail? (lambda () (dxgi-present-result (- #x887a0005 #x100000000)))))
   (test-case "unknown positive statuses fail closed"
     (check-exn exn:fail? (lambda () (dxgi-present-result 1))))
   (test-case "HRESULT is not a Boolean or oversized integer"
     (for ([x '(#f #t 0.0 4294967295)])
       (check-exn exn:fail? (lambda () (dxgi-present-result x)))))
   (test-case "completed fence admits reuse" (check-true (dxgi-fence-completed! 5 5)))
   (test-case "incomplete fence requires a wait" (check-false (dxgi-fence-completed! 4 5)))
   (test-case "later completion also admits reuse" (check-true (dxgi-fence-completed! 6 5)))
   (test-case "device removed sentinel is not completion"
     (check-exn exn:fail? (lambda () (dxgi-fence-completed! #xffffffffffffffff 5))))
   (test-case "fence values reject invalid representations"
     (for ([x '(#t #f -1 1.0)])
       (check-exn exn:fail? (lambda () (dxgi-fence-completed! x 0))))
     (check-exn exn:fail? (lambda () (dxgi-fence-completed! 1 -1))))
   (test-case "fences advance monotonically" (check-equal? (dxgi-next-fence 12) 13))
   (test-case "fence overflow is rejected"
     (check-exn exn:fail? (lambda () (dxgi-next-fence #xfffffffffffffffe))))
   (test-case "two back-buffer indices only"
     (check-equal? (dxgi-buffer-index! 0) 0) (check-equal? (dxgi-buffer-index! 1) 1))
   (test-case "foreign or malformed back-buffer indices reject"
     (for ([x '(#f #t -1 2 1.0)])
       (check-exn exn:fail? (lambda () (dxgi-buffer-index! x)))))
   (test-case "POD layouts match the reviewed 64-bit sizes"
     (check-not-exn check-dxgi-layouts!)
     (check-equal? (hash-ref (dxgi-layout-sizes) 'copy_location) 48))
   (test-case "retirement waits before releases"
     (define log '())
     (call-with-dxgi-retirement (lambda () (set! log (cons 'wait log)))
       (lambda () (set! log (cons 'release log))) (lambda (_) (error 'test "unexpected quarantine")))
     (check-equal? (reverse log) '(wait release)))
   (test-case "failed wait quarantines without releasing resources"
     (define released? #f) (define saved #f)
     (check-exn #rx"timeout"
       (lambda () (call-with-dxgi-retirement (lambda () (error 'test "timeout"))
                    (lambda () (set! released? #t)) (lambda (e) (set! saved e)))))
     (check-false released?) (check-true (exn:fail? saved)))
   (test-case "failed destruction is quarantined and not retried"
     (define attempts 0) (define quarantines 0)
     (check-exn exn:fail?
       (lambda () (call-with-dxgi-retirement void
                    (lambda () (set! attempts (add1 attempts)) (error 'test "release failed"))
                    (lambda (_) (set! quarantines (add1 quarantines))))))
     (check-equal? attempts 1) (check-equal? quarantines 1))
   (test-case "Direct3D is a shared presenter backend"
     (fixture (lambda (p o m a r q) (check-eq? (gpu-presenter-backend p) 'direct3d))))
   (test-case "occluded Present does not count as successful submission"
     (fixture (lambda (p o m a r q)
       (check-eq? (gpu-presenter-render! p) 'skipped)
       (check-equal? (hash-ref (gpu-presenter-info p) 'presents_requested) 0)
       (check-equal? (hash-ref (gpu-presenter-info p) 'frames_skipped) 1))))
   (test-case "occlusion still retires the acquired target"
     (fixture (lambda (p o m a r q)
       (gpu-presenter-render! p) (check-equal? (unbox a) 1) (check-equal? (unbox r) 1))))
   (test-case "occlusion does not schedule a busy redraw loop"
     (fixture (lambda (p o m a r q)
       (gpu-presenter-render! p) (check-equal? (unbox q) '())
       (check-eq? (gpu-presenter-state p) 'ready))))
   (test-case "presentation resumes after occlusion"
     (fixture (lambda (p o m a r q)
       (gpu-presenter-render! p) (set-box! o (void))
       (check-eq? (gpu-presenter-render! p) 'present-requested)
       (check-equal? (hash-ref (gpu-presenter-info p) 'presents_requested) 1))))
   (test-case "occluded frame expires"
     (define frame #f)
     (fixture (lambda (p o m a r q)
       (gpu-presenter-render! p)
       (check-true (gpu-frame-expired? frame))
       (check-exn #rx"expired" (lambda () (gpu-frame-canvas frame))))
       (lambda (f) (set! frame f))))
   (test-case "hidden geometry avoids native acquisition altogether"
     (fixture (lambda (p o m a r q)
       (set-box! m (presentation-metrics 120 80 60 40 #:visible? #f))
       (check-eq? (gpu-presenter-render! p) 'skipped)
       (check-equal? (unbox a) 0) (check-equal? (unbox r) 0))))
   (test-case "occlusion never claims physical display verification"
     (fixture (lambda (p o m a r q)
       (gpu-presenter-render! p)
       (check-false (hash-ref (gpu-presenter-info p) 'visible_pixels_verified))))))
)
