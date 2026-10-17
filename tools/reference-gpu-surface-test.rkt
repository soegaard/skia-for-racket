#lang racket/base

;; Explicit real-backend acceptance. No unavailable-backend skips or CPU fallback.
(require rackunit rackunit/text-ui json racket/cmdline racket/list racket/runtime-path
         syntax/modread skia skia/gpu skia/gpu-diagnostics
         "../private/gpu-io-trace.rkt")

;; `module+ main` imports bindings from this module, so command-line state
;; must live in mutable parameter values instead of module bindings set with
;; `set!`.
(define selected-backend (make-parameter #f))
(define selected-adapter (make-parameter 'hardware))
(define output-path (make-parameter #f))
(define contexts '())
(define case-names '())
(define pixel-probes 0)
(define completed-readbacks 0)
(define one-shot-successes 0)
(define-runtime-path reference-directory "../scribblings/reference")
(define-namespace-anchor anchor)

(define (new-context)
  (define context
    (case (selected-backend)
      [(opengl) ((dynamic-require 'skia/gpu-egl 'make-egl-gpu-context))]
      [(metal) (make-gpu-context #:backend 'metal)]
      [(direct3d) (make-gpu-context #:backend 'direct3d #:adapter (selected-adapter))]
      [else (error 'reference-gpu-surface "select a real backend")]))
  (set! contexts (cons context contexts))
  context)

(define (with-context proc)
  (define context (new-context))
  (dynamic-wind void (lambda () (proc context)) (lambda () (gpu-context-close! context))))

(define (with-active proc)
  (with-context (lambda (context) (call-with-gpu-context context (lambda () (proc context))))))

(define-syntax-rule (gpu-case name body ...)
  (test-case name
    (set! case-names (cons name case-names))
    body ...))

(define (read-surface surface)
  (define result (gpu-surface->rgba-bytes surface))
  (set! completed-readbacks (add1 completed-readbacks))
  result)

(define (read-image image)
  (define result (gpu-image->rgba-bytes image))
  (set! completed-readbacks (add1 completed-readbacks))
  result)

(define (probe bytes width x y expected)
  (define offset (* 4 (+ x (* width y))))
  (check-equal? (subbytes bytes offset (+ offset 4)) (list->bytes expected))
  (set! pixel-probes (add1 pixel-probes)))

(define (load-displayed-helpers)
  ;; Read the actual displayed definitions, not separately maintained copies.
  (define namespace (namespace-anchor->namespace anchor))
  (define (blocks form)
    (cond [(not (pair? form)) '()]
          [(memq (car form) '(quote quasiquote examples)) '()]
          [(eq? (car form) 'racketblock) (list (cdr form))]
          [else (append-map blocks form)]))
  (for ([name '("gpu-surfaces.scrbl" "gpu-images.scrbl" "gpu-transfers.scrbl")])
    (define path (build-path reference-directory name))
    (define document
      (call-with-input-file path
        (lambda (in)
          (with-module-reading-parameterization
            (lambda () (syntax->datum (read-syntax path in)))))))
    (for ([block (in-list (blocks document))])
      (parameterize ([current-namespace namespace]) (eval `(begin ,@block)))))
  (lambda (name)
    (parameterize ([current-namespace namespace]) (namespace-variable-value name))))

(define (suite)
  (test-suite
   "Reference GPU surfaces and transfers"

   (gpu-case "native target metadata and exact opaque pixels agree"
     (with-active
       (lambda (context)
         (with-skia ([surface (make-gpu-surface context 4 3 #:background 'red)])
           (check-equal? (surface-backend surface) (selected-backend))
           (check-equal? (image-info-color-type (gpu-surface->image-info surface)) 'rgba-8888)
           (check-false (hash-ref (gpu-surface-info surface) 'actual_sample_count))
           (probe (read-surface surface) 4 2 1 '(255 0 0 255))))))

   (gpu-case "snapshot owns captured contents after surface mutation and closure"
     (with-active
       (lambda (context)
         (with-skia ([surface (make-gpu-surface context 4 3 #:background 'red)]
                     [image (gpu-surface-snapshot surface)])
           (canvas-clear! (surface-canvas surface) 'blue)
           (skia-close! surface)
           (check-equal? (image-residency image) 'gpu)
           (probe (read-image image) 4 1 1 '(255 0 0 255))))))

   (gpu-case "upload survives closure of its CPU source"
     (with-active
       (lambda (context)
         (with-skia ([cpu (rgba-bytes->image 1 1 (bytes 0 255 0 255))]
                     [image (gpu-upload-image context cpu)])
           (skia-close! cpu)
           (check-eq? (skia-resource-gpu-context image) context)
           (probe (read-image image) 1 0 0 '(0 255 0 255))))))

   (gpu-case "same-context image reuse returns an independent wrapper"
     (with-active
       (lambda (context)
         (with-skia ([surface (make-gpu-surface context 2 2 #:background 'blue)]
                     [source (gpu-surface-snapshot surface)]
                     [copy (gpu-upload-image context source)])
           (skia-close! source)
           (probe (read-image copy) 2 0 0 '(0 0 255 255))))))

   (gpu-case "another context cannot consume a GPU image implicitly"
     (with-context
       (lambda (first)
         (with-context
           (lambda (second)
             (define image
               (call-with-gpu-context first
                 (lambda ()
                   (with-skia ([surface (make-gpu-surface first 2 2)])
                     (gpu-surface-snapshot surface)))))
             (call-with-skia-resource image
               (lambda (owned)
                 (call-with-gpu-context second
                   (lambda ()
                     (check-exn exn:fail? (lambda () (gpu-upload-image second owned))))))))))))

   (gpu-case "integer GPU subsets keep the selected source pixels"
     (with-active
       (lambda (context)
         (with-skia ([surface (make-gpu-surface context 4 2 #:background 'red)]
                     [paint (make-paint #:color 'blue #:antialias? #f)])
           (draw-rect (surface-canvas surface) 2 0 2 2 paint)
           (with-skia ([image (gpu-surface-snapshot surface)]
                       [part (gpu-image-subset image 2 0 2 2)])
             (check-exn exn:fail? (lambda () (gpu-image-subset image 4 0 1 1)))
             (probe (read-image part) 2 1 1 '(0 0 255 255)))))))

   (gpu-case "filter result geometry supplies a contained subset and offset"
     (with-active
       (lambda (context)
         (with-skia ([surface (make-gpu-surface context 4 3 #:background 'red)]
                     [image (gpu-surface-snapshot surface)]
                     [filter (make-offset-image-filter 2 1)])
           (define-values (result valid offset)
             (gpu-image-apply-filter image filter #:clip '(0 0 12 12)))
           (call-with-skia-resource result
             (lambda (owned)
               (check-true (gpu-image? owned))
               (check-true (immutable? valid))
               (check-true (immutable? offset))
               (check-true (<= (+ (vector-ref offset 0) (vector-ref valid 2)) 12))
               (with-skia ([part (gpu-image-subset owned
                                  (vector-ref valid 0) (vector-ref valid 1)
                                  (vector-ref valid 2) (vector-ref valid 3))])
                 (probe (read-image part) (image-width part) 0 0 '(255 0 0 255)))))))))

   (gpu-case "typed readback writes pixels but preserves row padding"
     (with-active
       (lambda (context)
         (with-skia ([surface (make-gpu-surface context 2 2 #:background 'red)]
                     [buffer (make-raster-buffer-from-info (make-image-info 2 2)
                                                          #:row-bytes 12)])
           (raster-buffer-write-storage! buffer (make-bytes 24 171))
           (call-with-raster-buffer-pixmap buffer
             (lambda (view) (gpu-surface-read-pixmap! surface view)) #:writable? #t)
           (set! completed-readbacks (add1 completed-readbacks))
           (define data (raster-buffer->storage-bytes buffer))
           (check-equal? (subbytes data 8 12) (make-bytes 4 171))
           (check-equal? (subbytes data 20 24) (make-bytes 4 171))
           (probe (raster-buffer->rgba-bytes buffer) 2 1 1 '(255 0 0 255))))))

   (gpu-case "tagged-to-untagged typed readback fails without destination mutation"
     (with-active
       (lambda (context)
         (with-skia ([space (make-srgb-color-space)]
                     [surface (make-gpu-surface context 2 2 #:color-space space)]
                     [buffer (make-raster-buffer-from-info (make-image-info 2 2))])
           (define before (raster-buffer->storage-bytes buffer))
           (call-with-raster-buffer-pixmap buffer
             (lambda (view)
               (check-exn exn:fail? (lambda () (gpu-surface-read-pixmap! surface view))))
             #:writable? #t)
           (check-equal? (raster-buffer->storage-bytes buffer) before)))))

   (gpu-case "legacy destination format restriction is enforced"
     (with-active
       (lambda (context)
         (with-skia ([surface (make-gpu-surface context 2 2 #:background 'blue)]
                     [wrong (make-raster-buffer-from-info
                             (make-image-info 2 2 #:color-type 'bgra-8888))]
                     [right (make-raster-buffer 2 2)])
           (check-exn exn:fail?
             (lambda () (gpu-surface-read-raster-buffer! surface wrong)))
           (gpu-surface-read-raster-buffer! surface right)
           (set! completed-readbacks (add1 completed-readbacks))
           (probe (raster-buffer->rgba-bytes right) 2 0 0 '(0 0 255 255))))))

   (gpu-case "snapshots readback and targeted flush reject unbalanced stacks"
     (with-active
       (lambda (context)
         (with-skia ([surface (make-gpu-surface context 2 2)])
           (define canvas (surface-canvas surface))
           (canvas-save! canvas)
           (dynamic-wind void
             (lambda ()
               (check-exn exn:fail? (lambda () (gpu-surface-snapshot surface)))
               (check-exn exn:fail? (lambda () (gpu-surface->rgba-bytes surface)))
               (check-exn exn:fail? (lambda () (gpu-flush-surface! context surface))))
             (lambda () (canvas-restore! canvas)))))))

   (gpu-case "typed CPU image remains usable after the GPU context is closed"
     (define detached
       (with-active
         (lambda (context)
           (with-skia ([surface (make-gpu-surface context 2 2 #:background 'blue)])
             (gpu-surface->raster-image surface)))))
     (call-with-skia-resource detached
       (lambda (image)
         (check-equal? (image-residency image) 'cpu)
         (check-false (gpu-image? image))
         (probe (image->rgba-bytes image) 2 1 1 '(0 0 255 255)))))

   (gpu-case "targeted flush requests no readback submission or completion"
     (with-active
       (lambda (context)
         (with-skia ([surface (make-gpu-surface context 2 2)]
                     [image (gpu-surface-snapshot surface)])
           (define ledger (box '()))
           (parameterize ([current-gpu-io-ledger ledger])
             (gpu-flush-surface! context surface)
             (gpu-flush-image! context image))
           (check-equal? (length (unbox ledger)) 2)
           (for ([entry (in-list (unbox ledger))])
             (check-equal? (hash-ref entry 'kind) "flush")
             (check-false (hash-ref entry 'submission_requested))
             (check-false (hash-ref entry 'completion_guaranteed)))
           (gpu-flush! context)
           (gpu-submit! context #:wait? #t)
           (gpu-flush-and-submit! context)
           (gpu-wait! context)))))

   (gpu-case "cache operations retain a usable context and restore its byte limit"
     (with-active
       (lambda (context)
         (define before (gpu-cache-info context))
         (define limit (hash-ref before 'limit_bytes))
         (check-false (hash-ref before 'limit_is_hard_allocation_cap))
         (dynamic-wind void
           (lambda ()
             (check-pred void? (gpu-set-cache-limit! context 0))
             (gpu-purge-unlocked! context #:scratch-only? #t)
             (gpu-purge-bytes! context 0)
             (gpu-perform-deferred-cleanup! context 0)
             (gpu-free-resources! context)
             (check-equal? (gpu-context-state context) 'ready))
           (lambda () (gpu-set-cache-limit! context limit))))))

   (gpu-case "bounded GPU memory report has a context scope and detached entries"
     (with-active
       (lambda (context)
         (define report (gpu-memory-statistics context #:max-entries 0 #:byte-limit 0))
         (check-equal? (memory-statistics-scope report) 'gpu-context-skia-resources)
         (check-true (immutable? (memory-statistics-entries report)))
         (check-equal? (vector-length (memory-statistics-entries report)) 0))))

   (gpu-case "format queries distinguish support from an allocated sample count"
     (with-active
       (lambda (context)
         (for ([format '(rgba-8888 rgba-f16 rgba-f32)])
           (define info (gpu-surface-format-info context format))
           (check-true (immutable? info))
           (check-false (hash-ref info 'allocation_verified))
           (check-false (hash-ref info 'actual_sample_count))
           (check-equal? (hash-ref info 'renderable)
                         (positive? (hash-ref info 'max_sample_count)))))))

   (gpu-case "opaque background and conflicting alpha requests are rejected"
     (with-active
       (lambda (context)
         (check-exn exn:fail?
           (lambda () (make-gpu-surface context 2 2 #:opaque? #t)))
         (check-exn exn:fail?
           (lambda () (make-gpu-surface context 2 2 #:opaque? #t
                                        #:background 'white #:alpha-type 'premul))))))

   (gpu-case "actual displayed helpers render and place their pixels"
     (define helper (load-displayed-helpers))
     (with-context
       (lambda (context)
         (with-skia ([image ((helper 'gpu-red-tile) context)])
           (call-with-gpu-context context
             (lambda ()
               (with-skia ([surface (make-gpu-surface context 12 12 #:background 'white)]
                           [buffer (make-raster-buffer 12 12)])
                 ((helper 'draw-shifted-gpu-image) (surface-canvas surface) image)
                 ((helper 'copy-gpu-surface-to-buffer) context surface buffer)
                 (set! completed-readbacks (add1 completed-readbacks))
                 (define data (raster-buffer->rgba-bytes buffer))
                 (probe data 12 3 2 '(255 0 0 255))
                 (probe data 12 0 0 '(255 255 255 255)))))))))

   (if (eq? (selected-backend) 'opengl)
       ;; This API requires a separately owned external host. It is explicitly
       ;; outside the owned-EGL surface suite, not an unavailable-backend skip.
       (test-suite "External-host one-shot acceptance is separate")
       (gpu-case "one-shot owned-backend rendering calls once and returns a CPU image"
         (define calls 0)
         (define image
           (render-gpu->raster-image 2 2
             (lambda (canvas)
               (set! calls (add1 calls))
               (check-equal? (canvas-execution-backend canvas) (selected-backend))
               (canvas-clear! canvas 'blue)
               (values 1 2))
             #:backend (selected-backend)
             #:adapter (and (eq? (selected-backend) 'direct3d) (selected-adapter))))
         (call-with-skia-resource image
           (lambda (owned)
             (check-equal? calls 1)
             (check-equal? (image-residency owned) 'cpu)
             (probe (image->rgba-bytes owned) 2 0 0 '(0 0 255 255))
             (set! one-shot-successes (add1 one-shot-successes))))))))

(module+ main
  (command-line
   #:once-each
   [("--backend") name "Required: opengl, metal, or direct3d. OpenGL uses owned EGL."
    (selected-backend (string->symbol name))]
   [("--adapter") name "Direct3D only: hardware or warp."
    (selected-adapter (string->symbol name))]
   [("--output") path "Write a JSON execution receipt." (output-path path)])
  (unless (memq (selected-backend) '(opengl metal direct3d))
    (error 'reference-gpu-surface "--backend must select a real backend"))
  (unless (and (memq (selected-adapter) '(hardware warp))
               (or (eq? (selected-backend) 'direct3d) (eq? (selected-adapter) 'hardware)))
    (error 'reference-gpu-surface "WARP requires Direct3D"))
  (define failures (run-tests (suite)))
  (define states (map gpu-context-state contexts))
  (define closed (count (lambda (state) (eq? state 'closed)) states))
  (define expected-cases (if (eq? (selected-backend) 'opengl) 18 19))
  (define passed?
    (and (zero? failures) (= expected-cases (length case-names))
         (pair? contexts) (= closed (length contexts))
         (positive? pixel-probes) (positive? completed-readbacks)
         (= one-shot-successes (if (eq? (selected-backend) 'opengl) 0 1))))
  (define receipt
    (hasheq 'schema 1 'status (if passed? "passed" "failed")
            'backend (symbol->string (selected-backend))
            'adapter (if (eq? (selected-backend) 'direct3d)
                         (symbol->string (selected-adapter)) #f)
            'tests_run (length case-names) 'case_names (reverse case-names) 'failures failures
            'managed_contexts_created (length contexts) 'managed_contexts_closed closed
            'context_states (map symbol->string states)
            'pixel_probes_checked pixel-probes 'readbacks_completed completed-readbacks
            'one_shot_successes one-shot-successes
            'one_shot_native_status (if (eq? (selected-backend) 'opengl)
                                       "not-run-external-host-required" "passed")
            'float_allocation_tested #f 'presentation_tested #f
            'hardware_acceleration_verified #f))
  (when (output-path)
    (call-with-output-file (output-path) #:exists 'error
      (lambda (out) (write-json receipt out) (newline out))))
  (exit (if passed? 0 1)))
