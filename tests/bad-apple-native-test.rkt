#lang racket/base

;;;
;;; Bad Apple!! Native Scene Tests
;;;

(require rackunit
         rackunit/text-ui
         "../main.rkt"
         "../examples/bad-apple/data.rkt"
         "../examples/bad-apple/scene.rkt")

(provide bad-apple-native-tests)

(define (fixture-asset)
  (bad-apple-asset-from-jsexpr
   (hasheq 'schema "skia-bad-apple-paths"
           'version 1
           'source (hasheq 'repository "fixture/repository"
                           'commit "abcdef"
                           'path "frames.js"
                           'sha256 "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
                           'first_source_index 1)
           'fps_numerator 30
           'fps_denominator 1
           'frame_count 2
           'view_box '(0 0 480 360)
           'source_to_view_box '(0.1 0 0 -0.1 0 360)
           'fill_rule "winding"
           ;; Source coordinates are tenths and are flipped vertically by the preserved transform.
           'frames '(("M0 0L4800 0L4800 3600L0 3600Z") ()))))

(define bad-apple-native-tests
  (test-suite
   "Bad Apple native scene"
   (test-case "native compilation preserves source paths and a blank frame clears the previous drawing"
     (define scene (compile-bad-apple-scene (fixture-asset)))
     (dynamic-wind
       void
       (lambda ()
         (with-skia ([surface (make-surface 480 360 #:background 'red)])
           (define canvas (surface-canvas surface))
           (draw-bad-apple-frame canvas scene 0 480 360)
           (check-equal? (surface-pixel surface 240 180) (rgb 0 0 0))
           (draw-bad-apple-frame canvas scene 1 480 360)
           (check-equal? (surface-pixel surface 240 180) (rgb 255 255 255))))
       (lambda () (bad-apple-scene-close! scene))))
   (test-case "incremental compilation retains each path and can be closed idempotently"
     (define builder (make-bad-apple-scene-builder (fixture-asset)))
     (define scene
       (let loop ()
         (or (bad-apple-scene-builder-step! builder #:path-limit 1 #:time-limit-ms 1000.0)
             (loop))))
     (check-equal? (bad-apple-scene-path-count scene) 1)
     (bad-apple-scene-close! scene)
     (bad-apple-scene-close! scene))))

(define (run-bad-apple-native-tests) (run-tests bad-apple-native-tests))
(module+ main (run-bad-apple-native-tests))
(module+ test (run-bad-apple-native-tests))
