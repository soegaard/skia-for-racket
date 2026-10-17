#lang racket/base

;;;
;;; Pict Native Test
;;;

;; Covers skia/pict eager CPU snapshots.
;; This native regression layer checks behavior and resource ownership against the installed
;; implementation.

;;;
;;; Imports and Exports
;;;

(require rackunit rackunit/text-ui racket/class racket/list
         pict/convert (prefix-in pict: pict) (prefix-in rd: racket/draw)
         "../main.rkt" "../pict.rkt" "../dc.rkt" "../dc-output.rkt")

(provide pict-native-tests)


;;;
;;; Fixtures and Assertions
;;;

; argb-at : pict? exact-nonnegative-integer? exact-nonnegative-integer? -> bytes?
;   Renders a pict through Racket Draw and samples one ARGB pixel.
(define (argb-at picture x y)
  (define bitmap (pict:pict->bitmap picture))
  (define bytes (make-bytes 4))
  (send bitmap get-argb-pixels x y 1 1 bytes #f #t)
  bytes)


; thread-result : procedure? -> any/c
;   Captures the result or exception of a pict operation on a different thread.
(define (thread-result thunk)
  (define reply (make-channel))
  (thread (lambda ()
            (channel-put reply
                         (with-handlers ([exn:fail? values]) (thunk) 'returned))))
  (channel-get reply))


; source-pict : -> pict?
;   Builds the small colored pict used to check the Skia conversion bridge.
(define (source-pict)
  (with-skia ([paint (make-paint #:color 'red #:antialias? #f)]
              [picture (call-with-picture 101 71
                         (lambda (canvas) (draw-rect canvas 0 0 101 71 paint)))])
    (picture->pict picture #:bounds #(0 0 101/2 71/3) #:raster-scale 3/2)))


;;;
;;; Regression Suite
;;;

; pict-native-tests : test-suite?
;   Collects the regression cases for skia/pict eager CPU snapshots.
(define pict-native-tests
  (test-suite
   "skia/pict eager CPU snapshots"
   (test-case "images produce ordinary picts with premultiplied alpha and detached pixels"
     (define picture
       (with-skia ([image (rgba-bytes->image 3 1
                                            (bytes 255 0 0 255 0 0 128 128 0 0 0 0)
                                            #:premultiplied? #t)])
         (check-false (pict-convertible? image))
         (image->pict image)))
     (check-true (pict:pict? picture))
     (check-true (pict-convertible? picture))
     (check-equal? (list (pict:pict-width picture) (pict:pict-height picture)
                         (pict:pict-ascent picture) (pict:pict-descent picture))
                   '(3 1 1 0))
     (check-equal? (argb-at picture 0 0) (bytes 255 255 0 0))
     (check-equal? (argb-at picture 1 0) (bytes 128 0 0 128))
     (check-equal? (bytes-ref (argb-at picture 2 0) 0) 0))
   (test-case "surface conversion snapshots once and honors logical backing scale"
     (define picture
       (with-skia ([surface (make-surface 101 51 #:background 'red)])
         (check-false (pict-convertible? surface))
         (define out (surface->pict surface #:backing-scale 2))
         (canvas-clear! (surface-canvas surface) 'blue)
         out))
     (check-equal? (list (pict:pict-width picture) (pict:pict-height picture)
                         (pict:pict-ascent picture) (pict:pict-descent picture))
                   '(101/2 51/2 51/2 0))
     ;; The pict's source bitmap is an independent red snapshot after surface close.
     (check-equal? (argb-at picture 0 0) (bytes 255 255 0 0)))
   (test-case "tagged images are read into sRGB while untagged samples stay numerical"
     (with-skia ([linear (make-linear-srgb-color-space)]
                 [srgb (make-srgb-color-space)]
                 [image (rgba-bytes->image 1 1 (bytes 128 128 128 255)
                                           #:color-space linear)])
       (define expected (image->rgba-bytes image #:premultiplied? #t #:color-space srgb))
       (define actual (argb-at (image->pict image) 0 0))
       (check-equal? actual
                     (bytes (bytes-ref expected 3) (bytes-ref expected 0)
                            (bytes-ref expected 1) (bytes-ref expected 2)))))
   (test-case "picture bounds use actual ceiling ratios while logical size is invariant"
     (with-skia ([paint (make-paint #:color 'red #:antialias? #f)]
                 [picture (call-with-picture 101 71
                            (lambda (canvas) (draw-rect canvas 0 0 101 71 paint)))])
       (check-false (pict-convertible? picture))
       (for ([scale '(1 3/2 2)])
         (define rendered (picture->pict picture #:bounds #(0 0 101/2 71/3) #:raster-scale scale))
         (check-equal? (list (pict:pict-width rendered) (pict:pict-height rendered)
                             (pict:pict-ascent rendered) (pict:pict-descent rendered))
                       '(101/2 71/3 71/3 0)))
       ;; The source picture remains live; conversion has no move/close behavior.
       (check-true (picture? picture))
       (check-false (skia-closed? picture))))
   (test-case "picture bounds translate and clip the requested viewport"
     (with-skia ([paint (make-paint #:color 'red #:antialias? #f)]
                 [picture (call-with-picture 20 20
                            (lambda (canvas) (draw-rect canvas 10 5 8 10 paint)))])
       (define rendered (picture->pict picture #:bounds #(10 5 8 10) #:raster-scale 2))
       (check-equal? (list (pict:pict-width rendered) (pict:pict-height rendered)) '(8 10))
       (check-equal? (argb-at rendered 0 0) (bytes 255 255 0 0))))
   (test-case "a zero nominal picture asks for explicit positive bounds"
     (with-skia ([recorder (make-picture-recorder)]
                 [picture (begin
                            (picture-recorder-begin-recording! recorder 0 0 0 1)
                            (picture-recorder-finish-recording! recorder))])
       (check-exn #rx"supply positive" (lambda () (picture->pict picture)))))
   (test-case "closed and wrong-thread sources retain the ordinary resource failures"
     (define image (rgba-bytes->image 1 1 (bytes 0 0 0 0)))
     (dynamic-wind
       void
       (lambda ()
         (check-true (exn:fail? (thread-result (lambda () (image->pict image)))))
         (skia-close! image)
         (check-exn #rx"closed" (lambda () (image->pict image))))
       (lambda () (skia-close! image))))
   (test-case "returned picts compose through bitmap, Skia DC, recording, PDF, and SVG consumers"
     (define picture (source-pict))
     (define target (make-object rd:bitmap% 60 30 #f #t))
     (define target-dc (new rd:bitmap-dc% [bitmap target]))
     (pict:draw-pict picture target-dc 0 0)
     (send target-dc set-bitmap #f)
     (define toolkit-pixel (make-bytes 4))
     (send target get-argb-pixels 1 1 1 1 toolkit-pixel)
     (check-equal? toolkit-pixel (bytes 255 255 0 0))
     (define dc (new skia-dc% [width 60] [height 30]))
     (dynamic-wind
       void
       (lambda ()
         (pict:draw-pict picture dc 0 0)
         (check-equal? (subbytes (send dc get-rgba-bytes) 0 4) (bytes 255 0 0 255)))
       (lambda () (send dc close)))
     (define page (make-dc-output-page 60 30 (lambda (dc) (pict:draw-pict picture dc 0 0))))
     (check-true (regexp-match? #rx#"<image" (output->bytes page 'svg)))
     (check-equal? (subbytes (output->bytes page 'pdf) 0 5) #"%PDF-"))))

(module+ test
  (skia-check!)

  ;;;
  ;;; Test Entry Point
  ;;;

  ; failures : exact-nonnegative-integer?
  ;   Counts failed or errored RackUnit cases for the command-line exit status.
  (define failures (run-tests pict-native-tests))
  (unless (zero? failures) (error 'pict-native-test "~a failures" failures)))
