#lang racket/base
(require racket/cmdline
         "../private/unicode-conformance.rkt")

(define line-break-path #f)
(define bidi-path #f)

(command-line
 #:program "unicode-conformance.rkt"
 #:once-each
 [("--line-break") path "Unicode 15.1 auxiliary/LineBreakTest.txt"
  (set! line-break-path path)]
 [("--bidi") path "Unicode 15.1 BidiCharacterTest.txt"
  (set! bidi-path path)]
 #:args () (void))

(unless (or line-break-path bidi-path)
  (error 'unicode-conformance "give --line-break and/or --bidi"))

(define failed? #f)

(define (report label result)
  (define total (unicode-conformance-result-total result))
  (define passed (unicode-conformance-result-passed result))
  (define failures (unicode-conformance-result-failures result))
  (printf "~a: ~a/~a passed\n" label passed total)
  (unless (= passed total) (set! failed? #t))
  (for ([failure (in-list failures)])
    (printf "  ~s\n" failure))
  (when (and (< passed total) (= (length failures) 20))
    (printf "  ... first 20 failures shown\n")))

(when line-break-path
  (report "LineBreakTest"
          (run-line-break-conformance-file line-break-path)))
(when bidi-path
  (report "BidiCharacterTest"
          (run-bidi-character-conformance-file bidi-path)))

(when failed? (exit 1))
