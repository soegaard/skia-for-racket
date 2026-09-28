#lang racket/base
(require racket/cmdline racket/file racket/path racket/runtime-path racket/list
         rackunit/text-ui
         "../main.rkt" "../gpu.rkt" "../private/gpu-image-native.rkt"
         "../private/gpu-surface-native.rkt" "../private/gpu-io-trace.rkt"
         "../examples/gpu-images.rkt" "../tests/gpu-image-native-test.rkt"
         "gpu-report.rkt" "gpu-test-host.rkt")
(provide gpu-image-doctor!)
(define (gpu-image-doctor! prefix #:backend [backend 'opengl] #:required? [required? #t] #:require-hardware? [hardware? #f]
                              #:host [host-mode 'gui] #:egl-platform [platform 'surfaceless]
                              #:egl-device-index [index 0] #:egl-surface [egl-surface 'surfaceless])
  (unless (memq backend '(opengl metal))
    (raise-argument-error 'gpu-image-doctor! "'opengl or 'metal" backend))
  (define context #f) (define other #f) (define survivor #f)
  (define initial #f) (define host-info #f) (define started? #f)
  (define scenes '()) (define native-failures #f)
  (define (file suffix) (string-append prefix suffix))
  (define (basename path) (path->string (file-name-from-path (string->path path))))
  (define (report status message)
    (hasheq 'schema_version 1 'stage "0.41" 'kind "images" 'backend (symbol->string backend)
            'status status 'message message 'required required? 'require_hardware hardware?
            'os (symbol->string (system-type 'os)) 'architecture (symbol->string (system-type 'arch))
            'racket_version (version) 'validation_run (or (getenv "SKIA_GPU_VALIDATION_RUN") #f) 'initial_context initial 'host host-info
            'native_test_failures native-failures 'native_test_cases gpu-image-native-test-count
            'scenes (reverse scenes) 'performance_measured #f))
  (define (publish value) (write-gpu-json (string->path (file ".diagnostic.json")) value))
  (define (cpu-source name)
    (if (eq? name 'upload-reuse)
        (make-image-workflow-source)
        (with-skia ([s (make-surface 8 8)])
          (draw-image-workflow-source (surface-canvas s))
          (begin0 (surface-snapshot s) (canvas-clear! (surface-canvas s) (rgb 255 0 255))))))
  (define (gpu-source name)
    (if (eq? name 'upload-reuse)
        (with-skia ([cpu (make-image-workflow-source)]) (gpu-upload-image context cpu))
        (with-skia ([s (make-gpu-surface context 8 8)])
          (draw-image-workflow-source (surface-canvas s))
          (begin0 (gpu-surface-snapshot s) (canvas-clear! (surface-canvas s) (rgb 255 0 255))))))
  (with-handlers
      ([exn:fail:gpu:unavailable?
        (lambda (e)
          (define skip? (and (not required?) (not started?)))
          (publish (report (if started? "error" "unavailable") (exn-message e)))
          (eprintf "GPU images ~a: ~a\n" (if skip? "SKIPPED" "FAILED") (exn-message e))
          (if skip? 0 1))]
       [exn:fail?
        (lambda (e)
          (publish (report "error" (exn-message e)))
          (eprintf "GPU images ERROR: ~a\n" (exn-message e)) 1)])
    (make-directory* (or (path-only (string->path prefix)) (current-directory)))
    (define (with-host proc) (call-with-gpu-backend-host backend proc #:host host-mode
      #:egl-platform platform #:egl-device-index index #:egl-surface egl-surface))
    (dynamic-wind
      void
      (lambda ()
        (with-host
         (lambda (make-context host)
           (set! host-info host)
           (with-host
            (lambda (make-other-context _other-host)
              (dynamic-wind
                void
                (lambda ()
                  (parameterize-break #f
                    (set! context (make-context))
                    (set! other (make-other-context)))
                  (gpu-image-native-check!) (gpu-surface-native-check!)
                  (set! initial (gpu-context-info context))
                  (when (and hardware? (not (equal? (hash-ref initial 'renderer_class "unclassified")
                                                    "hardware-reported")))
                    (error 'gpu-image-doctor "hardware-reported renderer required"))
                  (set! started? #t)
                  (set! native-failures (run-tests (make-gpu-image-native-tests context other)))
                  (unless (zero? native-failures)
                    (error 'gpu-image-doctor "live GPU image suite failed: ~a" native-failures))
                  (for ([name (in-list image-workflow-names)])
                    (define stem (symbol->string name))
                    (define cpu-file (file (string-append "." stem ".cpu.png")))
                    (define gpu-file (file (string-append "." stem ".gpu.png")))
                    (with-skia ([source (cpu-source name)] [subset (image-subset source 0 4 3 4)]
                                [picture (make-image-workflow-picture name source subset)]
                                [surface (make-surface image-workflow-width image-workflow-height)])
                      (skia-close! source) (skia-close! subset)
                      (draw-picture (surface-canvas surface) picture)
                      (save-png surface cpu-file #:exists 'replace))
                    (define reuse-io (box '())) (define download-io (box '()))
                    (define image-info #f) (define target-info #f) (define retained? #f)
                    (define detached
                      (parameterize ([current-gpu-io-ledger reuse-io])
                        (call-with-gpu-context context
                          (lambda ()
                            (with-skia
                                ([picture
                                  (with-skia ([source (gpu-source name)]
                                              [subset (gpu-image-subset source 0 4 3 4)])
                                    (set! image-info (gpu-image-info source))
                                    (make-image-workflow-picture name source subset))]
                                 [surface (make-gpu-surface context image-workflow-width image-workflow-height)])
                              (unless (eq? (skia-resource-gpu-context picture) context)
                                (error 'gpu-image-doctor "recorded graph lost GPU affinity"))
                              ;; Release the original wrappers' queued native refs
                              ;; before replay. The picture must stand on its own.
                              (gpu-drain-releases! context)
                              (set! retained? #t)
                              (set! target-info (gpu-surface-info surface))
                              (for ([iteration (in-range 2)])
                                (canvas-clear! (surface-canvas surface) 'transparent)
                                (draw-picture (surface-canvas surface) picture))
                              (gpu-flush-and-submit! context)
                              (when (for/or ([e (in-list (unbox reuse-io))])
                                      (or (equal? (hash-ref e 'kind) "readback")
                                          (hash-ref e 'wait_requested #f)))
                                (error 'gpu-image-doctor "resident replay performed an explicit readback or CPU wait"))
                              (parameterize ([current-gpu-io-ledger download-io])
                                (gpu-surface->raster-image surface)))))))
                    (with-skia ([im detached]) (save-image im gpu-file 'png #:exists 'replace))
                    (define info (gpu-context-info context))
                    (unless (and (zero? (hash-ref info 'live_children))
                                 (zero? (hash-ref info 'pending_releases)))
                      (error 'gpu-image-doctor "resident workflow left GPU wrappers behind"))
                    (set! scenes
                      (cons (hasheq 'name stem 'cpu_image (basename cpu-file) 'gpu_image (basename gpu-file)
                                    'width image-workflow-width 'height image-workflow-height
                                    'image image-info 'target target-info 'replay_count 2
                                    'original_wrappers_closed_before_replay retained?
                                    'intermediate_cpu_panels 0
                                    'reuse_events (reverse (unbox reuse-io))
                                    'download_events (reverse (unbox download-io))) scenes))
                    (printf "GPU image workflow ~a: retained replay and explicit output transfer completed\n" name))
                  (set! survivor
                    (call-with-gpu-context context
                      (lambda ()
                        (with-skia ([cpu (make-image-workflow-source)] [im (gpu-upload-image context cpu)])
                          (gpu-image->raster-image im))))))
                (lambda () (close-gpu-contexts! (list other context) gpu-context-close!)))))))
        (define closed (gpu-context-info context))
        (define other-closed (gpu-context-info other))
        (check-gpu-teardown! closed) (check-gpu-teardown! other-closed)
        (unless (and (eq? (image-residency survivor) 'cpu)
                     (not (skia-resource-gpu-context survivor))
                     (equal? (image->rgba-bytes survivor) image-workflow-pixels))
          (error 'gpu-image-doctor "CPU image changed or retained affinity after GPU teardown"))
        (save-image survivor (file ".detached.png") 'png #:exists 'replace)
        (publish (hash-set* (report "passed" #f)
                            'closed_context closed 'other_closed_context other-closed
                            'image_symbol_inventory (gpu-image-native-inventory)
                            'surface_symbol_inventory (gpu-surface-native-inventory)
                            'detached_survived_teardown #t
                            'detached_image (basename (file ".detached.png"))))
        (displayln "GPU image tests and workflows completed; numerical comparison is the separate inspector step.")
        0)
      (lambda () (when survivor (skia-close! survivor))))))
(module+ main
  (define prefix "output/gpu-images-0.41")
  (define required? #t) (define hardware? #f) (define backend 'opengl)
  (define host-mode 'gui) (define platform 'surfaceless) (define device-index 0) (define egl-surface 'surfaceless)
  (command-line #:program "gpu-image-doctor" #:once-each
    [("--host") value "gui or egl" (set! host-mode (string->symbol value))]
    [("--egl-platform") value "surfaceless or device" (set! platform (string->symbol value))]
    [("--egl-device-index") value "EGL device enumeration index" (set! device-index (string->number value))]
    [("--egl-surface") value "surfaceless or pbuffer" (set! egl-surface (string->symbol value))]
    [("--backend") value "opengl or metal" (set! backend (string->symbol value))]
    [("--prefix") value "Artifact prefix" (set! prefix value)]
    [("--optional") "Allow initialization unavailability to skip" (set! required? #f)]
    [("--require-hardware") "Require hardware-reported renderer strings" (set! hardware? #t)]
    #:args () (void))
  (exit (gpu-image-doctor! prefix #:backend backend #:required? required? #:require-hardware? hardware?
    #:host host-mode #:egl-platform platform #:egl-device-index device-index #:egl-surface egl-surface)))
