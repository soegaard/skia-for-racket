#lang scribble/base

@(require "../main.rkt")
@(define page
   (make-output-page 12 8
     (lambda (canvas)
       (with-skia ([paint (make-paint #:color 'green)])
         (draw-rect canvas 0 0 12 8 paint)))))

@title{Convertible PDF fixture}

@para[page]
