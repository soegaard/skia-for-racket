#lang racket/base
(require racket/list racket/string
         "bidi.rkt" "line-break.rkt")

(provide line-break-case? line-break-case-text line-break-case-breaks
         bidi-character-case? bidi-character-case-text
         bidi-character-case-requested bidi-character-case-paragraph-level
         bidi-character-case-levels bidi-character-case-reorder
         unicode-conformance-result? unicode-conformance-result-total
         unicode-conformance-result-passed unicode-conformance-result-failures
         parse-line-break-test-line parse-bidi-character-test-line
         run-line-break-conformance-port run-line-break-conformance-file
         run-bidi-character-conformance-port run-bidi-character-conformance-file)

(struct line-break-case (text breaks source) #:transparent)
(struct bidi-character-case (text requested paragraph-level levels reorder source) #:transparent)
(struct unicode-conformance-result (total passed failures) #:transparent)

(define (data-part line)
  (string-trim (car (regexp-split #rx"#" line))))

(define (hex-codepoint token who)
  (define n (string->number token 16))
  (unless (and n (exact-integer? n) (<= 0 n #x10ffff)
               (not (<= #xd800 n #xdfff)))
    (error who "bad Unicode scalar ~s" token))
  n)

(define (parse-line-break-test-line line)
  ;; Unicode auxiliary/LineBreakTest.txt uses ÷ for a break and × for no break.
  (define body (data-part line))
  (cond
    [(or (string=? body "") (string-prefix? body "@")) #f]
    [else
     (define chars '())
     (define breaks '())
     (define index 0)
     (for ([token (in-list (string-split body))])
       (cond
         [(string=? token "÷") (set! breaks (cons index breaks))]
         [(string=? token "×") (void)]
         [else
          (set! chars
                (cons (integer->char
                       (hex-codepoint token 'parse-line-break-test-line))
                      chars))
          (set! index (add1 index))]))
     (line-break-case (list->string (reverse chars))
                      (reverse breaks) line)]))

(define (parse-bidi-character-test-line line)
  ;; BidiCharacterTest.txt fields:
  ;; codepoints ; paragraph direction ; paragraph level ; levels ; reorder
  (define body (data-part line))
  (cond
    [(or (string=? body "") (string-prefix? body "@")) #f]
    [else
     (define fields (map string-trim (string-split body ";" #:trim? #f)))
     (unless (= (length fields) 5)
       (error 'parse-bidi-character-test-line
              "expected five semicolon fields: ~s" line))
     (define cps
       (for/list ([token (in-list (string-split (list-ref fields 0)))])
         (hex-codepoint token 'parse-bidi-character-test-line)))
     (define direction-number (string->number (list-ref fields 1)))
     (define requested
       (case direction-number
         [(0) 'ltr]
         [(1) 'rtl]
         [(2) 'auto]
         [else
          (error 'parse-bidi-character-test-line
                 "bad paragraph direction ~s" direction-number)]))
     (define paragraph-level (string->number (list-ref fields 2)))
     (unless (memv paragraph-level '(0 1))
       (error 'parse-bidi-character-test-line
              "bad resolved paragraph level ~s" paragraph-level))
     (define levels
       (for/list ([token (in-list (string-split (list-ref fields 3)))])
         (if (string-ci=? token "x")
             'x
             (or (string->number token)
                 (error 'parse-bidi-character-test-line
                        "bad level ~s" token)))))
     (define reorder-field (list-ref fields 4))
     (define reorder
       (if (string=? reorder-field "")
           '()
           (for/list ([token (in-list (string-split reorder-field))])
             (or (string->number token)
                 (error 'parse-bidi-character-test-line
                        "bad reorder index ~s" token)))))
     (unless (= (length cps) (length levels))
       (error 'parse-bidi-character-test-line
              "codepoint/level length mismatch"))
     (bidi-character-case (list->string (map integer->char cps))
                          requested paragraph-level levels reorder line)]))

(define (grapheme-boundaries text)
  (define n (string-length text))
  (let loop ([i 0] [out '(0)])
    (if (= i n)
        (reverse out)
        (let ([next (+ i (string-grapheme-span text i n))])
          (loop next (cons next out))))))

(define (tailored-line-break-expected c)
  ;; Version 0.13 deliberately applies UAX #14 Example 6: do not break inside
  ;; a default grapheme cluster. Filter the normative corpus accordingly.
  (define allowed (grapheme-boundaries (line-break-case-text c)))
  (for/list ([i (in-list (line-break-case-breaks c))]
             #:when (and (positive? i) (memv i allowed)))
    i))

(define (line-break-case-failure c)
  (define actual
    (map line-break-opportunity-index
         (line-break-opportunities (line-break-case-text c))))
  (define expected (tailored-line-break-expected c))
  (and (not (equal? actual expected))
       (list 'line-break
             'expected expected
             'actual actual
             'source (line-break-case-source c))))

(define (bidi-conformance-reorder text levels expected-levels)
  ;; BidiCharacterTest's reorder field specifies the index order after X9/L2.
  ;; Rule L3 is renderer-dependent and is deliberately not reflected in that
  ;; field. Mixed layout already keeps combining marks attached through
  ;; grapheme clustering and HarfBuzz shaping.
  (define visible
    (for/list ([expected (in-list expected-levels)] [i (in-naturals)]
               #:unless (eq? expected 'x))
      i))
  (bidi-reorder-items visible (lambda (i) (vector-ref levels i))))

(define (bidi-case-failure c)
  (define text (bidi-character-case-text c))
  (define-values (levels direction)
    (bidi-resolve-levels text (bidi-character-case-requested c)))
  (define expected-direction
    (if (zero? (bidi-character-case-paragraph-level c)) 'ltr 'rtl))
  (define expected-levels (bidi-character-case-levels c))
  (define level-errors
    (for/list ([expected (in-list expected-levels)]
               [actual (in-vector levels)]
               [i (in-naturals)]
               #:when (and (not (eq? expected 'x))
                           (not (= expected actual))))
      (list i expected actual)))
  (define actual-reorder
    (bidi-conformance-reorder text levels expected-levels))
  (and (or (not (eq? direction expected-direction))
           (pair? level-errors)
           (not (equal? actual-reorder (bidi-character-case-reorder c))))
       (list 'bidi
             'direction (list expected-direction direction)
             'level-errors level-errors
             'reorder (list (bidi-character-case-reorder c) actual-reorder)
             'source (bidi-character-case-source c))))

(define (run-cases in parser failure-of)
  (define total 0)
  (define passed 0)
  (define failures '())
  (for ([line (in-lines in)])
    (define c (parser line))
    (when c
      (set! total (add1 total))
      (define failure (failure-of c))
      (if failure
          (when (< (length failures) 20)
            (set! failures (cons failure failures)))
          (set! passed (add1 passed)))))
  (unicode-conformance-result total passed (reverse failures)))

(define (run-line-break-conformance-port in)
  (run-cases in parse-line-break-test-line line-break-case-failure))

(define (run-bidi-character-conformance-port in)
  (run-cases in parse-bidi-character-test-line bidi-case-failure))

(define (run-line-break-conformance-file path)
  (call-with-input-file path run-line-break-conformance-port))

(define (run-bidi-character-conformance-file path)
  (call-with-input-file path run-bidi-character-conformance-port))
