#lang racket/base
(require racket/cmdline racket/file racket/list racket/path json rackunit rackunit/text-ui
         "../main.rkt" "../gpu.rkt" "../gpu-egl.rkt"
         "../private/gpu-io-trace.rkt" "image-operation-fixtures.rkt")
(module+ main
  (define backend 'auto) (define adapter 'hardware) (define report-path #f) (define token #f)
  (command-line #:once-each
    [("--backend") value "auto, egl, metal, direct3d" (set! backend (string->symbol value))]
    [("--adapter") value "hardware or warp" (set! adapter (string->symbol value))]
    [("--report") value "New JSON report" (set! report-path value)]
    [("--token") value "Invocation identity" (set! token value)] #:args () (void))
  (unless (and report-path token) (error 'image-gpu "--report and --token required"))
  (when (eq? backend 'auto)
    (set! backend (case (system-type 'os) [(macosx) 'metal] [(windows) 'direct3d] [else 'egl])))
  (define (create)
    (case backend [(egl) (make-egl-gpu-context)]
      [(metal) (make-gpu-context #:backend 'metal)]
      [(direct3d) (make-gpu-context #:backend 'direct3d #:adapter adapter)]
      [else (error 'image-gpu "unsupported backend")]))
  (define (reads ledger)
    (count (lambda (row) (equal? (hash-ref row 'kind #f) "readback")) (unbox ledger)))
  (define directory (or (path-only (string->path report-path)) (current-directory)))
  (define ctx (create)) (define other #f) (define foreign-filter #f)
  (define rows '()) (define failures 0) (define filter-calls 0)
  (define cpu-rejections 0) (define cross-rejected? #f) (define retained-tested? #f)
  (dynamic-wind void
    (lambda ()
      ;; Construction and entry of different GPU domains are never nested.
      (set! other (create))
      (call-with-gpu-context other
        (lambda ()
          (with-skia ([cpu (make-operation-source)] [gpu (gpu-upload-image other cpu)])
            (set! foreign-filter (make-image-source-filter gpu)))))
      (call-with-gpu-context ctx
        (lambda ()
          (set! failures
            (run-tests
              (test-suite "Direct GPU image operations"
                (test-case "all scenes preserve placement without drawing readbacks"
                  (for ([scene (in-list operation-scenes)])
                    (define ledger (box '()))
                    (define captured #f) (define placement #f)
                    (with-skia ([surface (make-gpu-surface ctx operation-width operation-height)])
                      (define c (surface-canvas surface))
                      (parameterize ([current-gpu-io-ledger ledger])
                        (canvas-clear! c 'white)
                        (with-skia ([marker (make-paint #:color (rgb 0 255 0) #:antialias? #f)])
                          (draw-rect c 2 2 5 5 marker))
                        (cond
                          [(memq scene '(offset clip blur shadow))
                           (with-skia ([cpu (make-operation-source)] [source (gpu-upload-image ctx cpu)]
                                       [filter (make-operation-filter scene)])
                             (define-values (result subset offset)
                               (gpu-image-apply-filter source filter #:subset (operation-filter-subset scene)
                                                       #:clip (operation-filter-clip scene)))
                             (set! filter-calls (add1 filter-calls))
                             (with-skia ([im result] [visible (apply gpu-image-subset im (vector->list subset))])
                               (check-true (gpu-image? im)) (check-true (image-texture-backed? im))
                               (check-eq? (skia-resource-gpu-context im) ctx)
                               (skia-close! cpu) (skia-close! source) (skia-close! filter)
                               (set! retained-tested? #t)
                               (set! placement (vector->list offset))
                               (draw-image c visible (+ 24 (vector-ref offset 0)) (+ 20 (vector-ref offset 1)) #:sampling 'nearest))) ]
                          [(eq? scene 'raw)
                           (with-skia ([cpu (make-operation-source)] [source (gpu-upload-image ctx cpu)]
                                       [shader (make-raw-image-shader source)] [paint (make-paint #:shader shader #:antialias? #f)])
                             (check-eq? (skia-resource-gpu-context shader) ctx)
                             (skia-close! source) (skia-close! shader)
                             (with-canvas-state c
                               (canvas-translate! c 24 20)
                               (draw-rect c 0 0 16 12 paint)))
                           (set! placement '(0 0))]
                          [else
                           (define-values (image offset metadata raw) (make-operation-scene-image scene))
                           (with-skia ([cpu image] [source (gpu-upload-image ctx cpu)])
                             (draw-image c source 24 20 #:sampling 'nearest))
                           (set! placement '(0 0))]))
                      (define drawing-reads (reads ledger)) (check-equal? drawing-reads 0)
                      (set! captured (parameterize ([current-gpu-io-ledger ledger])
                                       (gpu-surface->rgba-bytes surface #:premultiplied? #t)))
                      (check-equal? (reads ledger) 1)
                      (operation-check-pixels scene captured)
                      (define filename (string-append (symbol->string scene) ".rgba"))
                      (call-with-output-file (build-path directory filename)
                        (lambda (out) (write-bytes captured out)) #:exists 'error)
                      (set! rows (cons (hasheq 'scene (symbol->string scene) 'file filename
                                              'drawing_readbacks drawing-reads 'inspection_readbacks (reads ledger)
                                              'offset placement) rows)))))
                (test-case "CPU reads and materialization reject GPU sources"
                  (with-skia ([cpu (make-operation-source)] [source (gpu-upload-image ctx cpu)]
                              [buffer (make-raster-buffer 16 12)])
                    (call-with-raster-buffer-pixmap buffer
                      (lambda (dst)
                        (for ([op (list (lambda () (image-read-pixmap! source dst))
                                        (lambda () (image-scale-pixmap! source dst))
                                        (lambda () (image->raster-image source))
                                        (lambda () (image->non-texture-image source)))])
                          (check-exn exn:fail? op)
                          (set! cpu-rejections (add1 cpu-rejections)))) #:writable? #t)))
                (test-case "foreign filter graph cannot cross GPU contexts"
                  (with-skia ([cpu (make-operation-source)] [source (gpu-upload-image ctx cpu)])
                    (check-exn exn:fail?
                      (lambda () (gpu-image-apply-filter source foreign-filter #:clip '(0 0 16 12))))
                    (set! cross-rejected? #t)))))))))
    (lambda ()
      (dynamic-wind void
        (lambda () (when foreign-filter (skia-close! foreign-filter)))
        (lambda ()
          (dynamic-wind void (lambda () (when other (gpu-context-close! other)))
            (lambda () (gpu-context-close! ctx)))))))
  (define closed? (and (eq? (gpu-context-state ctx) 'closed) other (eq? (gpu-context-state other) 'closed)))
  (call-with-output-file report-path
    (lambda (out)
      (write-json (hasheq 'schema 1 'stage "0.72" 'run_token token
        'status (if (and (zero? failures) closed?) "passed" "failed")
        'failures failures 'backend (symbol->string backend) 'adapter (symbol->string adapter)
        'scenes (reverse rows) 'frames (length rows) 'filter_calls filter-calls
        'cpu_rejections cpu-rejections 'cross_context_rejected cross-rejected?
        'retained_result_tested retained-tested? 'contexts_closed closed?
        'gui_executed #f 'physical_display_verified #f 'float_gpu_storage_verified #f) out)) #:exists 'error)
  (exit (if (and (zero? failures) closed?) 0 1)))
