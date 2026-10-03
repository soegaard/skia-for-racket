#lang racket/base
(require (prefix-in sk: "../main.rkt") (prefix-in gpu: "../gpu.rkt")
         "dc-render.rkt" "dc-native-util.rkt" "gpu-dc-scope.rkt")
(provide call-with-gpu-frame-dc/native call-with-gpu-surface-dc/native)

(define (gpu-renderer context [borrowed-root #f])
  (define root-issued? #f)
  (make-surface-dc-renderer
   (lambda (width height)
     (cond
       [(and borrowed-root (not root-issued?))
        (unless (and (= width (sk:surface-width borrowed-root))
                     (= height (sk:surface-height borrowed-root)))
          (error 'call-with-gpu-surface-dc "borrowed root dimensions changed"))
        (set! root-issued? #t)
        borrowed-root]
       [else (gpu:make-gpu-surface context width height #:background 'transparent)]))
   (lambda (surface)
     (if (eq? surface borrowed-root)
         (set! borrowed-root #f)
         (sk:skia-close! surface)))
   ;; Public output methods are explicitly synchronous CPU transfers. Returned
   ;; images/bytes survive both the DC scope and the original GPU context.
   gpu:gpu-surface->raster-image
   (lambda (surface premultiplied?)
     (gpu:gpu-surface->rgba-bytes surface #:premultiplied? premultiplied?))
   (lambda (surface)
     (sk:with-skia ([image (gpu:gpu-surface->raster-image surface)])
       (sk:image->png-bytes image)))
   ;; Overlap copies and alpha merges stay entirely on the same GPU context.
   #:internal-snapshot gpu:gpu-surface-snapshot))

(define (call-with-gpu-frame-dc/native frame proc background smoothing)
  (define canvas (gpu:gpu-frame-canvas frame))
  (define context (gpu:gpu-frame-context frame))
  (define extent
    (checked-frame-size (gpu:gpu-frame-width frame) (gpu:gpu-frame-height frame)
                        (gpu:gpu-frame-logical-width frame) (gpu:gpu-frame-logical-height frame)))
  (call-with-frame-dc/renderer
   (gpu-renderer context) extent proc
   (lambda (root)
     ;; Recheck the frame before touching its drawable. This is a GPU-to-GPU
     ;; composition, not a CPU bitmap bridge, PNG roundtrip, or zero-copy claim.
     (gpu:gpu-frame-canvas frame)
     (sk:with-skia ([image (gpu:gpu-surface-snapshot root)]
                   [paint (sk:make-paint #:blend-mode 'src #:antialias? #f)])
       (sk:call-with-canvas-state canvas
         (lambda ()
           (set-matrix! canvas '#(1.0 0.0 0.0 1.0 0.0 0.0))
           (sk:draw-image canvas image 0 0 #:paint paint)))))
   #:background background #:smoothing smoothing #:clear? #t))

(define (call-with-gpu-surface-dc/native surface proc lw lh background smoothing clear?)
  (unless (gpu:gpu-surface? surface)
    (raise-argument-error 'call-with-gpu-surface-dc "gpu-surface?" surface))
  ;; This also verifies that the owning thread/context is currently active.
  (gpu:gpu-surface-info surface)
  (unless (= 1 (sk:canvas-save-count (sk:surface-canvas surface)))
    (error 'call-with-gpu-surface-dc "borrowed surface requires a balanced native canvas stack"))
  (define width (sk:surface-width surface))
  (define height (sk:surface-height surface))
  (define extent (checked-frame-size width height (or lw width) (or lh height)))
  (call-with-frame-dc/renderer
   (gpu-renderer (gpu:skia-resource-gpu-context surface) surface)
   extent proc void #:background background #:smoothing smoothing #:clear? clear?))
