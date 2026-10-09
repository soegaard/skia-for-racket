#lang racket/base
;; Public modules only. This example needs neither Skia nor a display.
(require "../../main.rkt")
(module+ main
  (define packed #x80402010)
  (define value (color->color4f packed))
  (unless (= (color->argb (color4f->rgba value)) packed)
    (error 'public-value-example "packed-color round trip failed"))
  (unless (procedure? xyz-d50-concat)
    (error 'public-value-example "XYZ-D50 arithmetic is not exported"))
  ;; Do not call XYZ operations here: they intentionally require the native
  ;; library, although merely importing their procedures does not.
  (displayln "public-value-example: passed"))
