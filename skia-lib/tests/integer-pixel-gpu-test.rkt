#lang racket/base

;;;
;;; Integer Pixel GPU Test
;;;

;; Covers integer storage -> explicit RGBA upload -> GPU draw/readback.
;; This executable supplies backend-specific drawing and transfer evidence to the GPU validation
;; workflow.

;;;
;;; Imports and Exports
;;;

(require racket/cmdline racket/file racket/list json rackunit rackunit/text-ui
         "../main.rkt" "../gpu.rkt" "../gpu-egl.rkt" "../private/gpu-io-trace.rkt"
         "integer-pixel-fixtures.rkt")

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

  ; directory : (or/c path-string? #f)
  ;   Holds the evidence output directory selected for this run.
  (define directory #f)

  ; token : (or/c string? #f)
  ;   Carries the caller's run identifier into evidence so independent validation can match
  ;   artifacts.
  (define token #f)
  (command-line #:once-each
    [("--backend") value "auto, egl, metal, direct3d" (set! backend (string->symbol value))]
    [("--adapter") value "hardware or warp" (set! adapter (string->symbol value))]
    [("--directory") value "New evidence directory" (set! directory value)]
    [("--token") value "Invocation identity" (set! token value)] #:args () (void))
  (unless (and directory token) (error 'integer-pixel-gpu "--directory and --token required"))
  (when (directory-exists? directory) (error 'integer-pixel-gpu "evidence directory already exists"))
  (make-directory* directory)
  (when (eq? backend 'auto)
    (set! backend (case (system-type 'os) [(macosx) 'metal] [(windows) 'direct3d] [else 'egl])))

  ;;;
  ;;; Context and Capture Fixtures
  ;;;

  ; ctx : gpu-context?
  ;   Owns the primary native GPU context used by the fixture run.
  (define ctx
    (case backend [(egl) (make-egl-gpu-context)]
      [(metal) (make-gpu-context #:backend 'metal)]
      [(direct3d) (make-gpu-context #:backend 'direct3d #:adapter adapter)]
      [else (error 'integer-pixel-gpu "unsupported backend")]))

  ; frames : exact-nonnegative-integer?
  ;   Counts successfully rendered fixture frames for the evidence report.
  (define frames 0)

  ; reads : exact-nonnegative-integer?
  ;   Counts explicit readbacks used to inspect integer-pixel fixtures.
  (define reads 0)

  ; draw-reads : exact-nonnegative-integer?
  ;   Counts unexpected readbacks while integer-pixel fixtures are drawn.
  (define draw-reads 0)

  ; rejections : exact-nonnegative-integer?
  ;   Counts unsupported integer-pixel requests rejected by the GPU path.
  (define rejections 0)

  ; rows : (listof hash?)
  ;   Accumulates capture and operation evidence for the run's JSON manifest.
  (define rows '())

  ; failures : exact-nonnegative-integer?
  ;   Counts failed or errored RackUnit cases for the command-line exit status.
  (define failures 0)

  ; read-count : box? -> exact-nonnegative-integer?
  ;   Counts readback events in the wrapper I/O ledger, separating drawing from explicit
  ;   inspection.
  (define (read-count ledger)
    (count (lambda (entry) (equal? (hash-ref entry 'kind #f) "readback")) (unbox ledger)))

  ;;;
  ;;; Packed Pixel Rendering and Rejection Checks
  ;;;

  (dynamic-wind void
    (lambda ()
      (call-with-gpu-context ctx
        (lambda ()
          (set! failures
            (run-tests
              (test-suite "Integer storage -> explicit RGBA upload -> GPU draw/readback"
                (test-case "seven source formats, guarded destination layout, no hidden readback"
                  (for ([format (in-vector integer-pixel-formats)])
                    (with-skia ([cpu (make-integer-fixture-image format)]
                                [image (gpu-upload-image ctx cpu)]
                                [surface (make-gpu-surface ctx 80 64)]
                                [readback (make-raster-buffer-from-info (make-image-info 80 64))]
                                [wrong (make-raster-buffer-from-info
                                         (make-image-info 79 64 #:color-type 'gray-8 #:alpha-type
                                           'opaque))])
                      (skia-close! cpu)
                      (define ledger (box '()))
                      (parameterize ([current-gpu-io-ledger ledger])
                        (canvas-clear! (surface-canvas surface) 'white)
                        (draw-integer-fixture (surface-canvas surface) image #:scale 1))
                      (set! draw-reads (+ draw-reads (read-count ledger)))
                      (check-equal? (read-count ledger) 0)
                      ;; A dimension mismatch must leave all destination storage unchanged.
                      (define before (raster-buffer->storage-bytes wrong))
                      (check-exn exn:fail?
                        (lambda () (gpu-surface-read-raster-buffer! surface wrong)))
                      (check-equal? (raster-buffer->storage-bytes wrong) before)
                      (set! rejections (add1 rejections))
                      (parameterize ([current-gpu-io-ledger ledger])
                        (gpu-surface-read-raster-buffer! surface readback))
                      (check-equal? (read-count ledger) 1)
                      (set! reads (+ reads (read-count ledger)))
                      (define data (raster-buffer->rgba-bytes readback #:premultiplied? #t))
                      (define filename (string-append (symbol->string format) ".rgba"))
                      (call-with-output-file (build-path directory filename)
                        (lambda (out) (write-bytes data out)) #:exists 'error)
                      (set! rows (cons
                                   (hasheq 'source_format (symbol->string format) 'file filename)
                                   rows))
                      (set! frames (add1 frames)))))))))))
    (lambda () (gpu-context-close! ctx)))

  ;;;
  ;;; Teardown and Evidence Publication
  ;;;

  ; closed? : boolean?
  ;   Records whether context teardown completed with no live or failed resource releases.
  (define closed? (eq? (gpu-context-state ctx) 'closed))
  (call-with-output-file (build-path directory "gpu.json")
    (lambda (out)
      (write-json (hasheq 'schema 1 'stage "0.70" 'run_token token
                         'status (if (and (zero? failures) closed?) "passed" "failed")
                         'backend (symbol->string backend) 'adapter (symbol->string adapter)
                         'failures failures 'frames frames 'drawing_readbacks draw-reads
                         'inspection_readbacks reads 'layout_rejections rejections
                         'conversion "explicit-rgba-nearest" 'gpu_target_format "rgba-8888"
                         'captures (reverse rows) 'contexts_closed closed?
                         'gui_executed #f 'physical_display_verified #f) out)) #:exists 'error)
  (exit (if (and (zero? failures) closed?) 0 1)))
