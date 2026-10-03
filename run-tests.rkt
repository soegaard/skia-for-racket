#lang racket/base
(require racket/cmdline racket/runtime-path rackunit/text-ui
         "main.rkt" "tests/pure-test.rkt" "tests/lifetime-test.rkt"
         "tests/codec-pure-test.rkt" "tests/pdf-pure-test.rkt"
         "tests/svg-pure-test.rkt" "tests/output-pure-test.rkt"
         "tests/path-matrix-pure-test.rkt" "tests/filter-graph-pure-test.rkt"
         "tests/color-output-pure-test.rkt" "tests/annotation-pure-test.rkt" "tests/runtime-pure-test.rkt" "tests/output-audit-pure-test.rkt" "tests/canvas-pure-test.rkt" "tests/geometry-pure-test.rkt" "tests/projective-pure-test.rkt" "tests/picture-pure-test.rkt" "tests/output-group-pure-test.rkt" "tests/portable-pure-test.rkt" "tests/color-filter-pure-test.rkt" "tests/raster-buffer-pure-test.rkt" "tests/gpu-pure-test.rkt" "tests/gpu-surface-pure-test.rkt" "tests/gpu-image-pure-test.rkt" "tests/gpu-metal-pure-test.rkt" "tests/gpu-presenter-pure-test.rkt" "tests/gpu-egl-pure-test.rkt" "tests/gpu-output-pure-test.rkt"
         "tests/gpu-cache-pure-test.rkt" "tests/gpu-performance-pure-test.rkt")

(require "tests/canvas-dc-pure-test.rkt"
         "tests/gpu-dc-pure-test.rkt"
         "tests/native-abi-pure-test.rkt" "tests/gpu-d3d12-pure-test.rkt" "tests/gpu-dxgi-pure-test.rkt"
         "tests/gpu-backends-pure-test.rkt" "tests/gpu-interop-pure-test.rkt"
         "tests/gpu-metal-interop-pure-test.rkt" "tests/dc-pure-test.rkt" "tests/dc-compat-pure-test.rkt" "tests/dc-replay-pure-test.rkt" "tests/dc-style-pure-test.rkt")
(define-runtime-path dc-native-tests-file "tests/dc-native-test.rkt")
(define-runtime-path dc-compat-native-tests-file "tests/dc-compat-native-test.rkt")
(define-runtime-path dc-replay-native-tests-file "tests/dc-replay-native-test.rkt")
(define-runtime-path dc-style-native-tests-file "tests/dc-style-native-test.rkt")
(define-runtime-path canvas-dc-native-tests-file "tests/canvas-dc-native-test.rkt")
(define-runtime-path native-abi-native-tests-file "tests/native-abi-native-test.rkt")
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

(define-runtime-path raster-buffer-native-tests-file "tests/raster-buffer-native-test.rkt")

(module+ main
  (define pure-only? #f)
  (command-line
   #:program "racket run-tests.rkt"
   #:once-each
   [("--pure") "Run only tests that do not load libSkiaSharp"
                 (set! pure-only? #t)]
   #:args () (void))
  (define failures (+ (run-tests pure-tests) (run-tests lifetime-tests)
                      (run-tests canvas-dc-pure-tests)
                      (run-tests gpu-dc-pure-tests)
                      (run-tests dc-style-pure-tests)
                      (run-tests native-abi-pure-tests) (run-tests gpu-d3d12-pure-tests) (run-tests gpu-dxgi-pure-tests) (run-tests gpu-backends-pure-tests) (run-tests gpu-interop-pure-tests) (run-tests gpu-metal-interop-pure-tests) (run-tests dc-pure-tests) (run-tests dc-compat-pure-tests) (run-tests dc-replay-pure-tests)
                      (run-tests codec-pure-tests) (run-tests pdf-pure-tests)
                      (run-tests svg-pure-tests) (run-tests output-pure-tests)
                      (run-tests path-matrix-pure-tests) (run-tests filter-graph-pure-tests)
                      (run-tests color-output-pure-tests) (run-tests annotation-pure-tests) (run-tests runtime-pure-tests) (run-tests output-audit-pure-tests) (run-tests canvas-pure-tests) (run-tests geometry-pure-tests) (run-tests projective-pure-tests) (run-tests picture-pure-tests) (run-tests output-group-pure-tests) (run-tests portable-pure-tests) (run-tests color-filter-pure-tests) (run-tests raster-buffer-pure-tests) (run-tests gpu-pure-tests) (run-tests gpu-surface-pure-tests) (run-tests gpu-image-pure-tests) (run-tests gpu-metal-pure-tests) (run-tests gpu-presenter-pure-tests) (run-tests gpu-egl-pure-tests) (run-tests gpu-output-pure-tests) (run-tests gpu-cache-pure-tests) (run-tests gpu-performance-pure-tests)))
  (cond
    [pure-only? (displayln "Native rendering tests NOT RUN (--pure).")]
    [else
     ;; A missing/incompatible library is a failure, not a silently skipped test.
     (skia-check!)
     (set! failures
           (+ failures (run-tests (dynamic-require native-tests-file 'native-tests))
              (run-tests (dynamic-require native-abi-native-tests-file 'native-abi-native-tests))
              (run-tests (dynamic-require dc-native-tests-file 'dc-native-tests))
              (run-tests (dynamic-require dc-compat-native-tests-file 'dc-compat-native-tests))
              (run-tests (dynamic-require dc-replay-native-tests-file 'dc-replay-native-tests))
              (run-tests (dynamic-require dc-style-native-tests-file 'dc-style-native-tests))
              (run-tests (dynamic-require canvas-dc-native-tests-file 'canvas-dc-native-tests))
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
              (run-tests (dynamic-require color-filter-native-tests-file 'color-filter-native-tests))
              (run-tests (dynamic-require raster-buffer-native-tests-file 'raster-buffer-native-tests))))])
  (exit (if (zero? failures) 0 1)))
