#lang racket/base
(require racket/cmdline racket/file racket/path racket/list rackunit/text-ui
         "../main.rkt" "../gpu.rkt" "../gpu-interop.rkt" "../unsafe/gpu-metal.rkt"
         "../private/gpu-io-trace.rkt" "../private/gpu-metal-interop-policy.rkt"
         "../private/gpu-metal-interop-native.rkt"
         "../tests/metal-interop-fixture.rkt" "../tests/gpu-metal-interop-native-test.rkt"
         "gpu-report.rkt")
(provide gpu-metal-interop-doctor!)
(define (gpu-metal-interop-doctor! directory fixture-path #:timeout-case? [timeout-case? #f])
  (define run (path->string (file-name-from-path (simplify-path directory))))
  (define file (build-path directory (if timeout-case? "metal-interop.timeout.json" "metal-interop.diagnostic.json")))
  (define base
    (hasheq 'schema 1 'stage "0.52" 'backend "metal" 'validation_run run
            'os (symbol->string (system-type 'os)) 'architecture (symbol->string (system-type 'arch))
            'racket_version (version) 'vm (symbol->string (system-type 'vm))
            'hardware_acceleration_verified #f 'presentation_verified #f 'performance_measured #f
            'zero_copy_claimed #f 'producer_coverage_verified #f))
  (define (emit value) (write-gpu-json file value))
  (define (failure e)
    (define message (if (exn? e) (exn-message e) "non-exception failure"))
    (emit (hash-set* base 'status "failed" 'error message))
    (eprintf "Metal interop FAILED: ~a\n" message) 1)
  (with-handlers ([(lambda (_) #t) failure])
    (unless (eq? (system-type 'os) 'macosx) (error 'metal-interop-doctor "requires macOS; no optional skip"))
    (make-directory* directory)
    (load-metal-fixture! fixture-path)
    (cond
      [timeout-case?
       (define c (make-gpu-context #:backend 'metal))
       (define f #f) (define t #f) (define caught #f)
       (dynamic-wind void
         (lambda ()
           (call-with-gpu-context c
             (lambda ()
               (set! f (make-metal-fixture c 11))
               (set! t (metal-handoff c f #:timeout-ms 25))
               (with-handlers ([exn:fail:metal-interop?
                                (lambda (e)
                                  (unless (eq? (exn:fail:metal-interop-reason e) 'timeout) (raise e))
                                  (set! caught (exn-message e)))])
                 (define image (gpu-import-image c t))
                 (skia-close! image)
                 (error 'metal-interop-doctor "unsignaled dependency unexpectedly completed"))))
           (unless caught (error 'metal-interop-doctor "specific timeout exception was not observed"))
           (define native (hash-ref (gpu-external-texture-info t) 'native))
           (define info (gpu-context-info c))
           (unless (and (hash-ref native 'quarantined) (equal? (hash-ref native 'error_reason) "timeout")
                        (null? (hash-ref native 'waits)) (hash-ref native 'retained_texture)
                        (hash-ref native 'retained_producer) (hash-ref info 'shutdown_requested)
                        (positive? (hash-ref info 'live_children)))
             (error 'metal-interop-doctor "timeout did not retain storage and quarantine context"))
           ;; Let the independent producer finish before process exit. This
           ;; does NOT recover or release the wrapper's quarantined session.
           (metal-fixture-unblock! f)
           (emit (hash-set* base 'status "expected-timeout-quarantined" 'error caught
             'native native 'context info 'normal_process_exit #t
             'graphics_handoff_submitted #f 'dependency_unblocked_after_timeout #t
             'intentional_retention_until_process_exit #t))
           0)
         (lambda ()
           (when f
             (with-handlers ([exn:fail? void]) (metal-fixture-unblock! f))
             (close-metal-fixture! f))))]
      [else
       (define a #f) (define b #f) (define failures #f) (define suite-closed '())
       (dynamic-wind void
         (lambda ()
           (set! a (make-gpu-context #:backend 'metal)) (set! b (make-gpu-context #:backend 'metal))
           (set! failures (run-tests (make-gpu-metal-interop-native-tests a b))))
         (lambda () (close-gpu-contexts! (filter values (list b a)) gpu-context-close!)))
       (set! suite-closed (map gpu-context-info (list a b)))
       (for-each check-gpu-teardown! suite-closed)
       (unless (and failures (zero? failures)) (error 'metal-interop-doctor "native interop suite failed"))
       (define cycles '()) (define captures '()) (define pending '())
       (dynamic-wind void
         (lambda ()
           (for ([cycle (in-range 3)])
             (define contexts '()) (define rows '())
             (dynamic-wind void
               (lambda ()
                 (for ([i (in-range 2)])
                   (set! contexts (append contexts (list (make-gpu-context #:backend 'metal)))))
                 (for ([c (in-list contexts)] [slot (in-naturals)])
                   (define initial (gpu-context-info c)) (define handoffs '())
                   (call-with-gpu-context c
                     (lambda ()
                       (for ([ordinal (in-range 24)])
                         (define mode (if (even? ordinal) 'copy 'surface))
                         (with-metal-fixture c
                           (lambda (f)
                             (define t (metal-handoff c f)) (define ledger (box '()))
                             (define image #f) (define image-info #f) (define bytes #f)
                             (dynamic-wind void
                               (lambda ()
                                 (parameterize ([current-gpu-io-ledger ledger])
                                   (if (eq? mode 'copy)
                                       (set! image (gpu-import-image c t))
                                       (call-with-gpu-external-surface c t draw-metal-overlay)))
                                 (cond
                                   [image
                                    (set! image-info (gpu-image-info image))
                                    (close-metal-fixture! f)
                                    (set! bytes (gpu-image->rgba-bytes image #:premultiplied? #t))]
                                   [else (set! bytes (metal-fixture-readback f))])
                                 (unless (bytes=? bytes (metal-pattern (eq? mode 'surface)))
                                   (error 'metal-interop-doctor "independent pixel oracle failed"))
                                 (when (< ordinal 2)
                                   (define name (format "cycle-~a-context-~a-~a.png" cycle slot mode))
                                   (define im (rgba-bytes->image 37 29 bytes #:premultiplied? #t))
                                   (set! pending (cons (cons im name) pending))
                                   (set! captures (cons (hasheq 'cycle cycle 'context slot 'ordinal ordinal
                                     'mode (symbol->string mode) 'png name 'width 37 'height 29) captures)))
                                 (set! handoffs (cons (hasheq 'ordinal ordinal 'mode (symbol->string mode)
                                   'handoff (gpu-external-texture-info t) 'image image-info
                                   'producer_closed_before_skia_readback (eq? mode 'copy)
                                   'independent_consumer_readback (eq? mode 'surface)
                                   'pixels_verified #t 'io_events (reverse (unbox ledger))) handoffs)))
                               (lambda () (when image (skia-close! image)))))))))
                   (set! rows (cons (hasheq 'context slot 'initial initial 'handoffs (reverse handoffs)) rows))))
               (lambda () (close-gpu-contexts! contexts gpu-context-close!)))
             (define finals (map gpu-context-info contexts))
             (for-each check-gpu-teardown! finals)
             (set! cycles (cons (hasheq 'cycle cycle 'contexts
               (for/list ([row (in-list (reverse rows))] [final (in-list finals)])
                 (hash-set row 'final final))) cycles))
             (printf "Metal interop cycle ~a: two contexts, 48 handoffs and clean teardown\n" cycle))
           ;; Real CPU-owned images are encoded only after all GPU contexts
           ;; close. A report cannot substitute for the retained pixel files.
           (for ([entry (in-list pending)])
             (save-image (car entry) (build-path directory (cdr entry)) 'png #:exists 'replace))
           (emit (hash-set* base 'status "passed" 'error #f
             'native_cases gpu-metal-interop-native-test-count 'native_failures failures
             'suite_contexts suite-closed 'cycles (reverse cycles)
             'captures (for/list ([c (in-list (reverse captures))])
                         (hash-set c 'encoded_after_context_teardown #t))
             'sdk_texture_getters_verified #t 'typed_swizzle_return_verified #t
             'producer "independent-metal-sdk-fixture" 'consumer "independent-metal-command-queue"
             'interop_symbols (metal-interop-native-inventory)))
           0)
         (lambda () (for ([entry (in-list pending)]) (skia-close! (car entry)))))])))
(module+ main
  (define directory #f) (define fixture #f) (define timeout? #f)
  (command-line #:once-each
    [("--directory") p "Fresh evidence directory" (set! directory (string->path p))]
    [("--fixture") p "Independent native test fixture" (set! fixture (string->path p))]
    [("--timeout-case") "Isolated expected-timeout test" (set! timeout? #t)]
    #:args () (void))
  (unless (and directory fixture) (error 'metal-interop-doctor "--directory and --fixture required"))
  (exit (gpu-metal-interop-doctor! directory fixture #:timeout-case? timeout?)))
