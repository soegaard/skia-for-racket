#lang racket/base

(require scribble/eval
         skia
         (prefix-in draw: racket/draw)
         (prefix-in pict: pict)
         "geometry-diagram.rkt")

(provide printable-interaction
         printable-racketblock+eval
         printable-image
         printable-finished-pict)

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

(define-syntax-rule (printable-interaction expression ...)
  (interaction #:eval printable-eval expression ...))

(define-syntax-rule (printable-racketblock+eval expression ...)
  (racketblock+eval #:eval printable-eval expression ...))

(define-syntax-rule (printable-image expression)
  (interaction-eval-show #:eval printable-eval expression))

;; The final figure calls the drawing function in geometry-diagram.rkt.
;; Native objects created for its preview are released after encoding.
(define (printable-finished-pict #:scale [scale 0.56])
  (with-skia ([image (output-page->image (make-diagram-page) #:dpi 96)])
    (pict:scale
     (pict:bitmap
      (draw:read-bitmap
       (open-input-bytes (image->png-bytes image))
       'png/alpha))
     scale)))
