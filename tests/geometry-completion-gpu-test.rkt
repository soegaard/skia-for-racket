#lang racket/base
(require racket/cmdline racket/file racket/list json rackunit rackunit/text-ui
         "../main.rkt" "../gpu.rkt" "../gpu-egl.rkt"
         "../private/gpu-io-trace.rkt" "geometry-completion-fixtures.rkt")
(module+ main
  (define backend 'auto) (define adapter 'hardware) (define report-path #f) (define token #f)
  (command-line #:once-each
    [("--backend") value "auto, egl, metal, direct3d" (set! backend (string->symbol value))]
    [("--adapter") value "hardware or warp" (set! adapter (string->symbol value))]
    [("--report") value "New report file" (set! report-path value)]
    [("--token") value "Invocation identity" (set! token value)] #:args () (void))
  (unless (and report-path token) (error 'geometry-gpu "--report and --token required"))
  (when (eq? backend 'auto)
    (set! backend (case (system-type 'os) [(macosx) 'metal] [(windows) 'direct3d] [else 'egl])))
  (define (create)
    (case backend [(egl) (make-egl-gpu-context)]
      [(metal) (make-gpu-context #:backend 'metal)]
      [(direct3d) (make-gpu-context #:backend 'direct3d #:adapter adapter)]
      [else (error 'geometry-gpu "unsupported backend")]))
  ;; Construction and entry of different domains are never nested.
  (define ctx (create)) (define other #f) (define held #f) (define failures 0)
  (define frames 0) (define readbacks 0) (define drawing-reads 0)
  (define reset-reads 0) (define reset-drawing-reads 0)
  (define completed '())
  (define (reads ledger) (count (lambda (e) (equal? (hash-ref e 'kind #f) "readback")) (unbox ledger)))
  (dynamic-wind void
    (lambda ()
      (set! other (create))
      (call-with-gpu-context ctx
        (lambda ()
          (set! failures
            (run-tests
              (test-suite "GPU geometry and retained paint reset"
                (test-case "seven geometry scenes render without wrapper readback"
                  (for ([name (in-list geometry-scene-names)])
                    (with-skia ([surface (make-gpu-surface ctx geometry-width geometry-height)])
                      (define ledger (box '()))
                      (parameterize ([current-gpu-io-ledger ledger])
                        (canvas-clear! (surface-canvas surface) 'white)
                        (draw-geometry-scene name (surface-canvas surface)))
                      (set! drawing-reads (+ drawing-reads (reads ledger)))
                      (check-equal? (reads ledger) 0)
                      (define pixels (parameterize ([current-gpu-io-ledger ledger])
                        (gpu-surface->rgba-bytes surface #:premultiplied? #t)))
                      (check-equal? (reads ledger) 1)
                      (set! frames (add1 frames)) (set! readbacks (+ readbacks (reads ledger)))
                      (check-geometry-pixels name pixels)
                      (set! completed (cons (symbol->string name) completed)))))
                (test-case "reset detaches paint but not an independently retained mask"
                  (with-skia ([input (rgba-bytes->image 2 2 (make-bytes 16 128))]
                              [image (gpu-upload-image ctx input)] [shader (make-image-shader image)]
                              [mask (make-shader-mask-filter shader)]
                              [paint (make-paint #:mask-filter mask)]
                              [retained (paint-mask-filter paint)])
                    (check-eq? (skia-resource-gpu-context paint) ctx)
                    (paint-set-dither! paint #t)
                    (paint-reset! paint)
                    (check-false (skia-resource-gpu-context paint))
                    (check-false (paint-mask-filter paint))
                    (check-false (paint-dither? paint))
                    (check-eq? (skia-resource-gpu-context retained) ctx))))))))
      ;; Publish one reset paint into a sequential second scope. A zero-failure
      ;; status is not possible when reset leaves its former GPU dependency.
      (set! held
        (call-with-gpu-context ctx
          (lambda ()
            (with-skia ([input (rgba-bytes->image 2 2 (make-bytes 16 128))]
                        [image (gpu-upload-image ctx input)] [shader (make-image-shader image)])
              (define p (make-paint #:shader shader))
              (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! p) (raise e))])
                (paint-reset! p) (paint-set-color! p 'blue) p)))))
      (call-with-gpu-context other
        (lambda ()
          (set! failures (+ failures
            (run-tests
              (test-suite "Reset paint crosses context only after detachment"
                (test-case "second-context draw produces expected pixels"
                  (check-false (skia-resource-gpu-context held))
                  (with-skia ([surface (make-gpu-surface other 8 8)])
                    (define ledger (box '()))
                    (parameterize ([current-gpu-io-ledger ledger])
                      (draw-rect (surface-canvas surface) 0 0 8 8 held))
                    (set! reset-drawing-reads (reads ledger))
                    (check-equal? reset-drawing-reads 0)
                    (define data (parameterize ([current-gpu-io-ledger ledger])
                      (gpu-surface->rgba-bytes surface #:premultiplied? #t)))
                    (set! reset-reads (reads ledger))
                    (check-equal? reset-reads 1)
                    (check-equal? (bytes->list (subbytes data 0 4)) '(0 0 255 255)))))))))))
    (lambda ()
      (dynamic-wind void
        (lambda () (when held (skia-close! held)))
        (lambda ()
          (dynamic-wind void (lambda () (when other (gpu-context-close! other)))
            (lambda () (gpu-context-close! ctx)))))))
  (define closed? (and (eq? (gpu-context-state ctx) 'closed) other (eq? (gpu-context-state other) 'closed)))
  (call-with-output-file report-path
    (lambda (out)
      (write-json (hasheq 'schema 1 'stage "0.67" 'run_token token
        'status (if (and (zero? failures) closed?) "passed" "failed")
        'backend (symbol->string backend) 'adapter (symbol->string adapter)
        'failures failures 'frames frames 'scenes (reverse completed)
        'drawing_readbacks drawing-reads 'inspection_readbacks readbacks
        'reset_drawing_readbacks reset-drawing-reads 'reset_inspection_readbacks reset-reads
        'reset_transfer_test_passed (zero? failures) 'contexts_closed closed?
        'gui_executed #f 'physical_display_verified #f) out)) #:exists 'error)
  (exit (if (and (zero? failures) closed?) 0 1)))
