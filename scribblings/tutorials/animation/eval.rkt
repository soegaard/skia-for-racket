#lang racket/base

;;;
;;; Animation Tutorial Evaluation
;;;

;; Runs the Animation tutorial's executable documentation examples and figure helpers.
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

(provide animation-interaction
         animation-frame-pict
         animation-frame-strip)

;;;
;;; Tutorial Evaluator Setup
;;;

; scene-module : path?
;   Locates scene module relative to this module rather than the current directory.
(define-runtime-path scene-module "scene.rkt")

; animation-eval : procedure?
;   Retains one evaluator so successive documentation examples share their bindings.
(define animation-eval (make-base-eval))
(animation-eval '(require racket))
(animation-eval `(require (file ,(path->string scene-module))))

;;;
;;; Animation Frame Figures
;;;

;; Catch an all-black or incorrectly colored figure during a documentation build.


; check-frame-colors : surface? -> void?
;   Checks that the rendered animation frame contains the expected scene colors.
(define (check-frame-colors surface)
  (define pixels (surface->rgba-bytes surface))
  (define (channel x y offset)
    (bytes-ref pixels (+ (* 4 (+ x (* scene-width y))) offset)))
  (define (near? value expected)
    (<= (abs (- value expected)) 2))
  (unless (and (near? (channel 10 10 0) 10)
               (near? (channel 10 10 1) 23)
               (near? (channel 10 10 2) 42)
               (> (channel 380 220 0) 150)
               (> (channel 380 220 1) 150))
    (error 'animation-frame-pict
           "expected a dark-blue background and an illuminated center")))

; animation-frame-pict : real? #:scale [real?] -> pict?
;   Renders the animation frame illustration from the tutorial's drawing code.
(define (animation-frame-pict seconds #:scale [scale 0.68])
  (with-skia ([surface (make-surface scene-width scene-height
                                     #:background scene-background)])
    (draw-scene (surface-canvas surface) seconds scene-width scene-height)
    (check-frame-colors surface)
    (pict:scale
     (pict:bitmap
      (draw:read-bitmap
       (open-input-bytes (surface->png-bytes surface))
       'png/alpha))
     scale)))

; captioned-frame : real? -> pict?
;   Builds the captioned frame illustration from the tutorial's actual drawing.
(define (captioned-frame time)
  (pict:vc-append
   8
   (pict:text (format "t = ~a s" time))
   (animation-frame-pict time #:scale 0.30)))

; animation-frame-strip : -> pict?
;   Builds the animation frame strip illustration from the tutorial's actual drawing.
(define (animation-frame-strip)
  (pict:ht-append
   12
   (captioned-frame 0.0)
   (captioned-frame 1.2)
   (captioned-frame 2.4)))

;;;
;;; Scribble Interaction Form
;;;

; animation-interaction : syntax -> syntax
;   Displays and evaluates tutorial expressions in the shared documentation evaluator.
(define-syntax-rule (animation-interaction expression ...)
  (interaction #:eval animation-eval expression ...))
