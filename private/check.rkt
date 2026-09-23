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
(define blur-style-values (hasheq 'normal 0 'solid 1 'outer 2 'inner 3))
(define trim-path-effect-mode-values (hasheq 'normal 0 'inverted 1))
(define path-op-values
  (hasheq 'difference 0 'intersect 1 'union 2 'xor 3 'reverse-difference 4))

;; Encoded image / codec values from the pinned SkiaSharp m119 ABI.
(define encoded-format-values
  (hasheq 'bmp 0 'gif 1 'ico 2 'jpeg 3 'png 4 'wbmp 5 'webp 6
          'pkm 7 'ktx 8 'astc 9 'dng 10 'heif 11 'avif 12 'jpeg-xl 13))
(define alpha-type-values
  (hasheq 'unknown 0 'opaque 1 'premul 2 'unpremul 3))
(define color-type-values
  (hasheq 'unknown 0 'alpha-8 1 'rgb-565 2 'argb-4444 3
          'rgba-8888 4 'rgb-888x 5 'bgra-8888 6
          'rgba-1010102 7 'bgra-1010102 8
          'rgb-101010x 9 'bgr-101010x 10 'bgr-101010x-xr 11
          'rgba-10x6 12 'gray-8 13 'rgba-f16-norm 14 'rgba-f16 15
          'rgba-f32 16 'r8g8-unorm 17 'a16-float 18 'r16g16-float 19
          'a16-unorm 20 'r16g16-unorm 21 'r16g16b16a16-unorm 22
          'srgba-8888 23 'r8-unorm 24))
(define encoded-origin-values
  (hasheq 'top-left 1 'top-right 2 'bottom-right 3 'bottom-left 4
          'left-top 5 'right-top 6 'right-bottom 7 'left-bottom 8))
(define jpeg-downsample-values
  (hasheq 'yuv-420 0 'yuv-422 1 'yuv-444 2))
(define jpeg-alpha-values
  (hasheq 'ignore 0 'blend-on-black 1))
(define webp-compression-values
  (hasheq 'lossy 0 'lossless 1))

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

(define (uint32 who value)
  (unless (and (exact-integer? value) (<= 0 value #xffffffff))
    (raise-argument-error who "exact integer from 0 through 4294967295" value))
  value)

(define (quality-integer who value)
  (unless (and (exact-integer? value) (<= 0 value 100))
    (raise-argument-error who "exact integer from 0 through 100" value))
  value)

(define (quality-scalar who value)
  (define q (scalar who value))
  (unless (<= 0.0 q 100.0)
    (raise-argument-error who "finite real from 0 through 100" value))
  q)

(define (positive-encoded-bytes who value)
  (unless (bytes? value) (raise-argument-error who "bytes?" value))
  (define n (bytes-length value))
  (unless (positive? n)
    (raise-arguments-error who "encoded image data is empty" "bytes" value))
  (unless (<= n (current-skia-byte-limit))
    (raise-arguments-error who "encoded image data exceeds current-skia-byte-limit"
                           "encoded bytes" n "limit" (current-skia-byte-limit)))
  value)

(define (exact-source-rectangle who x y w h image-width image-height)
  (for ([v (in-list (list x y))])
    (unless (exact-nonnegative-integer? v)
      (raise-argument-error who "exact-nonnegative-integer? for source x/y" v)))
  (for ([v (in-list (list w h))])
    (unless (exact-positive-integer? v)
      (raise-argument-error who "exact-positive-integer? for source width/height" v)))
  (unless (and (<= (+ x w) image-width) (<= (+ y h) image-height))
    (raise-arguments-error who "source rectangle lies outside the image"
                           "source" (list x y w h)
                           "image size" (list image-width image-height)))
  (make-sk-irect x y (+ x w) (+ y h)))

(define (source-rect who x y w h image-width image-height)
  (define fx (nonnegative-scalar who x))
  (define fy (nonnegative-scalar who y))
  (define fw (nonnegative-scalar who w))
  (define fh (nonnegative-scalar who h))
  (unless (and (<= (+ fx fw) image-width) (<= (+ fy fh) image-height))
    (raise-arguments-error who "source rectangle lies outside the image"
                           "source" (list x y w h)
                           "image size" (list image-width image-height)))
  (make-sk-rect fx fy (+ fx fw) (+ fy fh)))

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
