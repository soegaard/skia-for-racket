#lang racket/base

;;;
;;; GPU EGL Doctor
;;;

;; Exercises EGL activation, surface selection, and resource ownership and reports native
;; diagnostic evidence.
;; The validation workflow uses this focused probe alongside automated regression suites.

;;;
;;; Imports and Exports
;;;
(require racket/cmdline racket/file racket/path rackunit/text-ui
         "../main.rkt" "../gpu.rkt" "../gpu-egl.rkt"
         "../tests/gpu-egl-native-test.rkt" "gpu-report.rkt")
(provide gpu-egl-doctor!)

;;;
;;; Diagnostic Operations
;;;

; gpu-egl-doctor! : path-string? [#:platform symbol? #:device-index exact-nonnegative-integer?
; #:surface symbol? #:required? boolean? #:require-hardware? boolean?] -> exact-integer?
;   Checks EGL context ownership, explicit readback, native lifecycle cases, and repeated teardown.
(define (gpu-egl-doctor! prefix #:platform [platform 'surfaceless] #:device-index [index 0]
                         #:surface [surface 'surfaceless] #:required? [required? #t]
                         #:require-hardware? [hardware? #f])
  (define started? #f) (define cycles '()) (define failures #f)
  (define (factory) (make-egl-gpu-context #:platform platform #:device-index index #:surface surface))
  (define (report status message)
    (hasheq 'schema_version 1 'stage "0.43" 'kind "egl-lifecycle" 'backend "opengl"
            'status status 'message message 'required required? 'require_hardware hardware?
            'os (symbol->string (system-type 'os)) 'architecture (symbol->string (system-type 'arch))
            'racket_version (version) 'validation_run (or (getenv "SKIA_GPU_VALIDATION_RUN") #f)
            'headless #t 'window_created #f 'performance_measured #f
            'display_environment_unset (and (not (getenv "DISPLAY")) (not (getenv "WAYLAND_DISPLAY")))
            'native_test_cases gpu-egl-native-test-count 'native_test_failures failures
            'cycles (reverse cycles)))
  (define (publish status message)
    (write-gpu-json (string->path (string-append prefix ".diagnostic.json")) (report status message)))
  (with-handlers
      ([exn:fail:gpu:unavailable?
        (lambda (e) (publish (if started? "error" "unavailable") (exn-message e))
          (eprintf "EGL lifecycle: ~a\n" (exn-message e))
          (if (and (not required?) (not started?)) 0 1))]
       [exn:fail? (lambda (e) (publish "error" (exn-message e))
                   (eprintf "EGL lifecycle ERROR: ~a\n" (exn-message e)) 1)])
    (make-directory* (or (path-only (string->path prefix)) (current-directory)))
    (for ([i (in-range 3)])
      (define context (factory))
      (define initial (gpu-context-info context))
      (define smoke #f)
      (dynamic-wind void
        (lambda ()
          (set! started? #t)
          (when (and hardware? (not (equal? (hash-ref initial 'renderer_class) "hardware-reported")))
            (error 'gpu-egl-doctor "hardware-reported renderer required; software is not relabeled"))
          (set! smoke (gpu-smoke-test context)))
        (lambda () (gpu-context-close! context)))
      (define closed (gpu-context-info context)) (check-gpu-teardown! closed)
      (define image-path (format "~a.cycle-~a.png" prefix (add1 i)))
      (with-skia ([im (rgba-bytes->image 8 8 (hash-ref smoke 'rgba))])
        (save-image im image-path 'png #:exists 'replace))
      (set! cycles (cons (hasheq 'index i 'initial_context initial 'closed_context closed
                                'target (hash-remove smoke 'rgba) 'encoded_after_teardown #t
                                'image
                           (path->string (file-name-from-path (string->path image-path)))) cycles))
      (printf "EGL cycle ~a: window-system-free Ganesh rendering, exact readback, teardown\n"
        (add1 i)))
    (set! failures (run-tests (make-gpu-egl-native-tests factory)))
    (unless (zero? failures) (error 'gpu-egl-doctor "EGL lifecycle suite failed: ~a" failures))
    (publish "passed" #f)
    0))
(module+ main

  ;;;
  ;;; Command-Line Run
  ;;;

  ; prefix : path-string?
  ;   Sets the common output-path prefix for diagnostic images and JSON evidence.
  (define prefix "output/gpu-egl-0.43")

  ; platform : symbol?
  ;   Selects the EGL platform, initially the display-server-free surfaceless platform.
  (define platform 'surfaceless)

  ; index : exact-nonnegative-integer?
  ;   Selects the zero-based EGL device for device-platform contexts.
  (define index 0)

  ; surface : symbol?
  ;   Selects the EGL binding surface kind, initially surfaceless.
  (define surface 'surfaceless)

  ; required? : boolean?
  ;   Makes unavailable backend support a failed run when true, rather than a permitted skip.
  (define required? #t)

  ; hardware? : boolean?
  ;   Requires evidence of a hardware renderer instead of accepting a software implementation.
  (define hardware? #f)
  (command-line #:once-each
    [("--prefix") p "Artifact prefix" (set! prefix p)]
    [("--egl-platform") p "surfaceless or device" (set! platform (string->symbol p))]
    [("--egl-device-index") i "Device enumeration index" (set! index (string->number i))]
    [("--egl-surface") p "surfaceless or pbuffer" (set! surface (string->symbol p))]
    [("--optional") "Allow initial unavailability only" (set! required? #f)]
    [("--require-hardware") "Reject software/unclassified renderers" (set! hardware? #t)]
    #:args () (void))
  (exit (gpu-egl-doctor! prefix #:platform platform #:device-index index #:surface surface
                       #:required? required? #:require-hardware? hardware?)))
