#lang racket/base

;; Real, explicitly selected backend acceptance. No skip-on-unavailability and
;; no CPU fallback. This suite checks lifecycle, not rendering or performance.
(require rackunit rackunit/text-ui json racket/cmdline racket/list
         skia skia/gpu)

;; `module+ main` imports bindings from this module, so command-line state
;; must live in mutable parameter values instead of module bindings set with
;; `set!`.
(define selected-backend (make-parameter #f))
(define selected-adapter (make-parameter 'hardware))
(define output-path (make-parameter #f))
(define contexts '())

(define (new-context [options #f])
  (define context
    (case (selected-backend)
      [(opengl)
       ;; The owned EGL route supplies an actual desktop OpenGL host.
       ((dynamic-require 'skia/gpu-egl 'make-egl-gpu-context) #:options options)]
      [(direct3d)
       (make-gpu-context #:backend 'direct3d #:adapter (selected-adapter) #:options options)]
      [(metal) (make-gpu-context #:backend 'metal #:options options)]
      [else (error 'reference-gpu-context "select a backend explicitly")]))
  (set! contexts (cons context contexts))
  context)

(define (with-context proc #:options [options #f])
  (define context (new-context options))
  (dynamic-wind void
    (lambda () (proc context))
    (lambda ()
      ;; Preserve teardown failures. Do not substitute abandonment for a failed close.
      (gpu-context-close! context))))

(define (make-child context)
  (call-with-gpu-context context (lambda () (make-gpu-surface context 2 2))))

(define suite
  (test-suite
   "Reference GPU context native acceptance"

   (test-case "construction uses the selected backend and reports native-default requests"
     (with-context
       (lambda (context)
         (check-true (gpu-context? context))
         (check-equal? (gpu-context-backend context) (selected-backend))
         (check-equal? (gpu-context-state context) 'ready)
         (define info (gpu-context-info context))
         (check-equal? (hash-ref info 'context_options_source) "native-defaults")
         (check-false (hash-ref info 'context_options_native_readback))
         (check-true (immutable? info))
         (check-false (hash-ref info 'shutdown_requested)))))

   (test-case "explicit options remain reported requests rather than native readback"
     (define options (make-gpu-context-options #:runtime-program-cache-size 64))
     (with-context
       (lambda (context)
         (define info (gpu-context-info context))
         (check-equal? (hash-ref info 'context_options_source) "explicit")
         (check-equal? (hash-ref info 'context_options) (gpu-context-options->jsexpr options))
         (check-false (hash-ref info 'context_options_native_readback)))
       #:options options))

   (test-case "same-context nesting preserves zero and multiple results"
     (with-context
       (lambda (context)
         (check-equal?
          (call-with-values
           (lambda () (call-with-gpu-context context
             (lambda () (call-with-gpu-context context (lambda () (values 1 2)))))) list)
          '(1 2))
         (check-equal? (call-with-values (lambda () (call-with-gpu-context context values)) list)
                       '()))))

   (test-case "different contexts cannot nest and generation identities differ"
     (with-context
       (lambda (first)
         (with-context
           (lambda (second)
             (check-not-equal? (gpu-context-generation first) (gpu-context-generation second))
             (call-with-gpu-context first
               (lambda ()
                 (check-exn exn:fail? (lambda () (call-with-gpu-context second void)))
                 (check-exn exn:fail? (lambda () (gpu-context-close! second))))))))))

   (test-case "borrowed canvases expire while their surface can be entered again"
     (with-context
       (lambda (context)
         (with-skia ([surface (make-child context)])
           (define saved
             (call-with-gpu-context context (lambda () (surface-canvas surface))))
           (call-with-gpu-context context
             (lambda ()
               (check-exn exn:fail? (lambda () (canvas-save-count saved)))
               (check-equal? (canvas-save-count (surface-canvas surface)) 1)))))))

   (test-case "live child rejection leaves the context available for orderly cleanup"
     (with-context
       (lambda (context)
         (with-skia ([surface (make-child context)])
           (check-exn exn:fail? (lambda () (gpu-context-close! context)))
           (check-equal? (gpu-context-state context) 'ready)
           (call-with-gpu-context context
             (lambda () (check-equal? (canvas-save-count (surface-canvas surface)) 1)))))))

   (test-case "callback failure leaves a fresh activation usable"
     (with-context
       (lambda (context)
         (check-exn exn:fail?
           (lambda () (call-with-gpu-context context (lambda () (error 'callback "failure")))))
         (check-equal? (call-with-gpu-context context (lambda () 19)) 19))))

   (test-case "shutdown request closes through the owner drain and preserves metadata"
     (with-context
       (lambda (context)
         (define worker (thread (lambda () (gpu-context-request-shutdown! context))))
         (thread-wait worker)
         (check-equal? (gpu-context-state context) 'ready)
         (check-true (hash-ref (gpu-context-info context) 'shutdown_requested))
         (check-exn exn:fail? (lambda () (call-with-gpu-context context void)))
         (define reports (gpu-drain-pending-contexts!))
         (define report (findf (lambda (row) (= (hash-ref row 'generation)
                                               (gpu-context-generation context))) reports))
         (check-pred hash? report)
         (check-false (hash-has-key? report 'shutdown_error))
         (check-equal? (hash-ref report 'state) "closed")
         (check-equal? (gpu-context-backend context) (selected-backend)))))

   (test-case "lost-host abandonment is distinct from child retirement and close"
     (with-context
       (lambda (context)
         (with-skia ([surface (make-child context)])
           (gpu-context-abandon! context)
           (check-equal? (gpu-context-state context) 'abandoned)
           (check-exn exn:fail? (lambda () (call-with-gpu-context context void)))
           (check-exn exn:fail? (lambda () (gpu-context-close! context)))))))

   (test-case "healthy release-and-abandon retains ownership until final close"
     (with-context
       (lambda (context)
         (with-skia ([surface (make-child context)])
           (gpu-context-release-and-abandon! context)
           (check-equal? (gpu-context-state context) 'abandoned)
           (check-exn exn:fail? (lambda () (gpu-context-close! context)))
           (check-exn exn:fail? (lambda () (call-with-gpu-context context void)))))))))

(module+ main
  (command-line
   #:program "reference-gpu-context-test"
   #:once-each
   [("--backend") name "Required: opengl, metal, or direct3d. OpenGL uses owned EGL."
    (selected-backend (string->symbol name))]
   [("--adapter") name "Direct3D only: hardware or warp."
    (selected-adapter (string->symbol name))]
   [("--output") path "Write a JSON execution receipt."
    (output-path path)])
  (unless (memq (selected-backend) '(opengl metal direct3d))
    (error 'reference-gpu-context "--backend must select opengl, metal, or direct3d"))
  (unless (and (memq (selected-adapter) '(hardware warp))
               (or (eq? (selected-backend) 'direct3d) (eq? (selected-adapter) 'hardware)))
    (error 'reference-gpu-context "--adapter warp requires --backend direct3d"))
  (define failures (run-tests suite))
  (define closed (count (lambda (context) (eq? (gpu-context-state context) 'closed)) contexts))
  (define passed? (and (zero? failures) (= closed (length contexts)) (pair? contexts)))
  (define receipt
    (hasheq 'schema 1 'status (if passed? "passed" "failed")
            'backend (symbol->string (selected-backend))
            'adapter (if (eq? (selected-backend) 'direct3d)
                         (symbol->string (selected-adapter)) #f)
            'tests_run 10 'failures failures
            'native_contexts_created (length contexts) 'contexts_closed closed
            'pixel_validation_performed #f 'hardware_acceleration_verified #f
            'context_states (map (lambda (context) (symbol->string (gpu-context-state context)))
                                 (reverse contexts))))
  (when (output-path)
    (call-with-output-file (output-path) #:exists 'error
      (lambda (out) (write-json receipt out) (newline out))))
  (exit (if passed? 0 1)))
