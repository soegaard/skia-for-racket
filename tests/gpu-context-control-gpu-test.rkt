#lang racket/base

;;;
;;; GPU Context Control GPU Test
;;;

;; Checks GPU context options, flush controls, and context lifecycle.
;; This executable supplies backend-specific drawing and transfer evidence to the GPU validation
;; workflow.

;;;
;;; Imports and Exports
;;;
;; Required selected-backend execution. No mocks, automatic CPU fallback or skip.
(require racket/cmdline racket/file racket/path racket/list json rackunit rackunit/text-ui
         "../main.rkt" "../gpu.rkt" "../gpu-egl.rkt" "../private/gpu-io-trace.rkt")

;;;
;;; Fixtures and Assertions
;;;

; WIDTH : exact-positive-integer?
;;   Sets the fixture width in pixels for drawing and storage-layout checks.
(define WIDTH 32)

; HEIGHT : exact-positive-integer?
;;   Sets the fixture height in pixels for drawing and storage-layout checks.
(define HEIGHT 24)

; GPU-CASES : exact-nonnegative-integer?
;;   Records the expected number of real-GPU checks in the evidence receipt.
(define GPU-CASES 20)

; read-count : list? -> exact-nonnegative-integer?
;;   Counts explicit readback records without treating drawing as transfer.
(define (read-count entries)
  (count (lambda (e) (equal? (hash-ref e 'kind #f) "readback")) entries))

; paint-pattern : canvas? -> void?
;;   Draws a high-contrast fixed pattern for context-control capture comparisons.
(define (paint-pattern canvas)
  (canvas-clear! canvas (rgb 17 34 51))
  (with-skia ([red (make-paint #:color (rgb 229 41 53) #:antialias? #f)]
              [green (make-paint #:color (rgb 11 179 67) #:antialias? #f)])
    (draw-rect canvas 2 3 11 7 red)
    (draw-rect canvas 15 10 13 10 green)))
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

  ; report-path : (or/c path-string? #f)
  ;;   Holds the destination for this run's machine-readable evidence report.
  (define report-path #f)

  ; token : (or/c string? #f)
  ;;   Carries the caller's run identifier into evidence so independent validation can match
  ;;   artifacts.
  (define token #f)
  (command-line #:once-each
    [("--backend") b "egl, metal, direct3d" (set! backend (string->symbol b))]
    [("--adapter") a "hardware or warp" (set! adapter (string->symbol a))]
    [("--report") p "New receipt path" (set! report-path (path->complete-path p))]
    [("--token") t "Invocation identity" (set! token t)] #:args () (void))
  (unless (and report-path token) (error 'gpu-context-controls "--report and --token required"))
  (when (eq? backend 'auto)
    (set! backend (case (system-type 'os) [(macosx) 'metal] [(windows) 'direct3d] [else 'egl])))
  (unless (memq backend '(egl metal direct3d)) (error 'gpu-context-controls "unknown backend"))
  (unless (memq adapter '(hardware warp)) (error 'gpu-context-controls "unknown adapter"))

  ; directory : (or/c path-string? #f)
  ;;   Holds the evidence output directory selected for this run.
  (define directory (path-only report-path))
  (make-directory* directory)

  ; contexts : (listof gpu-context?)
  ;;   Tracks owned contexts newest first so every created context is included in cleanup.
  (define contexts '())

  ; resources : (listof skia-resource?)
  ;;   Tracks retained resources newest first for cleanup before their parent contexts close.
  (define resources '())

  ; labels : (listof string?)
  ;;   Records executed test labels in execution order.
  (define labels '())

  ; failures : exact-nonnegative-integer?
  ;;   Counts failed or errored RackUnit cases for the command-line exit status.
  (define failures 0)

  ; captures : (listof hash?)
  ;;   Collects capture filenames and pixel-layout metadata for independent inspection.
  (define captures '())

  ; traces : (listof hash?)
  ;;   Records named GPU I/O event traces in execution order.
  (define traces '())

  ; lifecycle : (or/c hash? #f)
  ;;   Captures context state transitions for reset and cleanup evidence.
  (define lifecycle #f)

  ; cleanup-errors : (listof string?)
  ;;   Collects teardown failures without preventing cleanup of later resources.
  (define cleanup-errors '())

  ; retain : skia-resource? -> skia-resource?
  ;;   Registers an owned resource for reverse-creation-order cleanup and returns it unchanged.
  (define (retain v) (set! resources (cons v resources)) v)

  ; fresh : [(or/c gpu-context-options? #f)] -> gpu-context?
  ;;   Creates and records a selected-backend context with the requested immutable options.
  (define (fresh [options #f])
    (define c (case backend
      [(egl) (make-egl-gpu-context #:options options)]
      [(metal) (make-gpu-context #:backend 'metal #:options options)]
      [(direct3d) (make-gpu-context #:backend 'direct3d #:adapter adapter #:options options)]))
    (set! contexts (cons c contexts)) c)

  ; test! : string? procedure? -> void?
  ;;   Runs one named acceptance case and accumulates its failure count for final reporting.
  (define (test! label thunk)
    (set! labels (append labels (list label)))
    (set! failures (+ failures (run-tests (test-suite label (test-case label (thunk)))))))

  ; surface : gpu-context? -> gpu-surface?
  ;;   Creates a fixture-sized surface and registers it for cleanup before its parent context.
  (define (surface c) (retain (make-gpu-surface c WIDTH HEIGHT)))

  ; snapshot : gpu-surface? -> gpu-image?
  ;;   Retains a surface snapshot and registers the owned wrapper for cleanup.
  (define (snapshot s) (retain (gpu-surface-snapshot s)))

  ; trace! : string? procedure? -> list?
  ;;   Records a named operation's chronological GPU I/O events and returns that event sequence.
  (define (trace! name thunk)
    (define ledger (box '()))
    (parameterize ([current-gpu-io-ledger ledger]) (thunk))
    (define entries (reverse (unbox ledger)))
    (set! traces (append traces (list (hasheq 'name name 'events entries))))
    entries)

  ; tuned : gpu-context-options?
  ;;   Exercises nondefault stencil, program-cache, glyph-cache, path-mask, and buffer-mapping
  ;;   settings.
  (define tuned (make-gpu-context-options #:avoid-stencil-buffers? #t #:runtime-program-cache-size 16
                  #:glyph-cache-texture-maximum-bytes 1048576 #:allow-path-mask-caching? #f
                  #:buffer-map-threshold 4096))

  ; manual : gpu-context-options?
  ;;   Exercises manual mipmapping together with immediate buffer mapping.
  (define manual (make-gpu-context-options #:manual-mipmapping? #t #:buffer-map-threshold 0))

  ; capture! : string? (or/c gpu-context-options? #f) -> void?
  ;;   Renders with selected context options, verifies targeted flush/readback accounting, and saves
  ;;   capture evidence.
  (define (capture! name options)
    (define c (fresh options))
    (define info (gpu-context-info c))
    (define ledger (box '()))
    (define pixels
      (call-with-gpu-context c
        (lambda ()
          (define s (surface c))
          (parameterize ([current-gpu-io-ledger ledger])
            (paint-pattern (surface-canvas s))
            (gpu-flush-surface! c s)
            (define im (snapshot s))
            (gpu-flush-image! c im)
            (check-equal? (read-count (unbox ledger)) 0)
            (check-false (ormap (lambda (e) (equal? (hash-ref e 'kind) "submit")) (unbox ledger)))
            (gpu-submit! c #:wait? #t)
            (gpu-surface->rgba-bytes s)))))
    (check-equal? (read-count (unbox ledger)) 1)
    (check-false (hash-ref info 'context_options_native_readback))
    (define filename (string-append name ".rgba"))
    (call-with-output-file (build-path directory filename) (lambda (out) (write-bytes pixels out))
      #:exists 'error #:mode 'binary)
    (set! captures (append captures (list
      (hasheq 'name name 'file filename 'info info 'width WIDTH 'height HEIGHT
              'requested_options (and options (gpu-context-options->jsexpr options))
              'drawing_readbacks 0 'readbacks 1 'events (reverse (unbox ledger)))))))

  ; primary : (or/c gpu-context? #f)
  ;;   Retains the primary context used by control and state-transition assertions.
  (define primary #f)

  ; other : (or/c gpu-context? #f)
  ;;   Owns a second context used to verify cross-context resource rejection.
  (define other #f)

  ; s : (or/c gpu-surface? #f)
  ;;   Retains the primary surface for targeted flush and lifecycle checks.
  (define s #f)

  ; im : (or/c gpu-image? #f)
  ;;   Retains the primary surface snapshot for targeted image-flush checks.
  (define im #f)

  ; foreign-s : (or/c gpu-surface? #f)
  ;;   Retains a secondary-context surface for cross-context rejection checks.
  (define foreign-s #f)

  ; foreign-im : (or/c gpu-image? #f)
  ;;   Retains a secondary-context snapshot for cross-context rejection checks.
  (define foreign-im #f)
  (dynamic-wind void
    (lambda ()
      (test! "native-default factory pixels" (lambda () (capture! "native-defaults" #f)))
      (test! "explicit-default factory pixels"
        (lambda () (capture! "explicit-defaults" (make-gpu-context-options))))
      (test! "tuned context pixels" (lambda () (capture! "tuned" tuned)))
      (test! "manual mipmap context pixels" (lambda () (capture! "manual" manual)))
      (set! primary (fresh tuned))
      (set! other (fresh))
      (call-with-gpu-context primary
        (lambda () (set! s (surface primary)) (paint-pattern (surface-canvas s))
          (set! im (snapshot s))))
      (call-with-gpu-context other
        (lambda () (set! foreign-s (surface other)) (set! foreign-im (snapshot foreign-s))))
      (test! "surface targeted flush only"
        (lambda () (call-with-gpu-context primary (lambda ()
          (define events (trace! "surface" (lambda () (gpu-flush-surface! primary s))))
          (check-equal? (length events) 1)
          (check-equal? (hash-ref (car events) 'target) "surface")
          (check-false (hash-ref (car events) 'completion_guaranteed))))))
      (test! "image targeted flush only"
        (lambda () (call-with-gpu-context primary (lambda ()
          (define events (trace! "image" (lambda () (gpu-flush-image! primary im))))
          (check-equal? (length events) 1)
          (check-equal? (hash-ref (car events) 'target) "image")
          (check-false (hash-ref (car events) 'submission_requested))))))
      (test! "explicit completion stays separate"
        (lambda () (call-with-gpu-context primary (lambda ()
          (define events
            (trace! "submit"
              (lambda () (gpu-flush-surface! primary s) (gpu-submit! primary #:wait? #t))))
          (check-equal? (map (lambda (e) (hash-ref e 'kind)) events) '("flush" "submit"))
          (check-true (hash-ref (cadr events) 'wait_requested))))))
      (test! "unbalanced surface state is rejected"
        (lambda () (call-with-gpu-context primary (lambda ()
          (call-with-canvas-state (surface-canvas s) (lambda ()
            (check-exn exn:fail? (lambda () (gpu-flush-surface! primary s)))))))))
      (test! "CPU resources are rejected"
        (lambda () (with-skia ([cpu (make-surface 4 4)] [ci (surface-snapshot cpu)])
          (check-exn exn:fail:contract? (lambda () (gpu-flush-surface! primary cpu)))
          (check-exn exn:fail:contract? (lambda () (gpu-flush-image! primary ci))))))
      (test! "closed GPU resources are rejected"
        (lambda () (call-with-gpu-context primary (lambda ()
          (define dead-s (surface primary)) (define dead-im (snapshot dead-s))
          (skia-close! dead-im) (skia-close! dead-s)
          (check-exn exn:fail? (lambda () (gpu-flush-surface! primary dead-s)))
          (check-exn exn:fail? (lambda () (gpu-flush-image! primary dead-im)))))))
      (test! "inactive targeted flush is rejected"
        (lambda ()
          (check-exn exn:fail? (lambda () (gpu-flush-surface! primary s)))
          (check-exn exn:fail? (lambda () (gpu-flush-image! primary im)))))
      (test! "foreign context resources are rejected"
        (lambda () (call-with-gpu-context primary (lambda ()
          (check-exn exn:fail? (lambda () (gpu-flush-surface! primary foreign-s)))
          (check-exn exn:fail? (lambda () (gpu-flush-image! primary foreign-im)))))))
      (test! "healthy teardown rejects active scope"
        (lambda () (call-with-gpu-context primary (lambda ()
          (check-exn exn:fail? (lambda () (gpu-context-release-and-abandon! primary)))))))
      (test! "healthy teardown rejects foreign owner"
        (lambda ()
          (define channel (make-channel))
          (thread (lambda () (with-handlers ([exn:fail? (lambda (e) (channel-put channel #t))])
            (gpu-context-release-and-abandon! primary) (channel-put channel #f))))
          (check-true (channel-get channel))))
      (test! "free resources does not abandon"
        (lambda () (call-with-gpu-context primary (lambda () (gpu-free-resources! primary)))
          (check-eq? (gpu-context-state primary) 'ready)))
      (test! "healthy release invalidates live children without readback"
        (lambda ()
          (define before (gpu-context-info primary))
          (define events (trace! "release" (lambda () (gpu-context-release-and-abandon! primary))))
          (check-eq? (gpu-context-state primary) 'abandoned)
          (check-equal? (read-count events) 0)
          (check-false (skia-closed? s)) (check-false (skia-closed? im))
          (check-exn exn:fail? (lambda () (call-with-gpu-context primary void)))
          (check-exn exn:fail? (lambda () (gpu-context-close! primary)))
          (set! lifecycle (hasheq 'before before 'after_release (gpu-context-info primary)
                                 'children_invalidated #t 'child_close_required #t))))
      (test! "retire children then close native context"
        (lambda ()
          (skia-close! im) (skia-close! s) (gpu-context-close! primary)
          (check-eq? (gpu-context-state primary) 'closed)
          (set! lifecycle (hash-set lifecycle 'after_close (gpu-context-info primary)))))
      (test! "closed release operation is rejected"
        (lambda () (check-exn exn:fail? (lambda () (gpu-context-release-and-abandon! primary)))))
      (test! "existing loss abandonment still works"
        (lambda ()
          (skia-close! foreign-im) (skia-close! foreign-s)
          (gpu-context-abandon! other)
          (check-eq? (gpu-context-state other) 'abandoned)
          (gpu-context-close! other)))
      (test! "new context renders after teardown" (lambda () (capture! "after-release" tuned))))
    (lambda ()
      (for ([resource (in-list resources)])
        (with-handlers
          ([exn:fail? (lambda (e) (set! cleanup-errors (cons (exn-message e) cleanup-errors)))])
          (skia-close! resource)))
      (for ([c (in-list contexts)])
        (with-handlers
          ([exn:fail? (lambda (e) (set! cleanup-errors (cons (exn-message e) cleanup-errors)))])
          (gpu-context-close! c)))))

  ; passed? : boolean?
  ;;   Combines test assertions and required evidence/cleanup checks into the final run status.
  (define passed? (and (= (length labels) GPU-CASES) (zero? failures) (null? cleanup-errors)))
  (call-with-output-file report-path
    (lambda (out)
      (write-json (hasheq 'schema 1 'stage "0.77b" 'status (if passed? "passed" "failed")
                         'run_token token 'native_version (skia-native-version)
                         'backend (symbol->string backend) 'adapter (symbol->string adapter)
                         'gpu_executed #t 'native_option_readback #f
                         'cases (length labels) 'failures failures 'labels labels
                         'captures captures 'targeted_traces traces 'lifecycle lifecycle
                         'cleanup_errors cleanup-errors) out)) #:exists 'error)
  (printf "gpu-context-control-gpu: ~a cases, ~a failures\n" (length labels) failures)
  (exit (if passed? 0 1)))
