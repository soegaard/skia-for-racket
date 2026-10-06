#lang racket/base
(require racket/cmdline racket/file racket/list racket/path json rackunit rackunit/text-ui
         "../main.rkt" "../gpu.rkt" "../gpu-egl.rkt" "../private/gpu-io-trace.rkt"
         "float-pixel-fixtures.rkt")
(module+ main
  (define backend 'auto) (define adapter 'hardware) (define report-path #f) (define token #f)
  (command-line #:once-each
    [("--backend") b "auto, egl, metal, direct3d" (set! backend (string->symbol b))]
    [("--adapter") a "hardware or warp" (set! adapter (string->symbol a))]
    [("--report") p "New report file" (set! report-path p)]
    [("--token") t "Invocation identity" (set! token t)] #:args () (void))
  (unless (and report-path token) (error 'float-pixel-gpu "--report and --token required"))
  (when (eq? backend 'auto)
    (set! backend (case (system-type 'os) [(macosx) 'metal] [(windows) 'direct3d] [else 'egl])))
  (define context
    (case backend [(egl) (make-egl-gpu-context)] [(metal) (make-gpu-context #:backend 'metal)]
      [(direct3d) (make-gpu-context #:backend 'direct3d #:adapter adapter)]
      [else (error 'float-pixel-gpu "unsupported backend")]))
  (define failures 0) (define captures '()) (define rejected 0)
  (define drawing-reads 0) (define inspection-reads 0)
  (define (reads ledger) (count (lambda (e) (equal? (hash-ref e 'kind #f) "readback")) (unbox ledger)))
  (define directory (path-only (path->complete-path report-path)))
  (dynamic-wind void
    (lambda ()
      (call-with-gpu-context context
        (lambda ()
          (set! failures
            (run-tests
              (test-suite "Float colors on existing RGBA GPU targets"
                (test-case "six native shader and by-value clear scenes without hidden readback"
                  (for ([scene (in-list float-scene-names)])
                    (with-skia ([surface (make-gpu-surface context 64 32)])
                      (define ledger (box '()))
                      (parameterize ([current-gpu-io-ledger ledger])
                        (canvas-clear! (surface-canvas surface) 'white)
                        (draw-float-scene scene (surface-canvas surface)))
                      (set! drawing-reads (+ drawing-reads (reads ledger)))
                      (check-equal? (reads ledger) 0)
                      (define pixels (parameterize ([current-gpu-io-ledger ledger])
                                       (gpu-surface->rgba-bytes surface #:premultiplied? #t)))
                      (check-equal? (reads ledger) 1)
                      (set! inspection-reads (+ inspection-reads (reads ledger)))
                      (define name (string-append (symbol->string scene) ".rgba"))
                      (call-with-output-file (build-path directory name)
                        (lambda (o) (write-bytes pixels o)) #:exists 'error)
                      (set! captures (cons (hasheq 'scene (symbol->string scene) 'file name) captures)))))
                (test-case "legacy readback refuses both float destination layouts"
                  (with-skia ([surface (make-gpu-surface context 2 2)])
                    (for ([format-name (in-vector float-pixel-formats)])
                      (with-skia ([buffer (make-raster-buffer-from-info (float-fixture-info format-name 2 2))])
                        (define before (raster-buffer->storage-bytes buffer))
                        (check-exn exn:fail? (lambda () (gpu-surface-read-raster-buffer! surface buffer)))
                        (check-equal? (raster-buffer->storage-bytes buffer) before)
                        (set! rejected (add1 rejected))))))))))))
    (lambda () (gpu-context-close! context)))
  (define closed? (eq? (gpu-context-state context) 'closed))
  (call-with-output-file report-path
    (lambda (o)
      (write-json (hasheq 'schema 1 'stage "0.71" 'run_token token
                    'status (if (and (zero? failures) closed?) "passed" "failed")
                    'backend (symbol->string backend) 'adapter (symbol->string adapter)
                    'failures failures 'captures (reverse captures) 'frames (length captures)
                    'drawing_readbacks drawing-reads 'inspection_readbacks inspection-reads
                    'float_readback_rejections rejected 'context_closed closed?
                    'gpu_target_format "rgba-8888" 'float_gpu_storage_verified #f
                    'hdr_verified #f 'physical_display_verified #f) o)) #:exists 'error)
  (exit (if (and (zero? failures) closed?) 0 1)))
