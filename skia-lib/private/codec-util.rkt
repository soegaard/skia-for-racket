#lang racket/base

;;;
;;; Codec Orientation and Status
;;;

;; Maps codec result codes and applies encoded-image orientation to RGBA pixels.
;; Provides common image-decoding helpers for the core API.

(require "check.rkt")
(provide oriented-dimensions orient-rgba-bytes checked-codec-index
         codec-result-name codec-disposal-values codec-blend-values)

;; Private, allocation-checked helpers. No native library is loaded here.

; checked-codec-index : symbol? exact-integer? -> exact-nonnegative-integer?
;   Checks a frame/index value against the signed native 32-bit range.
(define (checked-codec-index who index)
  (unless (and (exact-integer? index) (<= 0 index #x7fffffff))
    (raise-argument-error who "exact integer from 0 through 2147483647" index))
  index)

; oriented-dimensions : symbol? integer? integer? symbol? -> (values integer? integer?)
;   Swaps dimensions for encoded orientations that transpose the pixel axes.
(define (oriented-dimensions who w h origin)
  (choice who origin encoded-origin-values)
  (if (memq origin '(left-top right-top right-bottom left-bottom))
      (values h w)
      (values w h)))

;; The caller supplies packed RGBA pixels in encoded coordinates. The identity
;; case shares its input; all other cases return a new byte string. No channel
;; arithmetic, filtering, alpha conversion, or color conversion occurs here.

; orient-rgba-bytes : symbol? integer? integer? bytes? symbol? -> (values integer? integer? bytes?)
;   Applies encoded orientation to packed RGBA pixels, reusing input only for top-left orientation.
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

; codec-disposal-values : hash?
;   Maps animation disposal names to pinned native keep/background/previous codes.
(define codec-disposal-values
  (hasheq 'keep 1 'restore-background 2 'restore-previous 3))

; codec-blend-values : hash?
;   Maps frame source-over and source replacement to native blend codes.
(define codec-blend-values (hasheq 'src-over 0 'src 1))

; codec-result-names : (vectorof symbol?)
;   Indexes native result codes in ABI order, from success through unimplemented.
(define codec-result-names
  '#(success incomplete-input error-in-input invalid-conversion invalid-scale
     invalid-parameters invalid-input could-not-rewind internal-error unimplemented))

; codec-result-name : any/c -> symbol?
;   Returns the native result name or unknown-result for an unrecognized code.
(define (codec-result-name n)
  (if (and (exact-nonnegative-integer? n) (< n (vector-length codec-result-names)))
      (vector-ref codec-result-names n)
      'unknown-result))
