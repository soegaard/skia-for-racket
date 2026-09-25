#lang racket/base
(require "check.rkt")
(provide oriented-dimensions orient-rgba-bytes checked-codec-index
         codec-result-name codec-disposal-values codec-blend-values)

;; Private, allocation-checked helpers. No native library is loaded here.
(define (checked-codec-index who index)
  (unless (and (exact-integer? index) (<= 0 index #x7fffffff))
    (raise-argument-error who "exact integer from 0 through 2147483647" index))
  index)

(define (oriented-dimensions who w h origin)
  (choice who origin encoded-origin-values)
  (if (memq origin '(left-top right-top right-bottom left-bottom))
      (values h w)
      (values w h)))

;; The caller supplies packed RGBA pixels in encoded coordinates. The identity
;; case shares its input; all other cases return a new byte string. No channel
;; arithmetic, filtering, alpha conversion, or color conversion occurs here.
(define (orient-rgba-bytes who w h pixels origin)
  (define n (check-dimensions who w h))
  (unless (and (bytes? pixels) (= (bytes-length pixels) n))
    (raise-arguments-error who "expected exactly width*height*4 RGBA bytes"
                           "required length" n "pixels" pixels))
  (define-values (ow oh) (oriented-dimensions who w h origin))
  (cond
    [(eq? origin 'top-left) (values ow oh pixels)]
    [else
     (define out (make-bytes n 0))
     (for* ([y (in-range h)] [x (in-range w)])
       (define-values (dx dy)
         (case origin
           [(top-right)    (values (- w 1 x) y)]
           [(bottom-right) (values (- w 1 x) (- h 1 y))]
           [(bottom-left)  (values x (- h 1 y))]
           [(left-top)     (values y x)]
           [(right-top)    (values (- h 1 y) x)]
           [(right-bottom) (values (- h 1 y) (- w 1 x))]
           [(left-bottom)  (values y (- w 1 x))]))
       (define src (* 4 (+ x (* y w))))
       (bytes-copy! out (* 4 (+ dx (* dy ow))) pixels src (+ src 4)))
     (values ow oh out)]))

(define codec-disposal-values
  (hasheq 'keep 1 'restore-background 2 'restore-previous 3))
(define codec-blend-values (hasheq 'src-over 0 'src 1))
(define codec-result-names
  '#(success incomplete-input error-in-input invalid-conversion invalid-scale
     invalid-parameters invalid-input could-not-rewind internal-error unimplemented))
(define (codec-result-name n)
  (if (and (exact-nonnegative-integer? n) (< n (vector-length codec-result-names)))
      (vector-ref codec-result-names n)
      'unknown-result))
