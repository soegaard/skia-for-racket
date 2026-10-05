#lang racket/base
(require racket/cmdline racket/list json rackunit rackunit/text-ui
         "../main.rkt" "../gpu.rkt" "../gpu-egl.rkt"
         "../private/gpu-io-trace.rkt" "font-query-fixtures.rkt")
(module+ main
  (define backend 'auto) (define adapter 'hardware) (define report-path #f) (define token #f)
  (command-line #:once-each
    [("--backend") value "auto, egl, metal, direct3d" (set! backend (string->symbol value))]
    [("--adapter") value "hardware or warp" (set! adapter (string->symbol value))]
    [("--report") value "New report file" (set! report-path value)]
    [("--token") value "Invocation identity" (set! token value)] #:args () (void))
  (unless (and report-path token) (error 'font-query-gpu "--report and --token required"))
  (unless (memq adapter '(hardware warp)) (error 'font-query-gpu "invalid adapter"))
  (when (eq? backend 'auto)
    (set! backend (case (system-type 'os) [(macosx) 'metal] [(windows) 'direct3d] [else 'egl])))
  (define ctx
    (case backend
      [(egl) (make-egl-gpu-context)]
      [(metal) (make-gpu-context #:backend 'metal)]
      [(direct3d) (make-gpu-context #:backend 'direct3d #:adapter adapter)]
      [else (error 'font-query-gpu "unsupported backend")]))
  (define failures 0) (define frames 0) (define drawing-reads 0) (define inspection-reads 0)
  (define completed '())
  (define (reads ledger)
    (count (lambda (e) (equal? (hash-ref e 'kind #f) "readback")) (unbox ledger)))
  (define scenes-suite
    (test-suite "GPU font mutation, snapshots and batch outlines"
      (test-case "each scene renders without hidden CPU readbacks"
        (for ([scene (in-list font-query-scenes)])
          (with-skia ([surface (make-gpu-surface ctx font-query-width font-query-height)])
            (define ledger (box '()))
            (parameterize ([current-gpu-io-ledger ledger])
              (canvas-clear! (surface-canvas surface) 'white)
              (draw-font-query-scene scene (surface-canvas surface)))
            (set! drawing-reads (+ drawing-reads (reads ledger)))
            (check-equal? (reads ledger) 0)
            (define data
              (parameterize ([current-gpu-io-ledger ledger])
                (gpu-surface->rgba-bytes surface #:premultiplied? #t)))
            (check-equal? (reads ledger) 1)
            (set! inspection-reads (+ inspection-reads (reads ledger)))
            (check-font-query-pixels scene data)
            (set! frames (add1 frames))
            (set! completed (cons (symbol->string scene) completed)))))))
  (dynamic-wind void
    (lambda ()
      (call-with-gpu-context ctx
        (lambda () (set! failures (run-tests scenes-suite)))))
    (lambda () (gpu-context-close! ctx)))
  (define closed? (eq? (gpu-context-state ctx) 'closed))
  (define passed? (and (zero? failures) closed? (= frames (length font-query-scenes))))
  (call-with-output-file report-path
    (lambda (out)
      (write-json (hasheq 'schema 1 'stage "0.68b" 'run_token token
                          'status (if passed? "passed" "failed")
                          'backend (symbol->string backend) 'adapter (symbol->string adapter)
                          'failures failures 'frames frames 'scenes (reverse completed)
                          'drawing_readbacks drawing-reads 'inspection_readbacks inspection-reads
                          'contexts_closed closed? 'gui_executed #f 'physical_display_verified #f) out))
    #:exists 'error)
  (exit (if passed? 0 1)))
