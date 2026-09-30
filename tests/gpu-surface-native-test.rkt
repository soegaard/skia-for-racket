#lang racket/base
(require rackunit racket/list
         "../main.rkt" "../gpu.rkt"
         "gpu-fixtures.rkt")
(provide make-gpu-surface-native-tests)

;; Explicit live contexts are supplied by the diagnostic host. Requiring this
;; suite neither loads a GPU library nor creates a window.
(define (make-gpu-surface-native-tests gpu other)
  (define backend (gpu-context-backend gpu))
  (define backend-id (case backend [(opengl) 0] [(metal) 2] [(direct3d) 3]
                      [else (error 'gpu-surface-tests "unexpected backend")]))
  (define (target proc #:background [background 'transparent])
    (call-with-gpu-context gpu
      (lambda ()
        (with-skia ([s (make-gpu-surface gpu 8 8 #:background background)])
          (proc s (surface-canvas s))))))
  (define (pixel data x y)
    (subbytes data (* 4 (+ x (* 8 y))) (* 4 (+ 1 x (* 8 y)))))
  (test-suite
   "GPU surfaces: live Ganesh drawing, leases, submission, and transfers"
   (test-case "ordinary surface and canvas types report explicit execution"
     (target (lambda (s c)
               (check-true (surface? s)) (check-true (gpu-surface? s))
               (check-true (canvas? c)) (check-true (skia-resource? s))
               (check-eq? (surface-backend s) backend)
               (check-eq? (canvas-execution-backend c) backend))))
   (test-case "native target is backed by the requested Ganesh context"
     (target (lambda (s c)
               (define info (gpu-surface-info s))
               (check-true (hash-ref info 'context_matches))
               (check-equal? (hash-ref info 'native_backend) backend-id)
               (check-equal? (hash-ref info 'render_path) "sk_surface_new_render_target")
               (check-false (hash-ref info 'actual_sample_count)))))
   (test-case "default transparent pixels are initialized"
     (target (lambda (s c) (check-equal? (gpu-surface->rgba-bytes s) (make-bytes 256)))))
   (test-case "opaque background survives submission and readback"
     (target (lambda (s c)
               (check-equal? (gpu-surface->rgba-bytes s)
                             (apply bytes (apply append (make-list 64 '(255 0 0 255))))))
             #:background 'red))
   (test-case "asymmetric ordinary rectangles preserve top-left coordinates"
     (target
      (lambda (s c)
        (with-skia ([r (make-paint #:color 'red #:antialias? #f)]
                    [g (make-paint #:color 'green #:antialias? #f)]
                    [b (make-paint #:color 'blue #:antialias? #f)])
          (draw-rect c 0 0 3 4 r) (draw-rect c 4 0 4 4 g) (draw-rect c 0 4 3 4 b))
        (define pixels (gpu-surface->rgba-bytes s))
        (check-equal? (pixel pixels 1 1) (bytes 255 0 0 255))
        (check-equal? (pixel pixels 1 6) (bytes 0 0 255 255))
        (check-equal? (pixel pixels 3 3) (bytes 0 0 0 0))
        (check-equal? (pixel pixels 7 7) (bytes 0 0 0 0)))))
   (test-case "straight and premultiplied readbacks are distinct"
     (target
      (lambda (s c)
        (canvas-clear! c (rgba 255 0 0 128))
        (check-equal? (pixel (gpu-surface->rgba-bytes s) 3 3) (bytes 255 0 0 128))
        (check-equal? (pixel (gpu-surface->rgba-bytes s #:premultiplied? #t) 3 3)
                      (bytes 128 0 0 128)))))
   (test-case "flush submit and wait are explicit usable operations"
     (target (lambda (s c)
               (canvas-clear! c 'blue)
               (check-true (void? (gpu-flush! gpu)))
               (check-true (void? (gpu-submit! gpu)))
               (check-true (void? (gpu-flush-and-submit! gpu)))
               (check-true (void? (gpu-wait! gpu)))
               (check-equal? (pixel (gpu-surface->rgba-bytes s) 2 2) (bytes 0 0 255 255)))))
   (test-case "submission rejects a missing activation"
     (for ([op (list gpu-flush! gpu-submit! gpu-flush-and-submit! gpu-wait!)])
       (check-exn exn:fail? (lambda () (op gpu)))))
   (test-case "readback requires a live activation"
     (define s (call-with-gpu-context gpu (lambda () (make-gpu-surface gpu 8 8))))
     (dynamic-wind void
       (lambda () (check-exn exn:fail? (lambda () (gpu-surface->rgba-bytes s))))
       (lambda () (skia-close! s))))
   (test-case "borrowed canvas cannot escape and then revive"
     (define s (call-with-gpu-context gpu (lambda () (make-gpu-surface gpu 8 8))))
     (dynamic-wind
       void
       (lambda ()
         (define c (call-with-gpu-context gpu (lambda () (surface-canvas s))))
         (check-true (skia-closed? c))
         (check-exn exn:fail? (lambda () (canvas-clear! c 'red)))
         (call-with-gpu-context gpu
           (lambda ()
             (check-exn exn:fail? (lambda () (canvas-clear! c 'red)))
             (canvas-clear! (surface-canvas s) 'blue)
             (check-equal? (pixel (gpu-surface->rgba-bytes s) 0 0) (bytes 0 0 255 255)))))
       (lambda () (skia-close! s))))
   (test-case "nested inner canvas expires while outer canvas remains live"
     (target
      (lambda (s outer)
        (define inner (call-with-gpu-context gpu (lambda () (surface-canvas s))))
        (check-exn exn:fail? (lambda () (canvas-clear! inner 'red)))
        (canvas-clear! outer 'blue))))
   (test-case "wrong thread cannot draw through an inherited activation"
     (target (lambda (s c)
               (check-true (exn:fail? (in-worker (lambda () (canvas-clear! c 'red)))))) ))
   (test-case "wrong live native context cannot borrow another domain's surface"
     (define s (call-with-gpu-context gpu (lambda () (make-gpu-surface gpu 8 8))))
     (dynamic-wind void
       (lambda ()
         (call-with-gpu-context other
           (lambda ()
             (check-exn exn:fail? (lambda () (surface-canvas s)))
             (check-exn exn:fail? (lambda () (gpu-surface->rgba-bytes s))))))
       (lambda () (skia-close! s))))
   (test-case "GPU surface blocks normal context close until released"
     (define s (call-with-gpu-context gpu (lambda () (make-gpu-surface gpu 8 8))))
     (dynamic-wind void
       (lambda () (check-exn exn:fail? (lambda () (gpu-context-close! gpu))))
       (lambda () (skia-close! s))))
   (test-case "explicit close queues destruction and owner scope drains it"
     (define s (call-with-gpu-context gpu (lambda () (make-gpu-surface gpu 8 8))))
     (skia-close! s) (skia-close! s)
     (check-true (skia-closed? s))
     (check-equal? (hash-ref (gpu-context-info gpu) 'pending_releases) 1)
     (call-with-gpu-context gpu void)
     (check-equal? (hash-ref (gpu-context-info gpu) 'pending_releases) 0))
   (test-case "closed target cannot yield a new canvas"
     (target (lambda (s c)
               (skia-close! s)
               (check-exn exn:fail? (lambda () (surface-canvas s)))
               (check-exn exn:fail? (lambda () (canvas-clear! c 'red))))))
   (test-case "protected state cannot be invalidated by closing its target"
     (target
      (lambda (s c)
        (with-canvas-state c
          (check-exn exn:fail? (lambda () (skia-close! s)))
          (canvas-translate! c 2 2))
        (check-equal? (canvas-save-count c) 1))))
   (test-case "readback rejects unfinished canvas state"
     (target
      (lambda (s c)
        (with-canvas-state c
          (check-exn exn:fail? (lambda () (gpu-surface->rgba-bytes s))))
        (check-equal? (bytes-length (gpu-surface->rgba-bytes s)) 256))))
   (test-case "CPU-only entry points cannot accidentally create GPU images"
     (target
      (lambda (s c)
        (for ([op (list surface-snapshot surface->rgba-bytes surface->png-bytes
                        (lambda (x) (surface-pixel x 0 0)))])
          (check-exn #rx"GPU transfers are explicit" (lambda () (op s)))))))
   (test-case "output groups do not silently route GPU drawing through CPU fallback"
     (target
      (lambda (s c)
        (define calls 0)
        (check-exn exn:fail?
          (lambda () (draw-output-group c 0 0 8 8 (lambda (ignored) (set! calls (add1 calls))))))
        (check-equal? calls 0))))
   (test-case "explicit CPU raster groups on GPU targets reject before the callback"
     (target
      (lambda (s c)
        (define calls 0)
        (check-exn exn:fail? (lambda () (draw-rasterized c 0 0 8 8
                                         (lambda (ignored) (set! calls (add1 calls))))))
        (check-equal? calls 0))))
   (test-case "ordinary recorded pictures replay on the GPU"
     (with-skia ([picture (call-with-picture 8 8
                           (lambda (c)
                             (with-skia ([paint (make-paint #:color 'red #:antialias? #f)])
                               (draw-rect c 0 0 8 8 paint))))])
       (target (lambda (s c)
                 (draw-picture c picture)
                 (check-equal? (pixel (gpu-surface->rgba-bytes s) 4 4) (bytes 255 0 0 255))))))
   (test-case "direct strided readback preserves padding and alpha"
     (target
      (lambda (s c)
        (canvas-clear! c (rgba 255 0 0 128))
        (with-skia ([buffer (make-raster-buffer 8 8 #:row-bytes 48)])
          (gpu-surface-read-raster-buffer! s buffer)
          (define storage (raster-buffer->storage-bytes buffer))
          (for ([y (in-range 8)])
            (check-equal? (subbytes storage (* y 48) (+ (* y 48) 4)) (bytes 128 0 0 128))
            (check-equal? (subbytes storage (+ (* y 48) 32) (* (add1 y) 48)) (make-bytes 16)))))))
   (test-case "dimension mismatch leaves the existing CPU destination unchanged"
     (target
      (lambda (s c)
        (with-skia ([buffer (make-raster-buffer 4 8)])
          (define before (raster-buffer->storage-bytes buffer))
          (check-exn exn:fail? (lambda () (gpu-surface-read-raster-buffer! s buffer)))
          (check-equal? (raster-buffer->storage-bytes buffer) before)))))
   (test-case "active pixmap borrow excludes GPU writes into the same buffer"
     (target
      (lambda (s c)
        (with-skia ([buffer (make-raster-buffer 8 8)])
          (call-with-raster-buffer-pixmap buffer
            (lambda (view)
              (check-exn exn:fail? (lambda () (gpu-surface-read-raster-buffer! s buffer)))))))))
   (test-case "CPU-detached image does not change after target mutation"
     (target
      (lambda (s c)
        (canvas-clear! c 'red)
        (with-skia ([image (gpu-surface->raster-image s)])
          (canvas-clear! c 'blue)
          (check-equal? (pixel (image->rgba-bytes image) 2 2) (bytes 255 0 0 255))))))
   (test-case "CPU-detached pixels remain valid outside every GPU activation"
     (define image
       (target (lambda (s c) (canvas-clear! c 'blue) (gpu-surface->raster-image s))))
     (with-skia ([detached image])
       (check-equal? (pixel (image->rgba-bytes detached) 5 5) (bytes 0 0 255 255))
       (check-true (> (bytes-length (image->png-bytes detached)) 20))))
   (test-case "GPU target retains its declared color space after wrapper close"
     (call-with-gpu-context gpu
       (lambda ()
         (with-skia ([space (make-srgb-color-space)]
                     [s (make-gpu-surface gpu 8 8 #:color-space space)])
           (skia-close! space)
           (with-skia ([copied (surface-color-space s)])
             (check-true (color-space-srgb? copied)))
           (check-equal? (bytes-length (gpu-surface->rgba-bytes s)) 256)))))
   (test-case "explicit readback color conversion uses the destination space"
     (call-with-gpu-context gpu
       (lambda ()
         (with-skia ([linear (make-linear-srgb-color-space)] [srgb (make-srgb-color-space)]
                     [image (rgba-bytes->image 1 1 (bytes 128 128 128 255) #:color-space linear)]
                     [s (make-gpu-surface gpu 8 8 #:color-space linear)])
           ;; Native SkColor clears may themselves be color transformed. Use
           ;; tagged sample data, not a paint color, to establish linear 128.
           (draw-image-rect (surface-canvas s) image 0 0 8 8 #:sampling 'nearest)
           (define converted (gpu-surface->rgba-bytes s #:color-space srgb))
           (for ([i '(0 1 2)]) (check-true (<= 186 (bytes-ref converted i) 190)))))))
   (test-case "unsupported sample request fails instead of choosing CPU rendering"
     (call-with-gpu-context gpu
       (lambda ()
         (define maximum (hash-ref (gpu-context-info gpu) 'max_rgba_sample_count))
         (check-exn exn:fail? (lambda () (make-gpu-surface gpu 8 8 #:sample-count (add1 maximum)))))))
   (test-case "GC enqueues native target destruction without context acquisition"
     (define weak
       (call-with-gpu-context gpu (lambda () (make-weak-box (make-gpu-surface gpu 8 8)))))
     (check-true (collect-until (lambda () (zero? (hash-ref (gpu-context-info gpu) 'live_children)))))
     (check-true (collect-until (lambda () (not (weak-box-value weak)))))
     (check-equal? (hash-ref (gpu-context-info gpu) 'pending_releases) 1)
     (call-with-gpu-context gpu void)
     (check-equal? (hash-ref (gpu-context-info gpu) 'pending_releases) 0))
   (test-case "failed constructor leaves no live target behind"
     (call-with-gpu-context gpu
       (lambda ()
         (define before (hash-ref (gpu-context-info gpu) 'live_children))
         (check-exn exn:fail? (lambda () (make-gpu-surface gpu 0 8)))
         (check-equal? (hash-ref (gpu-context-info gpu) 'live_children) before))))
   (test-case "context scopes preserve multiple return values"
     (check-equal? (call-with-values (lambda () (call-with-gpu-context gpu (lambda () (values 'a 'b)))) list)
                   '(a b)))))
