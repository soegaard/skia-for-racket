#lang scribble/base

@(require "../main.rkt"
          scribble/html-properties
          scribble/core)
@(define page
   (make-output-page 12 8
     (lambda (canvas)
       (with-skia ([paint (make-paint #:color 'blue)])
         (draw-rect canvas 0 0 12 8 paint)))))
@(define svg-style
   (make-style #f (list (render-convertible-as '(svg-bytes png-bytes)))) )

@title[#:style svg-style]{Convertible SVG fixture}

@para[page]
