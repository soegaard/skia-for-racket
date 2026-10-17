#lang racket/base

;;;
;;; GPU Tutorial Evaluation
;;;

;; Runs the GPU tutorial's executable documentation examples and figure helpers.
;; This module connects the manual to executable examples and their rendered figures.


;;;
;;; Imports and Exports
;;;

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

;;;
;;; Tutorial Evaluator Setup
;;;

; scene-module : path?
;   Locates scene module relative to this module rather than the current directory.
(define-runtime-path scene-module "scene.rkt")

; metal-reference : path?
;   Locates metal reference relative to this module rather than the current directory.
(define-runtime-path metal-reference
  "figures/metal-reference.png")

; metal-placeholder : path?
;   Locates metal placeholder relative to this module rather than the current directory.
(define-runtime-path metal-placeholder
  "figures/metal-reference-placeholder.png")

; gpu-eval : procedure?
;   Retains one evaluator so successive documentation examples share their bindings.
(define gpu-eval
  (make-base-eval))

(gpu-eval
 '(require racket
           skia))

(gpu-eval
 `(require (file ,(path->string scene-module))))

;;;
;;; CPU and Metal Comparison Figures
;;;

; image-file->pict : path-string? real? -> pict?
;   Renders the image file to pict illustration from the tutorial's drawing code.
(define (image-file->pict path scale)
  (pict:scale
   (pict:bitmap
    (draw:read-bitmap path 'png/alpha))
   scale))

; gpu-cpu-reference-pict : #:scale [real?] -> pict?
;   Renders the gpu cpu reference illustration from the tutorial's drawing code.
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

; gpu-metal-reference-generated? : -> boolean?
;   Reports whether the committed real Metal reference image is available.
(define (gpu-metal-reference-generated?)
  (file-exists? metal-reference))

; gpu-metal-reference-pict : #:scale [real?] -> pict?
;   Renders the gpu metal reference illustration from the tutorial's drawing code.
(define (gpu-metal-reference-pict
         #:scale [scale 0.72])
  (image-file->pict
   (if (gpu-metal-reference-generated?)
       metal-reference
       metal-placeholder)
   scale))

; captioned : any/c pict? -> pict?
;   Builds the captioned illustration from the tutorial's actual drawing.
(define (captioned label picture)
  (pict:vc-append
   8
   (pict:text label)
   picture))

; gpu-comparison-pict : #:scale [real?] -> pict?
;   Renders the gpu comparison illustration from the tutorial's drawing code.
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

;;;
;;; Scribble Interaction Forms
;;;

; gpu-interaction : syntax -> syntax
;   Displays and evaluates tutorial expressions in the shared documentation evaluator.
(define-syntax-rule (gpu-interaction expression ...)
  (interaction #:eval gpu-eval expression ...))

; gpu-racketblock+eval : syntax -> syntax
;   Displays a code block and evaluates the same expressions for the tutorial.
(define-syntax-rule
  (gpu-racketblock+eval expression ...)
  (racketblock+eval
   #:eval gpu-eval
   expression ...))

; gpu-image : syntax -> syntax
;   Evaluates the figure expression using the tutorial's shared drawing environment.
(define-syntax-rule (gpu-image expression)
  (interaction-eval-show
   #:eval gpu-eval
   expression))
