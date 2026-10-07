#lang racket/base
(require racket/cmdline racket/file racket/list racket/path json rackunit rackunit/text-ui
         "../main.rkt" "../gpu.rkt" "../gpu-egl.rkt" "../private/gpu-io-trace.rkt"
         "advanced-canvas-fixtures.rkt")
(module+ main
  (define backend 'auto) (define adapter 'hardware) (define directory #f) (define token #f)
  (command-line #:once-each
    [("--backend") value "auto, egl, metal, direct3d" (set! backend (string->symbol value))]
    [("--adapter") value "hardware or warp" (set! adapter (string->symbol value))]
    [("--directory") value "Fresh evidence directory" (set! directory value)]
    [("--token") value "Run token" (set! token value)] #:args () (void))
  (unless (and directory token) (error 'advanced-gpu "--directory and --token required"))
  (when (eq? backend 'auto)
    (set! backend (case (system-type 'os) [(macosx) 'metal] [(windows) 'direct3d] [else 'egl])))
  (unless (and (memq backend '(egl metal direct3d)) (memq adapter '(hardware warp))
               (or (eq? backend 'direct3d) (eq? adapter 'hardware)))
    (error 'advanced-gpu "invalid backend/adapter selection"))
  (make-directory* directory)
  (define (create)
    (case backend [(egl) (make-egl-gpu-context)]
      [(metal) (make-gpu-context #:backend 'metal)]
      [else (make-gpu-context #:backend 'direct3d #:adapter adapter)]))
  (define context (create)) (define other #f) (define foreign #f) (define foreign-filter #f)
  (define cases 0) (define failures 0) (define rows '()) (define checks (make-hasheq))
  (define (test! name thunk)
    (set! cases (add1 cases))
    (set! failures (+ failures (run-tests (test-suite name (test-case name (thunk)))))))
  (define (reads events) (count (lambda (e) (equal? (hash-ref e 'kind #f) "readback")) events))
  (define (save! name data)
    (call-with-output-file (build-path directory name) (lambda (out) (write-bytes data out)) #:exists 'error))
  (define (capture! name draw)
    (define ledger (box '()))
    (with-skia ([s (make-gpu-surface context advanced-width advanced-height #:background 'white)])
      (define target (gpu-surface-info s))
      (parameterize ([current-gpu-io-ledger ledger]) (draw (surface-canvas s)))
      (define drawing-reads (reads (unbox ledger))) (check-equal? drawing-reads 0)
      (define data (parameterize ([current-gpu-io-ledger ledger])
                    (gpu-surface->rgba-bytes s #:premultiplied? #t)))
      (check-equal? (reads (unbox ledger)) 1)
      (save! (string-append name ".rgba") data)
      (set! rows (cons (hasheq 'name name 'file (string-append name ".rgba") 'target target
                               'drawing_readbacks drawing-reads 'inspection_readbacks (reads (unbox ledger))
                               'io (reverse (unbox ledger))) rows))))
  (dynamic-wind void
    (lambda ()
      ;; Foreign resources are constructed in a SEQUENTIAL activation.
      (set! other (create))
      (call-with-gpu-context other
        (lambda ()
          (with-skia ([s (make-gpu-surface other 8 8 #:background 'red)] [im (gpu-surface-snapshot s)])
            (set! foreign-filter (make-image-source-filter im))
            ;; Exercise new SaveLayerRec affinity, not only ordinary draw-image
            ;; affinity: the recorded backdrop must follow its GPU input.
            (set! foreign
              (call-with-drawable 8 8
                (lambda (c) (call-with-canvas-layer-rec c void #:backdrop foreign-filter)))))))
      (call-with-gpu-context context
        (lambda ()
          (test! "group opacity on the selected GPU" (lambda () (capture! "layer" draw-advanced-layer)))
          (test! "previous content initialization on the selected GPU"
            (lambda () (capture! "initialization" draw-advanced-initialization)))
          (test! "backdrop field on the selected GPU"
            (lambda () (capture! "backdrop" draw-advanced-backdrop)))
          (test! "recorded drawable replay uses the selected GPU"
            (lambda ()
              (define called 0)
              (with-skia ([d (call-with-drawable advanced-width advanced-height
                              (lambda (c) (set! called (add1 called)) (draw-advanced-vector c)))])
                (capture! "drawable" (lambda (c) (draw-drawable c d)))
                (check-equal? called 1))))
          (test! "NWay uses two real same-context targets and calls authoring once"
            (lambda ()
              (define ledger (box '())) (define called 0)
              (with-skia ([a (make-gpu-surface context advanced-width advanced-height #:background 'white)]
                          [b (make-gpu-surface context advanced-width advanced-height #:background 'white)])
                (parameterize ([current-gpu-io-ledger ledger])
                  (call-with-nway-canvas (list a b)
                    (lambda (c) (set! called (add1 called)) (draw-advanced-vector c))))
                (check-equal? called 1) (check-equal? (reads (unbox ledger)) 0)
                (for ([s (in-list (list a b))] [name '("nway-a" "nway-b")])
                  (define capture-ledger (box '()))
                  (define data (parameterize ([current-gpu-io-ledger capture-ledger])
                                 (gpu-surface->rgba-bytes s #:premultiplied? #t)))
                  (check-equal? (reads (unbox capture-ledger)) 1)
                  (save! (string-append name ".rgba") data)
                  (set! rows (cons (hasheq 'name name 'file (string-append name ".rgba")
                                           'target (gpu-surface-info s) 'drawing_readbacks 0
                                           'inspection_readbacks (reads (unbox capture-ledger))
                                           'io (reverse (unbox capture-ledger))) rows))))
              (hash-set! checks 'nway_authoring_once #t)))
          (test! "F16 layer flag executes on the selected GPU without hidden readback"
            (lambda ()
              (define ledger (box '()))
              (with-skia ([s (make-gpu-surface context 8 6 #:color-type 'rgba-f16)])
                (define c (surface-canvas s))
                (parameterize ([current-gpu-io-ledger ledger])
                  (call-with-canvas-layer-rec c
                    (lambda ()
                      (canvas-clear-color4f! c (make-color4f 0.25 0.5 0.75 1)))
                    #:options (make-layer-options #:f16? #t)))
                (check-equal? (reads (unbox ledger)) 0)
                (with-skia ([pixels (parameterize ([current-gpu-io-ledger ledger])
                                     (gpu-surface->raster-buffer s))])
                  (save! "layer-f16.pixels" (raster-buffer->storage-bytes pixels)))
                (check-equal? (reads (unbox ledger)) 1))
              (hash-set! checks 'f16_layer #t)))
          (test! "foreign drawable fails at the ownership boundary"
            (lambda ()
              (with-skia ([s (make-gpu-surface context 8 8)])
                (check-exn #rx"different GPU contexts"
                  (lambda () (draw-drawable (surface-canvas s) foreign))))
              (hash-set! checks 'foreign_drawable_rejected #t)))
          (test! "foreign backdrop is rejected before changing canvas state"
            (lambda ()
              (with-skia ([s (make-gpu-surface context 8 8)])
                (define c (surface-canvas s))
                (check-exn #rx"different GPU contexts"
                  (lambda () (canvas-save-layer-rec! c #:backdrop foreign-filter)))
                (check-equal? (canvas-save-count c) 1))
              (hash-set! checks 'foreign_backdrop_rejected #t)))
          (test! "exceptional layer exit unpins GPU target and restores state"
            (lambda ()
              (with-skia ([s (make-gpu-surface context 8 8)])
                (define c (surface-canvas s))
                (check-exn #rx"expected layer failure" (lambda ()
                  (call-with-canvas-layer-rec c (lambda () (canvas-save! c) (error 'test "expected layer failure")))))
                (check-equal? (canvas-save-count c) 1))
              (hash-set! checks 'layer_exception_cleanup #t)))
          (test! "exceptional NWay exit releases both GPU borrows"
            (lambda ()
              (with-skia ([a (make-gpu-surface context 8 8)] [b (make-gpu-surface context 8 8)])
                (check-exn #rx"expected NWay failure" (lambda ()
                  (call-with-nway-canvas (list a b)
                    (lambda (c) (canvas-save! c) (error 'test "expected NWay failure")))))
                (check-equal? (canvas-save-count (surface-canvas a)) 1)
                (check-equal? (canvas-save-count (surface-canvas b)) 1))
              (hash-set! checks 'nway_exception_cleanup #t)))
          (test! "Alpha8 overdraw executes or explicitly rejects absent capability"
            (lambda ()
              (define capability (gpu-surface-format-info context 'alpha-8))
              (hash-set! checks 'overdraw_capability capability)
              (cond
                [(hash-ref capability 'renderable)
                 (with-skia ([s (make-gpu-surface context 12 10 #:color-type 'alpha-8)])
                   (call-with-overdraw-canvas s
                     (lambda (c)
                       (with-skia ([p (make-paint #:color 'red #:antialias? #f)])
                         (draw-rect c 2 2 6 6 p) (draw-rect c 4 2 6 6 p))))
                   (with-skia ([b (gpu-surface->raster-buffer s)])
                     (save! "overdraw.alpha" (raster-buffer->storage-bytes b))))
                 (hash-set! checks 'overdraw_supported #t)]
                [else
                 (check-exn #rx"unsupported GPU format" (lambda ()
                   (make-gpu-surface context 12 10 #:color-type 'alpha-8)))
                 (hash-set! checks 'overdraw_supported #f)])
              (hash-set! checks 'overdraw_capability_checked #t))))))
    (lambda ()
      (when foreign (skia-close! foreign))
      (when foreign-filter (skia-close! foreign-filter))
      (when other (gpu-context-close! other))
      (gpu-context-close! context)))
  (define closed? (and (eq? (gpu-context-state context) 'closed)
                       other (eq? (gpu-context-state other) 'closed)))
  (define report
    (hasheq 'schema 1 'stage "0.74" 'run_token token 'status (if (and (zero? failures) closed?) "passed" "failed")
            'backend (symbol->string backend) 'adapter (symbol->string adapter)
            'cases cases 'failures failures 'checks checks 'contexts_closed closed?
            'captures (reverse rows) 'float_order (if (system-big-endian?) "big" "little")
            'hdr_verified #f 'physical_display_verified #f))
  (call-with-output-file (build-path directory "gpu.json") (lambda (out) (write-json report out)) #:exists 'error)
  (exit (if (and (zero? failures) closed?) 0 1)))
