#lang racket/base

;;;
;;; Shared Argument Validation
;;;

;; Checks dimensions, scalars, strings, glyphs, and symbolic options before native calls.
;; Centralizes the public API's common value restrictions, native enum mappings,
;; and argument-location reporting for drawing primitives.

(require racket/string "types.rkt")
(provide (all-defined-out))

;;;
;;; Argument Locations in Error Messages
;;;

;; A calling form is a list beginning with the public procedure name, followed by
;; positional argument names and keyword/name pairs. Locations are argument names,
;; keywords, or lists of names when a restriction involves several arguments.
;; Only callers that supply a form opt in; other validation messages stay unchanged.

; argument-ordinal : exact-positive-integer? -> string?
;   Formats a one-based argument position, including the special suffixes for 11 through 13.
(define (argument-ordinal n)
  (format "~a~a" n
          (cond [(<= 11 (modulo n 100) 13) "th"]
                [else (case (modulo n 10) [(1) "st"] [(2) "nd"] [(3) "rd"] [else "th"])])))

; call-argument-fields : list? (or/c symbol? keyword? (listof symbol?)) -> list?
;   Describes an argument's name and position, or keyword, and the selected calling form.
(define (call-argument-fields form argument)
  (define (literal v) (unquoted-printing-string (format "~a" v)))
  (define positional
    (let loop ([args (cdr form)])
      (cond [(null? args) '()]
            [(keyword? (car args)) (loop (cddr args))]
            [else (cons (car args) (loop (cdr args)))])))
  (define (position name)
    (for/first ([candidate (in-list positional)] [n (in-naturals 1)]
                #:when (eq? name candidate))
      (argument-ordinal n)))
  (append
   (cond
     [(keyword? argument)
      (list "argument" (literal (cadr (memq argument form)))
            "argument keyword" (literal argument))]
     [(list? argument)
      (list "arguments" (literal (string-join (map symbol->string argument) ", "))
            "argument positions" (literal (string-join (map position argument) ", ")))]
     [else (list "argument" (literal argument) "argument position" (literal (position argument)))])
   (list "calling form" (literal form))))

; raise-call-arguments-error : symbol? string? (or/c list? #f) any/c any/c ... -> none/c
;   Raises a contract exception with existing diagnostic fields and optional argument location.
(define (raise-call-arguments-error who message form argument . fields)
  (apply raise-arguments-error who message
         (append fields (if form (call-argument-fields form argument) '()))))

; raise-call-argument-error : symbol? string? any/c [(or/c list? #f) any/c list?] -> none/c
;   Reports a rejected value, preserving the ordinary error format when no form is supplied.
(define (raise-call-argument-error who expected value [form #f] [argument #f] [details '()])
  (if form
      (apply raise-call-arguments-error who "contract violation" form argument
             "expected" (unquoted-printing-string expected) "given" value details)
      (raise-argument-error who expected value)))

;;;
;;; Allocation Bounds and Scalar Checks
;;;

; current-skia-byte-limit : (parameter/c exact-positive-integer?)
;   Bounds explicit wrapper allocations and copied payloads; defaults to 256 MiB.
(define current-skia-byte-limit
  (make-parameter
   (* 256 1024 1024)
   (lambda (v)
     (unless (exact-positive-integer? v)
       (raise-argument-error 'current-skia-byte-limit "exact-positive-integer?" v))
     v)))

; check-dimensions : symbol? integer? integer? -> exact-positive-integer?
;   Checks dimensions up to 32768 and returns the budgeted packed RGBA byte count.
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

; scalar : symbol? real? [(or/c list? #f) any/c list?] -> inexact-real?
;   Rejects nonfinite or out-of-float-range inputs and returns an inexact drawing scalar.
(define (scalar who v [form #f] [argument #f] [details '()])
  ;; Reject infinities, NaNs and values that overflow a C float.
  (unless (and (real? v) (<= -3.402823e38 v 3.402823e38))
    (raise-call-argument-error who "finite real representable as a C float"
                              v form argument details))
  (exact->inexact v))

; nonnegative-scalar : symbol? real? [(or/c list? #f) any/c] -> inexact-real?
;   Requires a nonnegative drawing scalar without clamping negative input.
(define (nonnegative-scalar who v [form #f] [argument #f])
  (define f (scalar who v form argument))
  (unless (>= f 0)
    (raise-call-argument-error who "nonnegative finite real" v form argument))
  f)

; boolean : symbol? boolean? [(or/c list? #f) any/c] -> boolean?
;   Rejects nonboolean truthy values before native conversion.
(define (boolean who v [form #f] [argument #f])
  (unless (boolean? v) (raise-call-argument-error who "boolean?" v form argument))
  v)

; choice : symbol? symbol? hash? [(or/c list? #f) any/c] -> any/c
;   Resolves a closed symbolic option, reporting sorted allowed names on failure.
(define (choice who v table [form #f] [argument #f])
  (hash-ref table v
            (lambda ()
              (raise-call-arguments-error who "invalid option" form argument
                                          "given" v
                                          "allowed" (sort (hash-keys table) symbol<?)))))

; rect : symbol? real? real? real? real? [(or/c list? #f)] -> sk-rect?
;   Checks x/y/width/height and converted right/bottom edges for native rectangle construction.
(define (rect who x y w h [form #f])
  (define fx (scalar who x form 'x))
  (define fy (scalar who y form 'y))
  (define fw (nonnegative-scalar who w form 'width))
  (define fh (nonnegative-scalar who h form 'height))
  (make-sk-rect
   fx fy
   (scalar who (+ fx fw) form '(x width) '("computed edge" "x + width"))
   (scalar who (+ fy fh) form '(y height) '("computed edge" "y + height"))))

;;;
;;; Drawing and Encoding Enumerations
;;;

; style-values : (hash/c symbol? exact-nonnegative-integer?)
;   Maps paint fill/stroke styles to native enumeration values.
(define style-values (hasheq 'fill 0 'stroke 1 'stroke-and-fill 2))

; cap-values : (hash/c symbol? exact-nonnegative-integer?)
;   Maps stroke caps to native enumeration values.
(define cap-values (hasheq 'butt 0 'round 1 'square 2))

; join-values : (hash/c symbol? exact-nonnegative-integer?)
;   Maps stroke joins to native enumeration values.
(define join-values (hasheq 'miter 0 'round 1 'bevel 2))

; fill-values : (hash/c symbol? exact-nonnegative-integer?)
;   Maps path fill rules to native enumeration values.
(define fill-values (hasheq 'winding 0 'even-odd 1))

; direction-values : (hash/c symbol? exact-nonnegative-integer?)
;   Maps contour directions to native enumeration values.
(define direction-values (hasheq 'cw 0 'ccw 1))

; clip-values : (hash/c symbol? exact-nonnegative-integer?)
;   Maps clip combinations to native enumeration values.
(define clip-values (hasheq 'difference 0 'intersect 1))

; sampling-values : (hash/c symbol? exact-nonnegative-integer?)
;   Maps image sampling filters to native enumeration values.
(define sampling-values (hasheq 'nearest 0 'linear 1))

; tile-mode-values : (hash/c symbol? exact-nonnegative-integer?)
;   Maps shader tile modes to native enumeration values.
(define tile-mode-values (hasheq 'clamp 0 'repeat 1 'mirror 2 'decal 3))

; blur-style-values : (hash/c symbol? exact-nonnegative-integer?)
;   Maps mask blur styles to native enumeration values.
(define blur-style-values (hasheq 'normal 0 'solid 1 'outer 2 'inner 3))

; trim-path-effect-mode-values : (hash/c symbol? exact-nonnegative-integer?)
;   Maps path-trim modes to native enumeration values.
(define trim-path-effect-mode-values (hasheq 'normal 0 'inverted 1))

; path-op-values : (hash/c symbol? exact-nonnegative-integer?)
;   Maps Boolean path operations to native enumeration values.
(define path-op-values
  (hasheq 'difference 0 'intersect 1 'union 2 'xor 3 'reverse-difference 4))

; path-add-mode-values : (hash/c symbol? exact-nonnegative-integer?)
;   Maps path append/extend modes to native enumeration values.
(define path-add-mode-values (hasheq 'append 0 'extend 1))

;; Encoded image / codec values from the pinned SkiaSharp m119 ABI.

; encoded-format-values : (hash/c symbol? exact-nonnegative-integer?)
;   Maps encoded formats to native enumeration values.
(define encoded-format-values
  (hasheq 'bmp 0 'gif 1 'ico 2 'jpeg 3 'png 4 'wbmp 5 'webp 6
          'pkm 7 'ktx 8 'astc 9 'dng 10 'heif 11 'avif 12 'jpeg-xl 13))

; alpha-type-values : (hash/c symbol? exact-nonnegative-integer?)
;   Maps alpha interpretations to native enumeration values.
(define alpha-type-values
  (hasheq 'unknown 0 'opaque 1 'premul 2 'unpremul 3))

; color-type-values : (hash/c symbol? exact-nonnegative-integer?)
;   Maps native pixel layouts, including non-public storage formats to native enumeration values.
(define color-type-values
  (hasheq 'unknown 0 'alpha-8 1 'rgb-565 2 'argb-4444 3
          'rgba-8888 4 'rgb-888x 5 'bgra-8888 6
          'rgba-1010102 7 'bgra-1010102 8
          'rgb-101010x 9 'bgr-101010x 10 'bgr-101010x-xr 11
          'rgba-10x6 12 'gray-8 13 'rgba-f16-norm 14 'rgba-f16 15
          'rgba-f32 16 'r8g8-unorm 17 'a16-float 18 'r16g16-float 19
          'a16-unorm 20 'r16g16-unorm 21 'r16g16b16a16-unorm 22
          'srgba-8888 23 'r8-unorm 24))

; encoded-origin-values : (hash/c symbol? exact-nonnegative-integer?)
;   Maps encoded orientations to native enumeration values.
(define encoded-origin-values
  (hasheq 'top-left 1 'top-right 2 'bottom-right 3 'bottom-left 4
          'left-top 5 'right-top 6 'right-bottom 7 'left-bottom 8))

; jpeg-downsample-values : (hash/c symbol? exact-nonnegative-integer?)
;   Maps JPEG chroma subsampling to native enumeration values.
(define jpeg-downsample-values
  (hasheq 'yuv-420 0 'yuv-422 1 'yuv-444 2))

; jpeg-alpha-values : (hash/c symbol? exact-nonnegative-integer?)
;   Maps JPEG alpha handling to native enumeration values.
(define jpeg-alpha-values
  (hasheq 'ignore 0 'blend-on-black 1))

; webp-compression-values : (hash/c symbol? exact-nonnegative-integer?)
;   Maps WebP compression modes to native enumeration values.
(define webp-compression-values
  (hasheq 'lossy 0 'lossless 1))

; blend-values : (hash/c symbol? exact-nonnegative-integer?)
;   Maps paint blend modes in ABI order to native enumeration values.
(define blend-values
  (for/hasheq ([name (in-list
                    '(clear src dst src-over dst-over src-in dst-in
                      src-out dst-out src-atop dst-atop xor plus modulate
                      screen overlay darken lighten color-dodge color-burn
                      hard-light soft-light difference exclusion multiply
                      hue saturation color luminosity))]
              [n (in-naturals)])
    (values name n)))

;;;
;;; Sampling, Encoding Quality, and Source Rectangles
;;;

; sampling : symbol? symbol? -> sk-sampling?
;   Builds nearest or linear sampling options with cubic filtering and mipmaps disabled.
(define (sampling who mode)
  (make-sk-sampling 0 #f 0.0 0.0
                    (choice who mode sampling-values) 0))

; uint32 : symbol? exact-integer? -> exact-nonnegative-integer?
;   Checks the inclusive unsigned 32-bit range.
(define (uint32 who value)
  (unless (and (exact-integer? value) (<= 0 value #xffffffff))
    (raise-argument-error who "exact integer from 0 through 4294967295" value))
  value)

; quality-integer : symbol? exact-integer? -> exact-nonnegative-integer?
;   Checks integer encoding quality on the inclusive 0–100 scale.
(define (quality-integer who value)
  (unless (and (exact-integer? value) (<= 0 value 100))
    (raise-argument-error who "exact integer from 0 through 100" value))
  value)

; quality-scalar : symbol? real? -> inexact-real?
;   Checks finite encoding quality on the inclusive 0–100 scale.
(define (quality-scalar who value)
  (define q (scalar who value))
  (unless (<= 0.0 q 100.0)
    (raise-argument-error who "finite real from 0 through 100" value))
  q)

; positive-encoded-bytes : symbol? bytes? -> bytes?
;   Requires nonempty encoded input within the byte budget without copying it.
(define (positive-encoded-bytes who value)
  (unless (bytes? value) (raise-argument-error who "bytes?" value))
  (define n (bytes-length value))
  (unless (positive? n)
    (raise-arguments-error who "encoded image data is empty" "bytes" value))
  (unless (<= n (current-skia-byte-limit))
    (raise-arguments-error who "encoded image data exceeds current-skia-byte-limit"
                           "encoded bytes" n "limit" (current-skia-byte-limit)))
  value)

; exact-source-rectangle : symbol? integer? integer? integer? integer? integer? integer? -> sk-irect?
;   Checks a nonempty integer subset fits the image and returns native edge bounds.
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

; source-rect : symbol? real? real? real? real? real? real? -> sk-rect?
;   Checks a nonnegative floating subset fits the image before converting its edges.
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

;;;
;;; Font Styles and Text Values
;;;

;; Fonts --------------------------------------------------------------------

; font-weight-values : (hash/c symbol? exact-nonnegative-integer?)
;   Maps named font weights to native enumeration values.
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

; font-width-values : (hash/c symbol? exact-nonnegative-integer?)
;   Maps named font widths to native enumeration values.
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

; font-slant-values : (hash/c symbol? exact-nonnegative-integer?)
;   Maps font slants to native enumeration values.
(define font-slant-values (hasheq 'upright 0 'italic 1 'oblique 2))

; font-edging-values : (hash/c symbol? exact-nonnegative-integer?)
;   Maps glyph edge rendering modes to native enumeration values.
(define font-edging-values (hasheq 'alias 0 'antialias 1 'subpixel-antialias 2))

; font-hinting-values : (hash/c symbol? exact-nonnegative-integer?)
;   Maps font hinting strengths to native enumeration values.
(define font-hinting-values (hasheq 'none 0 'slight 1 'normal 2 'full 3))

; font-weight : symbol? (or/c symbol? exact-integer?) -> exact-nonnegative-integer?
;   Resolves named weights or checks numeric weights from 0 through 1000.
(define (font-weight who v)
  (cond
    [(symbol? v) (choice who v font-weight-values)]
    [(and (exact-integer? v) (<= 0 v 1000)) v]
    [else (raise-argument-error who
                                "font weight symbol or exact integer from 0 through 1000"
                                v)]))

; font-width : symbol? (or/c symbol? exact-integer?) -> exact-positive-integer?
;   Resolves named widths or checks native width classes from 1 through 9.
(define (font-width who v)
  (cond
    [(symbol? v) (choice who v font-width-values)]
    [(and (exact-integer? v) (<= 1 v 9)) v]
    [else (raise-argument-error who
                                "font width symbol or exact integer from 1 through 9"
                                v)]))

; positive-scalar : symbol? real? -> inexact-real?
;   Requires a finite strictly positive drawing scalar.
(define (positive-scalar who v)
  (define f (scalar who v))
  (unless (> f 0)
    (raise-argument-error who "positive finite real" v))
  f)

; utf8-text : symbol? string? -> bytes?
;   Encodes checked text for length-delimited native UTF-8 APIs.
(define (utf8-text who v)
  (unless (string? v) (raise-argument-error who "string?" v))
  (string->bytes/utf-8 v))

; nul-free-string : symbol? string? string? -> string?
;   Rejects embedded NUL characters before terminated-string APIs.
(define (nul-free-string who v description)
  (unless (string? v) (raise-argument-error who description v))
  (when (regexp-match? #rx"\u0000" v)
    (raise-arguments-error who "string contains an embedded NUL" "given" v))
  v)

; nul-terminated-bytes : bytes? -> bytes?
;   Appends a native NUL terminator to already checked bytes.
(define (nul-terminated-bytes bs)
  (bytes-append bs #"\0"))

; enum-name : symbol? exact-integer? hash? string? -> symbol?
;   Resolves a native code to its public name, rejecting unknown enumeration values.
(define (enum-name who n table description)
  (or (for/or ([(name value) (in-hash table)])
        (and (= value n) name))
      (error who "unexpected native ~a value ~a" description n)))

; unicode-scalar : symbol? (or/c char? exact-integer?) -> exact-nonnegative-integer?
;   Returns a Unicode scalar number, excluding surrogates and out-of-range values.
(define (unicode-scalar who v)
  (define n (if (char? v) (char->integer v) v))
  (unless (and (exact-integer? n)
               (<= 0 n #x10ffff)
               (not (<= #xd800 n #xdfff)))
    (raise-argument-error who "char? or Unicode scalar value" v))
  n)

; glyph-id : symbol? exact-integer? -> exact-nonnegative-integer?
;   Checks a glyph identifier fits the native uint16 representation.
(define (glyph-id who v)
  (unless (and (exact-integer? v) (<= 0 v #xffff))
    (raise-argument-error who "exact integer from 0 through 65535" v))
  v)
