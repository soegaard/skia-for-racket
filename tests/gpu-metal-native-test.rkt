#lang racket/base
(require rackunit ffi/unsafe/atomic
         "../main.rkt" "../gpu.rkt" "gpu-fixtures.rkt")
(provide make-gpu-metal-native-tests gpu-metal-native-test-count)
(define gpu-metal-native-test-count 8)
(define (with-metal proc)
  (define context (make-gpu-context #:backend 'metal))
  (dynamic-wind void (lambda () (proc context)) (lambda () (gpu-context-close! context))))
(define (under context thunk) (call-with-gpu-context context thunk))
(define (make-gpu-metal-native-tests)
  (test-suite
   "Metal-specific owned queue, scope, GC, and abandonment"
   (test-case "owned Metal reports actual backend and no GL host"
     (with-metal
      (lambda (context)
        (define info (gpu-context-info context))
        (check-equal? (hash-ref info 'native_backend) 2)
        (check-eq? (gpu-context-backend context) 'metal)
        (check-true (hash-ref info 'owns_command_queue))
        (check-false (hash-ref info 'requires_gl_context))
        (check-false (hash-ref info 'presentation_tested)))))
   (test-case "native calls leave the application scope non-atomic and yieldable"
     (with-metal
      (lambda (context)
        (under context
          (lambda ()
            (check-false (in-atomic-mode?))
            (with-skia ([s (make-gpu-surface context 8 8)])
              (define c (surface-canvas s))
              (canvas-clear! c 'blue)
              (check-false (in-atomic-mode?))
              (sleep 0)
              (canvas-clear! c 'red)
              (check-equal? (subbytes (gpu-surface->rgba-bytes s) 0 4) (bytes 255 0 0 255))))))))
   (test-case "Metal context creation rejects nesting without corrupting the outer context"
     (with-metal
      (lambda (context)
        (under context
          (lambda () (check-exn exn:fail? (lambda () (make-gpu-context #:backend 'metal)))))
        (under context (lambda () (with-skia ([s (make-gpu-surface context 4 4)]) (void)))))))
   (test-case "nested Metal canvas expiration preserves its outer canvas"
     (with-metal
      (lambda (context)
        (under context
          (lambda ()
            (with-skia ([s (make-gpu-surface context 4 4)])
              (define c (surface-canvas s)) (define inner #f)
              (under context (lambda () (set! inner (surface-canvas s))))
              (check-exn exn:fail? (lambda () (canvas-clear! inner 'blue)))
              (canvas-clear! c 'green)))))))
   (test-case "Metal GPU image finalization queues before owner draining"
     (with-metal
      (lambda (context)
        (define weak
          (under context
            (lambda () (with-skia ([s (make-gpu-surface context 8 8)])
                         (make-weak-box (gpu-surface-snapshot s))))))
        (check-true (collect-until (lambda () (positive? (hash-ref (gpu-context-info context) 'pending_releases)))))
        (under context (lambda () (gpu-drain-releases! context)))
        (check-true (collect-until (lambda () (not (weak-box-value weak)))))
        (check-equal? (hash-ref (gpu-context-info context) 'live_children) 0)
        (check-equal? (hash-ref (gpu-context-info context) 'pending_releases) 0))))
   (test-case "Metal shutdown request rejects new work but allows queued destruction"
     (define context (make-gpu-context #:backend 'metal))
     (define image (under context (lambda () (with-skia ([s (make-gpu-surface context 8 8)]) (gpu-surface-snapshot s)))))
     (dynamic-wind void
       (lambda ()
         (gpu-context-request-shutdown! context)
         (check-exn exn:fail? (lambda () (under context void))))
       (lambda () (skia-close! image) (gpu-context-close! context)))
     (check-eq? (gpu-context-state context) 'closed))
   (test-case "Metal abandonment invalidates child use but preserves explicit cleanup"
     (define context (make-gpu-context #:backend 'metal))
     (define image (under context (lambda () (with-skia ([s (make-gpu-surface context 8 8)]) (gpu-surface-snapshot s)))))
     (dynamic-wind void
       (lambda ()
         (gpu-context-abandon! context)
         (check-eq? (gpu-context-state context) 'abandoned)
         ;; Abandon invalidates domain USE, but deliberately does not close or
         ;; free still-live child wrappers. They remain explicitly closeable so
         ;; their queued native unrefs can run during owner-side teardown.
         (check-false (skia-closed? image))
         (check-exn exn:fail? (lambda () (under context (lambda () (gpu-image->rgba-bytes image)))))
         (skia-close! image)
         (check-true (skia-closed? image))
         (check-equal? (hash-ref (gpu-context-info context) 'pending_releases) 1))
       (lambda () (skia-close! image) (gpu-context-close! context)))
     (check-equal? (hash-ref (gpu-context-info context) 'failed_releases) 0))
   (test-case "Metal context closure is idempotent and prevents later rendering"
     (define context (make-gpu-context #:backend 'metal))
     (gpu-context-close! context) (gpu-context-close! context)
     (check-exn exn:fail? (lambda () (under context void)))
     (check-equal? (hash-ref (gpu-context-info context) 'pending_releases) 0))))
