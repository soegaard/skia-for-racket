#lang racket/base

;;;
;;; Floating-Point Color Values
;;;

;; Stores unpremultiplied colors with extended-range RGB and bounded alpha.
;; This detached public representation lets floating-point painting and pixel
;; APIs exchange color values without loading Skia or quantizing RGB to bytes.

;; Detached UNPREMULTIPLIED float colors. No native library on import.

;;;
;;; Imports and Exports
;;;

(require "color.rkt" "private/check.rkt")
(provide color4f? make-color4f color4f-red color4f-green color4f-blue color4f-alpha
         color4f->vector color->color4f color4f->rgba)

;;;
;;; Color Representation and Construction
;;;

(struct color4f (red green blue alpha) #:transparent #:constructor-name make-color4f-record)
;; A color4f value stores channels in red, green, blue, alpha order.
;;  - red    real?  Finite, unpremultiplied red component within binary32 range.
;;  - green  real?  Finite, unpremultiplied green component within binary32 range.
;;  - blue   real?  Finite, unpremultiplied blue component within binary32 range.
;;  - alpha  real?  Opacity in the closed interval [0, 1].
;; Public construction copies components to inexact numbers. RGB may be negative
;; or exceed one; interpreting those values requires a separate color space.

; make-color4f : real? real? real? [real?] -> color4f?
;   Validates extended RGB and bounded alpha without clipping or premultiplying.
(define (make-color4f red green blue [alpha 1])
  (define who 'make-color4f)
  (define (component v)
    (unless (and (real? v) (<= -340282346638528859811704183484516925440 v
                                340282346638528859811704183484516925440))
      (raise-argument-error who "finite real in binary32 range" v))
    (exact->inexact v))
  (define r (component red)) (define g (component green)) (define b (component blue))
  (define a (scalar who alpha))
  (unless (<= 0 a 1) (raise-argument-error who "finite alpha in [0,1]" alpha))
  ;; Negative/extended RGB are intentional. Do not route through packed colors.
  (make-color4f-record r g b a))

; checked-color4f : symbol? color4f? -> color4f?
;   Checks a detached color and attributes a type error to the calling operation.
(define (checked-color4f who c)
  (unless (color4f? c) (raise-argument-error who "color4f?" c))
  c)

;;;
;;; Channel Conversion
;;;

; color4f->vector : color4f? -> vector?
;   Copies the red, green, blue, and alpha components into an immutable vector.
(define (color4f->vector c)
  (checked-color4f 'color4f->vector c)
  (vector-immutable (color4f-red c) (color4f-green c) (color4f-blue c) (color4f-alpha c)))

; color->color4f : color? -> color4f?
;   Converts byte channels to unit-range values without changing color space.
(define (color->color4f c)
  (define v (color->rgba c))
  (make-color4f (/ (rgba-red v) 255) (/ (rgba-green v) 255)
                (/ (rgba-blue v) 255) (/ (rgba-alpha v) 255)))

; color4f->rgba : color4f? [#:out-of-range (or/c 'error 'clip)] -> rgba?
;   Quantizes normalized channels to bytes, rejecting or explicitly clipping RGB.
(define (color4f->rgba c #:out-of-range [policy 'error])
  (define who 'color4f->rgba)
  (checked-color4f who c)
  (unless (memq policy '(error clip)) (raise-argument-error who "'error or 'clip" policy))
  (define (byte v)
    (when (and (eq? policy 'error) (not (<= 0 v 1)))
      (error who "extended RGB requires explicit #:out-of-range 'clip"))
    (inexact->exact (floor (+ 0.5 (* 255 (max 0 (min 1 v)))))))
  ;; Explicit numerical quantization, NOT a color-space conversion/tone mapper.
  (rgba (byte (color4f-red c)) (byte (color4f-green c))
        (byte (color4f-blue c)) (byte (color4f-alpha c))))
(module* internals #f (provide checked-color4f))
