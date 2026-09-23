#lang racket/base
(require rackunit rackunit/text-ui ffi/unsafe
         "../main.rkt" "../private/types.rkt")
(provide pure-tests)

(define pure-tests
  (test-suite
   "Colors, validation, and ABI layouts (no native library)"
   (test-case "byte colors and named colors"
     (check-equal? (rgb 1 2 3) (rgba 1 2 3 255))
     (check-equal? (color->argb 'red) #xffff0000)
     (check-equal? (color->argb 'transparent) 0)
     (check-equal? (color->rgba 'green) (rgba 0 128 0 255)))
   (test-case "string and integer color ordering are explicit"
     (check-equal? (color->rgba "#12345680") (rgba 18 52 86 128))
     (check-equal? (color->rgba #x80123456) (rgba 18 52 86 128))
     (check-equal? (color->rgba "#ABCDEF") (rgba 171 205 239 255)))
   (test-case "color packing round trips"
     (for* ([a '(0 1 127 255)] [r '(0 19 255)] [g '(0 71 255)] [b '(0 181 255)])
       (define c (rgba r g b a))
       (check-equal? (color->rgba (color->argb c)) c)))
   (test-case "invalid colors are rejected"
     (for ([v (in-list (list -1 #x100000000 "#abc" "#GG0000" 'unknown #f 1.0))])
       (check-false (color? v))
       (check-exn exn:fail:contract? (lambda () (color->rgba v))))
     (check-exn exn:fail:contract? (lambda () (rgba 1 2 3 0.5)))
     (check-exn exn:fail:contract? (lambda () (rgb 256 0 0))))
   (test-case "surface dimensions are checked before native loading"
     (for ([n (in-list '(0 -1 1.5 32769))])
       (check-exn exn:fail:contract? (lambda () (make-surface n 10))))
     (parameterize ([current-skia-byte-limit 15])
       (check-exn exn:fail:contract? (lambda () (make-surface 2 2)))))
   (test-case "paint options are checked before native loading"
     (check-exn exn:fail:contract? (lambda () (make-paint #:style 'wrong)))
     (check-exn exn:fail:contract? (lambda () (make-paint #:stroke-width -1)))
     (check-exn exn:fail:contract? (lambda () (make-paint #:stroke-width +inf.0)))
     (check-exn exn:fail:contract? (lambda () (make-paint #:stroke-width +nan.0)))
     (check-exn exn:fail:contract? (lambda () (make-paint #:antialias? 1))))
   (test-case "image buffer validation before native loading"
     (check-exn exn:fail:contract? (lambda () (rgba-bytes->image 2 2 (make-bytes 15))))
     (check-exn exn:fail? (lambda () (rgba-bytes->image 1 1 (bytes 255 0 0 128)
                                                                   #:premultiplied? #t))))
   (test-case "byte-limit parameter rejects invalid settings"
     (for ([n '(0 -1 1.5 #f)])
       (check-exn exn:fail:contract? (lambda () (current-skia-byte-limit n)))))
   (test-case "C bool is one byte"
     (check-equal? (ctype-sizeof _stdbool) 1))
   (test-case "native struct sizes"
     (define p (ctype-sizeof _pointer))
     (check-equal? (ctype-sizeof _sk-image-info) (+ p 16))
     (check-equal? (ctype-sizeof _sk-rect) 16)
     (check-equal? (ctype-sizeof _sk-sampling) 24)
     (check-equal? (ctype-sizeof _sk-png-options) (+ 8 (* 3 p)))
     (check-equal? (ctype-sizeof _sk-font-metrics) 64))
   (test-case "native struct field order"
     (define info (make-sk-image-info #f 123 456 4 2))
     (define p (ctype-sizeof _pointer))
     (check-false (ptr-ref info _pointer))
     (check-equal? (ptr-ref (ptr-add info p) _int32) 123)
     (check-equal? (ptr-ref (ptr-add info (+ p 4)) _int32) 456)
     (check-equal? (ptr-ref (ptr-add info (+ p 8)) _int) 4)
     (check-equal? (ptr-ref (ptr-add info (+ p 12)) _int) 2)
     (define options (make-sk-png-options 248 6 #f #f #f))
     (check-equal? (ptr-ref options _int) 248)
     (check-equal? (ptr-ref (ptr-add options 4) _int) 6)
     (for ([offset (in-list (list 8 (+ 8 p) (+ 8 (* 2 p))))])
       (check-false (ptr-ref (ptr-add options offset) _pointer))))
   (test-case "sampling padding is honored"
     (define s (make-sk-sampling 0 #f 0.0 0.0 1 0))
     (check-equal? (ptr-ref (ptr-add s 4) _uint8) 0)
     (check-equal? (ptr-ref (ptr-add s 16) _int) 1)
     (check-equal? (ptr-ref (ptr-add s 20) _int) 0))
   (test-case "font and typeface options validate before native loading"
     (check-exn exn:fail:contract? (lambda () (make-font 'not-a-typeface)))
     (check-exn exn:fail:contract? (lambda () (make-font #:size 0)))
     (check-exn exn:fail:contract? (lambda () (make-font #:scale-x -1)))
     (check-exn exn:fail:contract? (lambda () (make-font #:edging 'wrong)))
     (check-exn exn:fail:contract? (lambda () (make-font #:hinting 'wrong)))
     (check-exn exn:fail:contract? (lambda () (make-font #:subpixel? 1)))
     (check-exn exn:fail:contract?
                (lambda () (typeface-from-family "x" #:weight 1001)))
     (check-exn exn:fail:contract?
                (lambda () (typeface-from-family "x" #:width 0)))
     (check-exn exn:fail:contract?
                (lambda () (typeface-from-family "x" #:slant 'wrong)))
     (check-exn exn:fail?
                (lambda () (typeface-from-file "definitely-not-a-font-file.ttf"))))
   (test-case "font metrics ABI field order"
     (define m
       (make-sk-font-metrics #x0f
                             1.0 2.0 3.0 4.0 5.0
                             6.0 7.0 8.0 9.0 10.0 11.0
                             12.0 13.0 14.0 15.0))
     (check-equal? (ptr-ref m _uint32) #x0f)
     (for ([expected (in-range 1 16)] [offset (in-range 4 64 4)])
       (check-= (ptr-ref (ptr-add m offset) _float) expected 0.001)))
   (test-case "filesystem path predicate is not shadowed"
     (check-true (path? (string->path "sample.png")))
     (check-false (skia-path? (string->path "sample.png"))))))

(module+ test
  (define failures (run-tests pure-tests))
  (unless (zero? failures) (error 'pure-tests "~a failures" failures)))
