#lang racket/base
(require racket/cmdline racket/runtime-path rackunit/text-ui
         "main.rkt" "tests/pure-test.rkt" "tests/lifetime-test.rkt"
         "tests/codec-pure-test.rkt" "tests/pdf-pure-test.rkt"
         "tests/svg-pure-test.rkt" "tests/output-pure-test.rkt")

(define-runtime-path native-tests-file "tests/native-test.rkt")
(define-runtime-path codec-native-tests-file "tests/codec-native-test.rkt")
(define-runtime-path pdf-native-tests-file "tests/pdf-native-test.rkt")
(define-runtime-path svg-native-tests-file "tests/svg-native-test.rkt")
(define-runtime-path output-native-tests-file "tests/output-native-test.rkt")

(module+ main
  (define pure-only? #f)
  (command-line
   #:program "racket run-tests.rkt"
   #:once-each
   [("--pure") "Run only tests that do not load libSkiaSharp"
                 (set! pure-only? #t)]
   #:args () (void))
  (define failures (+ (run-tests pure-tests) (run-tests lifetime-tests)
                      (run-tests codec-pure-tests) (run-tests pdf-pure-tests)
                      (run-tests svg-pure-tests) (run-tests output-pure-tests)))
  (cond
    [pure-only? (displayln "Native rendering tests NOT RUN (--pure).")]
    [else
     ;; A missing/incompatible library is a failure, not a silently skipped test.
     (skia-check!)
     (set! failures
           (+ failures (run-tests (dynamic-require native-tests-file 'native-tests))
              (run-tests (dynamic-require codec-native-tests-file 'codec-native-tests))
              (run-tests (dynamic-require pdf-native-tests-file 'pdf-native-tests))
              (run-tests (dynamic-require svg-native-tests-file 'svg-native-tests))
              (run-tests (dynamic-require output-native-tests-file 'output-native-tests))))])
  (exit (if (zero? failures) 0 1)))
