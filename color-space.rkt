#lang racket/base
(require ffi/unsafe racket/list "private/core.rkt" "private/types.rkt"
         "private/native.rkt" "private/lifetime.rkt" "private/color-output-util.rkt"
         (submod "private/core.rkt" color-internals))
(provide transfer-function? make-transfer-function transfer-function-coefficients
         named-transfer-function transfer-function-evaluate transfer-function-invert
         named-xyz-d50 primaries->xyz-d50 make-rgb-color-space
         color-space-transfer-function color-space-xyz-d50)

;; Detached values. Coefficients are in skcms/ICC function-4 order g,a,b,c,d,e,f.
;; Never expose a native pointer.
(struct transfer-function (coefficients) #:transparent #:constructor-name transfer-record)

(define (make-transfer-function g a b c d e f)
  (define who 'make-transfer-function)
  (define v (color-sequence who (list g a b c d e f) 7 "seven transfer coefficients"))
  (define gg (vector-ref v 0))
  (define aa (vector-ref v 1))
  (define bb (vector-ref v 2))
  (define cc (vector-ref v 3))
  (define dd (vector-ref v 4))
  (unless (and (> gg 0) (>= aa 0) (>= cc 0) (>= dd 0) (>= (+ (* aa dd) bb) 0))
    (raise-arguments-error who "invalid SDR transfer function after float conversion"
                           "coefficients" v))
  (transfer-record v))

(define (check-transfer who tf)
  (unless (transfer-function? tf) (raise-argument-error who "transfer-function?" tf))
  (transfer-function-coefficients tf))
(define (transfer-native who tf)
  (apply make-sk-transfer (vector->list (check-transfer who tf))))
(define (transfer-value n)
  (transfer-record
   (vector-immutable (sk-transfer-g n) (sk-transfer-a n) (sk-transfer-b n)
                     (sk-transfer-c n) (sk-transfer-d n) (sk-transfer-e n) (sk-transfer-f n))))
(define (blank-transfer) (make-sk-transfer 0.0 0.0 0.0 0.0 0.0 0.0 0.0))
(define (blank-xyz) (make-sk-xyz 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0))
(define (xyz-value m)
  (vector-immutable (sk-xyz-m00 m) (sk-xyz-m01 m) (sk-xyz-m02 m)
                    (sk-xyz-m10 m) (sk-xyz-m11 m) (sk-xyz-m12 m)
                    (sk-xyz-m20 m) (sk-xyz-m21 m) (sk-xyz-m22 m)))

(define transfer-names '(srgb linear gamma-2.2 rec2020))
(define gamut-names '(srgb adobe-rgb display-p3 rec2020 xyz))
(define (check-name who v allowed)
  (unless (memq v allowed)
    (raise-arguments-error who "unknown named color value" "given" v "allowed" allowed)))

(define (named-transfer-function name)
  (define who 'named-transfer-function)
  (check-name who name transfer-names)
  (skia-check!)
  (define n (blank-transfer))
  ((case name
     [(srgb) sk_colorspace_transfer_fn_named_srgb]
     [(linear) sk_colorspace_transfer_fn_named_linear]
     [(gamma-2.2) sk_colorspace_transfer_fn_named_2dot2]
     [(rec2020) sk_colorspace_transfer_fn_named_rec2020]) n)
  (transfer-value n))

;; Evaluate the SDR formula on its nonnegative domain in Racket, without
;; loading Skia. This is not an HDR transfer function or a tone mapper.
(define (transfer-function-evaluate tf x)
  (define who 'transfer-function-evaluate)
  (define v (check-transfer who tf))
  (unless (and (real? x) (<= 0 x 3.402823e38))
    (raise-argument-error who "nonnegative finite real representable as float" x))
  (define g (vector-ref v 0))
  (define a (vector-ref v 1))
  (define b (vector-ref v 2))
  (define c (vector-ref v 3))
  (define d (vector-ref v 4))
  (define e (vector-ref v 5))
  (define f (vector-ref v 6))
  (define y (if (< x d) (+ (* c x) f) (+ (expt (+ (* a x) b) g) e)))
  (unless (and (real? y) (< -inf.0 y +inf.0))
    (error who "transfer evaluation is not finite at ~a" x))
  y)

(define (transfer-function-invert tf)
  (define n (transfer-native 'transfer-function-invert tf))
  (skia-check!)
  (define inverse (blank-transfer))
  (and (sk_colorspace_transfer_fn_invert n inverse) (transfer-value inverse)))

(define (named-xyz-d50 name)
  (define who 'named-xyz-d50)
  (check-name who name gamut-names)
  (skia-check!)
  (define m (blank-xyz))
  ((case name
     [(srgb) sk_colorspace_xyz_named_srgb]
     [(adobe-rgb) sk_colorspace_xyz_named_adobe_rgb]
     [(display-p3) sk_colorspace_xyz_named_display_p3]
     [(rec2020) sk_colorspace_xyz_named_rec2020]
     [(xyz) sk_colorspace_xyz_named_xyz]) m)
  (xyz-value m))

(define (primaries->xyz-d50 red green blue white)
  (define who 'primaries->xyz-d50)
  (define vals
    (append-map (lambda (xy) (vector->list (checked-chromaticity who xy)))
                (list red green blue white)))
  (skia-check!)
  (define primaries (apply make-sk-primaries vals))
  (define m (blank-xyz))
  (unless (sk_colorspace_primaries_to_xyzd50 primaries m)
    (raise-arguments-error who "primaries do not define a usable RGB gamut"
                           "red/green/blue/white" (list red green blue white)))
  (xyz-value m))

(define (make-rgb-color-space transfer gamut)
  (define who 'make-rgb-color-space)
  ;; Validate names/types on BOTH sides before named helpers load the library.
  (if (symbol? transfer) (check-name who transfer transfer-names) (check-transfer who transfer))
  (define checked-gamut
    (if (symbol? gamut)
        (begin (check-name who gamut gamut-names) #f)
        (checked-xyz-d50 who gamut)))
  (define tf (if (symbol? transfer) (named-transfer-function transfer) transfer))
  (define xyz (or checked-gamut (named-xyz-d50 gamut)))
  (define n (transfer-native who tf))
  (define m (apply make-sk-xyz (vector->list xyz)))
  (skia-check!)
  (wrap-owned-color-space who (lambda () (sk_colorspace_new_rgb n m))))

(define (color-space-transfer-function cs)
  (define who 'color-space-transfer-function)
  (call-with-owned who (list (color-space-h who cs))
    (lambda (cp)
      (define n (blank-transfer))
      (and (sk_colorspace_is_numerical_transfer_fn cp n) (transfer-value n)))))

(define (color-space-xyz-d50 cs)
  (define who 'color-space-xyz-d50)
  (call-with-owned who (list (color-space-h who cs))
    (lambda (cp)
      (define m (blank-xyz))
      (and (sk_colorspace_to_xyzd50 cp m) (xyz-value m)))))
