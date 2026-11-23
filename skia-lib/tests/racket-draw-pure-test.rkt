#lang racket/base

;;;
;;; Racket Draw Pure Test
;;;

;; Covers skia/racket-draw pure boundary and detached conversions.
;; This source-only regression layer checks contracts and lifecycle rules before native rendering
;; is involved.

;;;
;;; Imports and Exports
;;;

;; The facade and its detached helpers must be usable without initializing
;; Skia, HarfBuzz, a GUI eventspace, or a GPU context.
(require rackunit rackunit/text-ui racket/class
         (prefix-in rd: racket/draw)
         (prefix-in bitmap: "../bitmap.rkt")
         "../color.rkt"
         "../racket-draw.rkt"
         "../private/bitmap-transfer.rkt"
         "../private/racket-draw-bitmap.rkt"
         "../private/check.rkt")

(provide racket-draw-pure-tests)


;;;
;;; Regression Suite
;;;

; racket-draw-pure-tests : test-suite?
;   Collects the regression cases for skia/racket-draw pure boundary and detached conversions.
(define racket-draw-pure-tests
  (test-suite
   "skia/racket-draw pure boundary and detached conversions"
   (test-case "the two outbound bitmap bindings are re-exported unchanged"
     (check-eq? image->bitmap bitmap:image->bitmap)
     (check-eq? surface->bitmap bitmap:surface->bitmap)
     (check-true (procedure? bitmap->image))
     (check-true (procedure? dc-path->skia-path))
     (check-true (procedure? skia-path->dc-path)))
   (test-case "premultiplied ARGB/RGBA channel permutations are inverses"
     (define argb (bytes 0 0 0 0 1 1 0 1 127 12 34 56 255 20 40 60))
     (check-equal? (argb-premul->rgba argb)
                   (bytes 0 0 0 0 1 0 1 1 12 34 56 127 20 40 60 255))
     (check-equal? (rgba-premul->argb (argb-premul->rgba argb)) argb))
   (test-case "Draw colors preserve byte RGB and round every byte alpha"
     (for ([alpha (in-range 256)])
       (define draw-color (make-object rd:color% 17 91 203 (/ alpha 255.0)))
       (define converted (color%->rgba draw-color))
       (check-equal? (list (rgba-red converted) (rgba-green converted)
                           (rgba-blue converted) (rgba-alpha converted))
                     (list 17 91 203 alpha))
       (define copied (rgba->color% converted))
       (check-false (immutable? copied))
       (check-equal? (list (send copied red) (send copied green) (send copied blue))
                     '(17 91 203))
       (check-= (send copied alpha) (/ alpha 255.0) 1e-12)))
   (test-case "colors reject unrelated objects before any native action"
     (check-exn exn:fail:contract? (lambda () (color%->rgba 'blue)))
     (check-exn exn:fail:contract? (lambda () (rgba->color% 'blue))))
   (test-case "bitmap options and bridge budget are checked before image construction"
     (check-exn exn:fail:contract? (lambda () (bitmap->image 'not-a-bitmap)))
     (define bitmap (rd:make-bitmap 2 2 #t))
     (check-exn exn:fail:contract?
                (lambda () (racket-draw-bitmap-snapshot 'probe bitmap 'wrong #f)))
     (parameterize ([current-skia-byte-limit 47])
       ;; The neutral bridge charges 12 source/result/image bytes per pixel,
       ;; before Racket Draw readback or native image allocation.
       (check-exn exn:fail? (lambda ()
                              (racket-draw-bitmap-snapshot 'probe bitmap 'physical #f)))))
   (test-case "path options are validated at the public call boundary"
     (define path (new rd:dc-path%))
     (check-exn exn:fail:contract?
                (lambda () (dc-path->skia-path path #:fill-style 'even-odd)))
     (check-exn exn:fail:contract?
                (lambda () (skia-path->dc-path 'not-a-path #:conic-subdivisions 6))))))

(module+ test

  ;;;
  ;;; Test Entry Point
  ;;;

  ; failures : exact-nonnegative-integer?
  ;   Counts failed or errored RackUnit cases for the command-line exit status.
  (define failures (run-tests racket-draw-pure-tests))
  (unless (zero? failures) (error 'racket-draw-pure-test "~a failures" failures)))
