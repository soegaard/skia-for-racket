#lang racket/base
;; 0.68b: pure validation and synchronous callback-result ownership.
(require racket/list racket/vector "check.rkt")
(provide font-query-budget font-query-glyphs font-query-origin font-query-text
         font-break-prefix-length collect-glyph-path-results)

(define (font-query-budget who bytes)
  (unless (and (exact-nonnegative-integer? bytes)
               (<= bytes (current-skia-byte-limit)))
    (raise-arguments-error who "font query exceeds current-skia-byte-limit"
                           "required buffer bytes" bytes
                           "limit" (current-skia-byte-limit)))
  bytes)

(define (font-query-glyphs who glyphs bytes-per-glyph)
  (define count
    (cond [(vector? glyphs) (vector-length glyphs)]
          [(list? glyphs) (length glyphs)]
          [else (raise-argument-error who "list? or vector? of glyph IDs" glyphs)]))
  (unless (<= count #x7fffffff)
    (raise-arguments-error who "glyph count exceeds the native signed-int range"
                           "count" count))
  ;; Charge before copying either a list or a vector. bytes-per-glyph includes
  ;; the uint16 input, native output buffers, and detached result slots.
  (font-query-budget who (* count bytes-per-glyph))
  (vector->immutable-vector
   (if (vector? glyphs)
       (for/vector ([g (in-vector glyphs)]) (glyph-id who g))
       (for/vector ([g (in-list glyphs)]) (glyph-id who g)))))

(define (font-query-origin who origin)
  (define xs
    (cond [(and (list? origin) (= (length origin) 2)) origin]
          [(and (vector? origin) (= (vector-length origin) 2)) (vector->list origin)]
          [else (raise-argument-error who "(list x y) or #(x y)" origin)]))
  (list (scalar who (car xs)) (scalar who (cadr xs))))

(define (font-query-text who text)
  (unless (string? text) (raise-argument-error who "string?" text))
  (define n (string-length text))
  (unless (<= n #x7fffffff)
    (raise-arguments-error who "text scalar count exceeds the native signed-int range"
                           "count" n))
  ;; Conservative charge for the text snapshot, UTF-8 bytes, native glyph/width
  ;; scratch, and decoding a returned prefix. This is not a Skia cache quota.
  (font-query-budget who (* n 20))
  (string->bytes/utf-8 (string->immutable-string text)))

(define (font-break-prefix-length who utf8 count)
  (unless (and (exact-nonnegative-integer? count) (<= count (bytes-length utf8)))
    (error who "native break-text returned an invalid byte count: ~a" count))
  ;; #f requests strict UTF-8 decoding. A broken native result must not be
  ;; repaired with U+FFFD and then mistaken for a Racket string index.
  (with-handlers ([exn:fail? (lambda (_)
                             (error who "native break-text split a UTF-8 scalar at byte ~a" count))])
    (string-length (bytes->string/utf-8 utf8 #f 0 count))))

(define (collect-glyph-path-results who count invoke copy-path dispose)
  ;; Internal only: invoke calls receive synchronously; no application callback
  ;; is run from a C frame. All callback failures, including non-exn raised
  ;; values, are saved and re-raised only after invoke has returned.
  (define results (make-vector count #f))
  (define received 0)
  (define failed? #f)
  (define failure #f)
  (define (save-failure value)
    (unless failed? (set! failed? #t) (set! failure value))
    (void))
  (define (receive borrowed-path borrowed-matrix ignored-context)
    (with-handlers ([(lambda (_) #t) save-failure])
      (unless failed?
        (unless (< received count)
          (error who "native glyph callback count exceeded the input count"))
        (define index received)
        (set! received (add1 received))
        (when borrowed-path
          ;; copy-path must release its own partially constructed result if
          ;; copying fails. Completed results belong to this collector.
          (vector-set! results index (copy-path borrowed-path borrowed-matrix)))))
    (void))
  (define (cleanup!)
    (for ([p (in-vector results)] #:when p)
      ;; Always attempt every release, preserving the original failure.
      (with-handlers ([(lambda (_) #t) (lambda (_) (void))]) (dispose p))))
  (with-handlers ([(lambda (_) #t) (lambda (value) (cleanup!) (raise value))])
    (parameterize-break #f (invoke receive))
    (when failed? (raise failure))
    (unless (= received count)
      (error who "native glyph callback count mismatch: expected ~a, received ~a"
             count received))
    (vector->immutable-vector results)))
