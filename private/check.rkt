#lang racket/base
(require "types.rkt")
(provide (all-defined-out))

(define current-skia-byte-limit
  (make-parameter
   (* 256 1024 1024)
   (lambda (v)
     (unless (exact-positive-integer? v)
       (raise-argument-error 'current-skia-byte-limit "exact-positive-integer?" v))
     v)))

(define (check-dimensions who w h)
  (for ([n (in-list (list w h))])
    (unless (and (exact-integer? n) (<= 1 n 32768))
      (raise-argument-error who "exact integer from 1 through 32768" n)))
  (define n (* w h 4))
  (unless (<= n (current-skia-byte-limit))
    (raise-arguments-error who "image exceeds current-skia-byte-limit"
                           "required RGBA bytes" n
                           "limit" (current-skia-byte-limit)))
  n)

(define (scalar who v)
  ;; Reject infinities, NaNs and values that overflow a C float.
  (unless (and (real? v) (<= -3.402823e38 v 3.402823e38))
    (raise-argument-error who "finite real representable as a C float" v))
  (exact->inexact v))

(define (nonnegative-scalar who v)
  (define f (scalar who v))
  (unless (>= f 0)
    (raise-argument-error who "nonnegative finite real" v))
  f)

(define (boolean who v)
  (unless (boolean? v) (raise-argument-error who "boolean?" v))
  v)

(define (choice who v table)
  (hash-ref table v
            (lambda ()
              (raise-arguments-error who "invalid option"
                                     "given" v
                                     "allowed" (sort (hash-keys table) symbol<?)))))

(define (rect who x y w h)
  (define fx (scalar who x))
  (define fy (scalar who y))
  (define fw (nonnegative-scalar who w))
  (define fh (nonnegative-scalar who h))
  (make-sk-rect fx fy (scalar who (+ fx fw)) (scalar who (+ fy fh))))

(define style-values (hasheq 'fill 0 'stroke 1 'stroke-and-fill 2))
(define cap-values (hasheq 'butt 0 'round 1 'square 2))
(define join-values (hasheq 'miter 0 'round 1 'bevel 2))
(define fill-values (hasheq 'winding 0 'even-odd 1))
(define direction-values (hasheq 'cw 0 'ccw 1))
(define clip-values (hasheq 'difference 0 'intersect 1))
(define sampling-values (hasheq 'nearest 0 'linear 1))
(define tile-mode-values (hasheq 'clamp 0 'repeat 1 'mirror 2 'decal 3))
(define blend-values
  (for/hasheq ([name (in-list
                    '(clear src dst src-over dst-over src-in dst-in
                      src-out dst-out src-atop dst-atop xor plus modulate
                      screen overlay darken lighten color-dodge color-burn
                      hard-light soft-light difference exclusion multiply
                      hue saturation color luminosity))]
              [n (in-naturals)])
    (values name n)))

(define (sampling who mode)
  (make-sk-sampling 0 #f 0.0 0.0
                    (choice who mode sampling-values) 0))

;; Fonts --------------------------------------------------------------------

(define font-weight-values
  (hasheq 'invisible 0
          'thin 100
          'extra-light 200
          'light 300
          'normal 400
          'medium 500
          'semi-bold 600
          'bold 700
          'extra-bold 800
          'black 900
          'extra-black 1000))

(define font-width-values
  (hasheq 'ultra-condensed 1
          'extra-condensed 2
          'condensed 3
          'semi-condensed 4
          'normal 5
          'semi-expanded 6
          'expanded 7
          'extra-expanded 8
          'ultra-expanded 9))

(define font-slant-values (hasheq 'upright 0 'italic 1 'oblique 2))
(define font-edging-values (hasheq 'alias 0 'antialias 1 'subpixel-antialias 2))
(define font-hinting-values (hasheq 'none 0 'slight 1 'normal 2 'full 3))

(define (font-weight who v)
  (cond
    [(symbol? v) (choice who v font-weight-values)]
    [(and (exact-integer? v) (<= 0 v 1000)) v]
    [else (raise-argument-error who
                                "font weight symbol or exact integer from 0 through 1000"
                                v)]))

(define (font-width who v)
  (cond
    [(symbol? v) (choice who v font-width-values)]
    [(and (exact-integer? v) (<= 1 v 9)) v]
    [else (raise-argument-error who
                                "font width symbol or exact integer from 1 through 9"
                                v)]))

(define (positive-scalar who v)
  (define f (scalar who v))
  (unless (> f 0)
    (raise-argument-error who "positive finite real" v))
  f)

(define (utf8-text who v)
  (unless (string? v) (raise-argument-error who "string?" v))
  (string->bytes/utf-8 v))

(define (nul-free-string who v description)
  (unless (string? v) (raise-argument-error who description v))
  (when (regexp-match? #rx"\u0000" v)
    (raise-arguments-error who "string contains an embedded NUL" "given" v))
  v)

(define (nul-terminated-bytes bs)
  (bytes-append bs #"\0"))

(define (enum-name who n table description)
  (or (for/or ([(name value) (in-hash table)])
        (and (= value n) name))
      (error who "unexpected native ~a value ~a" description n)))

(define (unicode-scalar who v)
  (define n (if (char? v) (char->integer v) v))
  (unless (and (exact-integer? n)
               (<= 0 n #x10ffff)
               (not (<= #xd800 n #xdfff)))
    (raise-argument-error who "char? or Unicode scalar value" v))
  n)

(define (glyph-id who v)
  (unless (and (exact-integer? v) (<= 0 v #xffff))
    (raise-argument-error who "exact integer from 0 through 65535" v))
  v)
