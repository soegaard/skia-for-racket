#lang racket/base
(require "check.rkt" (only-in ffi/unsafe ctype-sizeof _intptr))
(provide raster-layout raster-point raster-subset prepare-raster-input raster-procedure)

;; RGBA8888 storage has four bytes/pixel, and every row starts on a 4-byte
;; boundary. Charge ALL allocated bytes, including the last row's padding.
(define (raster-layout who w h row-bytes)
  (check-dimensions who w h)
  (define rb (if row-bytes row-bytes (* w 4)))
  (unless (and (exact-integer? rb) (>= rb (* w 4)) (zero? (modulo rb 4)))
    (raise-argument-error who "row bytes: exact multiple of 4, at least width * 4" rb))
  (define allocation (* rb h))
  (define pointer-limit (sub1 (expt 2 (sub1 (* 8 (ctype-sizeof _intptr))))))
  (unless (<= allocation pointer-limit)
    (raise-arguments-error who "storage exceeds native pointer arithmetic range"
                           "storage bytes" allocation "native limit" pointer-limit))
  (unless (<= allocation (current-skia-byte-limit))
    (raise-arguments-error who "strided storage exceeds current-skia-byte-limit"
                           "storage bytes" allocation "limit" (current-skia-byte-limit)))
  (values rb (+ (* rb (sub1 h)) (* w 4)) allocation))

(define (raster-point who x y w h)
  (unless (and (exact-nonnegative-integer? x) (< x w)
               (exact-nonnegative-integer? y) (< y h))
    (raise-arguments-error who "pixel is outside the view"
                           "pixel" (list x y) "size" (list w h)))
  (void))

(define (raster-subset who x y w h outer-w outer-h)
  (unless (and (exact-nonnegative-integer? x) (exact-nonnegative-integer? y)
               (exact-positive-integer? w) (exact-positive-integer? h)
               (<= (+ x w) outer-w) (<= (+ y h) outer-h))
    (raise-arguments-error who "subset must be a nonempty integer rectangle inside the view"
                           "subset" (list x y w h) "view size" (list outer-w outer-h)))
  (void))

(define (raster-procedure who proc)
  (unless (and (procedure? proc) (procedure-arity-includes? proc 1))
    (raise-argument-error who "procedure accepting one argument" proc)))

(define (prepare-raster-input who w h data row-bytes premultiplied?)
  (boolean who premultiplied?)
  (unless (bytes? data) (raise-argument-error who "bytes?" data))
  (define-values (rb minimum allocation) (raster-layout who w h row-bytes))
  (unless (<= minimum (bytes-length data) (current-skia-byte-limit))
    (raise-arguments-error who "source bytes are truncated or exceed the byte limit"
                           "minimum bytes" minimum "given bytes" (bytes-length data)))
  ;; A detached tight buffer both snapshots mutable input and ensures a late
  ;; invalid premultiplied pixel cannot leave a partially updated destination.
  (define out (make-bytes (* 4 w h)))
  (for* ([y (in-range h)] [x (in-range w)])
    (define src (+ (* y rb) (* x 4)))
    (define dst (* 4 (+ x (* y w))))
    (define a (bytes-ref data (+ src 3)))
    (for ([c (in-range 3)])
      (define v (bytes-ref data (+ src c)))
      (when (and premultiplied? (> v a))
        (raise-arguments-error who "premultiplied RGB must not exceed alpha"
                               "pixel" (list x y) "channel" c "value" v "alpha" a))
      (bytes-set! out (+ dst c)
                  (if premultiplied? v (quotient (+ (* v a) 127) 255))))
    (bytes-set! out (+ dst 3) a))
  out)
