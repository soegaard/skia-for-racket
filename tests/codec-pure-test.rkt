#lang racket/base
(require rackunit ffi/unsafe
         "../main.rkt" "../private/types.rkt" "../private/codec-util.rkt"
         "codec-fixtures.rkt")
(provide codec-pure-tests)

(define origins
  '(top-left top-right bottom-right bottom-left left-top right-top right-bottom left-bottom))
(define sample (apply bytes (for*/list ([i (in-range 6)] [j (in-range 4)]) (+ (* i 4) j))))
(define (permuted pixels order)
  (apply bytes-append
         (for/list ([i (in-vector order)]) (subbytes pixels (* 4 i) (+ 4 (* 4 i))))))

(define codec-pure-tests
  (test-suite
   "Advanced codecs: pure checks"
   (test-case "pinned codec ABI sizes and alignments"
     (check-equal? (ctype-sizeof _sk-codec-options)
                   (if (= (ctype-sizeof _pointer) 8) 24 16))
     (check-equal? (ctype-alignof _sk-codec-options) (ctype-alignof _pointer))
     (check-equal? (ctype-sizeof _sk-codec-frame-info) 44)
     (check-equal? (ctype-alignof _sk-codec-frame-info) 4))
   (test-case "codec option field offsets"
     (define o (make-sk-codec-options 1 #f 23 -1))
     (define wide? (= (ctype-sizeof _pointer) 8))
     (check-equal? (ptr-ref o _int 0) 1)
     (check-false (ptr-ref (ptr-add o (if wide? 8 4)) _pointer))
     (check-equal? (ptr-ref (ptr-add o (if wide? 16 8)) _int) 23)
     (check-equal? (ptr-ref (ptr-add o (if wide? 20 12)) _int) -1))
   (test-case "frame-info field offsets include blend and inline rectangle"
     (define f (make-sk-codec-frame-info -1 70 #t 2 #t 3 1 (make-sk-irect 2 3 5 7)))
     (for ([offset (in-list '(0 4 12 20 24 28 32 36 40))]
           [value (in-list '(-1 70 2 3 1 2 3 5 7))])
       (check-equal? (ptr-ref (ptr-add f offset) _int) value))
     (check-equal? (ptr-ref (ptr-add f 8) _uint8) 1)
     (check-equal? (ptr-ref (ptr-add f 16) _uint8) 1))
   (test-case "all eight origins match independent asymmetric permutations"
     (for ([origin (in-list origins)] [order (in-vector orientation-orders)] [i (in-naturals)])
       (define-values (w h actual) (orient-rgba-bytes 'test 3 2 sample origin))
       (check-equal? (list w h) (if (< i 4) '(3 2) '(2 3)))
       (check-equal? actual (permuted sample order))))
   (test-case "orientation preserves channel and alpha bytes"
     (define pixel (bytes 13 127 231 42))
     (for ([origin (in-list origins)])
       (define-values (w h result) (orient-rgba-bytes 'test 1 1 pixel origin))
       (check-equal? (list w h) '(1 1))
       (check-equal? result pixel)))
   (test-case "inverse transforms recover non-square inputs"
     (for ([origin (in-list origins)]
           [inverse (in-list '(top-left top-right bottom-right bottom-left
                              left-top left-bottom right-bottom right-top))])
       (define-values (w h rotated) (orient-rgba-bytes 'test 3 2 sample origin))
       (define-values (rw rh restored) (orient-rgba-bytes 'test w h rotated inverse))
       (check-equal? (list rw rh restored) (list 3 2 sample))))
   (test-case "orientation rejects malformed input before any native call"
     (check-exn exn:fail:contract? (lambda () (orient-rgba-bytes 'test 3 2 #"" 'top-left)))
     (check-exn exn:fail:contract? (lambda () (orient-rgba-bytes 'test 0 2 #"" 'top-left)))
     (check-exn exn:fail:contract? (lambda () (orient-rgba-bytes 'test 3 2 sample 'sideways)))
     (parameterize ([current-skia-byte-limit 23])
       (check-exn exn:fail:contract? (lambda () (orient-rgba-bytes 'test 3 2 sample 'left-top)))))
   (test-case "encoded input and frame options validate without loading Skia"
     (check-exn exn:fail:contract? (lambda () (codec-from-bytes 'not-bytes)))
     (check-exn exn:fail:contract? (lambda () (codec-from-bytes #"")))
     (parameterize ([current-skia-byte-limit 1])
       (check-exn exn:fail:contract? (lambda () (codec-from-bytes #"ab"))))
     (for ([bad (in-list '(-1 1/2 1.0 2147483648 #f))])
       (check-exn exn:fail:contract? (lambda () (image-frame-from-bytes #"" bad))))
     (check-exn exn:fail:contract?
                (lambda () (image-frame-from-bytes #"" #:normalize-origin? 'yes)))
     (check-exn exn:fail:contract?
                (lambda () (image-frame-from-bytes #"" #:color-space 'srgb))))
   (test-case "codec predicates and result names"
     (check-false (codec? #f))
     (check-false (codec-frame-info? #f))
     (check-exn exn:fail:contract? (lambda () (codec-info #f)))
     (check-equal? (codec-result-name 0) 'success)
     (check-equal? (codec-result-name 1) 'incomplete-input)
     (check-equal? (codec-result-name 9) 'unimplemented)
     (check-equal? (codec-result-name 10) 'unknown-result)
     (check-equal? (codec-result-name -1) 'unknown-result))
   (test-case "EXIF fixture has correct segment size and orientation field"
     (define minimal-jpeg (bytes 255 216 255 217))
     (for ([origin (in-range 1 9)])
       (define exif-jpeg (jpeg-with-origin minimal-jpeg origin))
       (check-equal? (bytes-length exif-jpeg) 40)
       (check-equal? (subbytes exif-jpeg 2 6) (bytes 255 225 0 34))
       (check-equal? (bytes-ref exif-jpeg 30) origin)
       (check-equal? (subbytes exif-jpeg 38) (bytes 255 217))))))

(module+ test
  (require rackunit/text-ui)
  (define failures (run-tests codec-pure-tests))
  (unless (zero? failures) (error 'codec-pure-test "~a tests failed" failures)))
