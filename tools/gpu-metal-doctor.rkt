#lang racket/base
(require racket/cmdline racket/file racket/path racket/list rackunit/text-ui
         "../main.rkt" "../gpu.rkt" "../private/gpu-native.rkt"
         "../tests/gpu-metal-native-test.rkt" "gpu-report.rkt")
(provide gpu-metal-doctor!)
;; This process never imports/initializes a Racket GUI or OpenGL provider.
(define (gpu-metal-doctor! prefix #:required? [required? #t] #:require-hardware? [hardware? #f])
  (define started? #f) (define cycles '()) (define failures #f)
  (define (report status message)
    (hasheq 'schema_version 1 'stage "0.41" 'kind "metal-lifecycle" 'backend "metal"
            'status status 'message message 'required required? 'require_hardware hardware?
            'os (symbol->string (system-type 'os)) 'architecture (symbol->string (system-type 'arch))
            'racket_version (version) 'validation_run (or (getenv "SKIA_GPU_VALIDATION_RUN") #f) 'headless #t 'presentation_tested #f
            'native_test_cases gpu-metal-native-test-count 'native_test_failures failures
            'cycles (reverse cycles) 'performance_measured #f))
  (define (publish status message)
    (write-gpu-json (string->path (string-append prefix ".diagnostic.json")) (report status message)))
  (with-handlers
      ([exn:fail:gpu:unavailable?
        (lambda (e)
          (publish (if started? "error" "unavailable") (exn-message e))
          (eprintf "Metal lifecycle: ~a\n" (exn-message e))
          (if (and (not required?) (not started?)) 0 1))]
       [exn:fail? (lambda (e) (publish "error" (exn-message e))
                   (eprintf "Metal lifecycle ERROR: ~a\n" (exn-message e)) 1)])
    (make-directory* (or (path-only (string->path prefix)) (current-directory)))
    (for ([index (in-range 3)])
      (define context (make-gpu-context #:backend 'metal))
      (define initial (gpu-context-info context))
      (define smoke #f)
      (dynamic-wind void
        (lambda ()
          (set! started? #t)
          (when (and hardware? (not (equal? (hash-ref initial 'renderer_class) "hardware-reported")))
            (error 'gpu-metal-doctor "hardware-reported Metal device required"))
          (set! smoke (gpu-smoke-test context)))
        (lambda () (gpu-context-close! context)))
      (define closed (gpu-context-info context))
      (check-gpu-teardown! closed)
      (define filename (format "~a.cycle-~a.png" prefix (add1 index)))
      ;; Publish only copied CPU bytes, after the native context is gone.
      (with-skia ([im (rgba-bytes->image 8 8 (hash-ref smoke 'rgba))])
        (save-image im filename 'png #:exists 'replace))
      (set! cycles (cons (hasheq 'index index 'initial_context initial 'closed_context closed
                                'target (hash-remove smoke 'rgba)
                                'image (path->string (file-name-from-path (string->path filename)))
                                'encoded_after_teardown #t) cycles))
      (printf "Metal cycle ~a: exact Ganesh render/readback and teardown completed\n" (add1 index)))
    (set! failures (run-tests (make-gpu-metal-native-tests)))
    (unless (zero? failures) (error 'gpu-metal-doctor "Metal-specific suite failed: ~a" failures))
    (publish "passed" #f)
    0))
(module+ main
  (define prefix "output/gpu-metal-0.41") (define required? #t) (define hardware? #f)
  (command-line #:once-each
    [("--prefix") p "Artifact prefix" (set! prefix p)]
    [("--optional") "Allow initial unavailability only" (set! required? #f)]
    [("--require-hardware") "Require hardware-reported device name" (set! hardware? #t)]
    #:args () (void))
  (exit (gpu-metal-doctor! prefix #:required? required? #:require-hardware? hardware?)))
