#lang racket/base
(require (prefix-in sk: "../main.rkt") (prefix-in gpu: "../gpu.rkt")
         "dc-render.rkt" "dc-native-util.rkt" "gpu-dc-scope.rkt" "gpu-format-util.rkt"
         (only-in (submod "gpu-presenter.rkt" adapter-internals) call-with-gpu-frame-target))
(provide call-with-gpu-frame-dc/native call-with-gpu-surface-dc/native)

(define (gpu-renderer context [borrowed-root #f]
                      [color-type 'rgba-8888] [space #f] [samples 0]
                      [properties (sk:make-surface-properties)])
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
       [else
        (gpu:make-gpu-surface context width height #:background 'transparent
          #:color-type color-type #:color-space space #:sample-count samples
          #:surface-properties properties)]))
   (lambda (surface)
     (if (eq? surface borrowed-root) (set! borrowed-root #f) (sk:skia-close! surface)))
   gpu:gpu-surface->raster-image
   (lambda (surface premultiplied?)
     (gpu:gpu-surface->rgba-bytes surface #:premultiplied? premultiplied?))
   (lambda (surface)
     (sk:with-skia ([image (gpu:gpu-surface->raster-image surface)])
       (sk:image->png-bytes image)))
   #:internal-snapshot gpu:gpu-surface-snapshot))

(define (call-with-gpu-frame-dc/native frame proc background smoothing
                                      [color-type 'rgba-8888] [descriptor #f] [samples 0]
                                      [properties (sk:make-surface-properties)])
  (define canvas (gpu:gpu-frame-canvas frame))
  (define context (gpu:gpu-frame-context frame))
  (define extent
    (checked-frame-size (gpu:gpu-frame-width frame) (gpu:gpu-frame-height frame)
                        (gpu:gpu-frame-logical-width frame) (gpu:gpu-frame-logical-height frame)))
  (define width (dc-frame-size-pixel-width extent))
  (define height (dc-frame-size-pixel-height extent))
  (define key (gpu-staging-key 'call-with-gpu-frame-dc width height color-type descriptor samples properties))
  (define space (sk:descriptor->color-space (vector-ref key 2)))
  (dynamic-wind void
    (lambda ()
      (call-with-gpu-frame-target frame width height
       (lambda ()
         (gpu:make-gpu-surface context width height #:background 'transparent
           #:color-type color-type #:color-space space #:sample-count samples
           #:surface-properties properties))
       sk:skia-close!
       (lambda (staging)
         (unless (= 1 (sk:canvas-save-count (sk:surface-canvas staging)))
           (error 'call-with-gpu-frame-dc "cached staging surface has an unbalanced canvas stack"))
         (call-with-frame-dc/renderer
          (gpu-renderer context staging color-type space samples properties) extent proc
          (lambda (root)
            ;; Commit remains GPU-to-GPU; presentation may explicitly quantize
            ;; the selected staging format to the window's existing SDR format.
            (gpu:gpu-frame-canvas frame)
            (sk:with-skia ([image (gpu:gpu-surface-snapshot root)]
                          [paint (sk:make-paint #:blend-mode 'src #:antialias? #f)])
              (sk:call-with-canvas-state canvas
                (lambda ()
                  (set-matrix! canvas '#(1.0 0.0 0.0 1.0 0.0 0.0))
                  (sk:draw-image canvas image 0 0 #:paint paint)))))
          #:background background #:smoothing smoothing #:clear? #t))
       #:configuration key))
    (lambda () (when space (sk:skia-close! space)))))

(define (call-with-gpu-surface-dc/native surface proc lw lh background smoothing clear?)
  (unless (gpu:gpu-surface? surface)
    (raise-argument-error 'call-with-gpu-surface-dc "gpu-surface?" surface))
  (define description (gpu:gpu-surface-info surface))
  (unless (= 1 (sk:canvas-save-count (sk:surface-canvas surface)))
    (error 'call-with-gpu-surface-dc "borrowed surface requires a balanced native canvas stack"))
  (define width (sk:surface-width surface)) (define height (sk:surface-height surface))
  (define extent (checked-frame-size width height (or lw width) (or lh height)))
  (define info (gpu:gpu-surface->image-info surface))
  ;; The dc<%> compositor requires full-color transparent alpha intermediates.
  (define color (sk:image-info-color-type info))
  (unless (memq color '(rgba-8888 bgra-8888 rgba-f16 rgba-f32))
    (error 'call-with-gpu-surface-dc "DC alpha groups require an RGBA/BGRA/F16/F32 target"))
  (define space (sk:surface-color-space surface))
  (define properties (sk:surface-properties-of surface))
  (dynamic-wind void
    (lambda ()
      (call-with-frame-dc/renderer
       (gpu-renderer (gpu:skia-resource-gpu-context surface) surface color space
                     (hash-ref description 'requested_sample_count 0) properties)
       extent proc void #:background background #:smoothing smoothing #:clear? clear?))
    (lambda () (when space (sk:skia-close! space)))))
