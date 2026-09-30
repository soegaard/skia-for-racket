#lang racket/base
;; Backend-independent DC values. No GUI, renderer, or native allocation.
(require racket/list racket/math racket/vector)
(provide (struct-out exn:fail:skia-dc:unsupported)
         dc-unsupported dc-real dc-unit dc-extent dc-matrix dc-transformation
         dc-identity dc-multiply dc-effective dc-point dc-singular?
         dc-physical-size dc-path-map dc-capabilities
         (struct-out dc-renderer) (struct-out dc-ink) (struct-out dc-draw))

(struct exn:fail:skia-dc:unsupported exn:fail:contract (method feature stage) #:transparent)
(define (dc-unsupported who feature [stage "0.54/0.55"])
  (raise (exn:fail:skia-dc:unsupported
          (format "~a: ~a is outside skia-dc% 0.53; planned compatibility stage ~a"
                  who feature stage)
          (current-continuation-marks) who feature stage)))
(define (dc-real who v)
  (unless (and (real? v) (<= -3.402823e38 v 3.402823e38))
    (raise-argument-error who "finite real in the Skia binary32 coordinate range" v))
  (exact->inexact v))
(define (dc-unit who v)
  (define n (dc-real who v))
  (unless (<= 0 n 1) (raise-argument-error who "real in [0,1]" v))
  n)
(define (dc-extent who v)
  (define n (dc-real who v))
  (when (< n 0) (raise-argument-error who "nonnegative finite real" v))
  n)
(define dc-identity '#(1.0 0.0 0.0 1.0 0.0 0.0))
(define (dc-matrix who v)
  (unless (and (vector? v) (= (vector-length v) 6))
    (raise-argument-error who "vector of six finite affine coefficients" v))
  (vector->immutable-vector (for/vector ([n (in-vector v)]) (dc-real who n))))
(define (dc-transformation who v)
  (unless (and (vector? v) (= (vector-length v) 6))
    (raise-argument-error who "#(matrix origin-x origin-y scale-x scale-y rotation)" v))
  (vector-immutable (dc-matrix who (vector-ref v 0))
                    (dc-real who (vector-ref v 1)) (dc-real who (vector-ref v 2))
                    (dc-real who (vector-ref v 3)) (dc-real who (vector-ref v 4))
                    (dc-real who (vector-ref v 5))))
;; Column-vector algebra, with Racket's #(xx yx xy yy x0 y0) ordering.
(define (dc-multiply a b)
  (define (r i) (vector-ref a i))
  (define (s i) (vector-ref b i))
  (dc-matrix 'skia-dc-transform
   (vector (+ (* (r 0) (s 0)) (* (r 2) (s 1)))
           (+ (* (r 1) (s 0)) (* (r 3) (s 1)))
           (+ (* (r 0) (s 2)) (* (r 2) (s 3)))
           (+ (* (r 1) (s 2)) (* (r 3) (s 3)))
           (+ (* (r 0) (s 4)) (* (r 2) (s 5)) (r 4))
           (+ (* (r 1) (s 4)) (* (r 3) (s 5)) (r 5)))))
(define (dc-effective t)
  (define a (vector-ref t 5))
  (define c (cos a))
  (define s (sin a))
  ;; Positive Racket angles turn counter-clockwise on a y-down destination.
  (dc-multiply
   (dc-multiply
    (dc-multiply (vector-ref t 0) (vector 1 0 0 1 (vector-ref t 1) (vector-ref t 2)))
    (vector (vector-ref t 3) 0 0 (vector-ref t 4) 0 0))
   (vector c (- s) s c 0 0)))
(define (dc-point m x y)
  (values (dc-real 'skia-dc-point (+ (* (vector-ref m 0) x) (* (vector-ref m 2) y) (vector-ref m 4)))
          (dc-real 'skia-dc-point (+ (* (vector-ref m 1) x) (* (vector-ref m 3) y) (vector-ref m 5)))))
(define (dc-singular? m)
  (zero? (- (* (vector-ref m 0) (vector-ref m 3)) (* (vector-ref m 1) (vector-ref m 2)))))
(define (dc-physical-size who width height backing)
  (unless (and (exact-positive-integer? width) (exact-positive-integer? height))
    (raise-arguments-error who "logical dimensions must be positive exact integers"
                           "width" width "height" height))
  (define b (dc-real who backing))
  (unless (> b 0) (raise-argument-error who "positive finite backing scale" backing))
  (define w (inexact->exact (ceiling (dc-real who (* width b)))))
  (define h (inexact->exact (ceiling (dc-real who (* height b)))))
  (unless (and (<= 1 w #x7fffffff) (<= 1 h #x7fffffff))
    (raise-arguments-error who "physical dimensions exceed Skia's positive int range"
                           "pixel width" w "pixel height" h))
  (values w h b))
;; Internal immutable commands: #(move x y), #(line x y), #(cubic ...), #(close).
(define (dc-path-map commands point-proc)
  (for/list ([v (in-list commands)])
    (define values-list
      (append (list (vector-ref v 0))
              (append*
               (for/list ([i (in-range 1 (vector-length v) 2)])
                 (call-with-values (lambda () (point-proc (vector-ref v i) (vector-ref v (add1 i)))) list)))))
    (vector->immutable-vector (list->vector values-list))))
;; The renderer is private injection for testing the actual class, not a public
;; fallback or pluggable Cairo backend. Public construction always uses Skia.
(struct dc-renderer (create close draw clear snapshot rgba png) #:transparent)
(struct dc-ink (rgba stroke? width cap join dashes) #:transparent)
(struct dc-draw (commands rule matrix clip ink antialias?) #:transparent)
(define (dc-capabilities)
  (hasheq 'schema 1 'stage "0.53" 'scope "wrapper-declarations" 'class "skia-dc%" 'interface "dc<%>"
          'storage "persistent-cpu-raster" 'native_probe_performed #f
          'full_drop_in_compatibility #f 'gui_initialized #f
          'drawing '(draw-arc draw-ellipse draw-line draw-lines draw-path draw-point
                              draw-polygon draw-rectangle draw-rounded-rectangle draw-spline clear erase)
          'pen_styles '(solid transparent dot long-dash short-dash dot-dash)
          'brush_styles '(solid transparent)
          'smoothing '(unsmoothed smoothed aligned)
          'alignment "0.53 snaps positive axis-aligned transforms; use smoothed for rotation/shear/reflection"
          'selection_semantics "immutable pen/brush snapshots; caller objects are not locked"
          'clipping "transformed rectangle snapshots; same-DC snapshot restoration and #f reset"
          'deferred '(text text-metrics bitmap-input copy arbitrary-regions gradients stipples
                           hatches xor hilite alpha-groups path-ink-bounds gui gpu)))
