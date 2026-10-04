#lang racket/base
;; Font-name translation only. Plain family names need no parser/native probe.
;; Comma descriptions lazily use Racket's Pango library, never a text layout.
(require racket/list racket/string racket/promise racket/runtime-path
         "dc-support.rkt" (only-in "check.rkt" current-skia-byte-limit))
(provide (struct-out dc-face) dc-font-face dc-face-from-description)
(struct dc-face (family weight slant width) #:transparent)
(define-runtime-path parser-module "dc-font-name-native.rkt")
(define description-parser
  (delay/sync (dynamic-require parser-module 'parse-font-description)))
(define weights
  (hasheq 'thin 100 'ultralight 200 'light 300 'semilight 350 'book 380
          'normal 400 'medium 500 'semibold 600 'bold 700 'ultrabold 800
          'heavy 900 'ultraheavy 1000))
(define (checked-name who value)
  (unless (and (string? value) (not (regexp-match? #rx"\u0000" value)))
    (raise-argument-error who "NUL-free font-name string" value))
  (when (> (add1 (string-utf-8-length value)) (current-skia-byte-limit))
    (raise-arguments-error who "font name exceeds current-skia-byte-limit"
                           "limit" (current-skia-byte-limit)))
  (string->immutable-string value))
(define (weight-number who value)
  (define w (if (symbol? value) (hash-ref weights value #f) value))
  (unless (and (exact-integer? w) (<= 0 w 1000))
    (raise-argument-error who "font weight symbol or exact integer in [0,1000]" value))
  w)
(define (slant-value who value)
  (case value
    [(normal) 'upright] [(italic) 'italic] [(slant) 'oblique]
    [else (raise-argument-error who "'normal, 'italic, or 'slant" value)]))
(define (dc-face-from-description who fields weight style)
  ;; The native bridge returns copied values only, in this fixed order:
  ;; family, weight, style, stretch, variant, explicitly-set-field mask.
  (unless (and (vector? fields) (= (vector-length fields) 6))
    (raise-argument-error who "six-field parsed font description" fields))
  (define family (checked-name who (vector-ref fields 0)))
  (define parsed-weight (weight-number who (vector-ref fields 1)))
  (define parsed-style (vector-ref fields 2))
  (define stretch (vector-ref fields 3))
  (define variant (vector-ref fields 4))
  (define mask (vector-ref fields 5))
  (unless (and (exact-integer? parsed-style) (<= 0 parsed-style 2)
               (exact-integer? stretch) (<= 0 stretch 8)
               (exact-nonnegative-integer? variant)
               (exact-nonnegative-integer? mask))
    (raise-argument-error who "valid Pango style/stretch/variant/field values" fields))
  ;; Never silently replace an ordered per-glyph family cascade with Skia's
  ;; unrelated system fallback policy. It remains an explicit 1.0 boundary.
  (when (or (string=? (string-trim family) "") (string-contains? family ","))
    (dc-unsupported who 'pango-family-list
                    "0.64: exactly one explicit family is supported; no family cascade"))
  (unless (zero? variant)
    (dc-unsupported who 'pango-font-variant "0.64: non-normal font variants are not supported"))
  ;; Family, style, variant, weight, stretch, size are the six low bits.
  ;; Reject gravity, variation axes, and any future fields, even if Pango knows
  ;; them. Font size is deliberately supplied by font%, not this description.
  (unless (zero? (bitwise-and mask (bitwise-not #x3f)))
    (dc-unsupported who 'pango-font-extra-fields
                    "0.64: gravity, variation axes, and additional description fields are not supported"))
  (dc-face family
           (if (eq? weight 'normal) parsed-weight (weight-number who weight))
           (if (eq? style 'normal)
               (vector-ref '#(upright oblique italic) parsed-style)
               (slant-value who style))
           (add1 stretch)))
(define (dc-font-face who name weight style)
  (define checked (checked-name who name))
  ;; Validate explicit overrides before forcing the optional parser.
  (define w (weight-number who weight))
  (define slant (slant-value who style))
  (if (string-contains? checked ",")
      (dc-face-from-description who ((force description-parser) checked) weight style)
      (dc-face checked w slant 5)))
