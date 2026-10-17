#lang racket/base

;;;
;;; Geometry Completion GPU Test
;;;

;; Covers gPU geometry and retained paint reset.
;; This executable supplies backend-specific drawing and transfer evidence to the GPU validation
;; workflow.

;;;
;;; Imports and Exports
;;;

(require racket/cmdline racket/file racket/list json rackunit rackunit/text-ui
         "../main.rkt" "../gpu.rkt" "../gpu-egl.rkt"
         "../private/gpu-io-trace.rkt" "geometry-completion-fixtures.rkt")

;;;
;;; GPU Acceptance Run
;;;

(module+ main

  ;;;
  ;;; Backend and Evidence Options
  ;;;

  ; backend : (or/c symbol? #f)
  ;   Selects the explicitly requested GPU backend for this command-line run.
  (define backend 'auto)

  ; adapter : (or/c symbol? #f)
  ;   Selects Direct3D adapter policy when that backend is requested.
  (define adapter 'hardware)

  ; report-path : (or/c path-string? #f)
  ;   Holds the destination for this run's machine-readable evidence report.
  (define report-path #f)

  ; token : (or/c string? #f)
  ;   Carries the caller's run identifier into evidence so independent validation can match
  ;   artifacts.
  (define token #f)
  (command-line #:once-each
    [("--backend") value "auto, egl, metal, direct3d" (set! backend (string->symbol value))]
    [("--adapter") value "hardware or warp" (set! adapter (string->symbol value))]
    [("--report") value "New report file" (set! report-path value)]
    [("--token") value "Invocation identity" (set! token value)] #:args () (void))
  (unless (and report-path token) (error 'geometry-gpu "--report and --token required"))
  (when (eq? backend 'auto)
    (set! backend (case (system-type 'os) [(macosx) 'metal] [(windows) 'direct3d] [else 'egl])))

  ;;;
  ;;; Context and Capture Fixtures
  ;;;

  ; create : -> gpu-context?
  ;   Creates an owned context for the explicitly selected EGL, Metal, or Direct3D test backend.
  (define (create)
    (case backend [(egl) (make-egl-gpu-context)]
      [(metal) (make-gpu-context #:backend 'metal)]
      [(direct3d) (make-gpu-context #:backend 'direct3d #:adapter adapter)]
      [else (error 'geometry-gpu "unsupported backend")]))
  ;; Construction and entry of different domains are never nested.

  ; ctx : gpu-context?
  ;   Owns the primary native GPU context used by the fixture run.
  (define ctx (create))

  ; other : (or/c gpu-context? #f)
  ;   Owns a second context used to verify cross-context resource rejection.
  (define other #f)

  ; held : (or/c image? #f)
  ;   Retains a GPU snapshot to test cross-context rejection and lifecycle behavior.
  (define held #f)

  ; failures : exact-nonnegative-integer?
  ;   Counts failed or errored RackUnit cases for the command-line exit status.
  (define failures 0)

  ; frames : exact-nonnegative-integer?
  ;   Counts successfully rendered fixture frames for the evidence report.
  (define frames 0)

  ; readbacks : exact-nonnegative-integer?
  ;   Counts explicit GPU-to-CPU transfers used to inspect rendered output.
  (define readbacks 0)

  ; drawing-reads : exact-nonnegative-integer?
  ;   Counts wrapper readbacks during drawing, which these GPU-only fixtures require to remain
  ;   zero.
  (define drawing-reads 0)

  ; reset-reads : exact-nonnegative-integer?
  ;   Counts explicit readbacks after backend-state reset.
  (define reset-reads 0)

  ; reset-drawing-reads : exact-nonnegative-integer?
  ;   Counts unexpected readbacks during the post-reset drawing pass.
  (define reset-drawing-reads 0)

  ; completed : (listof string?)
  ;   Collects completed scene labels for coverage evidence.
  (define completed '())

  ; reads : box? -> exact-nonnegative-integer?
  ;   Counts readback events in the wrapper I/O ledger, separating drawing from explicit
  ;   inspection.
  (define (reads ledger)
    (count (lambda (e) (equal? (hash-ref e 'kind #f) "readback")) (unbox ledger)))

  ;;;
  ;;; Geometry Rendering and Context Checks
  ;;;

  (dynamic-wind void
    (lambda ()
      (set! other (create))
      (call-with-gpu-context ctx
        (lambda ()
          (set! failures
            (run-tests
              (test-suite "GPU geometry and retained paint reset"
                (test-case "seven geometry scenes render without wrapper readback"
                  (for ([name (in-list geometry-scene-names)])
                    (with-skia ([surface (make-gpu-surface ctx geometry-width geometry-height)])
                      (define ledger (box '()))
                      (parameterize ([current-gpu-io-ledger ledger])
                        (canvas-clear! (surface-canvas surface) 'white)
                        (draw-geometry-scene name (surface-canvas surface)))
                      (set! drawing-reads (+ drawing-reads (reads ledger)))
                      (check-equal? (reads ledger) 0)
                      (define pixels (parameterize ([current-gpu-io-ledger ledger])
                        (gpu-surface->rgba-bytes surface #:premultiplied? #t)))
                      (check-equal? (reads ledger) 1)
                      (set! frames (add1 frames)) (set! readbacks (+ readbacks (reads ledger)))
                      (check-geometry-pixels name pixels)
                      (set! completed (cons (symbol->string name) completed)))))
                (test-case "reset detaches paint but not an independently retained mask"
                  (with-skia ([input (rgba-bytes->image 2 2 (make-bytes 16 128))]
                              [image (gpu-upload-image ctx input)] [shader (make-image-shader image)]
                              [mask (make-shader-mask-filter shader)]
                              [paint (make-paint #:mask-filter mask)]
                              [retained (paint-mask-filter paint)])
                    (check-eq? (skia-resource-gpu-context paint) ctx)
                    (paint-set-dither! paint #t)
                    (paint-reset! paint)
                    (check-false (skia-resource-gpu-context paint))
                    (check-false (paint-mask-filter paint))
                    (check-false (paint-dither? paint))
                    (check-eq? (skia-resource-gpu-context retained) ctx))))))))
      ;; Publish one reset paint into a sequential second scope. A zero-failure
      ;; status is not possible when reset leaves its former GPU dependency.
      (set! held
        (call-with-gpu-context ctx
          (lambda ()
            (with-skia ([input (rgba-bytes->image 2 2 (make-bytes 16 128))]
                        [image (gpu-upload-image ctx input)] [shader (make-image-shader image)])
              (define p (make-paint #:shader shader))
              (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! p) (raise e))])
                (paint-reset! p) (paint-set-color! p 'blue) p)))))
      (call-with-gpu-context other
        (lambda ()
          (set! failures (+ failures
            (run-tests
              (test-suite "Reset paint crosses context only after detachment"
                (test-case "second-context draw produces expected pixels"
                  (check-false (skia-resource-gpu-context held))
                  (with-skia ([surface (make-gpu-surface other 8 8)])
                    (define ledger (box '()))
                    (parameterize ([current-gpu-io-ledger ledger])
                      (draw-rect (surface-canvas surface) 0 0 8 8 held))
                    (set! reset-drawing-reads (reads ledger))
                    (check-equal? reset-drawing-reads 0)
                    (define data (parameterize ([current-gpu-io-ledger ledger])
                      (gpu-surface->rgba-bytes surface #:premultiplied? #t)))
                    (set! reset-reads (reads ledger))
                    (check-equal? reset-reads 1)
                    (check-equal? (bytes->list (subbytes data 0 4)) '(0 0 255 255)))))))))))
    (lambda ()
      (dynamic-wind void
        (lambda () (when held (skia-close! held)))
        (lambda ()
          (dynamic-wind void (lambda () (when other (gpu-context-close! other)))
            (lambda () (gpu-context-close! ctx)))))))

  ;;;
  ;;; Teardown and Evidence Publication
  ;;;

  ; closed? : boolean?
  ;   Records whether context teardown completed with no live or failed resource releases.
  (define closed?
    (and (eq? (gpu-context-state ctx) 'closed) other (eq? (gpu-context-state other) 'closed)))
  (call-with-output-file report-path
    (lambda (out)
      (write-json (hasheq 'schema 1 'stage "0.67" 'run_token token
        'status (if (and (zero? failures) closed?) "passed" "failed")
        'backend (symbol->string backend) 'adapter (symbol->string adapter)
        'failures failures 'frames frames 'scenes (reverse completed)
        'drawing_readbacks drawing-reads 'inspection_readbacks readbacks
        'reset_drawing_readbacks reset-drawing-reads 'reset_inspection_readbacks reset-reads
        'reset_transfer_test_passed (zero? failures) 'contexts_closed closed?
        'gui_executed #f 'physical_display_verified #f) out)) #:exists 'error)
  (exit (if (and (zero? failures) closed?) 0 1)))
