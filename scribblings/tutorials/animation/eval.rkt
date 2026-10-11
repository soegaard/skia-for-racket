#lang racket/base

(require racket/runtime-path
         scribble/eval
         skia
         (prefix-in draw: racket/draw)
         (prefix-in pict: pict)
         "scene.rkt")

(provide animation-interaction
         animation-frame-pict
         animation-frame-strip)

(define-runtime-path scene-module "scene.rkt")

(define animation-eval (make-base-eval))
(animation-eval '(require racket))
(animation-eval `(require (file ,(path->string scene-module))))

;; Catch an all-black or incorrectly colored figure during a documentation build.
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

(define (captioned-frame time)
  (pict:vc-append
   8
   (pict:text (format "t = ~a s" time))
   (animation-frame-pict time #:scale 0.30)))

(define (animation-frame-strip)
  (pict:ht-append
   12
   (captioned-frame 0.0)
   (captioned-frame 1.2)
   (captioned-frame 2.4)))

(define-syntax-rule (animation-interaction expression ...)
  (interaction #:eval animation-eval expression ...))
