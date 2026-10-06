#lang racket/base
(require "../main.rkt" "../gpu.rkt")
(provide render-half-float-image)
;; The caller selects a backend and activates its own context. The returned
;; CPU image is independently owned and retains F16 precision after shutdown.
(define (render-half-float-image context)
  (call-with-gpu-context context
    (lambda ()
      (with-skia ([surface (make-gpu-surface context 64 32 #:color-type 'rgba-f16
                            #:surface-properties
                            (make-surface-properties #:device-independent-fonts? #t))])
        (canvas-clear-color4f! (surface-canvas surface) (make-color4f 0.5009765625 0.25 1.25 1))
        (gpu-surface->raster-image surface)))))
;; Explicit document conversion:
;; (with-skia ([cpu (render-half-float-image context)]
;;             [pixels (image->raster-buffer cpu #:info (make-image-info 64 32))]
;;             [sdr (raster-buffer->image pixels)])
;;   (save-image sdr "sdr.png" 'png))
