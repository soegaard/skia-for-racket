#lang racket/base
(require racket/runtime-path racket/list rackunit rackunit/text-ui
         "../tools/public-api-reflect.rkt")
(provide public-api-pure-tests public-api-pure-test-count)
(define-runtime-path fixture "public-api-fixture.rkt")
(define (exports) (hash-ref (reflect-public-module fixture "public-api-fixture.rkt") 'exports))
(define (entry name [phase "0"])
  (or (for/first ([row (in-list (exports))]
                 #:when (and (equal? name (hash-ref row 'name))
                             (equal? phase (hash-ref row 'phase)))) row)
      (error 'fixture "missing export ~a at phase ~a" name phase)))
(define public-api-pure-test-count 22)
(define public-api-pure-tests
  (test-suite "public API reflection"
    (test-case "fixed arity" (check-equal? (hash-ref (entry "fixed") 'arity_mask) "8"))
    (test-case "optional arity" (check-equal? (hash-ref (entry "optional") 'arity_mask) "6"))
    (test-case "rest arity" (check-equal? (hash-ref (entry "variadic") 'arity_mask) "-2"))
    (test-case "case-lambda disjoint mask" (check-equal? (hash-ref (entry "alternatives") 'arity_mask) "-11"))
    (test-case "required keyword" (check-equal? (hash-ref (entry "keywords") 'required_keywords) '("required")))
    (test-case "optional keyword" (check-equal? (hash-ref (entry "keywords") 'allowed_keywords) '("optional" "required")))
    (test-case "positional arity despite required keywords" (check-equal? (hash-ref (entry "keywords") 'arity_mask) "2"))
    (test-case "arbitrary keywords" (check-equal? (hash-ref (entry "all-keywords") 'allowed_keywords) 'null))
    (test-case "no keywords" (check-equal? (hash-ref (entry "fixed") 'allowed_keywords) '()))
    (test-case "parameter distinction" (check-equal? (hash-ref (entry "current-choice") 'kind) "parameter"))
    (test-case "parameter getter setter arity" (check-equal? (hash-ref (entry "current-choice") 'arity_mask) "3"))
    (test-case "ordinary rename" (check-equal? (hash-ref (entry "renamed") 'arity_mask) "8"))
    (test-case "syntax rename exposes real procedure" (check-equal? (hash-ref (entry "alias") 'arity_mask) "2"))
    (test-case "contract wrapper is reflected" (check-equal? (hash-ref (entry "contracted") 'arity_mask) "2"))
    (test-case "real syntax has no fabricated arity"
      (check-equal? (hash-ref (entry "macro-form") 'kind) "syntax")
      (check-false (hash-has-key? (entry "macro-form") 'arity_mask)))
    (test-case "structure constructor" (check-equal? (hash-ref (entry "sample") 'arity_mask) "4"))
    (test-case "structure accessor" (check-equal? (hash-ref (entry "sample-a") 'arity_mask) "2"))
    (test-case "class is not constructed" (check-equal? (hash-ref (entry "fixture%") 'kind) "class"))
    (test-case "interface distinction" (check-equal? (hash-ref (entry "fixture<%>") 'kind) "interface"))
    (test-case "constant contents are not promised" (check-equal? (hash-ref (entry "datum") 'kind) "value"))
    (test-case "higher phase name is preserved without invocation"
      (check-equal? (hash-ref (entry "compile-value" "1") 'kind) "phase-only"))
    (test-case "repeatable complete reflection without calls or GUI"
      (check-equal? (exports) (exports))
      (check-false (gui-instantiated?)))))
(module+ main
  (define failures (run-tests public-api-pure-tests))
  (printf "public-api-pure: ~a cases, ~a failures\n" public-api-pure-test-count failures)
  (exit (if (zero? failures) 0 1)))
