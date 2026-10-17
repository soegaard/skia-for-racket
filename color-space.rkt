#lang racket/base

;;;
;;; Color-Space Transforms
;;;

;; Constructs transfer functions, RGB spaces, and XYZ-D50 conversion matrices.
;; This public color-management layer combines detached transfer descriptions with the pinned native
;; color-space operations.

;;;
;;; Imports and Exports
;;;

(require ffi/unsafe racket/list "private/core.rkt" "private/types.rkt"
         "private/native.rkt" "private/lifetime.rkt" "private/color-output-util.rkt"
         (submod "private/core.rkt" color-internals))
(provide transfer-function? make-transfer-function transfer-function-coefficients
         named-transfer-function transfer-function-evaluate transfer-function-invert
         named-xyz-d50 primaries->xyz-d50 make-rgb-color-space
         color-space-transfer-function color-space-xyz-d50)

;;;
;;; Transfer-Function Values and Native Conversion
;;;

;; Detached values. Coefficients are in skcms/ICC function-4 order g,a,b,c,d,e,f.
;; Never expose a native pointer.
(struct transfer-function (coefficients) #:transparent #:constructor-name transfer-record)
;; A transfer-function stores a detached skcms/ICC function-4 description.
;;  - coefficients  immutable vector  Seven binary32 values in g, a, b, c, d, e,
;;                                     f order; this is not a geometric matrix.
;; Here g is the exponent; a/b scale and offset the power branch, c is the
;; linear slope, d is the branch threshold, and e/f are the output offsets:
;; y = (a*x+b)^g+e for x >= d, and y = c*x+f for x < d.
;; The public constructor checks g > 0, a >= 0, c >= 0, d >= 0, and a*d+b >= 0
;; after float conversion. Native query results are copied out of native storage.

; make-transfer-function : real? real? real? real? real? real? real? -> transfer-function?
;   Returns a transfer function with the seven supplied coefficients.
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

; check-transfer : symbol? transfer-function? -> vector?
;   Validates a transfer-function value and returns coefficients in g, a, b, c, d, e, f order.
(define (check-transfer who tf)
  (unless (transfer-function? tf) (raise-argument-error who "transfer-function?" tf))
  (transfer-function-coefficients tf))

; transfer-native : symbol? transfer-function? -> sk-transfer?
;   Copies checked transfer coefficients into the native transfer-function layout.
(define (transfer-native who tf)
  (apply make-sk-transfer (vector->list (check-transfer who tf))))

; transfer-value : sk-transfer? -> transfer-function?
;   Copies native transfer coefficients into an immutable public value.
(define (transfer-value n)
  (transfer-record
   (vector-immutable (sk-transfer-g n) (sk-transfer-a n) (sk-transfer-b n)
                     (sk-transfer-c n) (sk-transfer-d n) (sk-transfer-e n) (sk-transfer-f n))))

; blank-transfer : -> sk-transfer?
;   Allocates a zeroed native transfer-function result buffer.
(define (blank-transfer) (make-sk-transfer 0.0 0.0 0.0 0.0 0.0 0.0 0.0))

; blank-xyz : -> sk-xyz?
;   Allocates a zeroed native 3-by-3 XYZ result buffer.
(define (blank-xyz) (make-sk-xyz 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0))

; xyz-value : sk-xyz? -> vector?
;   Copies an XYZ matrix into an immutable vector in row-major order.
(define (xyz-value m)
  (vector-immutable (sk-xyz-m00 m) (sk-xyz-m01 m) (sk-xyz-m02 m)
                    (sk-xyz-m10 m) (sk-xyz-m11 m) (sk-xyz-m12 m)
                    (sk-xyz-m20 m) (sk-xyz-m21 m) (sk-xyz-m22 m)))

;;;
;;; Named Transfers and Transfer Arithmetic
;;;

; transfer-names : (listof symbol?)
;   Lists the transfer-function names accepted by the named factory.
(define transfer-names '(srgb linear gamma-2.2 rec2020))

; gamut-names : (listof symbol?)
;   Lists the RGB gamut names accepted by the named factory.
(define gamut-names '(srgb adobe-rgb display-p3 rec2020 xyz))

; check-name : symbol? any/c (listof symbol?) -> void?
;   Rejects names outside the supplied closed set before crossing the native boundary.
(define (check-name who v allowed)
  (unless (memq v allowed)
    (raise-arguments-error who "unknown named color value" "given" v "allowed" allowed)))

; named-transfer-function : (or/c 'srgb 'linear 'gamma-2.2 'rec2020) -> transfer-function?
;   Returns a detached copy of the named native transfer coefficients.
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

; transfer-function-evaluate : transfer-function? (real-in 0 3.402823e+38) -> real?
;   Returns the transfer formula evaluated at x.
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

; transfer-function-invert : transfer-function? -> (or/c transfer-function? #f)
;   Returns detached coefficients for the native inverse, or #f when the native inversion reports
;   failure.
(define (transfer-function-invert tf)
  (define n (transfer-native 'transfer-function-invert tf))
  (skia-check!)
  (define inverse (blank-transfer))
  (and (sk_colorspace_transfer_fn_invert n inverse) (transfer-value inverse)))

;;;
;;; Color Gamut Matrices
;;;

; named-xyz-d50 : (or/c 'srgb 'adobe-rgb 'display-p3 'rec2020 'xyz) -> (and/c (vectorof real?)
;   immutable?)
;   Returns the named native RGB-to-XYZ-D50 matrix as nine row-major coefficients.
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

; primaries->xyz-d50 : (or/c (list/c real? real?) (vector/c real? real?)) (or/c (list/c real? real?)
;   (vector/c real? real?)) (or/c (list/c real? real?) (vector/c real? real?)) (or/c (list/c real?
;   real?) (vector/c real? real?)) -> (and/c (vectorof real?) immutable?)
;   Returns a nine-coefficient matrix for the supplied RGB primary chromaticities and source white,
;   adapted to D50 by the native implementation.
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

;;;
;;; RGB Color-Space Construction and Inspection
;;;

; make-rgb-color-space : (or/c transfer-function? 'srgb 'linear 'gamma-2.2 'rec2020) (or/c 'srgb
;   'adobe-rgb 'display-p3 'rec2020 'xyz (listof real?) (vectorof real?)) -> color-space?
;   Returns an owned RGB color-space resource with the supplied transfer function and gamut.
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

; color-space-transfer-function : color-space? -> (or/c transfer-function? #f)
;   Returns a detached numerical transfer description for an open color space, or #f when no such
;   description is available.
(define (color-space-transfer-function cs)
  (define who 'color-space-transfer-function)
  (call-with-owned who (list (color-space-h who cs))
    (lambda (cp)
      (define n (blank-transfer))
      (and (sk_colorspace_is_numerical_transfer_fn cp n) (transfer-value n)))))

; color-space-xyz-d50 : color-space? -> (or/c #f (and/c (vectorof real?) immutable?))
;   Returns nine detached row-major coefficients for an open space's XYZ-D50 matrix, or #f when the
;   native query cannot supply one.
(define (color-space-xyz-d50 cs)
  (define who 'color-space-xyz-d50)
  (call-with-owned who (list (color-space-h who cs))
    (lambda (cp)
      (define m (blank-xyz))
      (and (sk_colorspace_to_xyzd50 cp m) (xyz-value m)))))

;; 0.78b: detached XYZ-D50 matrix arithmetic. These are color-space matrices,
;; not geometric/projective matrices and not an encoded-pixel conversion API.
(provide xyz-d50-concat xyz-d50-invert)

;;;
;;; XYZ Matrix Composition and Inversion
;;;

; xyz-finite? : (vectorof real?) -> boolean?
;   Checks that every XYZ coefficient excludes infinities and NaN.
(define (xyz-finite? v)
  (for/and ([x (in-vector v)]) (< -inf.0 x +inf.0)))

; xyz-d50-concat : (or/c (listof real?) (vectorof real?)) (or/c (listof real?) (vectorof real?)) ->
;   (and/c (vectorof real?) immutable?)
;   Returns the matrix product a b as nine row-major binary32 coefficients.
(define (xyz-d50-concat a b)
  (define who 'xyz-d50-concat)
  ;; Unlike a gamut accepted by make-rgb-color-space, a matrix participating in
  ;; arithmetic may be singular. Validate and copy BOTH inputs before native
  ;; loading; no caller-owned vector or in-place native output is borrowed.
  (define av (color-sequence who a 9 "nine finite row-major XYZ-D50 coefficients"))
  (define bv (color-sequence who b 9 "nine finite row-major XYZ-D50 coefficients"))
  (skia-check!)
  (define an (apply make-sk-xyz (vector->list av)))
  (define bn (apply make-sk-xyz (vector->list bv)))
  (define out (blank-xyz))
  ;; skcms computes a*b: with column samples, b is applied first.
  (sk_colorspace_xyz_concat an bn out)
  (define result (xyz-value out))
  (void/reference-sink an bn out av bv)
  (unless (xyz-finite? result)
    (error who "native XYZ-D50 concatenation produced a nonfinite binary32 result"))
  result)

; xyz-d50-invert : (or/c (listof real?) (vectorof real?)) -> (or/c #f (and/c (vectorof real?)
;   immutable?))
;   Returns the native inverse as nine row-major coefficients, or #f when inversion fails or
;   produces nonfinite coefficients.
(define (xyz-d50-invert matrix)
  (define who 'xyz-d50-invert)
  (define v (color-sequence who matrix 9 "nine finite row-major XYZ-D50 coefficients"))
  (skia-check!)
  (define src (apply make-sk-xyz (vector->list v)))
  ;; skcms explicitly forbids aliasing the inversion input and output.
  (define out (blank-xyz))
  (define result
    (and (sk_colorspace_xyz_invert src out)
         (let ([value (xyz-value out)]) (and (xyz-finite? value) value))))
  (void/reference-sink src out v)
  result)
