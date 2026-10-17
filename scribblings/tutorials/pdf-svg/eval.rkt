#lang racket/base

;;;
;;; PDF SVG Tutorial Evaluation
;;;

;; Runs the PDF SVG tutorial's executable documentation examples and figure helpers.
;; This module connects the manual to executable examples and their rendered figures.


;;;
;;; Imports and Exports
;;;

(require scribble/eval
         skia
         (prefix-in draw: racket/draw)
         (prefix-in pict: pict)
         "geometry-diagram.rkt")

(provide printable-interaction
         printable-racketblock+eval
         printable-image
         printable-finished-pict)

;;;
;;; Evaluator and Figure Helpers
;;;

; printable-eval : procedure?
;   Retains one evaluator so successive documentation examples share their bindings.
(define printable-eval (make-base-eval))

(void
 (interaction-eval
  #:eval printable-eval
  (require racket
           skia
           (prefix-in draw: racket/draw)
           (prefix-in pict: pict))))

(void
 (interaction-eval
  #:eval printable-eval
  (define (printable-page-pict page
                               #:dpi [dpi 96]
                               #:scale [scale 0.54])
    (with-skia ([image (output-page->image page #:dpi dpi)])
      (pict:scale
       (pict:bitmap
        (draw:read-bitmap
         (open-input-bytes (image->png-bytes image))
         'png/alpha))
       scale)))))

; printable-interaction : syntax -> syntax
;   Displays and evaluates tutorial expressions in the shared documentation evaluator.
(define-syntax-rule (printable-interaction expression ...)
  (interaction #:eval printable-eval expression ...))

; printable-racketblock+eval : syntax -> syntax
;   Displays a code block and evaluates the same expressions for the tutorial.
(define-syntax-rule (printable-racketblock+eval expression ...)
  (racketblock+eval #:eval printable-eval expression ...))

; printable-image : syntax -> syntax
;   Evaluates the figure expression using the tutorial's shared drawing environment.
(define-syntax-rule (printable-image expression)
  (interaction-eval-show #:eval printable-eval expression))

;; The final figure calls the drawing function in geometry-diagram.rkt.
;; Native objects created for its preview are released after encoding.

; printable-finished-pict : #:scale [real?] -> pict?
;   Renders the printable finished illustration from the tutorial's drawing code.
(define (printable-finished-pict #:scale [scale 0.56])
  (with-skia ([image (output-page->image (make-diagram-page) #:dpi 96)])
    (pict:scale
     (pict:bitmap
      (draw:read-bitmap
       (open-input-bytes (image->png-bytes image))
       'png/alpha))
     scale)))
