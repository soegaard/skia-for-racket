#lang racket/base

(require racket/runtime-path
         scribble/eval
         skia
         (prefix-in draw: racket/draw)
         (prefix-in pict: pict)
         "scene.rkt")

(provide gpu-interaction
         gpu-racketblock+eval
         gpu-image
         gpu-cpu-reference-pict
         gpu-metal-reference-pict
         gpu-comparison-pict
         gpu-metal-reference-generated?)

(define-runtime-path scene-module "scene.rkt")
(define-runtime-path metal-reference
  "figures/metal-reference.png")
(define-runtime-path metal-placeholder
  "figures/metal-reference-placeholder.png")

(define gpu-eval
  (make-base-eval))

(gpu-eval
 '(require racket
           skia))

(gpu-eval
 `(require (file ,(path->string scene-module))))

(define (image-file->pict path scale)
  (pict:scale
   (pict:bitmap
    (draw:read-bitmap path 'png/alpha))
   scale))

(define (gpu-cpu-reference-pict
         #:scale [scale 0.72])
  (with-skia
      ([surface
        (make-surface
         scene-width scene-height
         #:background scene-background)])
    (draw-scene
     (surface-canvas surface))
    (pict:scale
     (pict:bitmap
      (draw:read-bitmap
       (open-input-bytes
        (surface->png-bytes surface))
       'png/alpha))
     scale)))

(define (gpu-metal-reference-generated?)
  (file-exists? metal-reference))

(define (gpu-metal-reference-pict
         #:scale [scale 0.72])
  (image-file->pict
   (if (gpu-metal-reference-generated?)
       metal-reference
       metal-placeholder)
   scale))

(define (captioned label picture)
  (pict:vc-append
   8
   (pict:text label)
   picture))

(define (gpu-comparison-pict
         #:scale [scale 0.42])
  (define metal-label
    (if (gpu-metal-reference-generated?)
        "Metal GPU surface"
        "Metal GPU surface — placeholder"))
  (pict:ht-append
   24
   (captioned
    "CPU raster surface"
    (gpu-cpu-reference-pict #:scale scale))
   (captioned
    metal-label
    (gpu-metal-reference-pict #:scale scale))))

(define-syntax-rule (gpu-interaction expression ...)
  (interaction #:eval gpu-eval expression ...))

(define-syntax-rule
  (gpu-racketblock+eval expression ...)
  (racketblock+eval
   #:eval gpu-eval
   expression ...))

(define-syntax-rule (gpu-image expression)
  (interaction-eval-show
   #:eval gpu-eval
   expression))
