#lang racket/base
;; Workloads and measurements; no host/window is initialized by requiring this module.
(require racket/list racket/path (only-in ffi/unsafe void/reference-sink)
         "../main.rkt" "../gpu.rkt" "../private/gpu-performance-util.rkt"
         "../private/gpu-io-trace.rkt" "../examples/gpu-scenes.rkt" "gpu-report.rkt")
(provide benchmark-scenes benchmark-scene! release-stress! benchmark-pattern-pixels)
(define benchmark-scenes '(paths text runtime))
(define (benchmark-pattern-pixels [w 128] [h 128])
  (define bs (make-bytes (* w h 4)))
  (for* ([y (in-range h)] [x (in-range w)])
    (define color (cond [(< y (/ h 2)) (if (< x (/ w 2)) '(255 0 0 255) '(0 255 0 255))]
                        [else (if (< x (/ w 2)) '(0 0 255 255) '(255 255 0 255))]))
    (for ([v (in-list color)] [i (in-naturals (* 4 (+ x (* y w))))]) (bytes-set! bs i v))) bs)
(define (completed context work)
  (define io (box '()))
  (define timing
    (parameterize ([current-gpu-io-ledger io])
      (measure-completed work (lambda () (gpu-flush! context))
                         (lambda () (gpu-submit! context #:wait? #f))
                         (lambda () (gpu-wait! context)))))
  (hash-set timing 'io_events (reverse (unbox io))))
(define (benchmark-scene! context name config prefix)
  (define width (hash-ref config 'width)) (define height (hash-ref config 'height))
  (define n (hash-ref config 'samples))
  (define (record)
    (call-with-picture width height
      (lambda (c)
        (canvas-scale! c (/ width gpu-scene-width) (/ height gpu-scene-height))
        (draw-gpu-scene c name))))
  (define authoring
    (for/list ([i (in-range n)])
      (define-values (pic row) (measure-one record))
      (skia-close! pic) row))
  ;; This measures host-side SkSL effect construction, not driver compilation.
  (define compilation
    (if (eq? name 'runtime)
        (for/list ([i (in-range n)])
          (define-values (e row)
            (measure-one (lambda () (make-runtime-effect
              "half4 main(float2 p) { return half4(0.5+0.5*sin(p.x*0.01),0.3,0.6,1); }"))))
          (skia-close! e) row) '()))
  (define detached #f)
  (define result #f)
  (define cpu-file (string-append prefix "." (symbol->string name) ".cpu.png"))
  (define gpu-file (string-append prefix "." (symbol->string name) ".gpu.png"))
  (define (base p) (path->string (file-name-from-path (string->path p))))
  (with-skia ([picture (record)] [cpu (make-surface width height)])
    (define cpu-times
      (for/list ([i (in-range n)])
        (define-values (_ row)
          (measure-one (lambda () (draw-picture (surface-canvas cpu) picture)))) row))
    (save-png cpu cpu-file #:exists 'replace)
    (call-with-gpu-context context
      (lambda ()
        (gpu-set-cache-limit! context (hash-ref config 'cache_limit_bytes))
        (with-skia ([surface (make-gpu-surface context width height #:sample-count (hash-ref config 'sample_count))])
          (define target (gpu-surface-info surface))
          (define (replay) (draw-picture (surface-canvas surface) picture))
          (define first (completed context replay))
          (define warmups (for/list ([i (in-range (hash-ref config 'warmup))]) (completed context replay)))
          (define replays (for/list ([i (in-range n)]) (completed context replay)))
          (define pattern (benchmark-pattern-pixels))
          (define upload-samples
            (for/list ([i (in-range n)])
              ;; A new CPU identity for every sample prevents a repeated-image
              ;; cache hit from masquerading as a fresh upload measurement.
              (with-skia ([source (rgba-bytes->image 128 128 pattern)])
                (define uploaded #f)
                (dynamic-wind void
                  (lambda ()
                    (define row (completed context (lambda () (set! uploaded (gpu-upload-image context source)))))
                    (unless (equal? (gpu-image->rgba-bytes uploaded) pattern)
                      (error 'gpu-performance "upload roundtrip pixel mismatch"))
                    (hash-set* row 'fresh_cpu_identity #t 'width 128 'height 128 'bytes (* 128 128 4)
                                    'image (gpu-image-info uploaded) 'pixels_verified #t))
                  (lambda () (when uploaded (skia-close! uploaded)) (gpu-drain-releases! context))))))
          (gpu-wait! context)
          (define reference-readback (gpu-surface->rgba-bytes surface))
          (define download-samples
            (for/list ([i (in-range n)])
              ;; Source is already complete; the public readback's own wait,
              ;; allocation and CPU copies remain INCLUDED in the measurement.
              (gpu-wait! context)
              (define io (box '()))
              (define-values (bytes row)
                (parameterize ([current-gpu-io-ledger io])
                  (measure-one (lambda () (gpu-surface->rgba-bytes surface)))))
              (unless (and (= (bytes-length bytes) (* width height 4)) (equal? bytes reference-readback))
                (error 'gpu-performance "readback size or stable-source pixel mismatch"))
              (hash-set* row 'bytes (bytes-length bytes) 'source_precompleted #t 'pixels_verified #t
                              'io_events (reverse (unbox io)))))
          (set! detached (gpu-surface->raster-image surface))
          (set! result
            (hasheq 'name (symbol->string name) 'scene_version "gpu-scenes-0.39/v1"
                    'logical_size (list gpu-scene-width gpu-scene-height) 'target target
                    'authoring_recording authoring 'sksl_effect_construction compilation
                    'first_use first 'warmup_completed (length warmups) 'warmup_replay warmups
                    'warm_replay replays 'cpu_raster cpu-times 'upload upload-samples 'readback download-samples
                    'cpu_image (base cpu-file) 'gpu_image (base gpu-file)
                    'first_use_scope "first picture replay in a new Ganesh context; OS/driver caches uncontrolled"
                    'isolated_driver_compile_ms #f 'cache_after (gpu-cache-info context)))))))
  ;; The caller closes the context before invoking this encoder; this tests the
  ;; detached image boundary without mixing encoding with readback latency.
  (values result detached gpu-file))

(define (await-retirement! context expected weak)
  (define deadline (+ (current-inexact-monotonic-milliseconds) 5000))
  (let loop ()
    (collect-garbage) (sleep 0.01)
    (call-with-gpu-context context (lambda () (gpu-drain-releases! context)))
    (define info (gpu-context-info context))
    (cond [(and (= (hash-ref info 'live_children) expected)
                (zero? (hash-ref info 'pending_releases))
                (andmap (lambda (w) (not (weak-box-value w))) weak)) (void)]
          [(>= (current-inexact-monotonic-milliseconds) deadline)
           (error 'gpu-release-stress "GC/owner draining failed to retire temporary wrappers: ~a" info)]
          [else (loop)])))
(define (release-stress! context config)
  (define target #f) (define checkpoints '()) (define weak '()) (define dropped 0)
  (define before #f) (define highwater 0)
  (define width (hash-ref config 'width)) (define height (hash-ref config 'height))
  (define source (rgba-bytes->image 128 128 (benchmark-pattern-pixels)))
  (dynamic-wind void
    (lambda ()
      (call-with-gpu-context context
        (lambda ()
          (gpu-set-cache-limit! context (hash-ref config 'cache_limit_bytes))
          (set! target (make-gpu-surface context width height))
          (gpu-wait! context) (gpu-free-resources! context) (gpu-wait! context) (gpu-purge-unlocked! context)
          (set! before (gpu-cache-info context))))
      (for ([batch (in-range (quotient (hash-ref config 'frames) 30))])
        (define io (box '()))
        (parameterize ([current-gpu-io-ledger io])
          (call-with-gpu-context context
            (lambda ()
              (for ([i (in-range 30)])
                (with-skia ([image (gpu-upload-image context source)]
                            [shader (make-image-shader image)]
                            [paint (make-paint #:shader shader)]
                            [picture (call-with-picture 128 128 (lambda (c) (draw-rect c 0 0 128 128 paint)))])
                  ;; Retained replay must survive closing its original wrappers.
                  (skia-close! paint) (skia-close! shader) (skia-close! image)
                  (draw-picture (surface-canvas target) picture))
                (when (zero? (modulo i 10))
                  (define abandoned-wrapper (gpu-surface-snapshot target))
                  (set! weak (cons (make-weak-box abandoned-wrapper) weak))
                  (set! dropped (add1 dropped)))
                (set! highwater (max highwater (hash-ref (gpu-context-info context) 'live_children)))
                (gpu-flush-and-submit! context)))))
        ;; Queue completion is a BATCH boundary, not a readback per frame.
        (call-with-gpu-context context (lambda () (gpu-wait! context)))
        (define pressure (make-bytes (hash-ref config 'cpu_pressure_bytes) 17))
        (void/reference-sink pressure) (set! pressure #f)
        (await-retirement! context 1 weak) (set! weak '())
        (define cache #f)
        (call-with-gpu-context context
          (lambda ()
            (gpu-set-cache-limit! context (if (even? batch) 0 (hash-ref config 'cache_limit_bytes)))
            (gpu-perform-deferred-cleanup! context 0)
            (gpu-free-resources! context) (gpu-wait! context) (gpu-purge-unlocked! context)
            (set! cache (gpu-cache-info context))))
        (define state (gpu-context-info context))
        (check-resource-envelope! state cache before config 1)
        (set! checkpoints
          (cons (hasheq 'frame (* 30 (add1 batch)) 'context state 'cache cache
                        'weak_wrappers_retired #t 'heap_bytes (current-memory-use)
                        'resident_io (reverse (unbox io))) checkpoints)))
      (define bytes (call-with-gpu-context context (lambda () (gpu-surface->rgba-bytes target))))
      (define positions '((0 0) (127 0) (0 127) (127 127)))
      (define actual (for/list ([xy (in-list positions)])
                       (define offset (* 4 (+ (car xy) (* width (cadr xy)))))
                       (bytes->list (subbytes bytes offset (+ offset 4)))))
      (unless (equal? actual '((255 0 0 255) (0 255 0 255) (0 0 255 255) (255 255 0 255)))
        (error 'gpu-release-stress "retained graph content changed under pressure"))
      (hasheq 'baseline_cache before 'checkpoints (reverse checkpoints) 'frames (hash-ref config 'frames)
              'intentional_gc_wrappers dropped 'max_observed_live_children highwater
              'final_pixel_samples actual 'content_verified #t
              'heap_accounting "Racket managed-memory estimate, diagnostic only; not RSS/VRAM"
              'pressure_kind "bounded CPU allocation and cache-budget pressure, not OS/device loss"))
    (lambda () (when target (skia-close! target)) (skia-close! source))))
