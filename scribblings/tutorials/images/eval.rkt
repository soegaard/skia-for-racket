#lang racket/base

(require racket/runtime-path
         scribble/eval)

(provide images-interaction
         images-interaction-eval
         images-racketmod+eval
         images-racketblock+eval
         images-def+int
         images-image)

(define-runtime-path fixture-directory "fixtures")

(define images-eval (make-base-eval))

(images-eval
 '(require racket
           skia
           (prefix-in draw: racket/draw)
           (prefix-in pict: pict)))

(images-eval
 `(define tutorial-fixture-directory
    ,(path->string fixture-directory)))

(images-eval
 '(define (tutorial-fixture name)
    (build-path tutorial-fixture-directory name)))

(images-eval
 '(define (images-render-pict width height draw)
    (with-skia ([surface (make-surface width height
                                      #:background "#F4F1EA")])
      (draw (surface-canvas surface))
      (pict:scale
       (pict:bitmap
        (draw:read-bitmap
         (open-input-bytes (surface->png-bytes surface))
         'png/alpha))
       0.72))))

(define-syntax-rule (images-interaction expression ...)
  (interaction #:eval images-eval expression ...))

(define-syntax-rule (images-interaction-eval expression ...)
  (interaction-eval #:eval images-eval expression ...))

(define-syntax-rule (images-racketmod+eval expression ...)
  (racketmod+eval #:eval images-eval expression ...))

(define-syntax-rule (images-racketblock+eval expression ...)
  (racketblock+eval #:eval images-eval expression ...))

(define-syntax-rule (images-def+int expression ...)
  (def+int #:eval images-eval expression ...))

(define-syntax-rule (images-image expression)
  (interaction-eval-show #:eval images-eval expression))
