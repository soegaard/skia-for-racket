#lang racket/base

;;;
;;; GPU Cross Backend Doctor
;;;

;; Exercises OpenGL/Metal separation and explicit cross-backend transfers and reports native
;; diagnostic evidence.
;; The validation workflow uses this focused probe alongside automated regression suites.

;;;
;;; Imports and Exports
;;;
(require racket/cmdline racket/file racket/path rackunit/text-ui
         "../gpu.rkt" "../tests/gpu-cross-backend-native-test.rkt"
         "gpu-test-host.rkt" "gpu-report.rkt")
(provide gpu-cross-backend-doctor!)

;;;
;;; Diagnostic Operations
;;;

; gpu-cross-backend-doctor! : path-string? [#:required? boolean? #:require-hardware? boolean?] ->
; exact-integer?
;;   Checks OpenGL/Metal isolation and explicit two-way CPU transfers, publishing teardown evidence
;;   and exit status.
(define (gpu-cross-backend-doctor! prefix #:required? [required? #t] #:require-hardware?
          [hardware? #f])
  (define gl #f) (define metal #f) (define gl-info #f) (define metal-info #f)
  (define started? #f) (define failures #f)
  (define (report status message)
    (hasheq 'schema_version 1 'stage "0.41" 'kind "cross-backend"
            'status status 'message message 'required required? 'require_hardware hardware?
            'os (symbol->string (system-type 'os)) 'architecture (symbol->string (system-type 'arch))
            'racket_version (version) 'validation_run (or (getenv "SKIA_GPU_VALIDATION_RUN") #f)
      'opengl_context gl-info 'metal_context metal-info
            'native_test_cases gpu-cross-backend-native-test-count 'native_test_failures failures
            'transfer_directions '("opengl-to-metal" "metal-to-opengl") 'performance_measured #f))
  (define (publish data)
    (write-gpu-json (string->path (string-append prefix ".diagnostic.json")) data))
  (with-handlers
      ([exn:fail:gpu:unavailable?
        (lambda (e)
          (publish (report (if started? "error" "unavailable") (exn-message e)))
          (eprintf "Cross-backend: ~a\n" (exn-message e))
          (if (and (not required?) (not started?)) 0 1))]
       [exn:fail? (lambda (e) (publish (report "error" (exn-message e)))
                   (eprintf "Cross-backend ERROR: ~a\n" (exn-message e)) 1)])
    (make-directory* (or (path-only (string->path prefix)) (current-directory)))
    (call-with-gpu-backend-host 'opengl
      (lambda (make-gl host)
        (dynamic-wind void
          (lambda ()
            (parameterize-break #f
              (set! gl (make-gl))
              (set! metal (make-gpu-context #:backend 'metal)))
            (set! gl-info (gpu-context-info gl))
            (set! metal-info (gpu-context-info metal))
            (set! started? #t)
            (when hardware?
              (for ([info (in-list (list gl-info metal-info))])
                (unless (equal? (hash-ref info 'renderer_class) "hardware-reported")
                  (error 'gpu-cross-backend-doctor "both hardware-reported backends required"))))
            (set! failures (run-tests (make-gpu-cross-backend-native-tests gl metal)))
            (unless (zero? failures) (error 'gpu-cross-backend-doctor "suite failed: ~a" failures)))
          (lambda () (close-gpu-contexts! (list metal gl) gpu-context-close!)))))
    (define closed-gl (gpu-context-info gl)) (define closed-metal (gpu-context-info metal))
    (check-gpu-teardown! closed-gl) (check-gpu-teardown! closed-metal)
    (publish (hash-set* (report "passed" #f) 'closed_opengl_context closed-gl 'closed_metal_context
               closed-metal))
    (displayln "OpenGL/Metal rejection and explicit two-way CPU transfer checks passed.")
    0))
(module+ main

  ;;;
  ;;; Command-Line Run
  ;;;

  ; prefix : path-string?
  ;;   Sets the common output-path prefix for diagnostic images and JSON evidence.
  (define prefix "output/gpu-cross-backend-0.41")
  ; required? : boolean?
  ;;   Makes unavailable backend support a failed run when true, rather than a permitted skip.
  (define required? #t)
  ; hardware? : boolean?
  ;;   Requires evidence of a hardware renderer instead of accepting a software implementation.
  (define hardware? #f)
  (command-line #:once-each
    [("--prefix") p "Artifact prefix" (set! prefix p)]
    [("--optional") "Allow initial unavailability only" (set! required? #f)]
    [("--require-hardware") "Require hardware-reported names" (set! hardware? #t)]
    #:args () (void))
  (exit (gpu-cross-backend-doctor! prefix #:required? required? #:require-hardware? hardware?)))
