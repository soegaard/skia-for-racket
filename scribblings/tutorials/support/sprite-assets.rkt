#lang racket

;; Documentation-local ownership helper. The library API is unchanged.
(require skia skia/gpu)
(provide make-sprite-texture sprite-texture-cpu sprite-texture-uploads
         sprite-texture-for-frame! close-sprite-texture!)

(struct sprite-texture (cpu [gpu #:mutable] [context #:mutable] [uploads #:mutable])
  #:constructor-name make-texture-record)

(define (make-sprite-texture cpu)
  (unless (and (image? cpu) (eq? (image-residency cpu) 'cpu))
    (raise-argument-error 'make-sprite-texture "live CPU image" cpu))
  ;; Ownership of this CPU wrapper is transferred to the helper.
  (make-texture-record cpu #f #f 0))

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

(define (close-sprite-texture! texture)
  ;; Close the context-bound wrapper before asking the presenter to close.
  ;; Skia queues its native release for the context's owner to drain.
  (when (sprite-texture-gpu texture)
    (skia-close! (sprite-texture-gpu texture))
    (set-sprite-texture-gpu! texture #f))
  (skia-close! (sprite-texture-cpu texture)))
