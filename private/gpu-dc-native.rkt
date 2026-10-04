#lang racket/base
(require (prefix-in sk: "../main.rkt") (prefix-in gpu: "../gpu.rkt")
         "dc-render.rkt" "dc-native-util.rkt" "gpu-dc-scope.rkt"
         (only-in (submod "gpu-presenter.rkt" adapter-internals) call-with-gpu-frame-target))
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
  ;; Retain one compatible staging surface, but NEVER the callback DC or a
  ;; borrowed frame canvas. A fresh DC clears the root and owns its own state
  ;; and alpha stack each time. Failed/escaped DC scopes discard this target.
  (call-with-gpu-frame-target frame
   (dc-frame-size-pixel-width extent) (dc-frame-size-pixel-height extent)
   (lambda ()
     (gpu:make-gpu-surface context (dc-frame-size-pixel-width extent)
                           (dc-frame-size-pixel-height extent) #:background 'transparent))
   sk:skia-close!
   (lambda (staging)
     (unless (= 1 (sk:canvas-save-count (sk:surface-canvas staging)))
       (error 'call-with-gpu-frame-dc "cached staging surface has an unbalanced canvas stack"))
     (call-with-frame-dc/renderer
      (gpu-renderer context staging) extent proc
      (lambda (root)
        ;; Transactional commit remains GPU-to-GPU. Keeping this boundary
        ;; preserves explicit snapshots and prevents partial callback drawing
        ;; from reaching the presenter target on a user exception or escape.
        (gpu:gpu-frame-canvas frame)
        (sk:with-skia ([image (gpu:gpu-surface-snapshot root)]
                      [paint (sk:make-paint #:blend-mode 'src #:antialias? #f)])
          (sk:call-with-canvas-state canvas
            (lambda ()
              (set-matrix! canvas '#(1.0 0.0 0.0 1.0 0.0 0.0))
              (sk:draw-image canvas image 0 0 #:paint paint)))))
      #:background background #:smoothing smoothing #:clear? #t))))

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
