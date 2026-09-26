#lang racket/base
(require racket/math)
(provide matrix? make-matrix matrix-identity
         matrix-xx matrix-yx matrix-xy matrix-yy matrix-x0 matrix-y0
         matrix->vector vector->matrix
         matrix-translate matrix-scale matrix-rotate matrix-rotate-degrees matrix-skew
         matrix-compose matrix-invert matrix-map-point matrix-map-vector matrix-map-rect)

;; Public affine values use the SVG/Racket six-coefficient order:
;; [xx xy x0] [x]   [xx*x + xy*y + x0]
;; [yx yy y0] [y] = [yx*x + yy*y + y0]
;; [ 0  0  1] [1]   [        1       ]
;; No native allocation, pointer, or mutable backing vector is retained.
(struct matrix (xx yx xy yy x0 y0) #:transparent #:constructor-name matrix-record)

(define (component who x)
  (unless (and (real? x) (<= -3.402823e38 x 3.402823e38))
    (raise-argument-error who "finite real representable as a C float" x))
  ;; Store the exact value that will cross the single-precision native boundary.
  (floating-point-bytes->real (real->floating-point-bytes x 4 #f) #f))

(define (checked who m)
  (unless (matrix? m) (raise-argument-error who "matrix?" m))
  m)

(define (make-matrix [xx 1] [yx 0] [xy 0] [yy 1] [x0 0] [y0 0])
  (apply matrix-record
         (map (lambda (v) (component 'make-matrix v)) (list xx yx xy yy x0 y0))))

(define matrix-identity (make-matrix))

(define (matrix->vector m)
  (checked 'matrix->vector m)
  (vector-immutable (matrix-xx m) (matrix-yx m) (matrix-xy m)
                    (matrix-yy m) (matrix-x0 m) (matrix-y0 m)))

(define (vector->matrix v)
  (unless (and (vector? v) (= (vector-length v) 6))
    (raise-argument-error 'vector->matrix "vector of six affine coefficients" v))
  (apply make-matrix (vector->list v)))

(define (matrix-translate x y) (make-matrix 1 0 0 1 x y))
(define (matrix-scale x [y x]) (make-matrix x 0 0 y 0 0))
(define (matrix-skew x y) (make-matrix 1 y x 1 0 0))

(define (matrix-rotate radians)
  (define angle (component 'matrix-rotate radians))
  (define c (cos angle))
  (define s (sin angle))
  (make-matrix c s (- s) c))

(define (matrix-rotate-degrees degrees)
  (define angle (component 'matrix-rotate-degrees degrees))
  ;; Reduce first, and keep quarter turns exact. Avoid needless pi-rounding.
  (define reduced (- angle (* 360.0 (floor (/ angle 360.0)))))
  (cond [(= reduced 0) matrix-identity]
        [(= reduced 90) (make-matrix 0 1 -1 0)]
        [(= reduced 180) (make-matrix -1 0 0 -1)]
        [(= reduced 270) (make-matrix 0 -1 1 0)]
        [else (matrix-rotate (* reduced (/ pi 180.0)))]))

(define (multiply a b)
  (make-matrix
   (+ (* (matrix-xx a) (matrix-xx b)) (* (matrix-xy a) (matrix-yx b)))
   (+ (* (matrix-yx a) (matrix-xx b)) (* (matrix-yy a) (matrix-yx b)))
   (+ (* (matrix-xx a) (matrix-xy b)) (* (matrix-xy a) (matrix-yy b)))
   (+ (* (matrix-yx a) (matrix-xy b)) (* (matrix-yy a) (matrix-yy b)))
   (+ (* (matrix-xx a) (matrix-x0 b)) (* (matrix-xy a) (matrix-y0 b)) (matrix-x0 a))
   (+ (* (matrix-yx a) (matrix-x0 b)) (* (matrix-yy a) (matrix-y0 b)) (matrix-y0 a))))

(define (matrix-compose . matrices)
  (for ([m (in-list matrices)]) (checked 'matrix-compose m))
  ;; A*B maps with B first, then A. canvas-concat! uses current*new.
  (for/fold ([out matrix-identity]) ([m (in-list matrices)]) (multiply out m)))

(define (matrix-invert m)
  (checked 'matrix-invert m)
  (define a (matrix-xx m))
  (define b (matrix-yx m))
  (define c (matrix-xy m))
  (define d (matrix-yy m))
  (define x (matrix-x0 m))
  (define y (matrix-y0 m))
  (define det (- (* a d) (* b c)))
  (cond
    [(zero? det) #f]
    [else
     (define values (list (/ d det) (/ (- b) det) (/ (- c) det) (/ a det)
                          (/ (- (* c y) (* d x)) det)
                          (/ (- (* b x) (* a y)) det)))
     ;; No arbitrary singularity epsilon. An inverse outside the representable
     ;; range is also unavailable, rather than a matrix containing infinities.
     (and (for/and ([v (in-list values)]) (<= -3.402823e38 v 3.402823e38))
          (apply make-matrix values))]))

(define (map-xy who m x y translate?)
  (checked who m)
  (define fx (component who x))
  (define fy (component who y))
  (values (component who (+ (* (matrix-xx m) fx) (* (matrix-xy m) fy)
                            (if translate? (matrix-x0 m) 0)))
          (component who (+ (* (matrix-yx m) fx) (* (matrix-yy m) fy)
                            (if translate? (matrix-y0 m) 0)))))

(define (matrix-map-point m x y) (map-xy 'matrix-map-point m x y #t))
(define (matrix-map-vector m x y) (map-xy 'matrix-map-vector m x y #f))

(define (matrix-map-rect m x y width height)
  (checked 'matrix-map-rect m)
  (define w (component 'matrix-map-rect width))
  (define h (component 'matrix-map-rect height))
  (unless (and (>= w 0) (>= h 0))
    (raise-arguments-error 'matrix-map-rect "rectangle extents must be nonnegative"
                           "width" width "height" height))
  (define fx (component 'matrix-map-rect x))
  (define fy (component 'matrix-map-rect y))
  (define corners
    (for/list ([p (in-list (list (list fx fy) (list (+ fx w) fy)
                                (list fx (+ fy h)) (list (+ fx w) (+ fy h))))])
      (call-with-values (lambda () (matrix-map-point m (car p) (cadr p))) list)))
  (define xs (map car corners))
  (define ys (map cadr corners))
  (define left (apply min xs))
  (define top (apply min ys))
  (values left top (component 'matrix-map-rect (- (apply max xs) left))
          (component 'matrix-map-rect (- (apply max ys) top))))
