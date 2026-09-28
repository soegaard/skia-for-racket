#lang racket/base
(require racket/list racket/path racket/file rackunit/text-ui
         "../main.rkt" "../gpu.rkt" "../private/gpu-cache-native.rkt"
         "../tests/gpu-cache-native-test.rkt" "gpu-performance-work.rkt"
         "gpu-performance-options.rkt" "gpu-test-host.rkt" "gpu-report.rkt")
(provide gpu-performance-doctor!)
(define (gpu-performance-doctor! options)
  (define prefix (hash-ref options 'prefix)) (define backend (hash-ref options 'backend))
  (define config (hash-ref options 'config)) (define started? #f) (define failures #f)
  (define scenes '()) (define cycles '()) (define host-info #f) (define inventory '())
  (clear-performance-results! prefix)
  (define sources (performance-source-fingerprints))
  (define run-id (or (getenv "SKIA_GPU_VALIDATION_RUN") (format "performance-~a" (current-inexact-milliseconds))))
  (define (report status message)
    (hasheq 'schema_version 1 'stage "0.45" 'kind "performance" 'status status 'message message
            'backend (symbol->string backend) 'validation_run run-id
            'os (symbol->string (system-type 'os)) 'architecture (symbol->string (system-type 'arch))
            'racket_version (version) 'vm (symbol->string (system-type 'vm))
            'required (hash-ref options 'required) 'require_hardware (hash-ref options 'hardware)
            'config config 'host host-info 'cache_symbols inventory
            'workload_sources sources
            'native_test_cases gpu-cache-native-test-count 'native_test_failures failures
            'scenes (reverse scenes) 'cycles (reverse cycles)
            'clock "current-inexact-monotonic-milliseconds"
            'timing_scope "instrumented host wall latency; process CPU/GC counters include other threads"
            'isolated_gpu_timestamps #f 'display_latency_measured #f 'total_gpu_memory_measured #f
            'performance_measured (equal? status "passed") 'speedup_claimed #f
            'linux_headless_baseline_status "deferred-to-future-CI"))
  (define (publish status message)
    (write-gpu-json (string->path (string-append prefix ".diagnostic.json")) (report status message)))
  (define (with-host proc)
    (call-with-gpu-backend-host backend proc #:host (hash-ref options 'host)
      #:egl-platform (hash-ref options 'egl_platform) #:egl-device-index (hash-ref options 'egl_index)
      #:egl-surface (hash-ref options 'egl_surface)))
  (define (identify c)
    (define info (gpu-context-info c))
    (when (and (hash-ref options 'hardware)
               (not (equal? (hash-ref info 'renderer_class "unclassified") "hardware-reported")))
      (error 'gpu-performance "hardware-reported renderer required")) info)
  (with-handlers
      ([exn:fail:gpu:unavailable?
        (lambda (e) (publish (if started? "error" "unavailable") (exn-message e))
          (eprintf "GPU performance unavailable/error: ~a\n" (exn-message e))
          (if (and (not started?) (not (hash-ref options 'required))) 0 1))]
       [exn:fail? (lambda (e) (publish "error" (exn-message e))
                    (eprintf "GPU performance ERROR: ~a\n" (exn-message e)) 1)])
    (make-directory* (or (path-only (string->path prefix)) (current-directory)))
    (with-host
      (lambda (make-context host)
        (set! host-info host)
        ;; The native cache suite receives two genuinely independent contexts.
        (with-host
          (lambda (make-other other-host)
            (define a #f) (define b #f)
            (dynamic-wind void
              (lambda ()
                (parameterize-break #f (set! a (make-context))) (set! started? #t)
                (identify a)
                (parameterize-break #f (set! b (make-other)))
                (set! inventory (gpu-cache-native-inventory))
                (set! failures (run-tests (make-gpu-cache-native-tests a b)))
                (unless (zero? failures) (error 'gpu-performance "cache native suite failed")))
              (lambda () (close-gpu-contexts! (list b a) gpu-context-close!)))))
        (for ([name (in-list benchmark-scenes)])
          (define c #f) (define initial #f) (define row #f) (define image #f) (define file #f)
          (dynamic-wind void
            (lambda ()
              (dynamic-wind void
                (lambda ()
                  (parameterize-break #f (set! c (make-context)))
                  (set! initial (identify c))
                  (define-values (r im p) (benchmark-scene! c name config prefix))
                  (set! row r) (set! image im) (set! file p))
                (lambda () (when c (gpu-context-close! c))))
              (define closed (gpu-context-info c)) (check-gpu-teardown! closed)
              (save-image image file 'png #:exists 'replace)
              (set! scenes (cons (hash-set* row 'initial_context initial 'closed_context closed
                                               'encoded_after_teardown #t) scenes))
              (printf "~a / ~a: recording, first-use, replay, upload and readback measured\n" backend name))
            (lambda () (when image (skia-close! image)))))
        (for ([i (in-range (hash-ref config 'cycles))])
          (define c #f) (define initial #f) (define row #f)
          (dynamic-wind void
            (lambda ()
              (parameterize-break #f (set! c (make-context)))
              (set! initial (identify c))
              (set! row (release-stress! c config)))
            (lambda () (when c (gpu-context-close! c))))
          (define closed (gpu-context-info c)) (check-gpu-teardown! closed)
          (set! cycles (cons (hash-set* row 'index i 'initial_context initial 'closed_context closed) cycles))
          (printf "~a: stress cycle ~a, ~a retained-graph frames and teardown completed\n"
                  backend (add1 i) (hash-ref config 'frames)))))
    (publish "passed" #f) 0))
(module+ main
  (exit (gpu-performance-doctor! (read-performance-options "output/performance-0.45"))))
