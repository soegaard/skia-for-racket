#lang racket/base
(require racket/cmdline racket/file racket/path rackunit/text-ui
         "../main.rkt" "../gpu.rkt" "../gpu-gl-interop.rkt"
         "../tests/gpu-gl-fixtures.rkt" "../tests/gpu-gl-interop-native-test.rkt"
         "../private/gpu-gl-interop-native.rkt" "../private/gpu-io-trace.rkt"
         "gpu-test-host.rkt" "gpu-report.rkt")
(provide gpu-interop-doctor!)
(define (gpu-interop-doctor! prefix #:host [host-mode 'gui] #:egl-platform [platform 'surfaceless]
                             #:egl-device-index [index 0] #:egl-surface [surface 'surfaceless]
                             #:required? [required? #t] #:require-hardware? [hardware? #f])
  (define started? #f) (define context #f) (define other #f)
  (define initial #f) (define host-info #f) (define failures #f)
  (define workflow #f) (define ledger (box '()))
  (define (file suffix) (string-append prefix suffix))
  (define (base path) (path->string (file-name-from-path (string->path path))))
  (define (report status message)
    (hasheq 'schema_version 1 'stage "0.43" 'kind "gl-interop" 'backend "opengl"
            'status status 'message message 'required required? 'require_hardware hardware?
            'os (symbol->string (system-type 'os)) 'architecture (symbol->string (system-type 'arch))
            'racket_version (version) 'validation_run (or (getenv "SKIA_GPU_VALIDATION_RUN") #f)
            'host host-info 'initial_context initial 'workflow workflow
            'native_test_cases gpu-gl-interop-native-test-count 'native_test_failures failures
            'resident_events (reverse (unbox ledger)) 'performance_measured #f))
  (define (publish data) (write-gpu-json (string->path (file ".diagnostic.json")) data))
  (define (with-host proc)
    (call-with-gpu-backend-host 'opengl proc #:host host-mode #:egl-platform platform
                              #:egl-device-index index #:egl-surface surface))
  (with-handlers
      ([exn:fail:gpu:unavailable?
        (lambda (e) (publish (report (if started? "error" "unavailable") (exn-message e)))
          (eprintf "GL interop: ~a\n" (exn-message e))
          (if (and (not required?) (not started?)) 0 1))]
       [exn:fail? (lambda (e) (publish (report "error" (exn-message e)))
                   (eprintf "GL interop ERROR: ~a\n" (exn-message e)) 1)])
    (make-directory* (or (path-only (string->path prefix)) (current-directory)))
    (with-host
     (lambda (make-context host)
       (set! host-info host)
       (with-host
        (lambda (make-other other-host)
          (dynamic-wind void
            (lambda ()
              (parameterize-break #f (set! context (make-context)) (set! other (make-other)))
              (set! initial (gpu-context-info context))
              (set! started? #t)
              (when (and hardware? (not (equal? (hash-ref initial 'renderer_class) "hardware-reported")))
                (error 'gpu-interop-doctor "hardware-reported renderer required"))
              (gl-interop-native-check!)
              (set! failures (run-tests (make-gpu-gl-interop-native-tests context other)))
              (unless (zero? failures) (error 'gpu-interop-doctor "GL interoperability suite failed: ~a" failures))
              (call-with-gpu-context context
                (lambda ()
                  (define native (make-gl-fixture context))
                  (define copied #f)
                  (dynamic-wind void
                    (lambda ()
                      (define source (gl-fixture-pixels native))
                      (set! copied
                        (parameterize ([current-gpu-io-ledger ledger])
                          (gpu-copy-gl-texture context (gl-fixture-texture native) 8 8 #:origin 'top-left)))
                      (define info (gpu-image-info copied))
                      (parameterize ([current-gpu-io-ledger ledger])
                        (call-with-gpu-gl-framebuffer context (gl-fixture-framebuffer native) 8 8
                          (lambda (canvas) (canvas-clear! canvas 'blue)) #:origin 'top-left))
                      (define alive (gl-fixture-alive? native))
                      (unless alive (error 'gpu-interop-doctor "host object name deleted by borrowing"))
                      (define framebuffer-result (gl-fixture-pixels native))
                      (delete-gl-fixture! native)
                      ;; The copied GPU image remains live after its external
                      ;; GL source is destroyed. Only final validation downloads.
                      (define copied-result (gpu-image->rgba-bytes copied))
                      (for ([pixels (in-list (list source framebuffer-result copied-result))]
                            [suffix (in-list '(".host-source.png" ".host-framebuffer.png" ".owned-copy.png"))])
                        (with-skia ([im (rgba-bytes->image 8 8 pixels)])
                          (save-image im (file suffix) 'png #:exists 'replace)))
                      (set! workflow
                        (hasheq 'source_image (base (file ".host-source.png"))
                                'framebuffer_image (base (file ".host-framebuffer.png"))
                                'copy_image (base (file ".owned-copy.png")) 'image info
                                'host_names_survived_borrow alive 'source_deleted_before_copy_readback #t
                                'framebuffer_read_by_host #t 'cpu_validation_readbacks 3)))
                    (lambda () (when copied (skia-close! copied)) (delete-gl-fixture! native))))))
            (lambda () (close-gpu-contexts! (list other context) gpu-context-close!)))))))
    (define closed (gpu-context-info context)) (define other-closed (gpu-context-info other))
    (check-gpu-teardown! closed) (check-gpu-teardown! other-closed)
    (publish (hash-set* (report "passed" #f) 'closed_context closed 'other_closed_context other-closed
                       'interop_symbol_inventory (gl-interop-native-inventory)))
    (displayln "GL borrowing/copy workflow passed; exact PNG inspection is a separate step.")
    0))
(module+ main
  (define prefix "output/gpu-interop-0.43") (define host-mode 'gui) (define platform 'surfaceless)
  (define index 0) (define surface 'surfaceless) (define required? #t) (define hardware? #f)
  (command-line #:once-each
    [("--prefix") p "Artifact prefix" (set! prefix p)]
    [("--host") p "gui or egl" (set! host-mode (string->symbol p))]
    [("--egl-platform") p "surfaceless or device" (set! platform (string->symbol p))]
    [("--egl-device-index") i "Device enumeration index" (set! index (string->number i))]
    [("--egl-surface") p "surfaceless or pbuffer" (set! surface (string->symbol p))]
    [("--optional") "Allow initial unavailability only" (set! required? #f)]
    [("--require-hardware") "Reject software/unclassified renderers" (set! hardware? #t)]
    #:args () (void))
  (exit (gpu-interop-doctor! prefix #:host host-mode #:egl-platform platform #:egl-device-index index
                           #:egl-surface surface #:required? required? #:require-hardware? hardware?)))
