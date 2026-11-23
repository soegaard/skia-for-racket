#lang racket/base

;;;
;;; Affine Matrix Values
;;;

;; Constructs and combines detached affine transformations and maps points, vectors, and rectangles.
;; This native-free public geometry module supplies the shared six-coefficient representation
;; consumed by canvas and shader adapters.

;;;
;;; Imports and Exports
;;;

(require racket/math)
(provide matrix? make-matrix matrix-identity
         matrix-xx matrix-yx matrix-xy matrix-yy matrix-x0 matrix-y0
         matrix->vector vector->matrix
         matrix-translate matrix-scale matrix-rotate-radians matrix-rotate-degrees matrix-skew
         matrix-compose matrix-invert matrix-map-point matrix-map-vector matrix-map-rect)

;;;
;;; Matrix Representation and Validation
;;;

;; Public affine values use the SVG/Racket six-coefficient order:
;; [xx xy x0] [x]   [xx*x + xy*y + x0]
;; [yx yy y0] [y] = [yx*x + yy*y + y0]
;; [ 0  0  1] [1]   [        1       ]
;; No native allocation, pointer, or mutable backing vector is retained.
(struct matrix (xx yx xy yy x0 y0) #:transparent #:constructor-name matrix-record)
;; A matrix stores finite binary32 coefficients in SVG/Racket affine order.
;;  - xx  real?  Contribution of input x to output x.
;;  - yx  real?  Contribution of input x to output y.
;;  - xy  real?  Contribution of input y to output x.
;;  - yy  real?  Contribution of input y to output y.
;;  - x0  real?  Translation added to output x for points, but not vectors.
;;  - y0  real?  Translation added to output y for points, but not vectors.
;; The field order is xx, yx, xy, yy, x0, y0, not a row-major flat matrix.
;; Public construction validates and rounds each component; singular values are
;; allowed, while inversion reports an unavailable result with #f.

; component : symbol? real? -> real?
;   Validates a drawing scalar and rounds it to the native binary32 boundary.
(define (component who x)
  (unless (and (real? x) (<= -3.402823e38 x 3.402823e38))
    (raise-argument-error who "finite real representable as a C float" x))
  ;; Store the exact value that will cross the single-precision native boundary.
  (floating-point-bytes->real (real->floating-point-bytes x 4 #f) #f))

; checked : symbol? matrix? -> matrix?
;   Checks an affine value and attributes a type error to the calling operation.
(define (checked who m)
  (unless (matrix? m) (raise-argument-error who "matrix?" m))
  m)

;;;
;;; Matrix Construction and Element Conversion
;;;

; make-matrix : [real?] [real?] [real?] [real?] [real?] [real?] -> matrix?
;   Returns an affine matrix with the given coefficients.
(define (make-matrix [xx 1] [yx 0] [xy 0] [yy 1] [x0 0] [y0 0])
  (apply matrix-record
         (map (lambda (v) (component 'make-matrix v)) (list xx yx xy yy x0 y0))))

; matrix-identity : matrix?
;   Leaves points and vectors unchanged under affine mapping.
(define matrix-identity (make-matrix))

; matrix->vector : matrix? -> (vectorof real?)
;   Returns an immutable six-element vector in the order xx, yx, xy, yy, x0, y0.
(define (matrix->vector m)
  (checked 'matrix->vector m)
  (vector-immutable (matrix-xx m) (matrix-yx m) (matrix-xy m)
                    (matrix-yy m) (matrix-x0 m) (matrix-y0 m)))

; vector->matrix : (vector/c real? real? real? real? real? real?) -> matrix?
;   Returns a matrix from the six coefficients in v, applying the same checks and
;   rounding as make-matrix.
(define (vector->matrix v)
  (unless (and (vector? v) (= (vector-length v) 6))
    (raise-argument-error 'vector->matrix "vector of six affine coefficients" v))
  (apply make-matrix (vector->list v)))

;;;
;;; Affine Transform Constructors
;;;

; matrix-translate : real? real? -> matrix?
;   Returns a translation matrix.
(define (matrix-translate x y) (make-matrix 1 0 0 1 x y))

; matrix-scale : real? [real?] -> matrix?
;   Returns an axis-aligned scaling matrix.
(define (matrix-scale x [y x]) (make-matrix x 0 0 y 0 0))

; matrix-skew : real? real? -> matrix?
;   Returns a shear matrix with horizontal factor x and vertical factor y.
(define (matrix-skew x y) (make-matrix 1 y x 1 0 0))

; matrix-rotate-radians : real? -> matrix?
;   Returns a rotation about the origin.
(define (matrix-rotate-radians radians)
  (define angle (component 'matrix-rotate-radians radians))
  (define c (cos angle))
  (define s (sin angle))
  (make-matrix c s (- s) c))

; matrix-rotate-degrees : real? -> matrix?
;   Like matrix-rotate-radians, with the angle measured in degrees.
(define (matrix-rotate-degrees degrees)
  (define angle (component 'matrix-rotate-degrees degrees))
  ;; Reduce first, and keep quarter turns exact. Avoid needless pi-rounding.
  (define reduced (- angle (* 360.0 (floor (/ angle 360.0)))))
  (cond [(= reduced 0) matrix-identity]
        [(= reduced 90) (make-matrix 0 1 -1 0)]
        [(= reduced 180) (make-matrix -1 0 0 -1)]
        [(= reduced 270) (make-matrix 0 -1 1 0)]
        [else (matrix-rotate-radians (* reduced (/ pi 180.0)))]))

;;;
;;; Composition and Inversion
;;;

; multiply : matrix? matrix? -> matrix?
;   Forms A times B, so the resulting mapping applies B before A.
(define (multiply a b)
  (make-matrix
   (+ (* (matrix-xx a) (matrix-xx b)) (* (matrix-xy a) (matrix-yx b)))
   (+ (* (matrix-yx a) (matrix-xx b)) (* (matrix-yy a) (matrix-yx b)))
   (+ (* (matrix-xx a) (matrix-xy b)) (* (matrix-xy a) (matrix-yy b)))
   (+ (* (matrix-yx a) (matrix-xy b)) (* (matrix-yy a) (matrix-yy b)))
   (+ (* (matrix-xx a) (matrix-x0 b)) (* (matrix-xy a) (matrix-y0 b)) (matrix-x0 a))
   (+ (* (matrix-yx a) (matrix-x0 b)) (* (matrix-yy a) (matrix-y0 b)) (matrix-y0 a))))

; matrix-compose : matrix? ... -> matrix?
;   Returns the product of the supplied matrices in argument order.
(define (matrix-compose . matrices)
  (for ([m (in-list matrices)]) (checked 'matrix-compose m))
  ;; A*B maps with B first, then A. canvas-concat! uses current*new.
  (for/fold ([out matrix-identity]) ([m (in-list matrices)]) (multiply out m)))

; matrix-invert : matrix? -> (or/c matrix? #f)
;   Returns the inverse of m, rounded to the matrix representation.
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
     ;; Inverting a translation naturally produces algebraic zeroes in the
     ;; off-diagonal positions.  Canonicalize their sign so an inverse has a
     ;; stable structural representation (rather than `-0.0` from negation).
     (define (canonical-zero v) (if (zero? v) 0.0 v))
     (define values
       (map canonical-zero
            (list (/ d det) (/ (- b) det) (/ (- c) det) (/ a det)
                  (/ (- (* c y) (* d x)) det)
                  (/ (- (* b x) (* a y)) det))))
     ;; No arbitrary singularity epsilon. An inverse outside the representable
     ;; range is also unavailable, rather than a matrix containing infinities.
     (and (for/and ([v (in-list values)]) (<= -3.402823e38 v 3.402823e38))
          (apply make-matrix values))]))

;;;
;;; Point, Vector, and Rectangle Mapping
;;;

; map-xy : symbol? matrix? real? real? boolean? -> (and/c (vector/c real? real?) immutable?)
;   Maps two coordinates, optionally adding translation, and checks the results.
(define (map-xy who m x y translate?)
  (checked who m)
  (define fx (component who x))
  (define fy (component who y))
  (vector-immutable
   (component who (+ (* (matrix-xx m) fx) (* (matrix-xy m) fy)
                     (if translate? (matrix-x0 m) 0)))
   (component who (+ (* (matrix-yx m) fx) (* (matrix-yy m) fy)
                     (if translate? (matrix-y0 m) 0)))))

; matrix-map-point : matrix? real? real? -> (and/c (vector/c real? real?) immutable?)
;   Returns the transformed point as an immutable #(x y) vector, including the translation terms.
(define (matrix-map-point m x y) (map-xy 'matrix-map-point m x y #t))

; matrix-map-vector : matrix? real? real? -> (and/c (vector/c real? real?) immutable?)
;   Returns the transformed displacement as an immutable #(x y) vector, omitting translation.
(define (matrix-map-vector m x y) (map-xy 'matrix-map-vector m x y #f))

; matrix-map-rect : matrix? real? real? (and/c real? (>=/c 0)) (and/c real? (>=/c 0)) ->
;   (and/c (vector/c real? real? real? real?) immutable?)
;   Returns the axis-aligned bounding rectangle of the four transformed corners, as an immutable
;   #(x y width height) vector.
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
      (matrix-map-point m (car p) (cadr p))))
  (define xs (map (lambda (p) (vector-ref p 0)) corners))
  (define ys (map (lambda (p) (vector-ref p 1)) corners))
  (define left (apply min xs))
  (define top (apply min ys))
  (vector-immutable left top (component 'matrix-map-rect (- (apply max xs) left))
                    (component 'matrix-map-rect (- (apply max ys) top))))
