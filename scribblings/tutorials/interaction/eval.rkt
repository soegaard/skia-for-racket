#lang racket/base

(require racket/runtime-path
         scribble/eval
         (except-in skia draw-points)
         (prefix-in draw: racket/draw)
         (prefix-in pict: pict)
         "scene.rkt")

(provide interaction-interaction
         editor-frame-pict
         editor-stage-pict
         editor-hit-area-pict
         editor-before-and-after-pict)

(define-runtime-path scene-module "scene.rkt")

(define interaction-eval (make-base-eval))
(interaction-eval '(require racket))
(interaction-eval `(require (file ,(path->string scene-module))))

;; A source figure should never be allowed to degrade into a black rectangle.
(define (check-editor-figure surface)
  (define pixels (surface->rgba-bytes surface))
  (define (channel x y offset)
    (bytes-ref pixels (+ (* 4 (+ x (* editor-width y))) offset)))
  (unless (and (<= (abs (- (channel 5 5 0) 12)) 2)
               (<= (abs (- (channel 5 5 1) 24)) 2)
               (<= (abs (- (channel 5 5 2) 43)) 2)
               (> (channel 120 320 0) 170)
               (> (channel 120 320 1) 85))
    (error 'editor-frame-pict
           "the Skia figure is missing its colored background or endpoint")))

;; Use the same geometry helpers as the editor for the progressive figures.
(define (editor-stage-pict stage #:scale [scale 0.60])
  (unless (memq stage '(curve guides))
    (raise-argument-error 'editor-stage-pict "'curve or 'guides" stage))
  (with-skia ([surface (make-surface editor-width editor-height
                                    #:background editor-background)])
    (define canvas (surface-canvas surface))
    (canvas-clear! canvas editor-background)
    (when (eq? stage 'guides)
      (draw-guides canvas initial-control-points))
    (draw-curve canvas initial-control-points)
    (when (eq? stage 'guides)
      (draw-points canvas initial-control-points #f))
    (surface-picture surface scale)))

;; This is a geometric diagram, not a second rendering implementation. The
;; outlined selection area is shown at 3x scale; the editor does not draw it.
(define (editor-hit-area-pict #:scale [scale 1])
  (define enlargement 3)
  (with-skia ([surface (make-surface 400 210 #:background editor-background)]
              [radius-paint (make-paint #:color "#779CBA"
                                        #:style 'stroke #:stroke-width 2)]
              [marker-paint (make-paint #:color "#56D3E1")]
              [ink (make-paint #:color "#E6F2FB")]
              [font (make-font #:size 17)])
    (define canvas (surface-canvas surface))
    (define x 105)
    (define y 103)
    (canvas-clear! canvas editor-background)
    (draw-circle canvas x y (* enlargement hit-radius) radius-paint)
    (draw-circle canvas x y (* enlargement marker-radius) marker-paint)
    (draw-simple-text canvas "P1" 184 76 font ink)
    (draw-simple-text canvas (format "~a-unit hit radius" hit-radius) 184 108 font ink)
    (draw-simple-text canvas (format "~a-unit marker radius" marker-radius) 184 142 font ink)
    (surface-picture surface scale)))

(define (surface-picture surface scale)
  (pict:scale
   (pict:bitmap
    (draw:read-bitmap
     (open-input-bytes (surface->png-bytes surface))
     'png/alpha))
   scale))

(define (editor-frame-pict [points initial-control-points]
                           #:selected [selected #f]
                           #:scale [scale 0.68])
  (with-skia ([surface (make-surface editor-width editor-height
                                    #:background editor-background)])
    (draw-editor (surface-canvas surface)
                 points editor-width editor-height selected)
    (when (eq? points initial-control-points)
      (check-editor-figure surface))
    (surface-picture surface scale)))

(define (captioned label picture)
  (pict:vc-append 8 (pict:text label) picture))

(define (editor-before-and-after-pict)
  (define moved (move-control-point initial-control-points 1 302 150))
  (pict:ht-append
   18
   (captioned "Before dragging P1"
              (editor-frame-pict #:scale 0.39))
   (captioned "After dragging P1"
              (editor-frame-pict moved #:selected 1 #:scale 0.39))))

(define-syntax-rule (interaction-interaction expression ...)
  (interaction #:eval interaction-eval expression ...))
