#lang racket/base

;;;
;;; Reference Color Management Pure Test
;;;

;; Checks floating color ranges, transfer descriptors, byte conversion, and ICC headers without
;; native parsing.
;; These acceptance checks keep the Reference's documented contracts aligned with the public
;; implementation.

;;;
;;; Imports and Exports
;;;

;; Native-free public color values and validation. Do not call named/native factories here.
(require rackunit skia/color skia/color4f
         (only-in skia/image-info color-space-descriptor?)
         (only-in skia/color-space make-transfer-function transfer-function?
                  transfer-function-coefficients transfer-function-evaluate))

(module+ test
  (test-case "floating values are not byte colors and preserve unpremultiplied RGB"
    (define color (make-color4f 1.25 -0.25 0.5 0.25))
    (check-true (color4f? color))
    (check-false (color? color))
    (check-false (color4f? '#(1 0 0 1)))
    (check-equal? (color4f->vector color) '#(1.25 -0.25 0.5 0.25))
    (check-true (immutable? (color4f->vector color))))
  (test-case "color construction is not binary32 quantization"
    (define color (make-color4f 1/10 0 0))
    (define single (floating-point-bytes->real (real->floating-point-bytes 0.1 4 #f) #f))
    (check-equal? (color4f-red color) 0.1)
    (check-not-equal? (color4f-red color) single))
  (test-case "RGB magnitude and alpha validation use their own ranges"
    (define maximum 340282346638528859811704183484516925440)
    (check-true (color4f? (make-color4f maximum (- maximum) 0)))
    (for ([bad (list (add1 maximum) +inf.0 +nan.0)])
      (check-exn exn:fail? (lambda () (make-color4f bad 0 0))))
    (for ([bad '(-0.1 1.1 +inf.0 +nan.0)])
      (check-exn exn:fail? (lambda () (make-color4f 0 0 0 bad))))
    ;; The alpha check occurs after conversion to an inexact Racket number.
    (check-equal? (color4f-alpha (make-color4f 0 0 0 (+ 1 (/ 1 (expt 10 100))))) 1.0))
  (test-case "byte conversion is numerical normalization and explicit clipping"
    (define original (rgba 50 109 230 128))
    (check-equal? (color4f->rgba (color->color4f original)) original)
    (check-equal? (color4f-red (color->color4f (rgba 128 0 0 255)))
                  (exact->inexact (/ 128 255)))
    (define extended (make-color4f 1.2 -0.1 0.5 0.25))
    (check-exn exn:fail? (lambda () (color4f->rgba extended)))
    (check-equal? (color4f->rgba extended #:out-of-range 'clip) (rgba 255 0 128 64)))
  (test-case "transfer branch formula uses detached rounded coefficients"
    (define transfer (make-transfer-function 2 1 0 0 0 0 0))
    (check-true (transfer-function? transfer))
    (check-true (immutable? (transfer-function-coefficients transfer)))
    (check-equal? (transfer-function-evaluate transfer 0.5) 0.25)
    (check-equal? (transfer-function-evaluate transfer 2) 4.0)
    (check-exn exn:fail? (lambda () (transfer-function-evaluate transfer -1))))
  (test-case "transfer constructor does not promise continuity or invertibility"
    (define discontinuous (make-transfer-function 1 1 0 0 1 0 2))
    (check-equal? (transfer-function-evaluate discontinuous 0.5) 2.0)
    (check-equal? (transfer-function-evaluate discontinuous 1) 1.0)
    (check-exn exn:fail? (lambda () (make-transfer-function 0 1 0 0 0 0 0)))
    (check-exn exn:fail? (lambda () (make-transfer-function 1 0 -1 0 0 0 0))))
  (test-case "descriptor predicate recognizes a header, not a parsed profile"
    (define header (make-bytes 128 0))
    (bytes-copy! header 0 (integer->integer-bytes 128 4 #f #t))
    (bytes-copy! header 36 #"acsp")
    (check-false (color-space-descriptor? header))
    (check-true (color-space-descriptor? (bytes->immutable-bytes header)))
    (check-true (color-space-descriptor? 'srgb))
    (check-true (color-space-descriptor? 'linear-srgb))
    (check-true (color-space-descriptor? #f))
    (check-false (color-space-descriptor? 'display-p3))))
