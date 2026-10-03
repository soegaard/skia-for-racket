#lang racket/base
;; Pure translation of the public font% and text arguments. No font probing.
(require racket/class racket/list racket/string
         (prefix-in rd: racket/draw) "dc-support.rkt"
         (only-in "check.rkt" current-skia-byte-limit))
(provide (struct-out dc-font-spec) (struct-out dc-text-spec)
         dc-font-description dc-text-description)
(struct dc-font-spec (family size weight slant edging hinting underlined? features) #:transparent)
(struct dc-text-spec (font units combine) #:transparent)
(define weights
  (hasheq 'thin 100 'ultralight 200 'light 300 'semilight 350 'book 380
          'normal 400 'medium 500 'semibold 600 'bold 700 'ultrabold 800
          'heavy 900 'ultraheavy 1000))
(define (dc-font-description who f)
  (unless (is-a? f rd:font%) (raise-argument-error who "font% object" f))
  ;; get-size #t, unlike get-point-size, preserves fractional sizes and Racket's
  ;; platform-specific point-to-pixel conversion. Backing scale is NOT font size.
  (define size (dc-extent who (send f get-size #t)))
  (define family
    (or (send f get-face)
        (send rd:the-font-name-directory get-screen-name
              (send f get-font-id) (send f get-weight) (send f get-style))))
  (unless (and (string? family) (not (regexp-match? #rx"\u0000" family)))
    (raise-arguments-error who "font family must be a NUL-free string" "family" family))
  ;; Font-name-directory can return a Pango font description, not a family.
  ;; Do not silently hand that description to Skia as if it were one family.
  (when (regexp-match? #rx"," family)
    (dc-unsupported who 'pango-font-description "deferred (select an explicit font face)"))
  (define weight (send f get-weight))
  (define features
    (for/list ([tag (in-list (sort (hash-keys (send f get-feature-settings)) string<?))])
      (format "~a=~a" tag (hash-ref (send f get-feature-settings) tag))))
  (dc-font-spec
   (string->immutable-string family) size
   (if (symbol? weight) (hash-ref weights weight) weight)
   (case (send f get-style) [(normal) 'upright] [(italic) 'italic] [else 'oblique])
   ;; Subpixel LCD AA needs a known opaque target/pixel geometry. This DC has
   ;; an alpha channel, so smoothed text intentionally uses grayscale AA.
   (if (eq? (send f get-smoothing) 'unsmoothed) 'alias 'antialias)
   (send f get-hinting) (send f get-underlined) features))
(define (dc-text-description who str f combine offset)
  (unless (string? str) (raise-argument-error who "string?" str))
  (unless (and (exact-nonnegative-integer? offset) (<= offset (string-length str)))
    (raise-arguments-error who "offset outside string" "offset" offset "length" (string-length str)))
  (define stop
    (or (for/first ([i (in-range offset (string-length str))]
                   #:when (char=? (string-ref str i) #\nul)) i)
        (string-length str)))
  (when (> (string-utf-8-length str offset stop) (current-skia-byte-limit))
    (raise-arguments-error who "text exceeds current-skia-byte-limit"
                           "limit" (current-skia-byte-limit)))
  (define text (substring str offset stop))
  (define mode (cond [(not combine) 'characters] [(eq? combine 'grapheme) 'grapheme] [else 'combined]))
  ;; dc<%> is a single-line drawing API. Paragraph/tabs in combined mode have
  ;; platform-dependent Pango behavior; keep that unsupported rather than
  ;; silently invoking this library's multiline paragraph layout.
  (when (and combine (regexp-match? #rx"[\t\r\n\u0085\u2028\u2029]" text))
    (dc-unsupported who 'combined-text-tabs-or-hard-breaks "deferred: combined tabs/hard breaks"))
  (define units
    (case mode
      [(characters)
       (for/list ([c (in-string text)] #:unless (memq (char-general-category c) '(cc cf)))
         (string->immutable-string (string c)))]
      [(grapheme)
       (let loop ([i 0] [out '()])
         (if (= i (string-length text)) (reverse out)
             (let ([j (+ i (string-grapheme-span text i))])
               (loop j (cons (string->immutable-string (substring text i j)) out)))))]
      [else (if (string=? text "") '() (list (string->immutable-string text)))]))
  (dc-text-spec (dc-font-description who f) units mode))
