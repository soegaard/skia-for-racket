#lang racket/base

;;;
;;; Font Query GPU Test
;;;

;; Covers gPU font mutation, snapshots and batch outlines.
;; This executable supplies backend-specific drawing and transfer evidence to the GPU validation
;; workflow.

;;;
;;; Imports and Exports
;;;
(require racket/cmdline racket/list json rackunit rackunit/text-ui
         "../main.rkt" "../gpu.rkt" "../gpu-egl.rkt"
         "../private/gpu-io-trace.rkt" "font-query-fixtures.rkt")
(module+ main

  ;;;
  ;;; Command-Line Run
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
  (unless (and report-path token) (error 'font-query-gpu "--report and --token required"))
  (unless (memq adapter '(hardware warp)) (error 'font-query-gpu "invalid adapter"))
  (when (eq? backend 'auto)
    (set! backend (case (system-type 'os) [(macosx) 'metal] [(windows) 'direct3d] [else 'egl])))

  ; ctx : gpu-context?
  ;   Owns the primary native GPU context used by the fixture run.
  (define ctx
    (case backend
      [(egl) (make-egl-gpu-context)]
      [(metal) (make-gpu-context #:backend 'metal)]
      [(direct3d) (make-gpu-context #:backend 'direct3d #:adapter adapter)]
      [else (error 'font-query-gpu "unsupported backend")]))

  ; failures : exact-nonnegative-integer?
  ;   Counts failed or errored RackUnit cases for the command-line exit status.
  (define failures 0)

  ; frames : exact-nonnegative-integer?
  ;   Counts successfully rendered fixture frames for the evidence report.
  (define frames 0)

  ; drawing-reads : exact-nonnegative-integer?
  ;   Counts wrapper readbacks during drawing, which these GPU-only fixtures require to remain
  ;   zero.
  (define drawing-reads 0)

  ; inspection-reads : exact-nonnegative-integer?
  ;   Counts explicit readbacks used only to inspect rendered fixture pixels.
  (define inspection-reads 0)

  ; completed : (listof string?)
  ;   Collects completed scene labels for coverage evidence.
  (define completed '())

  ; reads : box? -> exact-nonnegative-integer?
  ;   Counts readback events in the wrapper I/O ledger, separating drawing from explicit
  ;   inspection.
  (define (reads ledger)
    (count (lambda (e) (equal? (hash-ref e 'kind #f) "readback")) (unbox ledger)))

  ; scenes-suite : test-suite?
  ;   Checks font mutations, retained snapshots, and outline scenes while distinguishing drawing
  ;   from inspection readbacks.
  (define scenes-suite
    (test-suite "GPU font mutation, snapshots and batch outlines"
      (test-case "each scene renders without hidden CPU readbacks"
        (for ([scene (in-list font-query-scenes)])
          (with-skia ([surface (make-gpu-surface ctx font-query-width font-query-height)])
            (define ledger (box '()))
            (parameterize ([current-gpu-io-ledger ledger])
              (canvas-clear! (surface-canvas surface) 'white)
              (draw-font-query-scene scene (surface-canvas surface)))
            (set! drawing-reads (+ drawing-reads (reads ledger)))
            (check-equal? (reads ledger) 0)
            (define data
              (parameterize ([current-gpu-io-ledger ledger])
                (gpu-surface->rgba-bytes surface #:premultiplied? #t)))
            (check-equal? (reads ledger) 1)
            (set! inspection-reads (+ inspection-reads (reads ledger)))
            (check-font-query-pixels scene data)
            (set! frames (add1 frames))
            (set! completed (cons (symbol->string scene) completed)))))))
  (dynamic-wind void
    (lambda ()
      (call-with-gpu-context ctx
        (lambda () (set! failures (run-tests scenes-suite)))))
    (lambda () (gpu-context-close! ctx)))

  ; closed? : boolean?
  ;   Records whether context teardown completed with no live or failed resource releases.
  (define closed? (eq? (gpu-context-state ctx) 'closed))

  ; passed? : boolean?
  ;   Combines test assertions and required evidence/cleanup checks into the final run status.
  (define passed? (and (zero? failures) closed? (= frames (length font-query-scenes))))
  (call-with-output-file report-path
    (lambda (out)
      (write-json (hasheq 'schema 1 'stage "0.68b" 'run_token token
                          'status (if passed? "passed" "failed")
                          'backend (symbol->string backend) 'adapter (symbol->string adapter)
                          'failures failures 'frames frames 'scenes (reverse completed)
                          'drawing_readbacks drawing-reads 'inspection_readbacks inspection-reads
                          'contexts_closed closed? 'gui_executed #f 'physical_display_verified #f)
        out))
    #:exists 'error)
  (exit (if passed? 0 1)))
