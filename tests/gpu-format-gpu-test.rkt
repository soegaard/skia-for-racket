#lang racket/base

;;;
;;; GPU Format GPU Test
;;;

;; Checks GPU surface formats, surface properties, and explicit readback.
;; This executable supplies backend-specific drawing and transfer evidence to the GPU validation
;; workflow.

;;;
;;; Imports and Exports
;;;
(require racket/class racket/cmdline racket/file racket/list racket/path json rackunit
  rackunit/text-ui
         "../main.rkt" "../gpu.rkt" "../gpu-egl.rkt" "../gpu-dc.rkt"
         "../private/gpu-io-trace.rkt" "../private/gpu-frame-target-cache.rkt"
         "../private/gpu-format-util.rkt" "../private/gpu-surface-native.rkt")

;;;
;;; Fixtures and Assertions
;;;

; WIDTH : exact-positive-integer?
;;   Sets the fixture width in pixels for drawing and storage-layout checks.
(define WIDTH 8)
; HEIGHT : exact-positive-integer?
;;   Sets the fixture height in pixels for drawing and storage-layout checks.
(define HEIGHT 6)

; reads : box? -> exact-nonnegative-integer?
;;   Counts explicit readbacks in the GPU I/O ledger.
(define (reads ledger)
  (count (lambda (e) (equal? (hash-ref e 'kind #f) "readback")) (unbox ledger)))

; save : path-string? bytes? -> exact-nonnegative-integer?
;;   Writes a fresh binary capture, refusing to overwrite existing evidence.
(define (save path bytes)
  (call-with-output-file path (lambda (o) (write-bytes bytes o)) #:exists 'error))

; alpha-for : symbol? -> symbol?
;;   Chooses opaque alpha for alpha-less storage formats and premultiplied alpha otherwise.
(define (alpha-for color) (if (memq color '(rgb-888x rgb-565 gray-8)) 'opaque 'premul))

; draw-pattern : canvas? symbol? -> any
;;   Draws format-sensitive samples, including values that expose float precision and clipping.
(define (draw-pattern c color)
  (cond
    [(memq color '(rgba-f16 rgba-f32))
     (canvas-clear-color4f! c (make-color4f 0.5009765625 -0.125 1.25 1.0))
     (with-skia
       ([p (make-paint/color4f (make-color4f 0.501953125 -0.125 1.25 1.0) #:color-space 'srgb
             #:antialias? #f)])
       (draw-rect c 4 0 4 6 p))]
    [else
     (define a (cond [(eq? color 'alpha-8) (rgba 0 0 0 64)]
                     [(memq color '(rgba-8888 bgra-8888)) (rgb 32 96 192)] [else 'black]))
     (define b (cond [(eq? color 'alpha-8) (rgba 0 0 0 192)]
                     [(memq color '(rgba-8888 bgra-8888)) (rgb 192 96 32)] [else 'white]))
     (canvas-clear! c a)
     (with-skia ([p (make-paint #:color b #:blend-mode 'src #:antialias? #f)])
       (draw-rect c 4 0 4 6 p))]))

; make-context : symbol? symbol? -> gpu-context?
;;   Creates the requested EGL, Metal, or Direct3D context for a format probe.
(define (make-context backend adapter)
  (case backend [(egl) (make-egl-gpu-context)] [(metal) (make-gpu-context #:backend 'metal)]
    [(direct3d) (make-gpu-context #:backend 'direct3d #:adapter adapter)]
    [else (error 'gpu-formats "unsupported selected backend")]))

; write-documents : path-string? string? image? symbol? -> list?
;;   Exports a captured image with vector markers and returns document evidence records.
(define (write-documents directory token im color)
  (for/list ([kind '(pdf svg)])
    (define page (make-output-page 40 28
      (lambda (c)
        (draw-image c im 16 12 #:sampling 'nearest)
        (with-skia ([p (make-paint #:color (rgb 0 255 0) #:antialias? #f)]) (draw-rect c 2 2 4 4 p))
        (canvas-annotate-url! c 2 2 4 4 "https://example.invalid/gpu-formats")) #:background 'white))
    (define name (format "~a.~a" color kind))
    (define-values (encoded audit) (output->bytes/audit page kind #:policy 'error))
    (check-false (output-audit-report-blocking? audit))
    (save (build-path directory name) encoded)
    (hasheq 'file name 'format (symbol->string kind) 'color_type (symbol->string color)
            'conversion "explicit-rgba8888" 'audit (output-audit-report->jsexpr audit))))
(module+ main

  ;;;
  ;;; Command-Line Run
  ;;;

  ; backend : (or/c symbol? #f)
  ;;   Selects the explicitly requested GPU backend for this command-line run.
  (define backend 'auto)
  ; adapter : (or/c symbol? #f)
  ;;   Selects Direct3D adapter policy when that backend is requested.
  (define adapter 'hardware)
  ; report-path : (or/c path-string? #f)
  ;;   Holds the destination for this run's machine-readable evidence report.
  (define report-path #f)
  ; token : (or/c string? #f)
  ;;   Carries the caller's run identifier into evidence so independent validation can match
  ;;   artifacts.
  (define token #f)
  (command-line #:once-each
    [("--backend") b "egl, metal, direct3d" (set! backend (string->symbol b))]
    [("--adapter") a "hardware or warp" (set! adapter (string->symbol a))]
    [("--report") p "New report file" (set! report-path p)]
    [("--token") t "Invocation identity" (set! token t)] #:args () (void))
  (unless (and report-path token) (error 'gpu-formats "--report and --token required"))
  (when (eq? backend 'auto)
    (set! backend (case (system-type 'os) [(macosx) 'metal] [(windows) 'direct3d] [else 'egl])))

  ; directory : (or/c path-string? #f)
  ;;   Holds the evidence output directory selected for this run.
  (define directory (path-only (path->complete-path report-path)))

  ; context : gpu-context?
  ;;   Owns the primary native GPU context used by the fixture run.
  (define context (make-context backend adapter))

  ; other : (or/c gpu-context? #f)
  ;;   Owns a second context used to verify cross-context resource rejection.
  (define other #f)
  ; foreign-image : (or/c gpu-image? #f)
  ;;   Retains an image from another context for format-transfer affinity checks.
  (define foreign-image #f)

  ; cases : exact-nonnegative-integer?
  ;;   Counts acceptance cases attempted by the local test wrapper.
  (define cases 0)
  ; failures : exact-nonnegative-integer?
  ;;   Counts failed or errored RackUnit cases for the command-line exit status.
  (define failures 0)
  ; rows : (listof hash?)
  ;;   Accumulates capture and operation evidence for the run's JSON manifest.
  (define rows '())
  ; documents : (listof hash?)
  ;;   Collects PDF/SVG export evidence for validated GPU format captures.
  (define documents '())

  ; drawing-reads : exact-nonnegative-integer?
  ;;   Counts wrapper readbacks during drawing, which these GPU-only fixtures require to remain
  ;;   zero.
  (define drawing-reads 0)
  ; rejected : exact-nonnegative-integer?
  ;;   Counts rejected unsupported requests before they can produce invalid GPU output.
  (define rejected 0)
  ; survivor : (or/c image? #f)
  ;;   Keeps a detached CPU image to verify usability after GPU resources are closed.
  (define survivor #f)

  ; cache-result : (or/c hash? #f)
  ;;   Stores cache-control evidence collected without changing the rendering assertions.
  (define cache-result #f)
  ; symbols : (listof hash?)
  ;;   Records native backend-resource symbol names and availability for the format acceptance
  ;;   report.
  (define symbols '())

  ; test! : string? procedure? -> void?
  ;;   Runs one named acceptance case and accumulates its failure count for final reporting.
  (define (test! label thunk)
    (set! cases (add1 cases))
    (set! failures (+ failures (run-tests (test-suite label (test-case label (thunk)))))))
  (dynamic-wind void
    (lambda ()
      (set! other (make-context backend adapter))
      ;; Construct the foreign resource in its own activation. Different GPU
      ;; domains must never be nested merely to set up a cross-context test.
      (call-with-gpu-context other
        (lambda ()
          (with-skia ([foreign-surface
                       (make-gpu-surface other 8 6 #:color-type 'rgba-f16)])
            (set! foreign-image (gpu-surface-snapshot foreign-surface)))))
      (call-with-gpu-context context
        (lambda ()
          (set! symbols (gpu-backend-resource-native-inventory))
          (test! "all descriptor observation symbols resolve"
            (lambda () (for ([r (in-list symbols)]) (check-true (hash-ref r 'available)))))
          (for ([color (in-vector pixel-formats)])
            (test! (format "typed native target: ~a" color)
              (lambda ()
                (define cap (gpu-surface-format-info context color))
                (define alpha (alpha-for color))
                (cond
                  [(not (hash-ref cap 'renderable))
                   ;; Unsupported is accepted only from a native zero-capability
                   ;; observation, not from an arbitrary construction exception.
                   (check-equal? (hash-ref cap 'max_sample_count) 0)
                   (check-exn #rx"unsupported GPU format/sample"
                     (lambda () (make-gpu-surface context WIDTH HEIGHT #:color-type color
                                  #:alpha-type alpha #:background 'black)))
                   (set! rejected (add1 rejected))
                   (set! rows (cons (hasheq 'color_type (symbol->string color) 'status "unsupported"
                                          'capability cap) rows))]
                  [else
                   (with-skia ([s (make-gpu-surface context WIDTH HEIGHT #:color-type color
                                    #:alpha-type alpha #:background 'black)])
                     (define ledger (box '()))
                     (parameterize ([current-gpu-io-ledger ledger])
                       (draw-pattern (surface-canvas s) color))
                     (check-equal? (reads ledger) 0)
                     (set! drawing-reads (+ drawing-reads (reads ledger)))
                     (define info (gpu-surface->image-info s))
                     (check-eq? (image-info-color-type info) color)
                     (check-eq? (image-info-alpha-type info) alpha)
                     (check-equal? (surface-properties-of s) (make-surface-properties))
                     (define bpp (image-info-bytes-per-pixel info))
                     (define stride (* 10 bpp))
                     (with-skia ([buffer (make-raster-buffer-from-info info #:row-bytes stride)])
                       (define before (bytes-copy (raster-buffer->storage-bytes buffer)))
                       (for* ([y (in-range HEIGHT)] [i (in-range (* WIDTH bpp) stride)])
                         (bytes-set! before (+ (* y stride) i) 165))
                       (raster-buffer-write-storage! buffer before)
                       (parameterize ([current-gpu-io-ledger ledger])
                         (call-with-raster-buffer-pixmap buffer
                           (lambda (v) (gpu-surface-read-pixmap! s v)) #:writable? #t))
                       (check-equal? (reads ledger) 1)
                       (define raw (raster-buffer->storage-bytes buffer))
                       (for* ([y (in-range HEIGHT)] [i (in-range (* WIDTH bpp) stride)])
                         (check-equal? (bytes-ref raw (+ (* y stride) i)) 165))
                       (define name (format "~a.pixels" color)) (save (build-path directory name) raw)
                       (with-skia ([detached (gpu-surface->raster-image s)]
                                   [copy (image->raster-buffer detached)])
                         (check-eq? (image-color-type detached) color)
                         (check-equal? (raster-buffer->storage-bytes copy)
                                       (apply bytes-append
                                         (for/list ([y (in-range HEIGHT)])
                                           (subbytes raw (* y stride)
                                             (+ (* y stride) (* WIDTH bpp)))))))
                       (when (memq color '(rgba-8888 bgra-8888 rgba-f16 rgba-f32))
                         (with-skia ([snapshot (gpu-surface-snapshot s)]
                                     [copy (gpu-image->raster-buffer snapshot)]
                                     [cpu (raster-buffer->image copy)]
                                     [upload (gpu-upload-image context cpu)]
                                     [again (gpu-image->raster-buffer upload)])
                           (check-eq? (image-color-type upload) color)
                           (check-equal? (raster-buffer->storage-bytes copy)
                             (raster-buffer->storage-bytes again))))
                       (when (eq? color 'rgba-f16)
                         (set! survivor (gpu-surface->raster-image s))
                         (define page (make-output-page 40 28
                                        (lambda (c) (draw-image c survivor 16 12))))
                         (check-exn exn:fail:output-audit?
                           (lambda () (output->bytes/audit page 'pdf #:policy 'error))))
                       (when (memq color '(rgba-8888 rgba-f16))
                         (with-skia ([quantized
                                       (raster-buffer-convert buffer (make-image-info WIDTH HEIGHT))]
                                     [im (raster-buffer->image quantized)])
                           (set! documents
                             (append documents (write-documents directory token im color))))))
                     (set! rows (cons (hasheq 'color_type (symbol->string color) 'status "passed"
                                      'alpha_type (symbol->string alpha) 'file
                                        (format "~a.pixels" color)
                                      'row_bytes stride 'bytes_per_pixel bpp 'width WIDTH 'height
                                        HEIGHT
                                      'readbacks 1 'properties
                                        (surface-properties->jsexpr (surface-properties-of s))
                                      'capability cap) rows)))]))))
          (test! "required SDR and half-float formats are exercised"
            (lambda () (for ([color '("rgba-8888" "bgra-8888" "rgba-f16")])
              (check-true (for/or ([r (in-list rows)])
                            (and (equal? color (hash-ref r 'color_type))
                              (equal? "passed" (hash-ref r 'status))))))))
          (test! "property requests are observed natively"
            (lambda ()
              (for ([g '(unknown rgb-h bgr-h rgb-v bgr-v)])
                (define p (make-surface-properties #:pixel-geometry g #:device-independent-fonts? #t
                                                   #:always-dither? #t #:dynamic-msaa? #t))
                (with-skia ([s (make-gpu-surface context 8 6 #:surface-properties p)])
                  (check-equal? p (surface-properties-of s))
                  (check-equal? (hash-ref (gpu-surface-info s) 'surface_properties)
                    (surface-properties->jsexpr p))))))
          (test! "sample upper bound is per context and color format"
            (lambda ()
              (define maximum
                (hash-ref (gpu-surface-format-info context 'rgba-8888) 'max_sample_count))
              (check-exn exn:fail?
                (lambda () (make-gpu-surface context 8 6 #:sample-count (add1 maximum))))
              (with-skia ([s (make-gpu-surface context 8 6 #:sample-count (min 4 maximum))])
                (check-equal? (hash-ref (gpu-surface-info s) 'requested_sample_count) (min 4 maximum))
                (check-false (hash-ref (gpu-surface-info s) 'actual_sample_count)))))
          (test! "failed readback leaves destination and padding untouched"
            (lambda ()
              (with-skia ([space (make-srgb-color-space)]
                          [s (make-gpu-surface context 8 6 #:color-space space)]
                          [b (make-raster-buffer 8 6 #:row-bytes 40)])
                (define before (raster-buffer->storage-bytes b))
                (call-with-raster-buffer-pixmap b
                  (lambda (v) (check-exn exn:fail? (lambda () (gpu-surface-read-pixmap! s v))))
                  #:writable? #t)
                (check-equal? (raster-buffer->storage-bytes b) before))))
          (test! "tagged target retains its space and converts typed samples"
            (lambda ()
              (with-skia ([space (make-srgb-color-space)]
                           [s (make-gpu-surface context 8 6 #:color-type 'rgba-f16 #:color-space
                                space)])
                (skia-close! space)
                (canvas-clear-color4f! (surface-canvas s) (make-color4f 0.5 0.25 0.75 1))
                (check-eq? (image-info-color-space (gpu-surface->image-info s)) 'srgb)
                (with-skia ([b (gpu-surface->raster-buffer s
                                #:info
                                 (make-image-info 8 6 #:color-type 'rgba-f16 #:color-space
                                   'linear-srgb))])
                  (call-with-raster-buffer-pixmap b
                    (lambda (v)
                      (define sample (pixmap-sample v 0 0))
                      (check-= (vector-ref sample 0) 0.2140411 0.001)
                      (check-= (vector-ref sample 1) 0.0508761 0.001)
                      (check-= (vector-ref sample 2) 0.5225216 0.001)))))))
          (test! "legacy buffer transfer still rejects incompatible layouts"
            (lambda ()
              (with-skia ([s (make-gpu-surface context 8 6)]
                           [b (make-raster-buffer-from-info
                                (make-image-info 8 6 #:color-type 'rgba-f16))])
                (check-exn exn:fail? (lambda () (gpu-surface-read-raster-buffer! s b))))))
          (test! "context affinity is enforced before drawing"
            (lambda ()
              (check-true (and foreign-image (gpu-image? foreign-image)))
              (with-skia ([target (make-gpu-surface context 8 6)])
                (check-exn #rx"resources belong to different GPU contexts"
                  (lambda ()
                    (draw-image (surface-canvas target) foreign-image 0 0))))))
          (test! "real GPU staging retires on same-size format and property changes"
            (lambda ()
              (define cache (make-frame-target-cache))
              (define (use color w h props)
                (define key (gpu-staging-key 'test w h color #f 0 props))
                (call-with-frame-target cache w h
                  (lambda () (make-gpu-surface context w h #:color-type color #:surface-properties
                               props))
                  skia-close!
                  (lambda (s) (check-eq? (image-info-color-type (gpu-surface->image-info s)) color))
                  #:configuration key))
              (dynamic-wind void
                (lambda ()
                  (define p (make-surface-properties))
                  (use 'rgba-8888 8 6 p) (use 'rgba-8888 8 6 p)
                  (use 'rgba-f16 8 6 p)
                  (use 'rgba-f16 8 6 (make-surface-properties #:device-independent-fonts? #t))
                  (use 'rgba-f16 9 7 p)
                  (set! cache-result (frame-target-cache-info cache))
                  (check-equal? (hash-ref cache-result 'creations) 4)
                  (check-equal? (hash-ref cache-result 'reuses) 1)
                  (check-equal? (hash-ref cache-result 'retirements) 3))
                (lambda () (close-frame-target-cache! cache)))))
          (test! "float borrowed-surface DC supports nested alpha groups"
            (lambda ()
              (with-skia ([s (make-gpu-surface context 8 6 #:color-type 'rgba-f16)])
                (call-with-gpu-surface-dc s
                  (lambda (dc)
                    (send dc start-alpha 0.5)
                    (send dc set-brush "red" 'solid)
                    (send dc set-pen "red" 0 'transparent)
                    (send dc draw-rectangle 0 0 8 6)
                    (send dc end-alpha)))
                (with-skia ([pixels (gpu-surface->raster-buffer s)])
                  (call-with-raster-buffer-pixmap pixels
                    (lambda (v)
                      (define sample (pixmap-sample v 2 2))
                      (check-= (vector-ref sample 0) 0.5 0.005)
                      (check-= (vector-ref sample 3) 0.5 0.005))))
                (check-eq? (image-info-color-type (gpu-surface->image-info s)) 'rgba-f16)))))))
    (lambda ()
      ;; Close the foreign child before its owning context. Closing a GPU child
      ;; queues normal owner-domain retirement; context teardown drains it.
      (when foreign-image (skia-close! foreign-image))
      (when other (gpu-context-close! other))
      (gpu-context-close! context)))
  (test! "typed CPU result survives context closure"
    (lambda ()
      (check-true (and survivor (image? survivor)))
      (when survivor
        (with-skia ([image survivor] [b (image->raster-buffer image)])
          (check-eq? (image-color-type image) 'rgba-f16)
          (check-true (bytes? (raster-buffer->storage-bytes b)))))))

  ; closed? : boolean?
  ;;   Records whether context teardown completed with no live or failed resource releases.
  (define closed?
    (and (eq? (gpu-context-state context) 'closed) other (eq? (gpu-context-state other) 'closed)))
  (call-with-output-file report-path
    (lambda (o)
      (write-json (hasheq 'schema 1 'stage "0.73" 'run_token token
                    'status (if (and (zero? failures) closed?) "passed" "failed")
                    'backend (symbol->string backend) 'adapter (symbol->string adapter)
                    'cases cases 'failures failures 'formats (reverse rows) 'documents documents
                    'byte_order (if (system-big-endian?) "big-endian" "little-endian")
                    'drawing_readbacks drawing-reads 'unsupported_rejections rejected
                    'descriptor_symbols symbols 'staging cache-result 'context_closed closed?
                    'physical_display_verified #f 'hdr_verified #f) o)) #:exists 'error)
  (exit (if (and (zero? failures) closed?) 0 1)))
