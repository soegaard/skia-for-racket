#lang racket/base

;;;
;;; Reference Color Test
;;;

;; Checks byte-color construction, channel access, named colors, and packed ARGB conversion.
;; These acceptance checks keep the Reference's documented contracts aligned with the public
;; implementation.

;;;
;;; Imports and Exports
;;;

;; Pure color contracts and examples; no native library or GUI is needed.
(require rackunit skia/color)

;;;
;;; Color Value Examples
;;;

(module+ test

  ;;;
  ;;; Test Entry Point
  ;;;

  ; color : color?
  ;   Provides a half-transparent RGBA sample for color accessor and conversion assertions.
  (define color (rgba 50 109 230 128))
  (check-true (rgba? color))
  (check-true (struct-type? struct:rgba))
  (check-equal? (map (lambda (access) (access color))
                     (list rgba-red rgba-green rgba-blue rgba-alpha))
                '(50 109 230 128))
  (check-equal? (rgb 50 109 230) (rgba 50 109 230 255))
  (check-equal? (rgba-alpha (rgb 50 109 230)) 255)
  (for ([bad (in-list (list -1 256 1/2 1.0 'red #f))])
    (check-exn exn:fail:contract? (lambda () (rgba bad 0 0 255)))
    (check-exn exn:fail:contract? (lambda () (rgba 0 bad 0 255)))
    (check-exn exn:fail:contract? (lambda () (rgba 0 0 bad 255)))
    (check-exn exn:fail:contract? (lambda () (rgba 0 0 0 bad))))
  (check-true (color? 'blue))
  (check-false (color? "blue"))
  (check-true (color? "#326DE6"))
  (check-equal? (color->rgba "#12345678") (rgba #x12 #x34 #x56 #x78))
  (check-equal? (color->rgba #x78123456) (color->rgba "#12345678"))
  (check-eq? (color->rgba color) color)
  (check-equal? (color->argb "#12345678") #x78123456)
  (check-equal? (color->argb 'transparent) 0)
  (for ([sample (in-list (list 'green 'transparent "#123456" "#12345678" color #xffffffff))])
    (check-equal? (color->rgba (color->argb sample)) (color->rgba sample))))
