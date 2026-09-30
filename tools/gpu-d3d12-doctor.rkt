#lang racket/base
(require json racket/cmdline racket/file racket/path racket/list rackunit/text-ui
         "../main.rkt" "../gpu.rkt" "../private/gpu-io-trace.rkt"
         "../tests/gpu-surface-native-test.rkt" "../tests/gpu-image-native-test.rkt"
         "../tests/gpu-cache-native-test.rkt")
(provide d3d12-doctor!)
(define (d3d12-doctor! directory selection index)
  (define run-id (path->string (file-name-from-path (simplify-path directory))))
  (define cycles '())
  (define contexts '())
  (define counts (hasheq))
  (define (publish status [message #f])
    (call-with-output-file (build-path directory "d3d12.diagnostic.json")
      (lambda (out)
        (write-json (hasheq 'schema 1 'stage "0.48" 'status status 'error message
                             'validation_run run-id 'adapter_selection (symbol->string selection)
                             'racket_version (version) 'os (symbol->string (system-type 'os))
                             'architecture (symbol->string (system-type 'arch))
                             'test_counts counts 'cycles (reverse cycles)
                             'window_created #f 'presentation_verified #f
                             'hardware_acceleration_verified #f 'performance_measured #f) out))
      #:exists 'truncate/replace))
  (define (own!)
    (define c (make-gpu-context #:backend 'direct3d #:adapter selection #:adapter-index index))
    (set! contexts (cons c contexts)) c)
  (define (quiescent! c)
    (call-with-gpu-context c void)
    (define info (gpu-context-info c))
    (unless (for/and ([key '(live_children pending_releases failed_releases)]) (zero? (hash-ref info key)))
      (error 'd3d12-doctor "context did not become quiescent: ~a" info)))
  (publish "running")
  (with-handlers ([exn:fail?
                   (lambda (e)
                     (for ([c (in-list contexts)])
                       (with-handlers ([exn:fail? (lambda (_) (void))])
                         (gpu-context-abandon! c) (gpu-context-close! c)))
                     (publish "failed" (exn-message e)) (raise e))])
    (unless (and (eq? (system-type 'os) 'windows) (eq? (system-type 'arch) 'x86_64))
      (error 'd3d12-doctor "requires Windows x64"))
    (for ([cycle (in-range 3)])
      (define gpu (own!))
      (define other (own!))
      (define initial (gpu-context-info gpu))
      (define other-initial (gpu-context-info other))
      (when (zero? cycle)
        (define surface-failures (run-tests (make-gpu-surface-native-tests gpu other)))
        (define image-failures (run-tests (make-gpu-image-native-tests gpu other)))
        (define cache-failures (run-tests (make-gpu-cache-native-tests gpu other)))
        (set! counts (hasheq 'surface 33 'image gpu-image-native-test-count 'cache gpu-cache-native-test-count
                            'surface_failures surface-failures 'image_failures image-failures 'cache_failures cache-failures))
        (unless (zero? (+ surface-failures image-failures cache-failures))
          (error 'd3d12-doctor "shared D3D12 native suites failed")))
      (quiescent! gpu) (quiescent! other)
      (define ledger (box '()))
      (define target-info #f)
      (define image-info #f)
      (define cpu-file (format "cycle-~a-cpu.png" cycle))
      (define gpu-file (format "cycle-~a-gpu.png" cycle))
      (define detached-file (format "cycle-~a-detached.png" cycle))
      (define detached
        (parameterize ([current-gpu-io-ledger ledger])
          (call-with-gpu-context gpu
            (lambda ()
              (with-skia ([cpu (rgba-bytes->image 8 8 image-test-pixels #:premultiplied? #t)]
                          [s (make-gpu-surface gpu 8 8)]
                          [im (gpu-upload-image gpu cpu)]
                          [shader (make-image-shader im)]
                          [paint (make-paint #:shader shader #:blend-mode 'src #:antialias? #f)]
                          [pic (call-with-picture 8 8 (lambda (c) (draw-paint c paint)))])
                (with-skia ([cpu-surface (make-surface 8 8)])
                  (draw-image (surface-canvas cpu-surface) cpu 0 0 #:sampling 'nearest)
                  (unless (bytes=? (surface->rgba-bytes cpu-surface) image-test-pixels)
                    (error 'd3d12-doctor "CPU reference rendering failed"))
                  (call-with-output-file (build-path directory cpu-file)
                    (lambda (out) (write-bytes (surface->png-bytes cpu-surface) out)) #:exists 'error))
                (set! target-info (gpu-surface-info s))
                (set! image-info (gpu-image-info im))
                ;; The retained picture must keep the texture alive independently.
                (skia-close! paint) (skia-close! shader) (skia-close! im)
                (for ([frame (in-range 180)])
                  (canvas-clear! (surface-canvas s) 'transparent)
                  (draw-picture (surface-canvas s) pic)
                  (gpu-flush-and-submit! gpu) ; no explicit CPU wait on normal frames
                  (when (zero? (modulo (add1 frame) 30))
                    (with-skia ([snap (gpu-surface-snapshot s)] [part (gpu-image-subset snap 0 0 3 4)])
                      (define subset-pixels (gpu-image->rgba-bytes part))
                      (unless (bytes=? subset-pixels (apply bytes-append (make-list 12 (bytes 255 0 0 255))))
                        (error 'd3d12-doctor "GPU snapshot/subset pixels failed")))
                    (gpu-purge-unlocked! gpu)
                    (collect-garbage)))
                (define pixels (gpu-surface->rgba-bytes s))
                (unless (bytes=? pixels image-test-pixels) (error 'd3d12-doctor "GPU pixels differ from exact source"))
                (with-skia ([png-image (rgba-bytes->image 8 8 pixels)])
                  (call-with-output-file (build-path directory gpu-file)
                    (lambda (out) (write-bytes (image->png-bytes png-image) out)) #:exists 'error))
                (gpu-surface->raster-image s))))))
      (quiescent! gpu) (quiescent! other)
      (gpu-context-close! other) (gpu-context-close! gpu)
      (define final (gpu-context-info gpu))
      (define other-final (gpu-context-info other))
      (with-skia ([cpu-detached detached])
        (unless (bytes=? (image->rgba-bytes cpu-detached) image-test-pixels)
          (error 'd3d12-doctor "detached pixels failed after context teardown"))
        (call-with-output-file (build-path directory detached-file)
          (lambda (out) (write-bytes (image->png-bytes cpu-detached) out)) #:exists 'error))
      (set! cycles (cons (hasheq 'cycle cycle 'initial initial 'other_initial other-initial
                                  'final final 'other_final other-final 'target target-info 'image image-info
                                  'frames 180 'cpu_png cpu-file 'gpu_png gpu-file 'detached_png detached-file
                                  'detached_encoded_after_teardown #t 'io (reverse (unbox ledger))) cycles))
      (publish "running"))
    ;; No GUI or swap chain was used. Do not infer physical display pixels.
    (define gui?
      (with-handlers ([exn:fail? (lambda (_) #f)]) (module->namespace 'racket/gui/base) #t))
    (when gui? (error 'd3d12-doctor "offscreen doctor instantiated a GUI"))
    (publish "passed")
    (void)))
(module+ main
  (define directory #f) (define selection 'warp) (define index 0)
  (command-line #:once-each
    [("--directory") path "fresh output directory" (set! directory (path->complete-path path))]
    [("--adapter") name "warp or hardware" (set! selection (string->symbol name))]
    [("--adapter-index") value "hardware DXGI adapter index" (set! index (string->number value))]
    #:args () (void))
  (unless directory (error 'd3d12-doctor "--directory is required"))
  (d3d12-doctor! directory selection index))
