#lang racket/base

;;;
;;; Navigation Tutorial Evaluation
;;;

;; Runs the Navigation tutorial's executable documentation examples and figure helpers.
;; This module connects the manual to executable examples and their rendered figures.


;;;
;;; Imports and Exports
;;;

(require racket/runtime-path scribble/eval skia
         "model.rkt" "scene.rkt" "../support/figures.rkt")
(provide navigation-interaction navigation-pict navigation-views navigation-anchor-pair
         navigation-handle-sizes navigation-coordinate-pict)

;;;
;;; Tutorial Evaluator Setup
;;;

; model-source : path?
;   Locates model source relative to this module rather than the current directory.
(define-runtime-path model-source "model.rkt")

; navigation-eval : procedure?
;   Retains one evaluator so successive documentation examples share their bindings.
(define navigation-eval (make-base-eval))
(navigation-eval '(require racket))
(navigation-eval `(require (file ,(path->string model-source))))

;;;
;;; Coordinate and Viewport Figures
;;;

; navigation-pict : [view-state?] #:scale [real?] -> pict?
;   Renders the navigation illustration from the tutorial's drawing code.
(define (navigation-pict [view home-view] #:scale [scale 0.8])
  (render-pict editor-width editor-height
               (lambda (canvas)
                 (draw-editor canvas initial-points view editor-width editor-height))
               #:scale scale))

; navigation-coordinate-pict : -> pict?
;   Renders the navigation coordinate illustration from the tutorial's drawing code.
(define (navigation-coordinate-pict)
  (define view (view-state 2 40 -30))
  (define model-x 120)
  (define model-y 150)
  (define-values (window-x window-y) (model->screen view model-x model-y))
  (render-pict 684 390
               (lambda (canvas)
                 (define grid
                   (make-paint #:color "#DFE6ED" #:style 'stroke #:stroke-width 1))
                 (define axis
                   (make-paint #:color "#8192A4" #:style 'stroke #:stroke-width 1.5))
                 (define guide
                   (make-paint #:color "#25A5B6" #:style 'stroke #:stroke-width 1.5))
                 (define dot (make-paint #:color "#167F91"))
                 (define ink (make-paint #:color "#203653"))
                 (define font (make-font #:size 14))
                 (define title (make-font #:size 16))
                 (define (chart left label x y)
                   (define origin-x (+ left 16))
                   (define origin-y 52)
                   (define point-x (+ origin-x x))
                   (define point-y (+ origin-y y))
                   (draw-simple-text canvas label left 25 title ink)
                   (for ([step (in-range 50 301 50)])
                     (draw-line canvas (+ origin-x step) origin-y
                                (+ origin-x step) (+ origin-y 300) grid)
                     (draw-line canvas origin-x (+ origin-y step)
                                (+ origin-x 300) (+ origin-y step) grid))
                   (draw-line canvas origin-x origin-y (+ origin-x 300) origin-y axis)
                   (draw-line canvas origin-x origin-y origin-x (+ origin-y 300) axis)
                   (draw-simple-text canvas "(0, 0)" origin-x 44 font ink)
                   (draw-line canvas origin-x point-y point-x point-y guide)
                   (draw-line canvas point-x origin-y point-x point-y guide)
                   (draw-circle canvas point-x point-y 6 dot)
                   (draw-simple-text canvas (format "(~a, ~a)" x y)
                                     (+ point-x (if (> x 200) -100 12))
                                     (- point-y 12) font ink))
                 (chart 12 "Model coordinates" model-x model-y)
                 (chart 354 "Logical window coordinates" window-x window-y)
                 (draw-simple-text
                  canvas
                  (format "Zoom 2, pan (40, -30): (~a, ~a) maps to (~a, ~a)."
                          model-x model-y window-x window-y)
                  12 377 font ink))))

; navigation-views : -> pict?
;   Builds the navigation views illustration from the tutorial's actual drawing.
(define (navigation-views)
  (figure-row
   (captioned-pict "Before: zoom 1" (navigation-pict home-view #:scale 0.39))
   (captioned-pict "After: zoom 1.5 at (0, 0)"
                   (navigation-pict (view-state 1.5 0 0) #:scale 0.39))))

; navigation-anchor-pair : -> pict?
;   Builds the navigation anchor pair illustration from the tutorial's actual drawing.
(define (navigation-anchor-pair)
  ;; Anchor a visible model point, not an unmarked position in empty space.
  (define point (cadr initial-points))
  (define x (control-point-x point))
  (define y (control-point-y point))
  (define (one view)
    (render-pict editor-width editor-height
                 (lambda (canvas)
                   (define marker
                     (make-paint #:color "#EE786A" #:style 'stroke #:stroke-width 2))
                   (draw-editor canvas initial-points view editor-width editor-height)
                   (draw-circle canvas x y 22 marker))
                 #:scale 0.39))
  (figure-row
   (captioned-pict "Before: pointer on P1 (240, 150)" (one home-view))
   (captioned-pict "After: zoom 2, P1 stays put" (one (zoom-at home-view x y 2)))))

; navigation-handle-sizes : -> pict?
;   Builds the navigation handle sizes illustration from the tutorial's actual drawing.
(define (navigation-handle-sizes)
  (define point (cadr initial-points))
  (define (one zoom)
    ;; Put the actual P1 at (400, 250), then crop a 200-by-140 window around it.
    ;; The same draw-editor function draws the curve, marker, and label.
    (define view
      (view-state zoom (- 400 (* zoom (control-point-x point)))
                       (- 250 (* zoom (control-point-y point)))))
    (render-pict 200 140
                 (lambda (canvas)
                   (define hit-ring
                     (make-paint #:color "#EE786A" #:style 'stroke #:stroke-width 1))
                   (with-canvas-state canvas
                     (canvas-translate! canvas -300 -180)
                     (draw-editor canvas initial-points view editor-width editor-height)
                     (draw-circle canvas 400 250 18 hit-ring)))))
  (apply figure-row
         (for/list ([zoom '(1/2 1 2)])
           (captioned-pict (format "Zoom ~a / hit radius 18" zoom) (one zoom)))))

;;;
;;; Scribble Interaction Form
;;;

; navigation-interaction : syntax -> syntax
;   Displays and evaluates tutorial expressions in the shared documentation evaluator.
(define-syntax-rule (navigation-interaction expression ...)
  (interaction #:eval navigation-eval expression ...))
