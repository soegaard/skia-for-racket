#lang racket/base
(require racket/cmdline racket/file racket/list json rackunit rackunit/text-ui
         "../main.rkt" "../gpu.rkt" "../gpu-egl.rkt" "../private/gpu-io-trace.rkt"
         "integer-pixel-fixtures.rkt")
(module+ main
  (define backend 'auto) (define adapter 'hardware) (define directory #f) (define token #f)
  (command-line #:once-each
    [("--backend") value "auto, egl, metal, direct3d" (set! backend (string->symbol value))]
    [("--adapter") value "hardware or warp" (set! adapter (string->symbol value))]
    [("--directory") value "New evidence directory" (set! directory value)]
    [("--token") value "Invocation identity" (set! token value)] #:args () (void))
  (unless (and directory token) (error 'integer-pixel-gpu "--directory and --token required"))
  (when (directory-exists? directory) (error 'integer-pixel-gpu "evidence directory already exists"))
  (make-directory* directory)
  (when (eq? backend 'auto)
    (set! backend (case (system-type 'os) [(macosx) 'metal] [(windows) 'direct3d] [else 'egl])))
  (define ctx
    (case backend [(egl) (make-egl-gpu-context)]
      [(metal) (make-gpu-context #:backend 'metal)]
      [(direct3d) (make-gpu-context #:backend 'direct3d #:adapter adapter)]
      [else (error 'integer-pixel-gpu "unsupported backend")]))
  (define frames 0) (define reads 0) (define draw-reads 0) (define rejections 0)
  (define rows '()) (define failures 0)
  (define (read-count ledger)
    (count (lambda (entry) (equal? (hash-ref entry 'kind #f) "readback")) (unbox ledger)))
  (dynamic-wind void
    (lambda ()
      (call-with-gpu-context ctx
        (lambda ()
          (set! failures
            (run-tests
              (test-suite "Integer storage -> explicit RGBA upload -> GPU draw/readback"
                (test-case "seven source formats, guarded destination layout, no hidden readback"
                  (for ([format (in-vector integer-pixel-formats)])
                    (with-skia ([cpu (make-integer-fixture-image format)]
                                [image (gpu-upload-image ctx cpu)]
                                [surface (make-gpu-surface ctx 80 64)]
                                [readback (make-raster-buffer-from-info (make-image-info 80 64))]
                                [wrong (make-raster-buffer-from-info
                                         (make-image-info 80 64 #:color-type 'gray-8 #:alpha-type 'opaque))])
                      (skia-close! cpu)
                      (define ledger (box '()))
                      (parameterize ([current-gpu-io-ledger ledger])
                        (canvas-clear! (surface-canvas surface) 'white)
                        (draw-integer-fixture (surface-canvas surface) image #:scale 1))
                      (set! draw-reads (+ draw-reads (read-count ledger)))
                      (check-equal? (read-count ledger) 0)
                      ;; A wrong bpp must never get past the transfer lease.
                      (define before (raster-buffer->storage-bytes wrong))
                      (check-exn exn:fail? (lambda () (gpu-surface-read-raster-buffer! surface wrong)))
                      (check-equal? (raster-buffer->storage-bytes wrong) before)
                      (set! rejections (add1 rejections))
                      (parameterize ([current-gpu-io-ledger ledger])
                        (gpu-surface-read-raster-buffer! surface readback))
                      (check-equal? (read-count ledger) 1)
                      (set! reads (+ reads (read-count ledger)))
                      (define data (raster-buffer->rgba-bytes readback #:premultiplied? #t))
                      (define filename (string-append (symbol->string format) ".rgba"))
                      (call-with-output-file (build-path directory filename)
                        (lambda (out) (write-bytes data out)) #:exists 'error)
                      (set! rows (cons (hasheq 'source_format (symbol->string format) 'file filename) rows))
                      (set! frames (add1 frames)))))))))))
    (lambda () (gpu-context-close! ctx)))
  (define closed? (eq? (gpu-context-state ctx) 'closed))
  (call-with-output-file (build-path directory "gpu.json")
    (lambda (out)
      (write-json (hasheq 'schema 1 'stage "0.70" 'run_token token
                         'status (if (and (zero? failures) closed?) "passed" "failed")
                         'backend (symbol->string backend) 'adapter (symbol->string adapter)
                         'failures failures 'frames frames 'drawing_readbacks draw-reads
                         'inspection_readbacks reads 'layout_rejections rejections
                         'conversion "explicit-rgba-nearest" 'gpu_target_format "rgba-8888"
                         'captures (reverse rows) 'contexts_closed closed?
                         'gui_executed #f 'physical_display_verified #f) out)) #:exists 'error)
  (exit (if (and (zero? failures) closed?) 0 1)))
