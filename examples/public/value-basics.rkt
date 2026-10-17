#lang racket/base

;;;
;;; Value Basics Example
;;;

;; Checks public color-value arithmetic without loading native Skia or a display.
;; This is an example-suite client of the project's drawing APIs, not library implementation.

;; Public modules only. This example needs neither Skia nor a display.
;;;
;;; Imports and Exports
;;;

(require "../../main.rkt")
;;;
;;; Command-Line Entry Point
;;;

(module+ main

  ; packed : real?
  ;   Supplies the packed ARGB value used to verify lossless color conversion.
  (define packed #x80402010)

  ; value : color4f?
  ;   Retains the floating-point color produced from the packed ARGB sample.
  (define value (color->color4f packed))
  (unless (= (color->argb (color4f->rgba value)) packed)
    (error 'public-value-example "packed-color round trip failed"))
  (unless (procedure? xyz-d50-concat)
    (error 'public-value-example "XYZ-D50 arithmetic is not exported"))
  ;; Do not call XYZ operations here: they intentionally require the native
  ;; library, although merely importing their procedures does not.
  (displayln "public-value-example: passed"))
