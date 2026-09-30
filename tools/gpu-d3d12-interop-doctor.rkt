#lang racket/base
(require racket/cmdline racket/file racket/path racket/list json rackunit/text-ui
         "../main.rkt" "../gpu.rkt" "../gpu-interop.rkt" "../unsafe/gpu-d3d12.rkt"
         "../tests/gpu-interop-native-test.rkt" "../tests/d3d12-interop-fixture.rkt"
         "../private/gpu-io-trace.rkt" "gpu-report.rkt")
(provide gpu-d3d12-interop-doctor! gpu-d3d12-interop-timeout-doctor!)
(define (publish directory name data)
  (write-gpu-json (build-path directory name) data))
(define (base directory selection index)
  (hasheq 'schema 1 'stage "0.51" 'validation_run (path->string (file-name-from-path directory))
    'os (symbol->string (system-type 'os)) 'architecture (symbol->string (system-type 'arch))
    'racket_version (version) 'vm (symbol->string (system-type 'vm))
    'backend "direct3d" 'adapter_selection (symbol->string selection)
    'adapter_index (if (eq? selection 'warp) #f index)
    'hardware_acceleration_verified #f 'presentation_verified #f 'performance_measured #f
    'resource_state_declarations_verified #f 'zero_copy_claimed #f))
(define (gpu-d3d12-interop-doctor! directory dll selection index)
  (define cycles '()) (define captures '()) (define pending '())
  (define failures #f) (define suite-contexts '())
  (define (report status [error #f])
    (hash-set* (base directory selection index) 'status status 'error error
      'native_cases gpu-interop-native-test-count 'native_failures failures
      'sdk_getdesc_call_verified (and (exact-integer? failures) (zero? failures))
      'producer "independent-d3d12-sdk-fixture" 'consumer "independent-direct-command-queue"
      'suite_contexts suite-contexts 'cycles (reverse cycles) 'captures (reverse captures)))
  (define (new-context) (make-gpu-context #:backend 'direct3d #:adapter selection #:adapter-index index))
  (define (keep image name row)
    (set! pending (cons (list image name row) pending)))
  (define (one c cycle slot serial w h)
    (define mode (if (even? serial) 'copy 'surface))
    (define f (make-fixture c w h)) (define handoff #f) (define image #f)
    (define ledger (box '())) (define image-info #f) (define saved #f)
    (define producer-closed? #f) (define observed #f)
    (dynamic-wind void
      (lambda ()
        (set! handoff (interop-handoff c f))
        (when (eq? mode 'copy) (drop-fixture-texture f))
        (parameterize ([current-gpu-io-ledger ledger])
          (if (eq? mode 'copy)
              (set! image (gpu-import-image c handoff))
              (call-with-gpu-external-surface c handoff draw-interop-red)))
        (cond
          [(eq? mode 'copy)
           (set! image-info (gpu-image-info image))
           (unless (hash-ref image-info 'texture_backed) (error 'interop-doctor "imported image is not GPU-backed"))
           ;; No original producer COM reference remains while Skia consumes its
           ;; own returned image. Close the fixture before validation readback.
           (close-fixture f) (set! f #f) (set! producer-closed? #t)
           (set! observed (gpu-image->rgba-bytes image))
           (when (< serial 2) (set! saved (gpu-image->raster-image image)))]
          [else
           ;; Separate native queue, not Skia readPixels and not a Skia-created
           ;; substitute texture. Entry state is the promised outgoing state.
           (set! observed (fixture-readback f #x800 w h))
           (when (< serial 2) (set! saved (rgba-bytes->image w h observed #:premultiplied? #t)))])
        (unless (bytes=? observed (if (eq? mode 'copy) (interop-pattern w h) (interop-red w h)))
          (error 'interop-doctor "independent producer/consumer pixels disagree"))
        (define row
          (hasheq 'ordinal serial 'mode (symbol->string mode) 'width w 'height h
            'handoff (gpu-external-texture-info handoff) 'io_events (reverse (unbox ledger))
            'pixels_verified #t 'image image-info
            'producer_closed_before_skia_readback producer-closed?
            'independent_consumer_readback (eq? mode 'surface)))
        (when saved
          (define name (format "cycle-~a-context-~a-~a.png" cycle slot mode))
          (keep saved name (hasheq 'cycle cycle 'context slot 'ordinal serial
                                  'mode (symbol->string mode) 'width w 'height h))
          (set! saved #f))
        row)
      (lambda ()
        (when saved (skia-close! saved))
        (when image (skia-close! image))
        (when handoff (gpu-external-texture-close! handoff))
        (gpu-drain-releases! c)
        (when f (close-fixture f)))))
  (with-handlers ([(lambda (_) #t)
    (lambda (e)
      (publish directory "interop.diagnostic.json"
        (report "failed" (if (exn? e) (exn-message e) (format "~s" e))))
      (eprintf "Direct3D interop failed: ~a\n" e) 1)])
    (load-interop-fixture dll)
    (dynamic-wind void
      (lambda ()
        (define a #f) (define b #f)
        (dynamic-wind void
          (lambda ()
            (set! a (new-context)) (set! b (new-context))
            (set! failures (run-tests (make-gpu-interop-native-tests a b)))
            (unless (zero? failures) (error 'interop-doctor "native interop suite failed")))
          (lambda () (close-gpu-contexts! (list b a) gpu-context-close!)))
        (set! suite-contexts (list (gpu-context-info a) (gpu-context-info b)))
        (for-each check-gpu-teardown! suite-contexts)
        (for ([cycle (in-range 3)])
          (define pair '()) (define rows '())
          (dynamic-wind void
            (lambda ()
              (set! pair (list (new-context)))
              (set! pair (append pair (list (new-context))))
              (for ([c (in-list pair)] [slot (in-naturals)])
                (define initial (gpu-context-info c))
                (define w (if (zero? slot) 37 67)) (define h (if (zero? slot) 29 41))
                (define handoffs
                  (for/list ([serial (in-range 24)])
                    (define row (call-with-gpu-context c (lambda () (one c cycle slot serial w h))))
                    (define info (gpu-context-info c))
                    (unless (and (zero? (hash-ref info 'live_children))
                                 (zero? (hash-ref info 'pending_releases))
                                 (zero? (hash-ref info 'failed_releases)))
                      (error 'interop-doctor "handoff leaked a context resource"))
                    row))
                (set! rows (cons (hasheq 'context slot 'initial initial 'handoffs handoffs) rows))))
            (lambda () (close-gpu-contexts! pair gpu-context-close!)))
          (define contexts
            (for/list ([row (in-list (reverse rows))] [c (in-list pair)])
              (define final (gpu-context-info c)) (check-gpu-teardown! final)
              (hash-set row 'final final)))
          (set! cycles (cons (hasheq 'cycle cycle 'contexts contexts) cycles))
          (printf "Interop cycle ~a: two contexts, 48 handoffs, explicit state return and cleanup passed\n" cycle))
        ;; Detached images are deliberately encoded only after ALL six stress
        ;; contexts are closed; temporary image wrappers are tracked until then.
        (for ([entry (in-list (reverse pending))])
          (save-image (car entry) (build-path directory (cadr entry)) 'png #:exists 'replace)
          (set! captures (cons (hash-set* (caddr entry) 'png (cadr entry)
                                          'encoded_after_context_teardown #t) captures)))
        (publish directory "interop.diagnostic.json" (report "passed")) 0)
      (lambda () (for ([entry (in-list pending)]) (skia-close! (car entry)))))))
(define (gpu-d3d12-interop-timeout-doctor! directory dll selection index)
  ;; Disposable child: intentional quarantine, not a leak-free success. It
  ;; exits normally; no SIGABRT, core dump or Crash Reporter fixture.
  (load-interop-fixture dll)
  (define c (make-gpu-context #:backend 'direct3d #:adapter selection #:adapter-index index))
  (define caught #f) (define t #f)
  (call-with-gpu-context c
    (lambda ()
      (define f (make-fixture c)) (define fence (fixture-unsignaled f))
      (dynamic-wind void
        (lambda ()
          (set! t (make-d3d12-external-texture c (fixture-texture f)
                    #:producer-fence fence #:producer-value 1 #:timeout-ms 25
                    #:incoming-state 'pixel-shader-resource #:outgoing-state 'copy-source))
          (with-handlers ([exn:fail? (lambda (e) (set! caught (exn-message e)))])
            (define unexpected (gpu-import-image c t))
            (skia-close! unexpected)))
        (lambda () (fixture-release fence) (close-fixture f)))))
  (unless (and caught (regexp-match? #rx"fence timeout" caught))
    (error 'interop-timeout "expected a specific native fence timeout, got ~s" caught))
  (define n (hash-ref (gpu-external-texture-info t) 'native))
  (define context (gpu-context-info c))
  (unless (and (hash-ref n 'quarantined) (not (hash-ref n 'producer_completion_verified))
               (zero? (hash-ref n 'queue_submissions)) (hash-ref context 'shutdown_requested))
    (error 'interop-timeout "timeout did not fail closed"))
  (publish directory "interop.timeout.json"
    (hash-set* (base directory selection index) 'status "expected-timeout-quarantined"
      'error caught 'native n 'context context 'normal_process_exit #t
      'intentional_retention_until_process_exit #t 'graphics_handoff_submitted #f))
  0)
(module+ main
  (define directory #f) (define dll #f) (define selection 'warp) (define index 0) (define timeout? #f)
  (command-line #:once-each
    [("--directory") p "Fresh evidence directory" (set! directory (string->path p))]
    [("--fixture") p "Independent Windows SDK producer DLL" (set! dll p)]
    [("--adapter") p "warp or hardware" (set! selection (string->symbol p))]
    [("--adapter-index") p "Hardware enumeration index" (set! index (string->number p))]
    [("--timeout-case") "Run only disposable expected-timeout child" (set! timeout? #t)]
    #:args () (void))
  (unless (and directory dll) (error 'interop-doctor "--directory and --fixture are required"))
  (exit ((if timeout? gpu-d3d12-interop-timeout-doctor! gpu-d3d12-interop-doctor!) directory dll selection index)))
