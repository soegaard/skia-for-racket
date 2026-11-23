#lang racket/base

;;;
;;; Packed and Byte Colors
;;;

;; Represents byte-channel colors and normalizes the public shorthand notations.
;; This native-free entry point gives drawing APIs one consistent RGBA value and
;; converts it to the packed ARGB integer expected by the native Skia boundary.

;;;
;;; Exports and Color Representation
;;;

(provide (struct-out rgba) rgb color? color->rgba color->argb)

;; Channels are bytes, including alpha. No hidden float-to-byte convention.
(struct rgba (red green blue alpha)
  #:transparent
  #:guard
  (lambda (r g b a who)
    (for ([v (in-list (list r g b a))])
      (unless (byte? v)
        (raise-argument-error who "byte? (0 through 255)" v)))
    (values r g b a)))
;; An rgba value stores unpremultiplied channels in red, green, blue, alpha order.
;;  - red    byte?  Red intensity, from 0 through 255.
;;  - green  byte?  Green intensity, from 0 through 255.
;;  - blue   byte?  Blue intensity, from 0 through 255.
;;  - alpha  byte?  Opacity, with 0 transparent and 255 opaque.
;; The guard validates every channel; the immutable fields have no native owner.

; rgb : byte? byte? byte? -> rgba?
;   Constructs an opaque color from its red, green, and blue channels.
(define (rgb r g b) (rgba r g b 255))

; names : (hash/c symbol? exact-nonnegative-integer?)
;   Maps the supported color names to packed ARGB values, including transparency.
(define names
  (hasheq 'transparent #x00000000
          'black #xff000000 'white #xffffffff
          'red #xffff0000 'green #xff008000 'blue #xff0000ff
          'yellow #xffffff00 'cyan #xff00ffff 'magenta #xffff00ff
          'gray #xff808080 'grey #xff808080 'orange #xffffa500
          'purple #xff800080))

;;;
;;; Color Conversion and Validation
;;;

; argb->rgba : exact-nonnegative-integer? -> rgba?
;   Extracts the four byte channels from the low 32 bits of a packed ARGB value.
(define (argb->rgba n)
  (rgba (bitwise-and #xff (arithmetic-shift n -16))
        (bitwise-and #xff (arithmetic-shift n -8))
        (bitwise-and #xff n)
        (bitwise-and #xff (arithmetic-shift n -24))))

; color->rgba : color? -> rgba?
;   Resolves a color value, name, hexadecimal string, or packed integer to RGBA.
(define (color->rgba c)
  (cond
    [(rgba? c) c]
    [(and (exact-integer? c) (<= 0 c #xffffffff)) (argb->rgba c)]
    [(and (symbol? c) (hash-has-key? names c))
     (argb->rgba (hash-ref names c))]
    [(and (string? c) (regexp-match? #px"^#[0-9a-fA-F]{6}$" c))
     (argb->rgba (+ #xff000000 (string->number (substring c 1) 16)))]
    [(and (string? c) (regexp-match? #px"^#[0-9a-fA-F]{8}$" c))
     ;; Strings use CSS-like #RRGGBBAA, unlike integer #xAARRGGBB.
     (define n (string->number (substring c 1) 16))
     (rgba (bitwise-and #xff (arithmetic-shift n -24))
           (bitwise-and #xff (arithmetic-shift n -16))
           (bitwise-and #xff (arithmetic-shift n -8))
           (bitwise-and #xff n))]
    [else
     (raise-argument-error
      'color->rgba
      "rgba value, named-color symbol, #RRGGBB/#RRGGBBAA string, or unsigned #xAARRGGBB integer"
      c)]))

; color->argb : color? -> exact-nonnegative-integer?
;   Packs a supported color into a 32-bit alpha-red-green-blue integer.
(define (color->argb c)
  (define v (color->rgba c))
  (bitwise-ior (arithmetic-shift (rgba-alpha v) 24)
               (arithmetic-shift (rgba-red v) 16)
               (arithmetic-shift (rgba-green v) 8)
               (rgba-blue v)))

; color? : any/c -> boolean?
;   Tests whether a value can be normalized by the public color conversion.
(define (color? c)
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (color->rgba c) #t))
