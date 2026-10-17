#lang racket/base

;;;
;;; Text Blob GPU Test
;;;

;; Covers retained multi-run text on the selected GPU backend.
;; This executable supplies backend-specific drawing and transfer evidence to the GPU validation
;; workflow.

;;;
;;; Imports and Exports
;;;
(require racket/cmdline racket/file racket/list json rackunit rackunit/text-ui
         "../main.rkt" "../gpu.rkt" "../gpu-egl.rkt" "../private/gpu-io-trace.rkt"
  "text-blob-scenes.rkt")
(module+ main

  ;;;
  ;;; Command-Line Run
  ;;;

  ; backend : (or/c symbol? #f)
  ;;   Selects the explicitly requested GPU backend for this command-line run.
  (define backend 'auto)
  ; adapter : (or/c symbol? #f)
  ;;   Selects Direct3D adapter policy when that backend is requested.
  (define adapter 'hardware)
  ; directory : (or/c path-string? #f)
  ;;   Holds the evidence output directory selected for this run.
  (define directory #f)
  ; token : (or/c string? #f)
  ;;   Carries the caller's run identifier into evidence so independent validation can match
  ;;   artifacts.
  (define token #f)
  (command-line #:once-each
    [("--backend") value "auto, egl, metal, direct3d" (set! backend (string->symbol value))]
    [("--adapter") value "hardware or warp" (set! adapter (string->symbol value))]
    [("--directory") value "Fresh GPU evidence directory" (set! directory value)]
    [("--token") value "Invocation identity" (set! token value)] #:args () (void))
  (unless (and directory token) (error 'text-blob-gpu "--directory and --token required"))
  (when (directory-exists? directory) (error 'text-blob-gpu "evidence directory exists"))
  (make-directory* directory)
  (when (eq? backend 'auto)
    (set! backend (case (system-type 'os) [(macosx) 'metal] [(windows) 'direct3d] [else 'egl])))

  ; ctx : gpu-context?
  ;;   Owns the primary native GPU context used by the fixture run.
  (define ctx
    (case backend [(egl) (make-egl-gpu-context)] [(metal) (make-gpu-context #:backend 'metal)]
      [(direct3d) (make-gpu-context #:backend 'direct3d #:adapter adapter)]
      [else (error 'text-blob-gpu "unsupported backend")]))

  ; frames : exact-nonnegative-integer?
  ;;   Counts successfully rendered fixture frames for the evidence report.
  (define frames '())
  ; failures : exact-nonnegative-integer?
  ;;   Counts failed or errored RackUnit cases for the command-line exit status.
  (define failures 0)
  ; drawing-reads : exact-nonnegative-integer?
  ;;   Counts wrapper readbacks during drawing, which these GPU-only fixtures require to remain
  ;;   zero.
  (define drawing-reads 0)
  ; inspection-reads : exact-nonnegative-integer?
  ;;   Counts explicit readbacks used only to inspect rendered fixture pixels.
  (define inspection-reads 0)

  ; reads : box? -> exact-nonnegative-integer?
  ;;   Counts readback events in the wrapper I/O ledger, separating drawing from explicit
  ;;   inspection.
  (define (reads box) (count (lambda (e) (equal? (hash-ref e 'kind #f) "readback")) (unbox box)))
  (dynamic-wind void
    (lambda ()
      (call-with-gpu-context ctx
        (lambda ()
          (set! failures
            (run-tests
             (test-suite
              "Retained multi-run text on the selected GPU backend"
              (test-case "three scenes in native and outline modes have no hidden drawing readbacks"
                (for ([scene (in-list text-blob-scene-names)])
                  (with-skia ([blob (make-text-blob-scene scene)])
                    (check-false (skia-resource-gpu-context blob))
                    (with-skia ([font (text-blob-run-font blob 0)])
                      (check-false (skia-resource-gpu-context font)))
                    (for ([mode '(native outline)])
                      (with-skia ([surface
                                    (make-gpu-surface ctx text-blob-scene-width
                                      text-blob-scene-height)])
                        (define ledger (box '()))
                        (parameterize ([current-gpu-io-ledger ledger] [current-text-output-mode mode])
                          (canvas-clear! (surface-canvas surface) 'white)
                          (draw-text-blob-scene (surface-canvas surface) blob))
                        (set! drawing-reads (+ drawing-reads (reads ledger)))
                        (check-equal? (reads ledger) 0)
                        (define pixels
                          (parameterize ([current-gpu-io-ledger ledger])
                            (gpu-surface->rgba-bytes surface #:premultiplied? #t)))
                        (check-equal? (reads ledger) 1)
                        (set! inspection-reads (+ inspection-reads (reads ledger)))
                        (define file (format "~a-~a.rgba" scene mode))
                        (call-with-output-file (build-path directory file)
                          (lambda (out) (write-bytes pixels out)) #:exists 'error)
                        (set! frames (cons
                                       (hasheq 'scene (symbol->string scene) 'text_mode
                                         (symbol->string mode)
                                                   'file file) frames)))))))))))))
    (lambda () (gpu-context-close! ctx)))

  ; closed? : boolean?
  ;;   Records whether context teardown completed with no live or failed resource releases.
  (define closed? (eq? (gpu-context-state ctx) 'closed))
  (call-with-output-file (build-path directory "gpu.json")
    (lambda (out)
      (write-json
        (hasheq 'schema 1 'stage "0.69" 'status (if (and (zero? failures) closed?) "passed" "failed")
                          'run_token token 'backend (symbol->string backend) 'adapter
          (symbol->string adapter)
                          'failures failures 'frames (reverse frames) 'drawing_readbacks drawing-reads
                          'inspection_readbacks inspection-reads 'contexts_closed closed?
                          'gui_executed #f 'physical_display_verified #f) out)) #:exists 'error)
  (exit (if (and (zero? failures) closed?) 0 1)))
