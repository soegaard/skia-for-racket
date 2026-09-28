#lang racket/base
(require racket/class racket/list racket/path
         "../main.rkt" "../gpu.rkt" "../private/gpu-performance-util.rkt"
         "../private/gpu-io-trace.rkt" "../examples/gpu-presentation-scene.rkt"
         "gpu-performance-options.rkt" "gpu-presentation-host.rkt" "gpu-report.rkt")
(provide gpu-redraw-doctor!)
(define (gpu-redraw-doctor! options)
  (define prefix (hash-ref options 'prefix)) (define backend (hash-ref options 'backend))
  (define config (hash-ref options 'config)) (define started? #f) (define windows '())
  (clear-performance-results! prefix)
  (define sources (performance-source-fingerprints))
  (define run-id (or (getenv "SKIA_GPU_VALIDATION_RUN") (format "redraw-~a" (current-inexact-milliseconds))))
  (define (publish status message)
    (write-gpu-json (string->path (string-append prefix ".diagnostic.json"))
      (hasheq 'schema_version 1 'stage "0.45" 'kind "redraw" 'status status 'message message
              'backend (symbol->string backend) 'validation_run run-id 'config config
              'os (symbol->string (system-type 'os)) 'architecture (symbol->string (system-type 'arch))
              'racket_version (version) 'workload_sources sources 'required (hash-ref options 'required)
              'require_hardware (hash-ref options 'hardware) 'windows (reverse windows)
              'clock "current-inexact-monotonic-milliseconds"
              'timing_scope "host presenter call including acquisition, authoring, submission, swap/backpressure; not display latency"
              'performance_measured (equal? status "passed") 'visible_pixels_verified #f
              'display_latency_measured #f 'speedup_claimed #f)))
  (with-handlers
      ([exn:fail:gpu:unavailable?
        (lambda (e) (publish (if started? "error" "unavailable") (exn-message e))
          (eprintf "Redraw unavailable/error: ~a\n" (exn-message e))
          (if (and (not started?) (not (hash-ref options 'required))) 0 1))]
       [exn:fail? (lambda (e) (publish "error" (exn-message e))
                    (eprintf "Redraw ERROR: ~a\n" (exn-message e)) 1)])
    (unless (eq? (hash-ref options 'host) 'gui) (error 'gpu-redraw "presentation requires a GUI host"))
    (call-on-presentation-handler
      (lambda (gpu-window% settle)
        (for ([cycle (in-range (hash-ref config 'cycles))])
          (define hosts '())
          (define last-frames (make-vector 2 #f)) (define last-canvases (make-vector 2 #f))
          (define last-times (make-vector 2 #f)) (define counts (make-vector 2 0))
          (define (render i f)
            (vector-set! last-frames i f) (vector-set! last-canvases i (gpu-frame-canvas f))
            (define-values (_ row) (measure-one (lambda () (draw-presentation-scene f))))
            (vector-set! last-times i row) (vector-set! counts i (add1 (vector-ref counts i))))
          (dynamic-wind void
            (lambda ()
              (for ([i (in-range 2)])
                (define w (new gpu-window% [label (format "Skia 0.45 / ~a / ~a" backend i)]
                               [width (hash-ref config 'width)] [height (hash-ref config 'height)]
                               [backend backend] [on-error raise] [automatic? #f] [render (lambda (f) (render i f))]))
                (set! hosts (append hosts (list w))) (send w show #t))
              (settle)
              (define ps (map (lambda (w) (send w get-gpu-presenter)) hosts))
              (set! started? #t)
              (for ([w (in-list hosts)] [p (in-list ps)] [i (in-naturals)])
                (define context (gpu-presenter-context p)) (define initial (gpu-context-info context))
                (when (and (hash-ref options 'hardware)
                           (not (equal? (hash-ref initial 'renderer_class "unclassified") "hardware-reported")))
                  (error 'gpu-redraw "hardware-reported renderer required"))
                (define skips 0)
                (define (draw-now)
                  (let loop ([remaining 8])
                    (define io (box '()))
                    (define-values (result row)
                      (parameterize ([current-gpu-io-ledger io])
                        (measure-one (lambda () (gpu-presenter-render! p)))))
                    (cond
                      [(eq? result 'present-requested)
                       (define f (vector-ref last-frames i))
                       (unless (and (gpu-frame-expired? f) (skia-closed? (vector-ref last-canvases i)))
                         (error 'gpu-redraw "frame/canvas escaped its scope"))
                       (hash-set* row 'callback (vector-ref last-times i) 'frame (gpu-frame-info f)
                                  'frame_expired #t 'canvas_expired #t 'io_events (reverse (unbox io)))]
                      [(and (eq? result 'skipped) (positive? remaining))
                       (set! skips (add1 skips)) (settle) (loop (sub1 remaining))]
                      [else (error 'gpu-redraw "frame could not be presented: ~a" result)])))
                (define (cache-check)
                  (call-with-gpu-context context
                    (lambda ()
                      (gpu-set-cache-limit! context (hash-ref config 'cache_limit_bytes))
                      (gpu-free-resources! context) (gpu-wait! context) (gpu-purge-unlocked! context)
                      (gpu-cache-info context))))
                (define warm (draw-now)) (define baseline (cache-check))
                (define rows '()) (define checkpoints '())
                (for ([batch (in-range (quotient (hash-ref config 'frames) 30))])
                  (send w resize (+ (hash-ref config 'width) (* 40 (modulo batch 3)))
                                 (+ (hash-ref config 'height) (* 30 (modulo batch 3))))
                  (settle)
                  (for ([j (in-range 30)]) (set! rows (cons (draw-now) rows)))
                  ;; Exercise actual queued, coalesced redraws without counting
                  ;; deliberate sleep/yield time as a rendering measurement.
                  (define old (vector-ref counts i)) (define queued-io (box '()))
                  (parameterize ([current-gpu-io-ledger queued-io])
                    (for ([j (in-range 4)]) (gpu-presenter-request-render! p))
                    (settle))
                  (unless (= (vector-ref counts i) (add1 old)) (error 'gpu-redraw "redraw coalescing failed"))
                  (define cache (cache-check)) (collect-garbage)
                  (define info (gpu-context-info context))
                  (check-resource-envelope! info cache baseline config 0)
                  (define presenter (gpu-presenter-info p))
                  (set! checkpoints
                    (cons (hasheq 'frame (* 30 (add1 batch)) 'context info 'cache cache
                                  'presenter presenter 'queued_requests 4 'queued_callbacks 1
                                  'queued_io (reverse (unbox queued-io))
                                  'heap_bytes (current-memory-use)) checkpoints)))
                (send w close-gpu)
                (define closed (gpu-presenter-info p))
                (check-gpu-teardown! (hash-ref (hash-ref closed 'adapter) 'context))
                (set! windows
                  (cons (hasheq 'cycle cycle 'window i 'initial_context initial
                                'warmup warm 'baseline_cache baseline 'frames (reverse rows)
                                'checkpoints (reverse checkpoints) 'retry_skips skips
                                'render_callbacks (vector-ref counts i) 'closed_presenter closed) windows))
                (printf "~a: redraw cycle ~a/window ~a, ~a frames; queued redraw and cleanup verified\n"
                        backend (add1 cycle) i (hash-ref config 'frames))))
            (lambda () (close-gpu-contexts! hosts (lambda (w) (send w close-gpu))))))))
    (publish "passed" #f) 0))
(module+ main
  (exit (gpu-redraw-doctor! (read-performance-options "output/redraw-0.45"))))
