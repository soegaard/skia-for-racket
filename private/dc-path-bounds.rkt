#lang racket/base
;; Geometric path queries. No reference DC and no Cairo rasterization.
(require (prefix-in sk: "../main.rkt")
         (only-in (submod "core.rkt" geometry-internals) path-h paint-h)
         (only-in "lifetime.rkt" call-with-owned)
         (only-in "native.rkt" sk_paint_get_fill_path)
         (only-in "types.rkt" make-sk-matrix)
         "dc-support.rkt" "dc-native-util.rkt" "dc-style-render.rkt")
(provide dc-path-ink-bounds)

;; PathOps simplification preserves some zero-area geometry, such as a lone
;; line contour. `path-tight-bounds` then reports geometric bounds even though
;; filling the path paints nothing. After simplification, reject contours whose
;; complete geometry (including Bezier control points) is collinear.
(define (contour-has-area? contour)
  (define points
    (for*/list ([segment (in-list (sk:path-contour-segments contour))]
                [point (in-list (sk:path-segment-points segment))])
      point))
  (and (pair? points)
       (let* ([p0 (car points)]
              [p1
               (for/first ([p (in-list (cdr points))]
                           #:when (or (not (= (car p) (car p0)))
                                      (not (= (cadr p) (cadr p0)))))
                 p)])
         (and p1
              (for/or ([p (in-list points)])
                (not
                 (zero?
                  (- (* (- (car p1) (car p0))
                        (- (cadr p) (cadr p0)))
                     (* (- (cadr p1) (cadr p0))
                        (- (car p) (car p0)))))))))))

(define (filled-path-has-area? path)
  (for/or ([contour (in-list (sk:path-contours path #:mode 'raw))])
    (contour-has-area? contour)))

(define (dc-path-ink-bounds commands kind ink)
  (call-with-path commands 'odd-even
    (lambda (path)
      (case kind
        [(path) (sk:path-tight-bounds path)]
        [(fill)
         ;; Resolve self-intersections and zero-area contours before querying
         ;; filled bounds; path bounds alone include unpainted control points.
         (sk:with-skia ([filled (sk:path-simplify path)])
           (if (filled-path-has-area? filled)
               (sk:path-tight-bounds filled)
               (values 0.0 0.0 0.0 0.0)))]
        [(stroke)
         (call-with-dc-paint ink #f
           (lambda (paint)
             (sk:with-skia ([outline (sk:make-path)])
               (define filled?
                 (call-with-owned 'skia-dc-path-bounds
                   (list (paint-h 'skia-dc-path-bounds paint)
                         (path-h 'skia-dc-path-bounds path) (path-h 'skia-dc-path-bounds outline))
                   (lambda (pp src dst)
                     ;; Pass explicit identity rather than relying on shim
                     ;; behavior for a null matrix pointer. Cull is optional.
                     (sk_paint_get_fill_path pp src dst #f
                       (make-sk-matrix 1.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 1.0)))))
               (unless filled? (error 'skia-dc-path-bounds "native stroke outline failed"))
               (sk:path-tight-bounds outline))))]
        [else (raise-argument-error 'skia-dc-path-bounds "path/fill/stroke" kind)]))))
