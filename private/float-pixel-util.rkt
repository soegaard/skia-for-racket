#lang racket/base
;; Exact IEEE binary16 storage codec. Native rendering may flush subnormals;
;; storage read/write itself does not. No Skia/native library on import.
(require racket/list racket/vector "check.rkt" "../image-info.rkt")
(provide float-info? float-sample-check float-sample->bytes float-bytes->sample
         float-black-sample real->binary16 binary16->real)
(define (float-info? info)
  (and (image-info? info) (memq (image-info-color-type info) '(rgba-f16 rgba-f32)) #t))
(define (real->binary16 value)
  (define who 'real->binary16)
  (unless (and (real? value) (<= -65504 value 65504))
    (raise-argument-error who "finite binary16-range real [-65504,65504]" value))
  (define sign (if (or (< value 0) (eqv? value -0.0)) #x8000 0))
  (define x (abs (if (exact? value) value (inexact->exact value))))
  (define word
    (cond
      [(zero? x) 0]
      [(< x (expt 2 -14)) (round (* x (expt 2 24)))]
      [else
       ;; floor(log2(x)), computed on integers without transcendental rounding.
       (define guess (- (integer-length (numerator x)) (integer-length (denominator x))))
       (define e (if (< x (expt 2 guess)) (sub1 guess) guess))
       (define q (round (/ x (expt 2 (- e 10))))) ; ties to even, directly from input
       (if (= q 2048)
           (arithmetic-shift (+ e 16) 10)
           (+ (arithmetic-shift (+ e 15) 10) (- q 1024)))]))
  (bitwise-ior sign word))
(define (binary16->real word)
  (unless (and (exact-integer? word) (<= 0 word #xffff))
    (raise-argument-error 'binary16->real "unsigned 16-bit word" word))
  (define e (bitwise-bit-field word 10 15))
  (define f (bitwise-bit-field word 0 10))
  (when (= e 31) (error 'binary16->real "nonfinite float storage is not accepted"))
  (define magnitude (if (zero? e) (* f (expt 2 -24)) (* (+ 1024 f) (expt 2 (- e 25)))))
  (define value (exact->inexact magnitude))
  (if (bitwise-bit-set? word 15) (- value) value))
(define (float-sample-check who info sample)
  (unless (float-info? info) (raise-argument-error who "F16/F32 image-info" info))
  (define xs (cond [(vector? sample) (vector->list sample)] [(list? sample) sample]
                   [else (raise-argument-error who "four finite float channels" sample)]))
  (unless (= (length xs) 4) (error who "float RGBA requires four channels"))
  (define limit (if (eq? (image-info-color-type info) 'rgba-f16) 65504 340282346638528859811704183484516925440))
  (define values
    (for/list ([v (in-list xs)])
      (unless (and (real? v) (<= (- limit) v limit))
        (raise-argument-error who "finite channel within the selected float storage range" v))
      (exact->inexact v)))
  (define alpha (list-ref values 3))
  (unless (<= 0 alpha 1) (error who "float alpha must be in [0,1]"))
  (when (and (eq? (image-info-alpha-type info) 'opaque) (not (= alpha 1)))
    (error who "opaque float storage requires alpha 1"))
  ;; Extended premultiplied RGB may be negative or larger than alpha. At zero
  ;; alpha require canonical zero RGB; otherwise no [0,alpha] clamping is done.
  (when (and (eq? (image-info-alpha-type info) 'premul) (zero? alpha)
             (ormap (lambda (v) (not (zero? v))) (take values 3)))
    (error who "zero-alpha premultiplied storage requires zero RGB"))
  (vector->immutable-vector (list->vector values)))
(define (float-black-sample info)
  (vector-immutable 0.0 0.0 0.0 (if (eq? (image-info-alpha-type info) 'opaque) 1.0 0.0)))
(define (float-bytes->sample who info data [offset 0])
  (unless (float-info? info) (raise-argument-error who "F16/F32 image-info" info))
  (define width (if (eq? (image-info-color-type info) 'rgba-f16) 2 4))
  (unless (and (bytes? data) (exact-nonnegative-integer? offset)
               (<= (+ offset (* 4 width)) (bytes-length data)))
    (error who "truncated float pixel sample"))
  (float-sample-check who info
    (for/vector ([i (in-range 4)])
      (define at (+ offset (* i width)))
      (if (= width 2)
          (binary16->real (integer-bytes->integer data #f (system-big-endian?) at (+ at 2)))
          (floating-point-bytes->real data (system-big-endian?) at (+ at 4))))))
(define (float-sample->bytes who info sample)
  (define values (float-sample-check who info sample))
  (define result
    (apply bytes-append
      (for/list ([value (in-vector values)])
        (if (eq? (image-info-color-type info) 'rgba-f16)
            (integer->integer-bytes (real->binary16 value) 2 #f (system-big-endian?))
            (real->floating-point-bytes value 4 (system-big-endian?))))))
  ;; Quantization must not turn tiny alpha into zero while leaving RGB nonzero.
  (float-bytes->sample who info result)
  result)
