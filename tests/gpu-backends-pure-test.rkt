#lang racket/base
(require rackunit racket/list json
         "../gpu.rkt" "../private/gpu-backends.rkt"
         "../private/gpu-surface-identity.rkt" "../private/output-executor.rkt")
(provide gpu-backends-pure-tests)
(define (plan backend [generation 7] [render (lambda (w h cs replay consume) (void))])
  (make-output-raster-executor void (lambda (_) (output-raster-plan backend generation #f render))))
(define gpu-backends-pure-tests
  (test-suite
   "Source-only backend policy and production output/metadata boundaries"
   (test-case "implemented backends have stable order"
     (check-equal? (gpu-backends) '(opengl metal direct3d)))
   (test-case "native IDs have one source"
     (check-equal? (map gpu-backend-native-id (gpu-backends)) '(0 2 3)))
   (test-case "predicate returns Booleans, not member tails"
     (for ([b (in-list (gpu-backends))]) (check-eq? (gpu-backend? b) #t))
     (for ([b '(raster cpu vulkan graphite auto #f "direct3d" 3)]) (check-eq? (gpu-backend? b) #f)))
   (test-case "unknown backend declarations reject"
     (for ([b '(raster vulkan auto #f "metal")])
       (check-exn exn:fail? (lambda () (gpu-backend-capabilities b)))))
   (test-case "metadata does not claim native execution"
     (for ([b (in-list (gpu-backends))])
       (define c (gpu-backend-capabilities b))
       (check-equal? (hash-ref c 'scope) "wrapper-declarations")
       (check-equal? (hash-ref c 'runtime_availability) "not-probed")
       (check-false (hash-ref c 'native_probe_performed))
       (check-false (hash-ref c 'hardware_acceleration_verified))
       (check-false (hash-ref c 'visible_pixels_verified))
       (check-false (hash-ref c 'performance_measured))))
   (test-case "capability hashes and nested hashes are immutable"
     (define c (gpu-backend-capabilities 'direct3d))
     (check-true (immutable? c)) (check-true (immutable? (hash-ref c 'features)))
     (check-true (immutable? (hash-ref c 'backend)))
     (check-exn exn:fail? (lambda () (hash-set! c 'native_probe_performed #t))))
   (test-case "declarations serialize as detached JSON"
     (for ([b (in-list (gpu-backends))]) (check-not-exn (lambda () (jsexpr->string (gpu-backend-capabilities b))))))
   (test-case "all three support the common functionality"
     (for* ([b (in-list (gpu-backends))]
            [f '(offscreen images explicit_transfers cache_controls presentation document_executor)])
       (check-true (hash-ref (hash-ref (gpu-backend-capabilities b) 'features) f))))
   (test-case "external resource support remains explicitly asymmetric"
     (check-true (hash-ref (hash-ref (gpu-backend-capabilities 'opengl) 'features) 'external_resource_interop))
     (check-true (hash-ref (hash-ref (gpu-backend-capabilities 'direct3d) 'features) 'external_resource_interop))
     (check-false (hash-ref (hash-ref (gpu-backend-capabilities 'metal) 'features) 'external_resource_interop)))
   (test-case "WARP is a selection declaration, not an availability result"
     (define c (gpu-backend-capabilities 'direct3d))
     (check-equal? (hash-ref c 'software_selection) "explicit-warp")
     (check-equal? (hash-ref c 'runtime_availability) "not-probed"))
   (test-case "all production raster plans accept registered GPUs"
     (for ([b (in-list (gpu-backends))])
       (check-eq? (output-raster-plan-backend (prepare-output-raster (plan b) 'picture)) b)))
   (test-case "CPU raster plan remains unchanged"
     (check-eq? (prepare-output-raster 'cpu 'picture) cpu-output-raster-plan))
   (test-case "unimplemented GPU plan rejects"
     (check-exn exn:fail? (lambda () (prepare-output-raster (plan 'vulkan) 'picture))))
   (test-case "Direct3D needs a real generation"
     (for ([g '(#f #t 0 -1 1.0)])
       (check-exn exn:fail? (lambda () (prepare-output-raster (plan 'direct3d g) 'picture)))))
   (test-case "Direct3D needs a renderer of the protocol arity"
     (check-exn exn:fail? (lambda () (prepare-output-raster (plan 'direct3d 1 #f) 'picture))))
   (test-case "completed GPU plans report one explicit readback"
     (for ([b (in-list (gpu-backends))])
       (define e (plan b))
       (define p (prepare-output-raster e 'picture))
       (define r (output-execution-details e 'completed b #:plan p))
       (check-equal? (hash-ref r 'readback_count) 1)
       (check-equal? (hash-ref r 'transfer) "gpu-to-cpu")
       (check-equal? (hash-ref r 'image_storage) "cpu-owned")
       (check-equal? (hash-ref r 'backend) (symbol->string b))))
   (test-case "planned Direct3D work does not claim completed transfer"
     (define e (plan 'direct3d))
     (define r (output-execution-details e 'prepared 'direct3d #:plan (prepare-output-raster e 'picture)))
     (check-equal? (hash-ref r 'readback_count) 0)
     (check-equal? (hash-ref r 'transfer) "none"))
   (test-case "CPU execution does not fabricate GPU transfer"
     (define r (output-execution-details 'cpu 'completed 'raster #:plan cpu-output-raster-plan))
     (check-equal? (hash-ref r 'readback_count) 0) (check-equal? (hash-ref r 'transfer) "none"))
   (test-case "production metadata helper fills missing backend on every GPU"
     (for ([b (in-list (gpu-backends))])
       (define r (gpu-surface-identity/validated (hasheq 'target_kind "dxgi-back-buffer")
                                                b 9 (gpu-backend-native-id b) 37 29))
       (check-equal? (hash-ref r 'backend) (symbol->string b))
       (check-true (hash-ref r 'context_matches))
       (check-equal? (hash-ref r 'target_kind) "dxgi-back-buffer")))
   (test-case "constructor labels cannot override validated backend and extent"
     (define r (gpu-surface-identity/validated
       (hasheq 'backend "opengl" 'context_generation -1 'native_backend 0
               'context_matches #f 'storage "cpu" 'width 1 'height 1)
       'direct3d 17 3 67 41))
     (check-equal? (map (lambda (k) (hash-ref r k))
                      '(backend context_generation native_backend context_matches storage width height))
                   '("direct3d" 17 3 #t "gpu" 67 41)))
   (test-case "metadata helper rejects mismatched native identity"
     (check-exn exn:fail? (lambda () (gpu-surface-identity/validated (hasheq) 'direct3d 1 0 2 2))))
   (test-case "metadata helper rejects mutable input"
     (check-exn exn:fail? (lambda () (gpu-surface-identity/validated (make-hasheq) 'direct3d 1 3 2 2))))
   (test-case "metadata helper rejects malformed native numbers"
     (for ([n '(#f #t 3.0 -1)])
       (check-exn exn:fail? (lambda () (gpu-surface-identity/validated (hasheq) 'direct3d 1 n 2 2)))))
   (test-case "metadata helper validates generation and dimensions"
     (for ([n '(#f #t 0 -1 1.5)])
       (check-exn exn:fail? (lambda () (gpu-surface-identity/validated (hasheq) 'direct3d n 3 2 2)))
       (check-exn exn:fail? (lambda () (gpu-surface-identity/validated (hasheq) 'direct3d 1 3 n 2)))
       (check-exn exn:fail? (lambda () (gpu-surface-identity/validated (hasheq) 'direct3d 1 3 2 n)))))))
