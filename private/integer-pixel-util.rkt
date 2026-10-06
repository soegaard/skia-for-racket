#lang racket/base
(require racket/list racket/vector "check.rkt" "../image-info.rkt")
(provide integer-sample-check integer-sample->bytes integer-bytes->sample
         integer-black-sample integer-storage-input integer-sample-alpha
         integer-tight-input)

(define (integer-sample-check who info sample)
  (unless (image-info? info) (raise-argument-error who "image-info?" info))
  (define xs (cond [(vector? sample) (vector->list sample)]
                   [(list? sample) sample]
                   [else (raise-argument-error who "list or vector of integer channels" sample)]))
  (define bits (vector->list (image-info-channel-bits info)))
  (unless (= (length xs) (length bits)) (error who "incorrect sample channel count"))
  (for ([v (in-list xs)] [b (in-list bits)])
    (unless (and (exact-nonnegative-integer? v) (< v (arithmetic-shift 1 b)))
      (raise-argument-error who "integer channel within the format's bit depth" v)))
  (define color (image-info-color-type info))
  (when (memq color '(rgba-8888 bgra-8888 rgba-1010102 alpha-8))
    (define a (last xs))
    (define amax (sub1 (arithmetic-shift 1 (last bits))))
    (when (and (eq? (image-info-alpha-type info) 'opaque) (not (= a amax)))
      (error who "opaque storage requires the maximum alpha sample"))
    (when (and (not (eq? color 'alpha-8)) (eq? (image-info-alpha-type info) 'premul))
      (for ([c (in-list (take xs 3))] [b (in-list (take bits 3))])
        (unless (<= (* c amax) (* a (sub1 (arithmetic-shift 1 b))))
          (error who "premultiplied color sample exceeds alpha")))))
  (vector->immutable-vector (list->vector xs)))
(define (integer-black-sample info)
  (define bits (image-info-channel-bits info))
  (define n (vector-length bits))
  (define opaque? (eq? (image-info-alpha-type info) 'opaque))
  (define alpha? (memq (image-info-color-type info) '(rgba-8888 bgra-8888 rgba-1010102 alpha-8)))
  (vector->immutable-vector
   (for/vector ([b (in-vector bits)] [i (in-naturals)])
     (if (and opaque? alpha? (= i (sub1 n))) (sub1 (arithmetic-shift 1 b)) 0))))
(define (integer-sample->bytes who info sample)
  (define v (integer-sample-check who info sample))
  (define (c i) (vector-ref v i))
  (case (image-info-color-type info)
    [(rgba-8888) (bytes (c 0) (c 1) (c 2) (c 3))]
    [(bgra-8888) (bytes (c 2) (c 1) (c 0) (c 3))]
    [(rgb-888x) (bytes (c 0) (c 1) (c 2) 255)]
    [(alpha-8 gray-8) (bytes (c 0))]
    [(rgb-565)
     (integer->integer-bytes (bitwise-ior (arithmetic-shift (c 0) 11)
                                          (arithmetic-shift (c 1) 5) (c 2))
                             2 #f (system-big-endian?))]
    [(rgba-1010102)
     (integer->integer-bytes (bitwise-ior (c 0) (arithmetic-shift (c 1) 10)
                                          (arithmetic-shift (c 2) 20) (arithmetic-shift (c 3) 30))
                             4 #f (system-big-endian?))]))
(define (integer-bytes->sample who info data [offset 0])
  (unless (image-info? info) (raise-argument-error who "image-info?" info))
  (define bpp (image-info-bytes-per-pixel info))
  (unless (and (bytes? data) (exact-nonnegative-integer? offset)
               (<= (+ offset bpp) (bytes-length data)))
    (error who "truncated pixel sample"))
  (define (b i) (bytes-ref data (+ offset i)))
  (case (image-info-color-type info)
    [(rgba-8888) (vector-immutable (b 0) (b 1) (b 2) (b 3))]
    [(bgra-8888) (vector-immutable (b 2) (b 1) (b 0) (b 3))]
    [(rgb-888x) (vector-immutable (b 0) (b 1) (b 2))]
    [(alpha-8 gray-8) (vector-immutable (b 0))]
    [(rgb-565 rgba-1010102)
     (define n (integer-bytes->integer data #f (system-big-endian?) offset (+ offset bpp)))
     (if (eq? (image-info-color-type info) 'rgb-565)
         (vector-immutable (bitwise-bit-field n 11 16) (bitwise-bit-field n 5 11) (bitwise-bit-field n 0 5))
         (vector-immutable (bitwise-bit-field n 0 10) (bitwise-bit-field n 10 20)
                           (bitwise-bit-field n 20 30) (bitwise-bit-field n 30 32)))]))
(define (integer-sample-alpha info sample)
  (case (image-info-color-type info)
    [(alpha-8) (vector-ref sample 0)]
    [(rgba-8888 bgra-8888) (vector-ref sample 3)]
    [(rgba-1010102) (* 85 (vector-ref sample 3))]
    [else 255]))
;; Validate a detached copy BEFORE any destination write. Full allocation-sized
;; buffer input preserves padding; view input needs only the final row's pixels.
(define (integer-storage-input who info data rb #:full? [full? #f])
  (unless (bytes? data) (raise-argument-error who "bytes?" data))
  (define-values (_ minimum allocation) (image-info-storage-layout info #:row-bytes rb))
  (unless (and (if full? (= (bytes-length data) allocation) (<= minimum (bytes-length data)))
               (<= (bytes-length data) (current-skia-byte-limit)))
    (error who "storage input length is truncated, nonexact, or over the byte limit"))
  (define copy (bytes-copy data))
  (define bpp (image-info-bytes-per-pixel info))
  (for* ([y (in-range (image-info-height info))] [x (in-range (image-info-width info))])
    (integer-sample-check who info (integer-bytes->sample who info copy (+ (* y rb) (* x bpp)))))
  copy)
(define (integer-tight-input who info data rb)
  (define input (integer-storage-input who info data rb))
  (define tight (image-info-min-row-bytes info))
  (define out (make-bytes (* tight (image-info-height info))))
  (for ([y (in-range (image-info-height info))])
    (bytes-copy! out (* y tight) input (* y rb) (+ (* y rb) tight)))
  out)
