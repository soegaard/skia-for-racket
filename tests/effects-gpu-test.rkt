#lang racket/base
;; Explicit offscreen gate. Missing contexts and failed cleanup are failures.
(require racket/cmdline racket/list racket/file json rackunit rackunit/text-ui
         "../main.rkt" "../gpu.rkt" "../gpu-egl.rkt"
         "../private/gpu-io-trace.rkt" "effects-fixtures.rkt" "effects-native-test.rkt")
(module+ main
  (define backend 'auto)
  (define adapter 'hardware)
  (define report-path #f)
  (define token #f)
  (command-line
   #:once-each
   [("--backend") value "auto, egl, metal or direct3d" (set! backend (string->symbol value))]
   [("--adapter") value "hardware or warp (Direct3D only)" (set! adapter (string->symbol value))]
   [("--report") path "JSON receipt" (set! report-path path)]
   [("--token") value "Invocation identity" (set! token value)]
   #:args () (void))
  (unless (and report-path token) (error 'effects-gpu "--report and --token are required"))
  (when (eq? backend 'auto)
    (set! backend (case (system-type 'os) [(macosx) 'metal] [(windows) 'direct3d] [else 'egl])))
  (define (new-context)
    (case backend
      [(egl) (make-egl-gpu-context)]
      [(metal) (make-gpu-context #:backend 'metal)]
      [(direct3d) (make-gpu-context #:backend 'direct3d #:adapter adapter)]
      [else (error 'effects-gpu "unknown test backend: ~a" backend)]))
  ;; Context construction itself is not nestable. Create the second context
  ;; before entering either GPU scope so the wrong-context test exercises the
  ;; ownership check instead of the scope-construction guard.
  (define ctx (new-context))
  (define other (new-context))
  (define failures 0)
  (define frames 0)
  (define readbacks 0)
  (define (count-reads ledger)
    (count (lambda (e) (equal? (hash-ref e 'kind #f) "readback")) (unbox ledger)))
  (define (render draw)
    (with-skia ([s (make-gpu-surface ctx effect-width effect-height)])
      (define ledger (box '()))
      (parameterize ([current-gpu-io-ledger ledger]) (draw (surface-canvas s)))
      (unless (zero? (count-reads ledger)) (error 'effects-gpu "implicit wrapper readback during drawing"))
      (set! frames (add1 frames))
      (define pixels
        (parameterize ([current-gpu-io-ledger ledger])
          (gpu-surface->rgba-bytes s #:premultiplied? #t)))
      (unless (= 1 (count-reads ledger)) (error 'effects-gpu "explicit capture must record exactly one readback"))
      (set! readbacks (add1 readbacks))
      pixels))
  (dynamic-wind
    void
    (lambda ()
      ;; The ordinary rendering suite and same-context retention test run under
      ;; the primary context.
      (call-with-gpu-context ctx
        (lambda ()
          (parameterize ([current-effects-renderer render])
            (set! failures (run-tests effects-native-tests)))
          (set! failures
            (+ failures
               (run-tests
                (test-suite
                 "Shader masks retain GPU affinity through paint and getters"
                 (test-case "retained shader mask survives original closure and rejects CPU use"
                   (with-skia ([input (rgba-bytes->image 2 2 (make-bytes 16 128))]
                               [image (gpu-upload-image ctx input)]
                               [shader (make-image-shader image)]
                               [mask (make-shader-mask-filter shader)]
                               [paint (make-paint #:color 'red #:mask-filter mask)]
                               [retained (paint-mask-filter paint)]
                               [p2 (make-paint #:color 'red #:mask-filter retained)]
                               [s (make-gpu-surface ctx 16 16)]
                               [cpu (make-surface 16 16)])
                     (for-each skia-close! (list input image shader mask paint))
                     (check-eq? (skia-resource-gpu-context retained) ctx)
                     (check-eq? (skia-resource-gpu-context p2) ctx)
                     (skia-close! retained)
                     (draw-rect (surface-canvas s) 0 0 16 16 p2)
                     (check-exn exn:fail? (lambda () (draw-rect (surface-canvas cpu) 0 0 16 16 p2)))))))))))
      ;; Build the GPU-dependent paint under ctx, leave that scope, then enter
      ;; `other`. Context scopes are deliberately sequential, never nested.
      (set! failures
        (+ failures
           (run-tests
            (test-suite
             "Shader masks reject a different GPU context"
             (test-case "wrong-context drawing rejects; ordinary masks stay CPU-independent"
               (define p #f)
               (dynamic-wind
                 void
                 (lambda ()
                   (set! p
                     (call-with-gpu-context ctx
                       (lambda ()
                         (with-skia ([input (rgba-bytes->image 2 2 (make-bytes 16 128))]
                                     [image (gpu-upload-image ctx input)]
                                     [shader (make-image-shader image)]
                                     [mask (make-shader-mask-filter shader)]
                                     [ordinary (make-gamma-mask-filter 2)])
                           (check-false (skia-resource-gpu-context ordinary))
                           (define retained-paint (make-paint #:mask-filter mask))
                           (check-eq? (skia-resource-gpu-context retained-paint) ctx)
                           retained-paint))))
                   (call-with-gpu-context other
                     (lambda ()
                       (with-skia ([s (make-gpu-surface other 8 8)]
                                   [plain (make-paint #:color 'blue)])
                         (draw-rect (surface-canvas s) 0 0 8 8 plain)
                         (check-exn exn:fail?
                                    (lambda () (draw-rect (surface-canvas s) 0 0 8 8 p)))))))
                 (lambda () (when p (skia-close! p))))))))))
    (lambda ()
      (gpu-context-close! other)
      (gpu-context-close! ctx)))
  (unless (and (eq? (gpu-context-state ctx) 'closed)
               (eq? (gpu-context-state other) 'closed))
    (error 'effects-gpu "contexts did not close"))
  (call-with-output-file report-path
    (lambda (out)
      (write-json (hasheq 'schema 1 'stage "0.66" 'run_token token
                         'status (if (zero? failures) "passed" "failed")
                         'backend (symbol->string backend) 'frames frames
                         'inspection_readbacks readbacks 'drawing_readbacks 0
                         'context_closed #t 'failures failures
                         'gui_executed #f 'physical_display_verified #f) out))
    #:exists 'error)
  (exit (if (zero? failures) 0 1)))
