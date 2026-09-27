#lang racket/base
(require rackunit "../main.rkt" "../private/output-group-util.rkt")
(define (choice b p fs) (call-with-values (lambda () (group-strategy b p fs)) list))

(provide output-group-pure-tests)
(define output-group-pure-tests
  (test-suite "Bounded output groups: pure decisions"
    (test-case "policies are explicit"
      (for ([x '(prefer-vector require-vector raster)]) (check-eq? (group-policy 'test x) x)))
    (test-case "unknown policy rejects"
      (check-exn exn:fail? (lambda () (group-policy 'test 'auto))))
    (test-case "label copied"
      (define s (string-copy "local")) (define t (group-label 'test s)) (string-set! s 0 #\x) (check-equal? t "local") (check-true (immutable? t)))
    (test-case "false label allowed"
      (check-false (group-label 'test #f)))
    (test-case "invalid label rejected"
      (check-exn exn:fail? (lambda () (group-label 'test 7))))
    (test-case "logical bounds and asymmetric padding"
      (define v (call-with-values (lambda () (group-geometry 'test 20 30 100 50 '(2 3 4 5) 2)) list)) (check-equal? v '(20.0 30.0 100.0 50.0 (2 3 4 5) 2 3 106.0 58.0)))
    (test-case "zero logical dimensions rejected"
      (check-exn exn:fail? (lambda () (group-geometry 'test 0 0 0 10 0 1))))
    (test-case "negative dimensions rejected"
      (check-exn exn:fail? (lambda () (group-geometry 'test 0 0 10 -1 0 1))))
    (test-case "nonfinite position rejected"
      (check-exn exn:fail? (lambda () (group-geometry 'test +inf.0 0 10 10 0 1))))
    (test-case "negative padding rejected"
      (check-exn exn:fail? (lambda () (group-geometry 'test 0 0 10 10 -1 1))))
    (test-case "padding list must have four values"
      (check-exn exn:fail? (lambda () (group-geometry 'test 0 0 10 10 '(1 2 3) 1))))
    (test-case "zero scale rejected"
      (check-exn exn:fail? (lambda () (group-geometry 'test 0 0 10 10 0 0))))
    (test-case "large vector bounds do not allocate pixels"
      (parameterize ([current-skia-byte-limit 4]) (check-not-exn (lambda () (call-with-values (lambda () (group-geometry 'test 0 0 10000 10000 0 1)) (lambda ignored (void)))))))
    (test-case "plain geometry native on both formats"
      (for ([b '(pdf svg)]) (check-equal? (choice b 'prefer-vector '(picture geometry)) '(native native-compatible))))
    (test-case "PDF filter fallback is explicit"
      (check-equal? (choice 'pdf 'prefer-vector '(image-filter)) '(raster backend-fallback)))
    (test-case "SVG runtime fallback"
      (check-equal? (choice 'svg 'prefer-vector '(runtime-shader)) '(raster backend-fallback)))
    (test-case "existing images are native embedding"
      (check-equal? (choice 'svg 'prefer-vector '(image)) '(native native-compatible)))
    (test-case "require vector rejects an image"
      (check-equal? (choice 'pdf 'require-vector '(image)) '(reject vector-required)))
    (test-case "require vector accepts geometry"
      (check-equal? (choice 'svg 'require-vector '(geometry clip-intersect linear-gradient)) '(native native-compatible)))
    (test-case "forced raster on plain geometry"
      (check-equal? (choice 'svg 'raster '(geometry)) '(raster explicit-raster)))
    (test-case "unknown cannot be forced raster"
      (for ([pol '(prefer-vector require-vector raster)]) (check-equal? (choice 'svg pol '(deserialized-picture)) '(reject unknown-provenance))))
    (test-case "unrecognized feature is unknown"
      (check-equal? (choice 'pdf 'prefer-vector '(not-a-feature)) '(reject unknown-provenance)))
    (test-case "native annotation remains native"
      (check-equal? (choice 'svg 'prefer-vector '(annotation geometry)) '(native native-compatible)))
    (test-case "annotation prevents fallback"
      (check-equal? (choice 'svg 'prefer-vector '(annotation runtime-shader)) '(reject annotation-would-be-lost)))
    (test-case "annotation prevents forced raster"
      (check-equal? (choice 'pdf 'raster '(annotation)) '(reject annotation-would-be-lost)))
    (test-case "discarded picture shader links rejected"
      (check-equal? (choice 'pdf 'prefer-vector '(picture-shader-annotation)) '(reject discarded-semantics)))
    (test-case "already rasterized annotation remains discarded"
      (check-equal? (choice 'svg 'prefer-vector '(rasterized-annotation)) '(reject discarded-semantics)))
    (test-case "native text cannot disappear in PDF fallback"
      (check-equal? (choice 'pdf 'prefer-vector '(native-text image-filter)) '(reject native-text-would-be-lost)))
    (test-case "viewer-dependent native SVG text is not silently outlined"
      (check-equal? (choice 'svg 'prefer-vector '(native-text)) '(native native-compatible)))
    (test-case "source replacement requires isolation"
      (check-equal? (choice 'pdf 'prefer-vector '(geometry source-replace)) '(raster isolated-compositing)))
    (test-case "blend operations require isolation even on raster"
      (check-equal? (choice 'raster 'prefer-vector '(blend-mode)) '(raster isolated-compositing)))
    (test-case "plain raster target replays without extra allocation"
      (check-equal? (choice 'raster 'prefer-vector '(geometry)) '(native raster-target)))
    (test-case "raster text can be rendered as raster"
      (check-equal? (choice 'raster 'raster '(native-text)) '(raster explicit-raster)))
    (test-case "new audit classifications are conservative"
      (check-eq? (output-capability-status (output-capability-for 'svg 'output-group)) 'vector) (check-eq? (output-capability-status (output-capability-for 'raster 'rasterized-annotation)) 'discarded))
    (test-case "invalid callback rejected before native access"
      (check-exn exn:fail:contract? (lambda () (draw-output-group #f 0 0 10 10 12))))
    (test-case "invalid report rejected"
      (check-exn exn:fail:contract? (lambda () (output-group-report->jsexpr 'report))))
))
