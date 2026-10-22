#lang racket/base

;;;
;;; Drawing Context Path Bounds
;;;

;; Computes filled and stroked path bounds while accounting for degenerate contours.
;; Supports accurate clipping and ink queries in the dc<%> adapter.

;; Geometric path queries. No reference DC and no Cairo rasterization.

;;;
;;; Imports and Exports
;;;

(require (prefix-in sk: "../main.rkt")
         (only-in (submod "core.rkt" geometry-internals) path-h paint-h)
         (only-in "lifetime.rkt" call-with-owned)
         (only-in "native.rkt" sk_paint_get_fill_path)
         (only-in "types.rkt" make-sk-matrix)
         "dc-support.rkt" "dc-native-util.rkt" "dc-style-render.rkt")
(provide dc-path-ink-bounds)

;;;
;;; Degenerate Fill Detection and Ink Bounds
;;;

;; PathOps simplification preserves some zero-area geometry, such as a lone
;; line contour. `path-tight-bounds` then reports geometric bounds even though
;; filling the path paints nothing. After simplification, reject contours whose
;; complete geometry (including Bezier control points) is collinear.

; contour-has-area? : path-contour? -> boolean?
;   Tests whether the contour's endpoints and control points include a noncollinear triple.
(define (contour-has-area? contour)
  (define points
    (for*/list ([segment (in-list (sk:path-contour-segments contour))]
                [point (in-vector (sk:path-segment-points segment))])
      point))
  (and (pair? points)
       (let* ([p0 (car points)]
              [p1
               (for/first ([p (in-list (cdr points))]
                           #:when (or (not (= (vector-ref p 0) (vector-ref p0 0)))
                                      (not (= (vector-ref p 1) (vector-ref p0 1)))))
                 p)])
         (and p1
              (for/or ([p (in-list points)])
                (not
                 (zero?
                  (- (* (- (vector-ref p1 0) (vector-ref p0 0))
                        (- (vector-ref p 1) (vector-ref p0 1)))
                     (* (- (vector-ref p1 1) (vector-ref p0 1))
                        (- (vector-ref p 0) (vector-ref p0 0)))))))))))

; filled-path-has-area? : path? -> boolean?
;   Detects any noncollinear contour after native fill simplification has resolved
;   self-intersections.
(define (filled-path-has-area? path)
  (for/or ([contour (in-list (sk:path-contours path #:mode 'raw))])
    (contour-has-area? contour)))

; dc-path-ink-bounds : (listof vector?) symbol? dc-ink? -> (values real? real? real? real?)
;   Returns left, top, width, and height for path geometry, filled area, or a stroke outline,
;   excluding degenerate empty fills.
(define (dc-path-ink-bounds commands kind ink)
  (call-with-path commands 'odd-even
    (lambda (path)
      (case kind
        [(path) (vector->values (sk:path-tight-bounds path))]
        [(fill)
         ;; Resolve self-intersections and zero-area contours before querying
         ;; filled bounds; path bounds alone include unpainted control points.
         (sk:with-skia ([filled (sk:path-simplify path)])
           (if (filled-path-has-area? filled)
               (vector->values (sk:path-tight-bounds filled))
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
               (vector->values (sk:path-tight-bounds outline)))))]
        [else (raise-argument-error 'skia-dc-path-bounds "path/fill/stroke" kind)]))))
