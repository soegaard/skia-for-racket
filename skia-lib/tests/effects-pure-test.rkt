#lang racket/base

;;;
;;; Effects Pure Test
;;;

;; Covers effect validation without loading Skia.
;; This source-only regression layer checks contracts and lifecycle rules before native rendering
;; is involved.

;;;
;;; Imports and Exports
;;;
(require rackunit rackunit/text-ui ffi/unsafe
         "../main.rkt" "../private/effects-util.rkt" "../private/color-filter-util.rkt" "../private/types.rkt")
(provide effects-pure-tests)

;;;
;;; Regression Suite
;;;

; effects-pure-tests : test-suite?
;   Collects the regression cases for effect validation without loading Skia.
(define effects-pure-tests
  (test-suite
   "0.66 effect validation without loading Skia"
   (test-case "identity trim composition is closeable without native allocation"
     (with-skia ([a (make-trim-path-effect 0 1)]
                 [b (make-trim-path-effect 0 1)]
                 [composed (make-compose-path-effect a b)]
                 [summed (make-sum-path-effect a b)])
       (skia-close! a)
       (skia-close! b)
       (check-false (skia-closed? composed))
       (check-false (skia-closed? summed))
       (check-exn #rx"closed" (lambda () (make-compose-path-effect a summed)))
       (check-exn #rx"closed" (lambda () (make-sum-path-effect summed b)))
       (define results (make-channel))
       (define worker
         (thread
          (lambda ()
            (channel-put results
              (with-handlers ([exn:fail? exn-message])
                (make-compose-path-effect composed summed))))))
       (check-regexp-match #rx"another Racket thread" (channel-get results))
       (thread-wait worker)))
   (test-case "new constructors are public procedures"
     (for ([p (in-list (list make-1d-path-effect make-2d-line-path-effect make-2d-path-effect
                            make-table-mask-filter make-gamma-mask-filter make-clip-mask-filter
                            make-shader-mask-filter make-fractal-noise-shader make-turbulence-shader
                            make-empty-shader shader-with-color-filter make-blender-shader
                            make-arithmetic-blender make-blender-image-filter))])
       (check-true (procedure? p))))
   (test-case "existing matrix and tile ABI sizes"
     (check-equal? (ctype-sizeof _sk-matrix) 36)
     (check-equal? (ctype-sizeof _sk-isize) 8))
   (test-case "positive scalars are checked after float rounding"
     (for ([x (in-list (list 0 -1 +inf.0 -inf.0 +nan.0 1e-100 'bad))])
       (check-exn exn:fail? (lambda () (effect-positive 'test x))))
     (check-equal? (effect-positive 'test 1) 1.0))
   (test-case "nonnegative noise frequencies"
     (for ([x (in-list (list -1 +inf.0 +nan.0 'bad))])
       (check-exn exn:fail? (lambda () (make-fractal-noise-shader x 0.1 3)))))
   (test-case "octaves cannot wrap or be silently clamped"
     (for ([n (in-list '(-1 256 1.5 #f many))])
       (check-exn exn:fail? (lambda () (make-turbulence-shader 0.1 0.1 n)))))
   (test-case "zero octaves remain a valid checked description"
     (define-values (x y n seed tile) (effect-noise 'test 0 0 0 0 #f))
     (check-equal? (list x y n seed tile) '(0.0 0.0 0 0.0 #f)))
   (test-case "nonfinite noise seed rejected before allocation"
     (check-exn exn:fail? (lambda () (make-turbulence-shader 0.1 0.1 2 +nan.0))))
   (test-case "invalid tile size"
     (for ([t (in-list '(bad () (1) (0 4) (4 -1) (4.5 8) (32769 4) (1 2 3)))])
       (check-exn exn:fail? (lambda () (make-fractal-noise-shader 0.1 0.1 2 #:tile-size t)))))
   (test-case "tile dimensions have no implicit RGBA allocation"
     (parameterize ([current-skia-byte-limit 1])
       (define-values (_x _y _n _s tile) (effect-noise 'test 0.1 0.1 3 0 '(64 48)))
       (check-equal? (list (sk-isize-width tile) (sk-isize-height tile)) '(64 48))))
   (test-case "table length and input type"
     (for ([t (in-list (list (make-bytes 255) (make-bytes 257) '#(1 2) #f))])
       (check-exn exn:fail? (lambda () (make-table-mask-filter t)))))
   (test-case "table snapshot and byte budget"
     (define input (make-bytes 256 32))
     (define copy (checked-filter-table 'test input))
     (bytes-fill! input 0)
     (check-true (immutable? copy)) (check-equal? (bytes-ref copy 42) 32)
     (parameterize ([current-skia-byte-limit 255])
       (check-exn exn:fail? (lambda () (make-table-mask-filter input)))))
   (test-case "table lists and vectors share byte validation and snapshot semantics"
     (define entries (build-list 256 values))
     (define input (list->vector entries))
     (define copy (checked-filter-table 'test input))
     (vector-set! input 42 0)
     (check-equal? copy (checked-filter-table 'test entries))
     (check-equal? (bytes-ref copy 42) 42)
     (for ([bad (in-list '(-1 256 1.5 #f))])
       (vector-set! input 42 bad)
       (check-exn exn:fail? (lambda () (make-table-mask-filter input))))
     (parameterize ([current-skia-byte-limit 255])
       (check-exn exn:fail? (lambda () (make-table-mask-filter entries)))))
   (test-case "clip thresholds are not silently normalized"
     (for ([p (in-list '((-1 3) (0 256) (10 10) (11 10) (0 1.5) (#f 4)))])
       (check-exn exn:fail? (lambda () (apply make-clip-mask-filter p))))
     (check-equal? (call-with-values (lambda () (effect-clip 'test 0 255)) list) '(0 255)))
   (test-case "gamma rejects nonpositive or unrepresentable values"
     (for ([g (in-list (list 0 -1 1e-100 +nan.0))])
       (check-exn exn:fail? (lambda () (make-gamma-mask-filter g)))))
   (test-case "singular lattice rejected"
     (check-exn exn:fail? (lambda () (make-2d-line-path-effect 1 (matrix-scale 0 1))))
     (check-exn exn:fail? (lambda () (make-2d-path-effect #f #f))))
   (test-case "stamp spacing and style validated first"
     (check-exn exn:fail? (lambda () (make-1d-path-effect #f 0)))
     (check-exn exn:fail? (lambda () (make-1d-path-effect #f 1 #:style 'unknown))))
   (test-case "bad resource types fail without native construction"
     (check-exn exn:fail? (lambda () (make-shader-mask-filter #f)))
     (check-exn exn:fail? (lambda () (shader-with-color-filter #f #f)))
     (check-exn exn:fail? (lambda () (make-blender-shader #f #f #f)))
     (check-exn exn:fail? (lambda () (make-blender-image-filter #f #f #f))))
   (test-case "arithmetic validates coefficients and boolean"
     (check-exn exn:fail? (lambda () (make-arithmetic-blender +nan.0 1 0 0)))
     (check-exn exn:fail? (lambda () (make-arithmetic-blender 0 1 0 0 #:enforce-premul? 1))))
   (test-case "new document feature classifications are explicit"
     (for* ([backend (in-list '(pdf svg))]
            [feature (in-list '(perlin-noise empty-shader arithmetic-blender))])
       (check-eq? (output-capability-status (output-capability-for backend feature)) 'needs-raster)))
   (test-case "legacy mask/path policies are not weakened"
     (check-eq? (output-capability-status (output-capability-for 'pdf 'mask-filter)) 'needs-raster)
     (check-eq? (output-capability-status (output-capability-for 'svg 'path-effect)) 'needs-raster))))
(module+ main (exit (if (zero? (run-tests effects-pure-tests)) 0 1)))
