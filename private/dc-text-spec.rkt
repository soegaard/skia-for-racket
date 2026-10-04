#lang racket/base
;; Public font% and text arguments -> immutable native-free requests.
;; Single-family comma descriptions use a lazy parsing-only Pango adapter.
;; No text layout or installed-font probing occurs while preparing a request.
(require racket/class racket/list racket/string
         (prefix-in rd: racket/draw) "dc-support.rkt" "dc-font-name.rkt"
         (only-in "check.rkt" current-skia-byte-limit))
(provide (struct-out dc-font-spec) (struct-out dc-text-spec)
         dc-font-description dc-text-description dc-font-request-width)
(struct dc-font-spec (family size weight slant edging hinting underlined? features) #:transparent)
(struct dc-font-spec/stretch dc-font-spec (width) #:transparent)
(define (dc-font-request-width spec)
  (if (dc-font-spec/stretch? spec) (dc-font-spec/stretch-width spec) 5))
(struct dc-text-spec (font units combine) #:transparent)
(define (dc-font-description who f)
  (unless (is-a? f rd:font%) (raise-argument-error who "font% object" f))
  ;; get-size #t, unlike get-point-size, preserves fractional sizes and Racket's
  ;; platform-specific point-to-pixel conversion. Backing scale is NOT font size.
  (define size (dc-extent who (send f get-size #t)))
  ;; Honour directory mappings for explicit faces too, as racket/draw does.
  ;; get-face alone bypasses user set-screen-name overrides.
  (define name
    (send rd:the-font-name-directory get-screen-name
          (send f get-font-id) (send f get-weight) (send f get-style)))
  (define face (dc-font-face who name (send f get-weight) (send f get-style)))
  (define features
    (for/list ([tag (in-list (sort (hash-keys (send f get-feature-settings)) string<?))])
      (format "~a=~a" tag (hash-ref (send f get-feature-settings) tag))))
  (define args
    (list (dc-face-family face) size (dc-face-weight face) (dc-face-slant face)
          ;; LCD antialiasing requires an opaque target with known geometry.
          (if (eq? (send f get-smoothing) 'unsmoothed) 'alias 'antialias)
          (send f get-hinting) (send f get-underlined) features))
  ;; Preserve the original private representation for ordinary-width fonts.
  (if (= (dc-face-width face) 5)
      (apply dc-font-spec args)
      (apply dc-font-spec/stretch (append args (list (dc-face-width face))))))
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
  (when (and combine (regexp-match? #rx"[\t\r\n\u000B\u000C\u0085\u2028\u2029]" text))
    (dc-unsupported who 'combined-text-tabs-or-hard-breaks "0.64: the single-line DC contract excludes combined tabs/hard breaks"))
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
