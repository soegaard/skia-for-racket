#lang racket

;;;
;;; Sprite Assets
;;;

;; Owns a CPU atlas and its lazily uploaded, context-bound GPU image.
;; This module supports documentation assembly and shared examples rather than the public Skia
;; API.


;; Documentation-local ownership helper. The library API is unchanged.
;;;
;;; Imports and Exports
;;;

(require skia skia/gpu)
(provide make-sprite-texture sprite-texture-cpu sprite-texture-uploads
         sprite-texture-for-frame! close-sprite-texture!)

;;;
;;; Documentation Data and Helpers
;;;

(struct sprite-texture (cpu [gpu #:mutable] [context #:mutable] [uploads #:mutable])
  #:constructor-name make-texture-record)
;; cpu: live CPU image whose ownership is transferred to this helper.
;; gpu: mutable GPU image or #f before upload or after closing the cached wrapper.
;; context: mutable GPU context identity, initially #f and captured on first upload.
;; uploads: mutable exact nonnegative count of successful uploads.
;; A cached GPU image may only be reused by a frame with the identical context.
;; Close the GPU wrapper before the CPU image and before presenter shutdown.
;; A closed texture is not reusable; closing does not reset its context identity.

; make-sprite-texture : image? -> sprite-texture?
;   Takes ownership of a live CPU atlas and initializes an empty GPU cache.
(define (make-sprite-texture cpu)
  (unless (and (image? cpu) (eq? (image-residency cpu) 'cpu))
    (raise-argument-error 'make-sprite-texture "live CPU image" cpu))
  ;; Ownership of this CPU wrapper is transferred to the helper.
  (make-texture-record cpu #f #f 0))

; sprite-texture-for-frame! : sprite-texture? gpu-frame? -> image?
;   Uploads the atlas once and rejects later use from a different GPU context.
(define (sprite-texture-for-frame! texture frame)
  (define context (gpu-frame-context frame))
  (cond
    [(sprite-texture-gpu texture)
     (unless (eq? context (sprite-texture-context texture))
       (error 'sprite-texture-for-frame! "atlas belongs to a different GPU context"))]
    [else
     ;; The presenter has already activated this context for the frame callback.
     (define image (gpu-upload-image context (sprite-texture-cpu texture)))
     (set-sprite-texture-gpu! texture image)
     (set-sprite-texture-context! texture context)
     (set-sprite-texture-uploads! texture (add1 (sprite-texture-uploads texture)))])
  (sprite-texture-gpu texture))

; close-sprite-texture! : sprite-texture? -> void?
;   Closes the GPU wrapper before releasing the owned CPU atlas.
(define (close-sprite-texture! texture)
  ;; Close the context-bound wrapper before asking the presenter to close.
  ;; Skia queues its native release for the context's owner to drain.
  (when (sprite-texture-gpu texture)
    (skia-close! (sprite-texture-gpu texture))
    (set-sprite-texture-gpu! texture #f))
  (skia-close! (sprite-texture-cpu texture)))
