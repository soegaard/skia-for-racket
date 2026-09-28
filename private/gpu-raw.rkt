#lang racket/base
(require ffi/unsafe ffi/unsafe/atomic "types.rkt")
(provide call-with-gpu-raw call-with-gpu-image-info)
(define (call-with-gpu-raw size proc)
  (define p #f)
  (dynamic-wind
    void
    (lambda ()
      (call-as-atomic
       (lambda ()
         (set! p (malloc size 'raw))
         (unless p (error 'gpu-transfer "raw allocation failed"))))
      (proc p))
    (lambda () (when p (free p) (set! p #f)))))
(define (call-with-gpu-image-info colorspace width height color-type alpha-type proc)
  (call-with-gpu-raw
   (ctype-sizeof _sk-image-info)
   (lambda (p)
     (define info (cast p _pointer _sk-image-info-pointer))
     (set-sk-image-info-colorspace! info colorspace)
     (set-sk-image-info-width! info width)
     (set-sk-image-info-height! info height)
     (set-sk-image-info-color-type! info color-type)
     (set-sk-image-info-alpha-type! info alpha-type)
     (proc p))))
