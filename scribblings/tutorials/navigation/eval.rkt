#lang racket/base

(require racket/runtime-path scribble/eval skia
         "model.rkt" "scene.rkt" "../support/figures.rkt")
(provide navigation-interaction navigation-pict navigation-views navigation-anchor-pair)
(define-runtime-path model-source "model.rkt")
(define navigation-eval (make-base-eval))
(navigation-eval '(require racket))
(navigation-eval `(require (file ,(path->string model-source))))

(define (navigation-pict [view home-view] #:scale [scale 0.8])
  (render-pict editor-width editor-height
               (lambda (canvas)
                 (draw-editor canvas initial-points view editor-width editor-height))
               #:scale scale))

(define (navigation-views)
  (figure-row
   (captioned-pict "Pan: (+90, +30)" (navigation-pict (pan-view home-view 90 30) #:scale 0.39))
   (captioned-pict "Zoom: 1.5 at the origin" (navigation-pict (view-state 1.5 0 0) #:scale 0.39))))

(define (navigation-anchor-pair)
  (define (one view)
    (render-pict editor-width editor-height
                 (lambda (canvas)
                   (define marker (make-paint #:color "#EE786A" #:style 'stroke #:stroke-width 2))
                   (draw-editor canvas initial-points view editor-width editor-height)
                   (draw-line canvas 386 270 414 270 marker)
                   (draw-line canvas 400 256 400 284 marker))
                 #:scale 0.39))
  (figure-row
   (captioned-pict "Before: anchor at (400, 270)" (one home-view))
   (captioned-pict "After: zoom 2 at the same anchor" (one (zoom-at home-view 400 270 2)))))

(define-syntax-rule (navigation-interaction expression ...)
  (interaction #:eval navigation-eval expression ...))
