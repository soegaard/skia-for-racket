#lang racket/base

;;;
;;; Reference Color Management Test
;;;

;; Checks retained color spaces, gamut transforms, ICC round trips, floating paints, and sample
;; conversion.
;; These acceptance checks keep the Reference's documented contracts aligned with the public
;; implementation.

;;;
;;; Imports and Exports
;;;

;; Opt-in native CPU acceptance for documented color behavior, with no fonts or GPU.
(require rackunit racket/vector skia)


;;;
;;; Diagnostic Operations
;;;

; near-vector : vector? vector? [real?] -> void?
;   Checks color-component vectors with a configurable absolute tolerance.
(define (near-vector actual expected [tolerance 0.0001])
  (check-equal? (vector-length actual) (vector-length expected))
  (for ([a (in-vector actual)] [e (in-vector expected)]) (check-= a e tolerance)))

(module+ test
  (skia-check!)
  (test-case "gamut and transfer are distinct and returned spaces own references"
    (with-skia ([p3 (make-rgb-color-space 'srgb 'display-p3)]
                [linear (color-space->linear-gamma p3)]
                [again (color-space->srgb-gamma linear)])
      (check-false (color-space-srgb? p3))
      (check-true (color-space-gamma-close-to-srgb? p3))
      (check-true (color-space-linear-gamma? linear))
      (define gamut (color-space-xyz-d50 p3))
      (skia-close! p3)
      (near-vector (color-space-xyz-d50 linear) gamut)
      (near-vector (color-space-xyz-d50 again) gamut)))
  (test-case "named transfer inversion and detached descriptions survive closure"
    (with-skia ([srgb (make-srgb-color-space)])
      (define transfer (color-space-transfer-function srgb))
      (define inverse (transfer-function-invert transfer))
      (define gamut (color-space-xyz-d50 srgb))
      (skia-close! srgb)
      (check-true (immutable? gamut))
      (check-= (transfer-function-evaluate transfer 0.5) 0.21404114 0.00001)
      (check-not-false inverse)
      (check-= (transfer-function-evaluate inverse
                                          (transfer-function-evaluate transfer 0.5))
                0.5 0.0001)))
  (test-case "XYZ multiplication applies the second matrix first and accepts singular input"
    (define scale '(2 0 0 0 3 0 0 0 4))
    (define shear '(1 1 0 0 1 0 0 0 1))
    (near-vector (xyz-d50-concat scale shear) '#(2 2 0 0 3 0 0 0 4))
    (near-vector (xyz-d50-concat shear scale) '#(2 3 0 0 3 0 0 0 4))
    (near-vector (xyz-d50-concat '(0 0 0 0 0 0 0 0 0) shear) '#(0 0 0 0 0 0 0 0 0))
    (check-false (xyz-d50-invert '(0 0 0 0 0 0 0 0 0)))
    (near-vector (xyz-d50-invert scale) '#(0.5 0 0 0 0.33333333 0 0 0 0.25)))
  (test-case "custom gamut inputs are copied and need a nonsingular rounded matrix"
    (define coefficients (vector-copy (named-xyz-d50 'srgb)))
    (with-skia ([space (make-rgb-color-space 'linear coefficients)])
      (define before (color-space-xyz-d50 space))
      (vector-set! coefficients 0 0)
      (check-equal? (color-space-xyz-d50 space) before))
    (check-exn exn:fail?
               (lambda () (make-rgb-color-space 'linear '(0 0 0 0 0 0 0 0 0)))))
  (test-case "standard primary chromaticities reproduce the named gamut"
    (near-vector (primaries->xyz-d50 '(0.64 0.33) '(0.30 0.60) '(0.15 0.06)
                                    '(0.3127 0.3290))
                 (named-xyz-d50 'srgb) 0.001))
  (test-case "ICC export returns mutable bytes while imported resources are independent"
    (with-skia ([space (make-rgb-color-space 'srgb 'display-p3)])
      (define profile (color-space->icc-bytes space))
      (check-false (immutable? profile))
      (check-false (color-space-descriptor? profile))
      (check-true (color-space-descriptor? (bytes->immutable-bytes profile)))
      (with-skia ([imported (color-space-from-icc-bytes profile)])
        (define before (color-space-xyz-d50 imported))
        (bytes-fill! profile 0)
        (skia-close! space)
        (check-equal? (color-space-xyz-d50 imported) before))))
  (test-case "sample conversion requires source knowledge and does not mutate the input"
    (with-skia ([srgb (make-srgb-color-space)] [linear (make-linear-srgb-color-space)]
                [source (rgba-bytes->image 1 1 (bytes 128 128 128 255))])
      (check-exn exn:fail? (lambda () (image-convert-color-space source srgb)))
      (with-skia ([converted (image-convert-color-space source srgb #:source-color-space linear)])
        (check-equal? (image->rgba-bytes source) (bytes 128 128 128 255))
        (for ([v (in-bytes (subbytes (image->rgba-bytes converted) 0 3))])
          (check-true (<= 187 v 189)))
        (check-exn exn:fail?
                   (lambda () (image-convert-color-space converted linear
                                                         #:source-color-space srgb)))
        (skia-close! source)
        (skia-close! srgb)
        (check-equal? (bytes-ref (image->rgba-bytes converted) 3) 255))))
  (test-case "floating-point paints require descriptors and store extended sRGB"
    (with-skia ([srgb (make-srgb-color-space)]
                [paint (make-paint/color4f (make-color4f 0.5 0.5 0.5)
                                          #:color-space 'linear-srgb)])
      (check-exn exn:fail?
                 (lambda () (paint-set-color4f! paint (make-color4f 1 0 0)
                                                #:color-space srgb)))
      (check-exn exn:fail?
                 (lambda () (paint-set-color4f! paint (make-color4f 1 0 0)
                                                #:color-space #f)))
      (check-= (color4f-red (paint-color4f paint)) 0.73535698 0.0001)
      (paint-set-color4f! paint (make-color4f 1.25 -0.25 0.5) #:color-space 'srgb)
      (near-vector (color4f->vector (paint-color4f paint)) '#(1.25 -0.25 0.5 1))))
  (test-case "floating gradients accept repeated and rounded-equal positions"
    (define colors (list (make-color4f 1 0 0) (make-color4f 0 0 1)))
    (for ([stops (list '(0 0) '(0.5 0.50000000001))])
      (with-skia ([shader (make-linear-gradient-color4f-shader
                          0 0 10 0 colors #:color-space 'srgb #:positions stops)])
        (check-true (shader? shader))))
    (with-skia ([shader (make-linear-gradient-color4f-shader
                        0 0 10 0 colors #:color-space 'srgb #:positions '(0 1))])
      (check-true (shader? shader))))
  (test-case "floating clear respects the clip while ignoring geometric translation"
    (with-skia ([surface (make-surface 4 1)])
      (define canvas (surface-canvas surface))
      (with-canvas-state canvas
        (canvas-clip-rect! canvas 1 0 2 1)
        (canvas-translate! canvas 100 100)
        (canvas-clear-color4f! canvas (make-color4f 1 0 0)))
      (check-equal? (rgba-alpha (surface-pixel surface 0 0)) 0)
      (check-equal? (surface-pixel surface 1 0) (color->rgba 'red))
      (check-equal? (surface-pixel surface 2 0) (color->rgba 'red))
      (check-equal? (rgba-alpha (surface-pixel surface 3 0)) 0)))
  (test-case "runtime source and packed uniforms are immutable after closure"
    (with-skia ([effect (make-runtime-effect
                        "uniform float gain; half4 main(float2 p){return half4(gain);}")])
      (skia-close! effect)
      (check-true (immutable? (runtime-effect-source effect)))
      (check-true (immutable? (runtime-effect-uniform-bytes effect (hash 'gain 0.5)))))))
