#lang racket/base

(require racket/runtime-path scribble/eval skia "badge.rkt" "../support/figures.rkt")
(provide paths-interaction paths-racketblock+eval badge-pict shape-pict operands-pict simplify-pict)
(define-runtime-path program-source "badge.rkt")
(define-runtime-path program-directory ".")
(define paths-eval (make-base-eval))
(paths-eval `(current-directory ,(path->string program-directory)))
(paths-eval '(require racket skia))
(paths-eval `(require (file ,(path->string program-source))))
(define parts (make-badge-parts))

(define (shape-pict key #:scale [scale 0.9])
  (render-pict 320 320
               (lambda (canvas)
                 (draw-checker canvas 320 320)
                 (draw-shape canvas (hash-ref parts key)))
               #:scale scale))

(define (badge-pict)
  (render-pict 720 468 (lambda (canvas) (draw-badge-sheet canvas parts)) #:scale 0.9))

(define (operands-pict)
  (figure-row (captioned-pict "Disk" (shape-pict 'disk #:scale 0.65))
              (captioned-pict "Cross: two overlapping contours" (shape-pict 'cross #:scale 0.65))))

(define (simplify-pict)
  (define source (cross-path))
  (define simplified (path-simplify source))
  (define (one path)
    (render-pict 320 320 (lambda (canvas) (draw-shape canvas path)) #:scale 0.7))
  (figure-row (captioned-pict "Original contours, stroked separately" (one source))
              (captioned-pict "Simplified filled region, then stroked" (one simplified))))

(define-syntax-rule (paths-interaction expression ...)
  (interaction #:eval paths-eval expression ...))
(define-syntax-rule (paths-racketblock+eval expression ...)
  (racketblock+eval #:eval paths-eval expression ...))
