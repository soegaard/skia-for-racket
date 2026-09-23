#lang racket/base
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

(define (rgb r g b) (rgba r g b 255))

(define names
  (hasheq 'transparent #x00000000
          'black #xff000000 'white #xffffffff
          'red #xffff0000 'green #xff008000 'blue #xff0000ff
          'yellow #xffffff00 'cyan #xff00ffff 'magenta #xffff00ff
          'gray #xff808080 'grey #xff808080 'orange #xffffa500
          'purple #xff800080))

(define (argb->rgba n)
  (rgba (bitwise-and #xff (arithmetic-shift n -16))
        (bitwise-and #xff (arithmetic-shift n -8))
        (bitwise-and #xff n)
        (bitwise-and #xff (arithmetic-shift n -24))))

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

(define (color->argb c)
  (define v (color->rgba c))
  (bitwise-ior (arithmetic-shift (rgba-alpha v) 24)
               (arithmetic-shift (rgba-red v) 16)
               (arithmetic-shift (rgba-green v) 8)
               (rgba-blue v)))

(define (color? c)
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (color->rgba c) #t))
