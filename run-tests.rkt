#lang racket/base
(require racket/cmdline racket/runtime-path rackunit/text-ui
         "main.rkt" "tests/pure-test.rkt" "tests/lifetime-test.rkt"
         "tests/codec-pure-test.rkt" "tests/pdf-pure-test.rkt"
         "tests/svg-pure-test.rkt" "tests/output-pure-test.rkt"
         "tests/path-matrix-pure-test.rkt" "tests/filter-graph-pure-test.rkt"
         "tests/color-output-pure-test.rkt" "tests/annotation-pure-test.rkt" "tests/runtime-pure-test.rkt" "tests/output-audit-pure-test.rkt" "tests/canvas-pure-test.rkt" "tests/geometry-pure-test.rkt" "tests/projective-pure-test.rkt" "tests/picture-pure-test.rkt" "tests/output-group-pure-test.rkt" "tests/portable-pure-test.rkt" "tests/color-filter-pure-test.rkt")

(define-runtime-path native-tests-file "tests/native-test.rkt")
(define-runtime-path codec-native-tests-file "tests/codec-native-test.rkt")
(define-runtime-path pdf-native-tests-file "tests/pdf-native-test.rkt")
(define-runtime-path svg-native-tests-file "tests/svg-native-test.rkt")
(define-runtime-path output-native-tests-file "tests/output-native-test.rkt")

(define-runtime-path path-matrix-native-tests-file "tests/path-matrix-native-test.rkt")

(define-runtime-path filter-graph-native-tests-file "tests/filter-graph-native-test.rkt")

(define-runtime-path color-output-native-tests-file "tests/color-output-native-test.rkt")

(define-runtime-path annotation-native-tests-file "tests/annotation-native-test.rkt")

(define-runtime-path runtime-native-tests-file "tests/runtime-native-test.rkt")
(define-runtime-path output-audit-native-tests-file "tests/output-audit-native-test.rkt")

(define-runtime-path canvas-native-tests-file "tests/canvas-native-test.rkt")

(define-runtime-path geometry-native-tests-file "tests/geometry-native-test.rkt")

(define-runtime-path projective-native-tests-file "tests/projective-native-test.rkt")

(define-runtime-path picture-native-tests-file "tests/picture-native-test.rkt")
(define-runtime-path output-group-native-tests-file "tests/output-group-native-test.rkt")
(define-runtime-path portable-native-tests-file "tests/portable-native-test.rkt")
(define-runtime-path color-filter-native-tests-file "tests/color-filter-native-test.rkt")

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
                      (run-tests svg-pure-tests) (run-tests output-pure-tests)
                      (run-tests path-matrix-pure-tests) (run-tests filter-graph-pure-tests)
                      (run-tests color-output-pure-tests) (run-tests annotation-pure-tests) (run-tests runtime-pure-tests) (run-tests output-audit-pure-tests) (run-tests canvas-pure-tests) (run-tests geometry-pure-tests) (run-tests projective-pure-tests) (run-tests picture-pure-tests) (run-tests output-group-pure-tests) (run-tests portable-pure-tests) (run-tests color-filter-pure-tests)))
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
              (run-tests (dynamic-require output-native-tests-file 'output-native-tests))
              (run-tests (dynamic-require path-matrix-native-tests-file 'path-matrix-native-tests))
              (run-tests (dynamic-require filter-graph-native-tests-file 'filter-graph-native-tests))
              (run-tests (dynamic-require color-output-native-tests-file 'color-output-native-tests))
              (run-tests (dynamic-require annotation-native-tests-file 'annotation-native-tests))
              (run-tests (dynamic-require runtime-native-tests-file 'runtime-native-tests))
              (run-tests (dynamic-require output-audit-native-tests-file 'output-audit-native-tests))
              (run-tests (dynamic-require canvas-native-tests-file 'canvas-native-tests))
              (run-tests (dynamic-require geometry-native-tests-file 'geometry-native-tests))
              (run-tests (dynamic-require projective-native-tests-file 'projective-native-tests))
              (run-tests (dynamic-require picture-native-tests-file 'picture-native-tests))
              (run-tests (dynamic-require output-group-native-tests-file 'output-group-native-tests))
              (run-tests (dynamic-require portable-native-tests-file 'portable-native-tests))
              (run-tests (dynamic-require color-filter-native-tests-file 'color-filter-native-tests))))])
  (exit (if (zero? failures) 0 1)))
