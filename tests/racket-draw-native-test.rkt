#lang racket/base

;;;
;;; Racket Draw Native Test
;;;

;; Covers skia/racket-draw owned raster and vector conversions.
;; This native regression layer checks behavior and resource ownership against the installed
;; implementation.

;;;
;;; Imports and Exports
;;;

(require rackunit rackunit/text-ui racket/class racket/list
         (prefix-in rd: racket/draw)
         "../main.rkt" "../racket-draw.rkt")

(provide racket-draw-native-tests)


;;;
;;; Fixtures and Assertions
;;;

; mul255 : byte? byte? -> byte?
;;   Multiplies a channel by byte coverage with integer rounding.
(define (mul255 component coverage)
  (quotient (+ (* component coverage) 127) 255))


; rgba-at : image? -> any/c
;;   Reads the converted image's RGBA sample for bitmap-bridge assertions.
(define (rgba-at image)
  (image->rgba-bytes image #:premultiplied? #t))


; source-bitmap : bytes? [exact-positive-integer? exact-positive-integer?] -> bitmap%
;;   Builds a source bitmap from explicitly supplied ARGB storage.
(define (source-bitmap argb [width 2] [height 1])
  (define bitmap (rd:make-bitmap width height #t))
  (send bitmap set-argb-pixels 0 0 width height argb #f #t)
  bitmap)


;;;
;;; Regression Suite
;;;

; racket-draw-native-tests : test-suite?
;;   Collects the regression cases for skia/racket-draw owned raster and vector conversions.
(define racket-draw-native-tests
  (test-suite
   "skia/racket-draw owned raster and vector conversions"
   (test-case "physical and logical bitmap imports copy premultiplied bytes"
     (define source
       (source-bitmap (bytes 255 12 34 56 128 50 80 100)))
     (with-skia ([physical (bitmap->image source #:mask #f)]
                 [logical (bitmap->image source #:resolution 'logical #:mask #f)])
       (check-equal? (list (image-width physical) (image-height physical)) '(2 1))
       (check-equal? (rgba-at physical) (bytes 12 34 56 255 50 80 100 128))
       (check-equal? (rgba-at logical) (rgba-at physical))
       ;; Snapshot ownership is independent of later Draw mutation.
       (send source set-argb-pixels 0 0 2 1 (bytes 255 1 2 3 255 4 5 6) #f #t)
       (check-equal? (rgba-at physical) (bytes 12 34 56 255 50 80 100 128))))
   (test-case "loaded and replacement masks are baked into all premultiplied components"
     (define source (source-bitmap (bytes 200 100 80 60 255 10 20 30)))
     (define loaded (source-bitmap (bytes 128 0 0 0 255 0 0 0)))
     (define replacement (source-bitmap (bytes 64 0 0 0 64 0 0 0)))
     (send source set-loaded-mask loaded)
     (with-skia ([masked (bitmap->image source)]
                 [unmasked (bitmap->image source #:mask #f)]
                 [replaced (bitmap->image source #:mask replacement)])
       (check-equal? (rgba-at masked)
                     (bytes (mul255 100 128) (mul255 80 128) (mul255 60 128) (mul255 200 128)
                            10 20 30 255))
       (check-equal? (rgba-at unmasked) (bytes 100 80 60 200 10 20 30 255))
       (check-equal? (rgba-at replaced)
                     (bytes (mul255 100 64) (mul255 80 64) (mul255 60 64) (mul255 200 64)
                            (mul255 10 64) (mul255 20 64) (mul255 30 64) 64))))
   (test-case "Draw path import creates a detached owned Skia path with its requested fill"
     (define source (new rd:dc-path%))
     (send source move-to -1/2 1/4)
     (send source line-to 8 1/4)
     (send source curve-to 9 1 9 7 8 8)
     (send source close)
     (define imported (dc-path->skia-path source #:fill-style 'odd-even))
     (dynamic-wind
       void
       (lambda ()
         (check-eq? (path-fill-rule imported) 'even-odd)
         (send source reset)
         (check-equal? (map car (path->commands imported)) '(move line cubic close)))
       (lambda () (skia-close! imported))))
   (test-case "Skia path export preserves fill, closure and exact quadratic geometry"
     (with-skia ([source (make-path '((move 0 0) (line 10 0) (quad 15 10 20 0) (close)
                                      (move 30 0) (line 40 0))
                                    #:fill-rule 'even-odd)])
       (define-values (draw-path fill-style) (skia-path->dc-path source))
       (check-eq? fill-style 'odd-even)
       (define-values (closed open) (send draw-path get-datum))
       (check-equal? (length closed) 1)
       (check-equal? (length open) 2)
       ;; The quadratic is represented by a cubic with the degree-elevated
       ;; first control point (40/3, 20/3).
       (define cubic (third (car closed)))
       (check-equal? (vector-length cubic) 6)
       (check-= (vector-ref cubic 0) (/ 40.0 3.0) 1e-5)
       (check-= (vector-ref cubic 1) (/ 20.0 3.0) 1e-5)))
   (test-case "unrepresentable topology and rational conics require an explicit policy"
     (with-skia ([two-opens (make-path '((move 0 0) (line 4 0)
                                         (move 8 0) (line 12 0)))])
       (check-exn #rx"open contour" (lambda () (skia-path->dc-path two-opens))))
     (with-skia ([conic (make-path '((move 0 0) (conic 10 20 20 0 0.5)))])
       (check-exn #rx"conic" (lambda () (skia-path->dc-path conic)))
       (define-values (draw-path fill-style)
         (skia-path->dc-path conic #:conic-subdivisions 0))
       (check-eq? fill-style 'winding)
       (define-values (_closed open) (send draw-path get-datum))
       (check-equal? (length open) 2)
       (check-equal? (vector-length (second open)) 6)))))

(module+ test
  (skia-check!)

  ;;;
  ;;; Test Entry Point
  ;;;

  ; failures : exact-nonnegative-integer?
  ;;   Counts failed or errored RackUnit cases for the command-line exit status.
  (define failures (run-tests racket-draw-native-tests))
  (unless (zero? failures) (error 'racket-draw-native-test "~a failures" failures)))
