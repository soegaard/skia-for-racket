#lang racket/base
;; Pure policy/math shared by the DC front end and its style renderer.
(require racket/list racket/math "dc-support.rkt")
(provide dc-pen-styles dc-brush-styles dc-hatch-styles dc-dash-spec
         dc-inverse dc-style-local-matrix dc-alignment-functions dc-axis-scales
         dc-hatch-lines dc-gradient-stops)
(define dc-pen-styles
  '(solid transparent xor hilite dot long-dash short-dash dot-dash
          xor-dot xor-long-dash xor-short-dash xor-dot-dash))
(define dc-hatch-styles
  '(horizontal-hatch vertical-hatch cross-hatch bdiagonal-hatch fdiagonal-hatch crossdiag-hatch))
(define dc-brush-styles
  (append '(solid transparent opaque xor hilite panel) dc-hatch-styles))
(define (dc-dash-spec style width [stipple? #f])
  ;; Upstream 8.18 accepts the legacy xor-* names but renders them solid;
  ;; it does not implement bitwise XOR. Preserve that behavior, not the name.
  ;; The pinned draw-lib implementation keeps the selected dash pattern on
  ;; stippled pens too. Do not infer a different native operator from the name.
  (define wide? (> width 1))
  (define gap (if wide? 2.0 4.0))
  (define pattern
    (case style
          [(dot) (list 1.0 gap)] [(long-dash) (list 4.0 gap)]
          [(short-dash) (list 2.0 gap)] [(dot-dash) (list 1.0 gap 4.0 gap)]
          [else '()]))
  (values (map (lambda (v) (* v (if wide? width 1.0))) pattern)
          (cond [(null? pattern) 0.0] [(eq? style 'dot-dash) 4.0] [else 2.0])))
(define (dc-inverse who m)
  (define a (dc-matrix who m))
  ;; Exact arithmetic avoids a binary64 determinant underflow producing a
  ;; false singular result. The returned coefficients still obey our F32 bound.
  (define x (for/vector ([v (in-vector a)]) (inexact->exact v)))
  (define det (- (* (vector-ref x 0) (vector-ref x 3))
                 (* (vector-ref x 1) (vector-ref x 2))))
  (when (zero? det) (raise-arguments-error who "singular pattern transformation" "matrix" m))
  (define aa (/ (vector-ref x 3) det)) (define bb (/ (- (vector-ref x 1)) det))
  (define cc (/ (- (vector-ref x 2)) det)) (define dd (/ (vector-ref x 0) det))
  (dc-matrix who (vector aa bb cc dd
                        (- (+ (* aa (vector-ref x 4)) (* cc (vector-ref x 5))))
                        (- (+ (* bb (vector-ref x 4)) (* dd (vector-ref x 5)))))))
(define (dc-style-local-matrix drawing brush-transform source-backing)
  ;; Drawing is in logical coordinates; both transforms share the destination
  ;; backing scale, so that factor cancels. Stipple coordinates are physical
  ;; source pixels, hence the final inverse *source* backing scale.
  (define b (dc-real 'skia-dc-style source-backing))
  (unless (> b 0) (raise-argument-error 'skia-dc-style "positive source backing scale" source-backing))
  (define base (if brush-transform
                   (dc-multiply (dc-inverse 'skia-dc-style drawing)
                                (dc-effective (dc-transformation 'skia-dc-style brush-transform)))
                   dc-identity))
  (dc-multiply base (vector (/ 1.0 b) 0 0 (/ 1.0 b) 0 0)))
(define (dc-axis-scales m alignment)
  ;; These row norms match racket/draw's effective-scale calculation. They
  ;; remain positive for rotations, reflections and nonsingular shear.
  (values (dc-real 'skia-dc-alignment (* alignment (sqrt (+ (sqr (vector-ref m 0)) (sqr (vector-ref m 2))))))
          (dc-real 'skia-dc-alignment (* alignment (sqrt (+ (sqr (vector-ref m 1)) (sqr (vector-ref m 3))))))))
(define (dc-alignment-functions who m alignment width smoothing)
  (cond
    [(eq? smoothing 'smoothed) (values values values 0.0 0.0)]
    [else
     (define-values (sx sy) (dc-axis-scales m alignment))
     (unless (and (> sx 0) (> sy 0))
       (raise-arguments-error who "degenerate alignment scale" "matrix" m))
     (define (delta scale)
       (if (odd? (inexact->exact (max 1 (floor (* width scale))))) 0.5 0.0))
     ;; Keep the established positive-axis result, now using the same positive
     ;; effective row norms as upstream under an arbitrary affine transform.
     (define ox (vector-ref m 4))
     (define oy (vector-ref m 5))
     (values (lambda (x) (/ (- (+ (floor (+ (* x sx) ox)) (delta sx)) ox) sx))
             (lambda (y) (/ (- (+ (floor (+ (* y sy) oy)) (delta sy)) oy) sy))
             (/ 1.0 sx) (/ 1.0 sy))]))
(define (dc-hatch-lines style)
  ;; A 12x12 repeating tile, using racket/draw's line positions. Color and
  ;; opacity are applied by the renderer; crosses form one stroke, not two
  ;; independently composited translucent strokes.
  (define h (for/list ([y '(3.5 7.5 11.5)]) (vector 0.0 y 12.0 y)))
  (define v (for/list ([x '(3.5 7.5 11.5)]) (vector x 0.0 x 12.0)))
  (define b (for/list ([i (in-range -2 3)]) (vector -1.0 (+ -1.0 (* i 6)) 13.0 (+ 13.0 (* i 6)))))
  (define f (for/list ([i (in-range -2 3)]) (vector 13.0 (+ -1.0 (* i 6)) -1.0 (+ 13.0 (* i 6)))))
  (case style [(horizontal-hatch) h] [(vertical-hatch) v] [(cross-hatch) (append h v)]
    [(bdiagonal-hatch) b] [(fdiagonal-hatch) f] [(crossdiag-hatch) (append b f)]
    [else (raise-argument-error 'dc-hatch-lines "hatch brush style" style)]))
(define (dc-gradient-stops who stops limit)
  ;; Input uses immutable RGBA vectors. Stable sort preserves a discontinuity
  ;; represented by adjacent equal-offset stops. Zero and one stop are valid.
  (unless (and (list? stops) (<= (* 40 (length stops)) limit))
    (raise-arguments-error who "gradient stop list exceeds current-skia-byte-limit" "limit" limit))
  (sort
   (for/list ([s (in-list stops)])
     (unless (and (list? s) (= (length s) 2)
                  (vector? (cadr s)) (= (vector-length (cadr s)) 4))
       (raise-argument-error who "list of (list position rgba-vector) stops" stops))
     (define c (cadr s))
     (for ([v (in-vector c)] [i (in-naturals)] #:when (< i 3))
       (unless (byte? v) (raise-argument-error who "byte color channel" v)))
     (list (dc-unit who (car s))
           (vector-immutable (vector-ref c 0) (vector-ref c 1) (vector-ref c 2)
                             (dc-unit who (vector-ref c 3)))))
   < #:key car #:cache-keys? #t))
