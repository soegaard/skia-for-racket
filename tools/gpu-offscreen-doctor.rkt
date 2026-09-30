#lang racket/base
(require racket/cmdline racket/file racket/path racket/runtime-path racket/list
         rackunit/text-ui
         "../main.rkt" "../gpu.rkt" "../private/gpu-surface-native.rkt" "../private/gpu-io-trace.rkt"
         "../examples/gpu-scenes.rkt" "../tests/gpu-surface-native-test.rkt"
         "gpu-report.rkt" "gpu-test-host.rkt")
(provide gpu-offscreen-doctor!)
(define (gpu-offscreen-doctor! prefix #:backend [backend 'opengl] #:required? [required? #t]
                              #:require-hardware? [hardware? #f]
                              #:host [host-mode 'gui] #:egl-platform [platform 'surfaceless]
                              #:egl-device-index [index 0] #:egl-surface [egl-surface 'surfaceless]
                              #:adapter [adapter #f] #:adapter-index [adapter-index #f])
  (unless (gpu-backend? backend)
    (raise-argument-error 'gpu-offscreen-doctor! "'opengl, 'metal, or 'direct3d" backend))
  (define started? #f)
  (define context #f)
  (define other #f)
  (define survivor #f)
  (define initial #f)
  (define host-info #f)
  (define scenes '())
  (define native-failures #f)
  (define (file suffix) (string-append prefix suffix))
  (define (basename path) (path->string (file-name-from-path (string->path path))))
  (define (report status message)
    (hasheq 'schema_version 1 'stage "0.41" 'backend (symbol->string backend) 'kind "offscreen"
            'status status 'message message 'required required?
            'require_hardware hardware? 'racket_version (version) 'validation_run (or (getenv "SKIA_GPU_VALIDATION_RUN") #f)
            'os (symbol->string (system-type 'os)) 'architecture (symbol->string (system-type 'arch))
            'host host-info 'initial_context initial 'scenes (reverse scenes)
            'native_test_failures native-failures 'native_test_cases 33
            'performance_measured #f))
  (define (publish data)
    (write-gpu-json (string->path (file ".diagnostic.json")) data))
  (with-handlers
      ([exn:fail:gpu:unavailable?
        (lambda (e)
          (define optional-skip? (and (not required?) (not started?)))
          (publish (report (if started? "error" "unavailable") (exn-message e)))
          (eprintf "Offscreen GPU ~a: ~a\n" (if optional-skip? "SKIPPED" "FAILED") (exn-message e))
          (if optional-skip? 0 1))]
       [exn:fail?
        (lambda (e)
          (publish (report "error" (exn-message e)))
          (eprintf "Offscreen GPU ERROR: ~a\n" (exn-message e))
          1)])
    (make-directory* (or (path-only (string->path prefix)) (current-directory)))
    (define (with-host proc) (call-with-gpu-backend-host backend proc #:host host-mode
      #:egl-platform platform #:egl-device-index index #:egl-surface egl-surface
      #:adapter adapter #:adapter-index adapter-index))
    (dynamic-wind
      void
      (lambda ()
        (with-host
         (lambda (make-context host)
           (set! host-info host)
           (with-host
            (lambda (make-other-context other-host)
              (dynamic-wind
                void
                (lambda ()
                  (parameterize-break #f
                    (set! context (make-context))
                    (set! other (make-other-context)))
                  (gpu-surface-native-check!)
                  (set! initial (gpu-context-info context))
                  (when (and hardware?
                             (not (equal? (hash-ref initial 'renderer_class "unclassified") "hardware-reported")))
                    (error 'gpu-offscreen-doctor "hardware-reported renderer required"))
                  (set! started? #t)
                  (set! native-failures (run-tests (make-gpu-surface-native-tests context other)))
                  (unless (zero? native-failures)
                    (error 'gpu-offscreen-doctor "live GPU surface suite failed: ~a" native-failures))
                  (for ([name (in-list gpu-scene-names)])
                    (define stem (symbol->string name))
                    (define cpu-file (file (string-append "." stem ".cpu.png")))
                    (define gpu-file (file (string-append "." stem ".gpu.png")))
                    ;; CPU reference: direct ordinary raster drawing, not a
                    ;; rasterization of the GPU result or a recorded fallback.
                    (with-skia ([cpu (make-surface gpu-scene-width gpu-scene-height)])
                      (draw-gpu-scene (surface-canvas cpu) name)
                      (save-png cpu cpu-file #:exists 'replace))
                    (define target-info #f)
                    (define scene-io (box '()))
                    (define image
                      (parameterize ([current-gpu-io-ledger scene-io])
                        (call-with-gpu-context context
                          (lambda ()
                            (with-skia ([gpu (make-gpu-surface context gpu-scene-width gpu-scene-height)])
                            (set! target-info (gpu-surface-info gpu))
                            (draw-gpu-scene (surface-canvas gpu) name)
                            ;; One explicit completed readback. Encoding occurs
                            ;; outside the GPU scope on the detached CPU image.
                              (gpu-surface->raster-image gpu))))))
                    (with-skia ([detached image]) (save-image detached gpu-file 'png #:exists 'replace))
                    (define info (gpu-context-info context))
                    (unless (and (zero? (hash-ref info 'live_children))
                                 (zero? (hash-ref info 'pending_releases)))
                      (error 'gpu-offscreen-doctor "scene left native GPU handles behind"))
                    (set! scenes
                      (cons (hasheq 'name stem 'width gpu-scene-width 'height gpu-scene-height
                                    'cpu_image (basename cpu-file) 'gpu_image (basename gpu-file)
                                    'target target-info 'explicit_readback #t
                                    'intermediate_cpu_panels 0 'io_events (reverse (unbox scene-io)))
                            scenes))
                    (printf "Offscreen scene ~a: GPU target and detached PNG generated\n" name))
                  (set! survivor
                    (call-with-gpu-context context
                      (lambda ()
                        (with-skia ([s (make-gpu-surface context 8 8 #:background 'blue)])
                          (gpu-surface->raster-image s))))))
                (lambda () (close-gpu-contexts! (list other context) gpu-context-close!)))))))
        (define closed (gpu-context-info context))
        (define other-closed (gpu-context-info other))
        (check-gpu-teardown! closed) (check-gpu-teardown! other-closed)
        (unless (equal? (image->rgba-bytes survivor)
                        (apply bytes (apply append (make-list 64 '(0 0 255 255)))))
          (error 'gpu-offscreen-doctor "CPU detached image changed after GPU teardown"))
        (save-image survivor (file ".detached.png") 'png #:exists 'replace)
        (publish (hash-set* (report "passed" #f)
                            'closed_context closed 'other_closed_context other-closed
                            'surface_symbol_inventory (gpu-surface-native-inventory)
                            'detached_survived_teardown #t
                            'detached_image (basename (file ".detached.png"))))
        (displayln "Offscreen GPU native tests and eight scenes passed; numerical comparison is a separate inspector step.")
        0)
      (lambda () (when survivor (skia-close! survivor))))))
(module+ main
  (define prefix "output/gpu-offscreen-0.41")
  (define required? #t) (define hardware? #f) (define backend 'opengl)
  (define host-mode 'gui) (define platform 'surfaceless) (define device-index 0) (define egl-surface 'surfaceless)
  (define adapter #f) (define adapter-index #f)
  (command-line #:program "gpu-offscreen-doctor" #:once-each
    [("--host") value "gui, egl, or owned" (set! host-mode (string->symbol value))]
    [("--egl-platform") value "surfaceless or device" (set! platform (string->symbol value))]
    [("--egl-device-index") value "EGL device enumeration index" (set! device-index (string->number value))]
    [("--egl-surface") value "surfaceless or pbuffer" (set! egl-surface (string->symbol value))]
    [("--backend") value "opengl, metal, or direct3d" (set! backend (string->symbol value))]
    [("--adapter") value "Explicit Direct3D hardware or warp" (set! adapter (string->symbol value))]
    [("--adapter-index") value "Explicit Direct3D adapter index" (set! adapter-index (or (string->number value) (error 'gpu-adapter "invalid adapter index")))]
    [("--prefix") value "Artifact prefix" (set! prefix value)]
    [("--optional") "Allow only initialization unavailability to skip" (set! required? #f)]
    [("--require-hardware") "Require a hardware-reported renderer string" (set! hardware? #t)]
    #:args () (void))
  (exit (gpu-offscreen-doctor! prefix #:backend backend #:required? required? #:require-hardware? hardware?
    #:host host-mode #:egl-platform platform #:egl-device-index device-index #:egl-surface egl-surface
    #:adapter adapter #:adapter-index adapter-index)))
