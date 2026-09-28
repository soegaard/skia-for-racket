#lang racket/base
(require rackunit racket/list
         "../main.rkt" "../gpu.rkt" "gpu-fixtures.rkt"
         "../private/gpu-io-trace.rkt")
(provide make-gpu-image-native-tests image-test-pixels gpu-image-native-test-count)

(define gpu-image-native-test-count 42)
(define image-test-pixels
  (apply bytes
    (append*
     (for*/list ([y (in-range 8)] [x (in-range 8)])
       (cond [(= x 3) '(0 0 0 0)]
             [(< y 4) (if (< x 3) '(255 0 0 255) '(0 255 0 255))]
             [else (if (< x 3) '(0 0 255 255) '(255 255 0 255))])))))
(define (call-with-gpu-io-trace thunk)
  (define ledger (box '()))
  (define result (parameterize ([current-gpu-io-ledger ledger]) (thunk)))
  (values result (reverse (unbox ledger))))

(define (make-gpu-image-native-tests gpu other)
  (define (cpu-image) (rgba-bytes->image 8 8 image-test-pixels #:premultiplied? #t))
  (define (uploaded proc)
    (call-with-gpu-context gpu
      (lambda ()
        (with-skia ([cpu (cpu-image)] [im (gpu-upload-image gpu cpu)]) (proc cpu im)))))
  (define (render proc)
    (with-skia ([s (make-gpu-surface gpu 8 8)])
      (proc (surface-canvas s))
      (gpu-surface->rgba-bytes s)))
  (define (render-paint paint) (render (lambda (c) (draw-paint c paint))))
  (define (same-context resource) (check-eq? (skia-resource-gpu-context resource) gpu))
  (define (held factory proc)
    (call-with-skia-resource (call-with-gpu-context gpu factory) proc))
  (define (retained-shader)
    (with-skia ([cpu (cpu-image)] [im (gpu-upload-image gpu cpu)])
      (make-image-shader im #:tile-x 'repeat #:tile-y 'repeat)))
  (test-suite
   "GPU images: live uploads, snapshots, transitive graphs, and explicit transfers"
   (test-case "upload returns an ordinary image with explicit GPU ownership"
     (uploaded (lambda (cpu im)
                 (check-true (image? im)) (check-true (gpu-image? im))
                 (check-eq? (image-residency cpu) 'cpu)
                 (check-eq? (image-residency im) 'gpu)
                 (same-context im)
                 (define info (gpu-image-info im))
                 (check-true (hash-ref info 'texture_backed))
                 (check-true (hash-ref info 'context_matches))
                 (check-equal? (hash-ref info 'backend) "opengl"))))
   (test-case "uploaded pixels survive an explicit image readback"
     (uploaded (lambda (cpu im) (check-equal? (gpu-image->rgba-bytes im) image-test-pixels))))
   (test-case "CPU upload source remains independent and unchanged"
     (uploaded (lambda (cpu im)
                 (check-false (skia-resource-gpu-context cpu))
                 (check-equal? (image->rgba-bytes cpu) image-test-pixels))))
   (test-case "closing the CPU source does not invalidate an upload"
     (uploaded (lambda (cpu im)
                 (skia-close! cpu)
                 (check-equal? (gpu-image->rgba-bytes im) image-test-pixels))))
   (test-case "mipmapped upload is explicitly requested and remains texture-backed"
     (call-with-gpu-context gpu
       (lambda ()
         (with-skia ([cpu (cpu-image)] [im (gpu-upload-image gpu cpu #:mipmapped? #t)])
           (check-true (hash-ref (gpu-image-info im) 'texture_backed))
           (check-equal? (gpu-image->rgba-bytes im) image-test-pixels)))))
   (test-case "same-context image reuse creates an independently closeable reference"
     (uploaded (lambda (cpu im)
                 (with-skia ([copy (gpu-upload-image gpu im)])
                   (skia-close! im)
                   (check-equal? (gpu-image->rgba-bytes copy) image-test-pixels)))))
   (test-case "snapshot remains unchanged after the source surface is redrawn"
     (uploaded (lambda (cpu im)
                 (with-skia ([s (make-gpu-surface gpu 8 8)])
                   (draw-image (surface-canvas s) im 0 0)
                   (with-skia ([snap (gpu-surface-snapshot s)])
                     (canvas-clear! (surface-canvas s) (rgb 255 0 255))
                     (check-equal? (gpu-image->rgba-bytes snap) image-test-pixels))))))
   (test-case "GPU snapshot survives explicit source-surface closure"
     (call-with-gpu-context gpu
       (lambda ()
         (with-skia ([s (make-gpu-surface gpu 8 8 #:background 'blue)]
                     [im (gpu-surface-snapshot s)])
           (skia-close! s)
           (check-equal? (subbytes (gpu-image->rgba-bytes im) 0 4) (bytes 0 0 255 255))))))
   (test-case "snapshot rejects an unbalanced state stack"
     (call-with-gpu-context gpu
       (lambda ()
         (with-skia ([s (make-gpu-surface gpu 8 8)])
           (define c (surface-canvas s))
           (canvas-save! c)
           (check-exn exn:fail? (lambda () (gpu-surface-snapshot s)))
           (canvas-restore! c)))))
   (test-case "subset stays GPU-resident and uses the requested coordinates"
     (uploaded (lambda (cpu im)
                 (with-skia ([sub (gpu-image-subset im 4 4 4 4)])
                   (check-equal? (image-width sub) 4)
                   (same-context sub)
                   (check-equal? (gpu-image->rgba-bytes sub)
                                 (apply bytes (append* (make-list 16 '(255 255 0 255)))))))))
   (test-case "subset remains valid after source image closure"
     (uploaded (lambda (cpu im)
                 (with-skia ([sub (gpu-image-subset im 0 4 3 4)])
                   (skia-close! im)
                   (check-equal? (subbytes (gpu-image->rgba-bytes sub) 0 4) (bytes 0 0 255 255))))))
   (test-case "subset rejects invalid rectangles instead of clipping them"
     (uploaded (lambda (cpu im)
                 (for ([box '((-1 0 1 1) (0 0 0 1) (7 7 2 2) (0.0 0 1 1))])
                   (check-exn exn:fail? (lambda () (apply gpu-image-subset im box)))))))
   (test-case "ordinary image and shader drawing do not require CPU readback"
     (uploaded (lambda (cpu im)
                 (with-skia ([s (make-gpu-surface gpu 8 8)]
                             [sh (make-image-shader im)] [p (make-paint #:shader sh)])
                   (define-values (ignored events)
                     (call-with-gpu-io-trace
                      (lambda () (draw-image (surface-canvas s) im 0 0)
                        (draw-paint (surface-canvas s) p)
                        (gpu-flush-and-submit! gpu))))
                   (check-false (for/or ([e (in-list events)])
                                  (or (equal? (hash-ref e 'kind) "readback")
                                      (hash-ref e 'wait_requested #f))))
                   (check-equal? (gpu-surface->rgba-bytes s) image-test-pixels)))))
   (test-case "shader and paint retain a closed original GPU image"
     (uploaded (lambda (cpu im)
                 (with-skia ([sh (make-image-shader im)] [p (make-paint #:shader sh)])
                   (same-context sh) (same-context p)
                   (skia-close! im) (skia-close! sh)
                   (check-equal? (render-paint p) image-test-pixels)))))
   (test-case "local matrix and composed shader keep transitive affinity"
     (held retained-shader
       (lambda (sh)
         (call-with-gpu-context gpu
           (lambda ()
             (with-skia ([local (shader-with-local-matrix sh (make-matrix))]
                         [background (make-color-shader 'transparent)]
                         [mixed (make-blend-shader 'src-over background local)]
                         [p (make-paint #:shader mixed)])
               (same-context local) (same-context mixed)
               (skia-close! sh) (skia-close! local)
               (check-equal? (render-paint p) image-test-pixels)))))))
   (test-case "paint clone and retained shader getter outlive their original wrappers"
     (held retained-shader
       (lambda (sh)
         (call-with-gpu-context gpu
           (lambda ()
             (with-skia ([p (make-paint #:shader sh)] [copy (paint-copy p)] [getter (paint-shader p)])
               (same-context copy) (same-context getter)
               (skia-close! p) (skia-close! sh)
               (check-equal? (render-paint copy) image-test-pixels)
               (with-skia ([replacement (make-paint #:shader getter)])
                 (check-equal? (render-paint replacement) image-test-pixels))))))))
   (test-case "CPU getter is not contaminated by an unrelated GPU paint slot"
     (uploaded (lambda (cpu im)
                 (with-skia ([solid (make-color-shader 'red)]
                             [filter (make-image-source-filter im)]
                             [p (make-paint #:shader solid #:image-filter filter)]
                             [getter (paint-shader p)] [fg (paint-image-filter p)])
                   (check-false (skia-resource-gpu-context getter))
                   (same-context fg)))))
   (test-case "cleared paint can be used on a CPU surface again"
     (uploaded (lambda (cpu im)
                 (with-skia ([sh (make-image-shader im)] [p (make-paint #:shader sh #:color 'red)]
                             [s (make-surface 8 8)])
                   (paint-set-shader! p #f)
                   (check-false (skia-resource-gpu-context p))
                   (draw-paint (surface-canvas s) p)
                   (check-equal? (surface-pixel s 0 0) (rgb 255 0 0))))))
   (test-case "clearing one paint slot preserves a GPU filter dependency"
     (uploaded (lambda (cpu im)
                 (with-skia ([sh (make-image-shader im)] [f (make-image-source-filter im #:sampling 'nearest)]
                             [p (make-paint #:shader sh #:image-filter f)])
                   (paint-set-shader! p #f)
                   (same-context p)
                   (skia-close! f) (skia-close! im)
                   (check-equal? (render-paint p) image-test-pixels)
                   (paint-set-image-filter! p #f)
                   (check-false (skia-resource-gpu-context p))))))
   (test-case "image filter composition and retained getter keep the original image"
     (uploaded (lambda (cpu im)
                 (with-skia ([source (make-image-source-filter im #:sampling 'nearest)]
                             [offset (make-offset-image-filter 0 0 #:input source #:crop '(0 0 8 8))]
                             [p (make-paint #:image-filter offset)] [getter (paint-image-filter p)])
                   (same-context source) (same-context offset) (same-context getter)
                   (skia-close! source) (skia-close! im) (skia-close! offset)
                   (check-equal? (render-paint p) image-test-pixels)))))
   (test-case "shader image filter retains GPU children"
     (held retained-shader
       (lambda (sh)
         (call-with-gpu-context gpu
           (lambda ()
             (with-skia ([f (make-shader-image-filter sh #:crop '(0 0 8 8))]
                         [p (make-paint #:image-filter f)])
               (same-context f) (skia-close! sh)
               (check-equal? (render-paint p) image-test-pixels)))))))
   (test-case "runtime shader child remains valid after child and effect closure"
     (held retained-shader
       (lambda (sh)
         (call-with-gpu-context gpu
           (lambda ()
             (with-skia ([effect (make-runtime-effect "uniform shader tex; half4 main(float2 p) { return tex.eval(p); }")]
                         [runtime (runtime-effect->shader effect #:children (hash "tex" sh))]
                         [p (make-paint #:shader runtime)])
               (same-context runtime) (skia-close! sh) (skia-close! effect)
               (check-equal? (render-paint p) image-test-pixels)))))))
   (test-case "recorded picture remains usable after original GPU image closure"
     (uploaded (lambda (cpu im)
                 (with-skia ([picture (call-with-picture 8 8 (lambda (c) (draw-image c im 0 0)))])
                   (same-context picture) (skia-close! im)
                   (check-equal? (render (lambda (c) (draw-picture c picture))) image-test-pixels)))))
   (test-case "nested picture and picture shader preserve transitive affinity"
     (uploaded (lambda (cpu im)
                 (with-skia ([p1 (call-with-picture 8 8 (lambda (c) (draw-image c im 0 0)))]
                             [p2 (call-with-picture 8 8 (lambda (c) (draw-picture c p1)))]
                             [sh (make-picture-shader p2 #:tile-rect '(0 0 8 8) #:sampling 'nearest)]
                             [paint (make-paint #:shader sh)])
                   (same-context p2) (same-context sh)
                   (skia-close! im) (skia-close! p1) (skia-close! p2)
                   (check-equal? (render-paint paint) image-test-pixels)))))
   (test-case "finished recorder is independent while its picture stays GPU-bound"
     (uploaded (lambda (cpu im)
                 (with-skia ([rec (make-picture-recorder)])
                   (draw-image (picture-recorder-begin-recording! rec 0 0 8 8) im 0 0)
                   (same-context rec)
                   (with-skia ([pic (picture-recorder-finish-recording! rec)])
                     (check-false (skia-resource-gpu-context rec))
                     (same-context pic))))))
   (test-case "GPU-dependent picture serialization and CPU rasterization are rejected"
     (uploaded (lambda (cpu im)
                 (with-skia ([pic (call-with-picture 8 8 (lambda (c) (draw-image c im 0 0)))])
                   (check-exn #rx"GPU" (lambda () (picture->bytes pic)))
                   (check-exn #rx"GPU" (lambda () (picture->image pic 8 8)))))))
   (test-case "GPU image rejects implicit encoding readback and raster subset"
     (uploaded (lambda (cpu im)
                 (for ([operation (list image->rgba-bytes image->png-bytes image->jpeg-bytes
                                        image->webp-bytes image-original-encoded-bytes)])
                   (check-exn #rx"GPU" (lambda () (operation im))))
                 (check-exn #rx"GPU" (lambda () (image-subset im 0 0 4 4))))))
   (test-case "CPU PDF and SVG targets reject GPU image graphs before drawing"
     (uploaded (lambda (cpu im)
                 (with-skia ([s (make-surface 8 8)])
                   (check-exn exn:fail? (lambda () (draw-image (surface-canvas s) im 0 0))))
                 (check-exn #rx"GPU" (lambda () (call-with-svg-bytes 8 8 (lambda (c) (draw-image c im 0 0)))))
                 (check-exn #rx"GPU" (lambda () (call-with-pdf-bytes (lambda (d)
                                             (call-with-document-page d 8 8 (lambda (c) (draw-image c im 0 0))))))))))
   (test-case "cross-context upload rejects without implicit transfer"
     (held (lambda () (with-skia ([cpu (cpu-image)]) (gpu-upload-image gpu cpu)))
       (lambda (im)
         (call-with-gpu-context other
           (lambda () (check-exn exn:fail? (lambda () (gpu-upload-image other im))))))))
   (test-case "cross-context retained shader and paint access rejects"
     (held retained-shader
       (lambda (sh)
         (call-with-gpu-context other
           (lambda ()
             (check-exn exn:fail? (lambda () (make-paint #:shader sh)))
             (with-skia ([target (make-gpu-surface other 8 8)])
               (check-exn exn:fail? (lambda () (make-shader-image-filter sh)))))))))
   (test-case "image access without activation or from another thread rejects"
     (held (lambda () (with-skia ([cpu (cpu-image)]) (gpu-upload-image gpu cpu)))
       (lambda (im)
         (check-exn exn:fail? (lambda () (gpu-image->rgba-bytes im)))
         (check-true (exn:fail? (in-worker (lambda () (gpu-image-info im))))))))
   (test-case "live retained shader prevents premature context teardown"
     (held retained-shader
       (lambda (sh)
         (check-exn exn:fail? (lambda () (gpu-context-close! gpu)))
         (call-with-gpu-context gpu
           (lambda ()
             (with-skia ([p (make-paint #:shader sh)])
               (check-equal? (render-paint p) image-test-pixels)))))))
   (test-case "explicit detachment permits CPU encoding and another-context upload"
     (define detached
       (call-with-gpu-context gpu
         (lambda ()
           (with-skia ([cpu (cpu-image)] [im (gpu-upload-image gpu cpu)])
             (gpu-image->raster-image im)))))
     (call-with-skia-resource detached
       (lambda (cpu)
         (check-eq? (image-residency cpu) 'cpu)
         (check-false (skia-resource-gpu-context cpu))
         (check-equal? (image->rgba-bytes cpu) image-test-pixels)
         (check-true (positive? (bytes-length (image->png-bytes cpu))))
         (call-with-gpu-context other
           (lambda ()
             (with-skia ([im (gpu-upload-image other cpu)])
               (check-eq? (skia-resource-gpu-context im) other)
               (check-equal? (gpu-image->rgba-bytes im) image-test-pixels)))))))
   (test-case "readback into a padded raster buffer preserves row padding"
     (uploaded (lambda (cpu im)
                 (with-skia ([buffer (make-raster-buffer 8 8 #:row-bytes 40)])
                   (gpu-image-read-raster-buffer! im buffer)
                   (check-equal? (raster-buffer->rgba-bytes buffer) image-test-pixels)
                   (define storage (raster-buffer->storage-bytes buffer))
                   (for ([y (in-range 8)])
                     (check-equal? (subbytes storage (+ (* y 40) 32) (* (add1 y) 40))
                                   (make-bytes 8 0)))))))
   (test-case "half-alpha and color-space metadata survive explicit detachment"
     (call-with-gpu-context gpu
       (lambda ()
         (with-skia ([cs (make-linear-srgb-color-space)]
                     [cpu (rgba-bytes->image 1 1 (bytes 128 0 0 128) #:premultiplied? #t #:color-space cs)]
                     [im (gpu-upload-image gpu cpu)] [space (image-color-space im)]
                     [detached (gpu-image->raster-image im)])
           (check-false (skia-resource-gpu-context space))
           (check-true (color-space=? cs space))
           (check-equal? (gpu-image->rgba-bytes im #:premultiplied? #t) (bytes 128 0 0 128))
           (check-equal? (image->rgba-bytes detached #:premultiplied? #t) (bytes 128 0 0 128))))))
   (test-case "closed GPU image never revives in a later activation"
     (held (lambda () (with-skia ([cpu (cpu-image)]) (gpu-upload-image gpu cpu)))
       (lambda (im)
         (skia-close! im)
         (call-with-gpu-context gpu
           (lambda ()
             (check-exn exn:fail? (lambda () (gpu-image-info im)))
             (check-exn exn:fail? (lambda () (make-image-shader im))))))))
   (test-case "lazy encoded CPU image uploads without changing source residency"
     (call-with-gpu-context gpu
       (lambda ()
         (with-skia ([raw (cpu-image)] [encoded (image-from-bytes (image->png-bytes raw))]
                     [im (gpu-upload-image gpu encoded)])
           (check-eq? (image-residency encoded) 'cpu)
           (check-false (skia-resource-gpu-context encoded))
           (check-equal? (gpu-image->rgba-bytes im) image-test-pixels)))))
   (test-case "picture keeps the recorded paint snapshot after the mutable paint is cleared"
     (uploaded
      (lambda (cpu im)
        (with-skia ([shader (make-image-shader im)] [paint (make-paint #:shader shader)]
                    [picture (call-with-picture 8 8 (lambda (c) (draw-paint c paint)))])
          (paint-set-shader! paint #f)
          (check-false (skia-resource-gpu-context paint))
          (same-context picture)
          (skia-close! im) (skia-close! shader)
          (gpu-drain-releases! gpu)
          (check-equal? (render (lambda (c) (draw-picture c picture))) image-test-pixels)))))
   (test-case "GPU-backed picture image filter retains a closed source picture"
     (uploaded
      (lambda (cpu im)
        (with-skia ([picture (call-with-picture 8 8 (lambda (c) (draw-image c im 0 0)))]
                    [filter (make-picture-image-filter picture #:crop '(0 0 8 8))]
                    [paint (make-paint #:image-filter filter)])
          (same-context filter)
          (skia-close! im) (skia-close! picture) (skia-close! filter)
          (gpu-drain-releases! gpu)
          (check-equal? (render-paint paint) image-test-pixels)))))
   (test-case "GPU image buffer readback rejects an active pixmap lease"
     (uploaded
      (lambda (cpu im)
        (with-skia ([buffer (make-raster-buffer 8 8)])
          (call-with-raster-buffer-pixmap buffer
            (lambda (view)
              (check-exn #rx"active|borrow|scope"
                (lambda () (gpu-image-read-raster-buffer! im buffer)))))
          (check-equal? (raster-buffer->storage-bytes buffer) (make-bytes 256))))))
   (test-case "GPU image buffer readback rejects incompatible dimensions without writes"
     (uploaded
      (lambda (cpu im)
        (with-skia ([buffer (make-raster-buffer 4 8)])
          (check-exn #rx"dimensions" (lambda () (gpu-image-read-raster-buffer! im buffer)))
          (check-equal? (raster-buffer->storage-bytes buffer) (make-bytes 128))))))
   (test-case "closing a retained shader outside activation queues its native destruction"
     (held retained-shader
       (lambda (shader)
         (skia-close! shader)
         (check-true (positive? (hash-ref (gpu-context-info gpu) 'pending_releases)))
         (call-with-gpu-context gpu void)
         (check-equal? (hash-ref (gpu-context-info gpu) 'pending_releases) 0))))
))
