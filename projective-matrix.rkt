#lang racket/base
(require racket/list racket/math racket/vector "matrix.rkt")
(provide matrix3? make-matrix3 matrix3-identity vector->matrix3 matrix3->vector matrix3-ref
         matrix3-compose matrix3-transpose matrix3-invert matrix3-perspective
         matrix3-affine? matrix->matrix3 matrix3->matrix
         matrix3-map-homogeneous matrix3-map-point matrix3-map-rect
         matrix4? make-matrix4 matrix4-identity vector->matrix4 matrix4->vector matrix4-ref
         matrix4-compose matrix4-transpose matrix4-invert
         matrix4-translate matrix4-scale matrix4-perspective
         matrix4-rotate-x-degrees matrix4-rotate-y-degrees matrix4-rotate-z-degrees
         matrix4-affine-2d? matrix->matrix4 matrix4->matrix
         matrix3->matrix4 matrix4->matrix3 matrix4-project-xy
         matrix4-map-homogeneous matrix4-map-point matrix4-map-rect)

;; These are separate types from the existing six-coefficient affine matrix.
;; Public storage is ROW-MAJOR; native SkM44 storage is converted at the FFI.
;; The backing vectors are immutable and contain only finite C-float values.
(struct matrix3 (elements) #:transparent #:constructor-name matrix3-record)
(struct matrix4 (elements) #:transparent #:constructor-name matrix4-record)
(define limit 3.4028234663852886e38) ; exact largest finite IEEE binary32 value
(define legacy-limit 3.402823e38) ; preserve the affine constructor's existing contract
(define (component who x)
  (unless (and (real? x) (<= (- limit) x limit))
    (raise-argument-error who "finite real representable as a C float" x))
  (floating-point-bytes->real (real->floating-point-bytes x 4 #f) #f))
(define (checked who pred name x)
  (unless (pred x) (raise-argument-error who name x))
  x)
(define (snapshot who v n)
  (unless (and (vector? v) (= (vector-length v) (* n n)))
    (raise-argument-error who (format "vector of ~a row-major coefficients" (* n n)) v))
  (vector->immutable-vector
   (for/vector ([x (in-vector v)]) (component who x))))
(define (vector->matrix3 v) (matrix3-record (snapshot 'vector->matrix3 v 3)))
(define (vector->matrix4 v) (matrix4-record (snapshot 'vector->matrix4 v 4)))
(define (make-matrix3 [a 1] [b 0] [c 0] [d 0] [e 1] [f 0] [g 0] [h 0] [i 1])
  (matrix3-record (snapshot 'make-matrix3 (vector a b c d e f g h i) 3)))
(define (make-matrix4 [a 1] [b 0] [c 0] [d 0]
                      [e 0] [f 1] [g 0] [h 0]
                      [i 0] [j 0] [k 1] [l 0]
                      [m 0] [n 0] [o 0] [p 1])
  (matrix4-record (snapshot 'make-matrix4 (vector a b c d e f g h i j k l m n o p) 4)))
(define matrix3-identity (make-matrix3))
(define matrix4-identity (make-matrix4))
(define (matrix3->vector m)
  (matrix3-elements (checked 'matrix3->vector matrix3? "matrix3?" m)))
(define (matrix4->vector m)
  (matrix4-elements (checked 'matrix4->vector matrix4? "matrix4?" m)))
(define (ref who v n row col)
  (for ([index (in-list (list row col))])
    (unless (and (exact-nonnegative-integer? index) (< index n))
      (raise-argument-error who (format "exact integer in [0, ~a]" (sub1 n)) index)))
  (vector-ref v (+ (* row n) col)))
(define (matrix3-ref m row col) (ref 'matrix3-ref (matrix3->vector m) 3 row col))
(define (matrix4-ref m row col) (ref 'matrix4-ref (matrix4->vector m) 4 row col))

;; Do small matrix arithmetic on the exact values of the stored C floats.
;; In particular a cancellation in a determinant must not acquire an arbitrary
;; singularity epsilon. A newly returned matrix is rounded once to C floats.
(define (exact-vector v) (vector-map inexact->exact v))
(define (multiply a b n)
  (define ea (exact-vector a)) (define eb (exact-vector b))
  (for*/vector ([r (in-range n)] [c (in-range n)])
    (for/sum ([k (in-range n)])
      (* (vector-ref ea (+ (* r n) k)) (vector-ref eb (+ (* k n) c))))))
(define (matrix3-compose . ms)
  (for ([m (in-list ms)]) (checked 'matrix3-compose matrix3? "matrix3?" m))
  (for/fold ([a matrix3-identity]) ([b (in-list ms)])
    (vector->matrix3 (multiply (matrix3-elements a) (matrix3-elements b) 3))))
(define (matrix4-compose . ms)
  (for ([m (in-list ms)]) (checked 'matrix4-compose matrix4? "matrix4?" m))
  (for/fold ([a matrix4-identity]) ([b (in-list ms)])
    (vector->matrix4 (multiply (matrix4-elements a) (matrix4-elements b) 4))))
(define (transpose v n)
  (for*/vector ([r (in-range n)] [c (in-range n)]) (vector-ref v (+ (* c n) r))))
(define (matrix3-transpose m) (vector->matrix3 (transpose (matrix3->vector m) 3)))
(define (matrix4-transpose m) (vector->matrix4 (transpose (matrix4->vector m) 4)))
(define (inverse v n)
  (let/ec unavailable
    (define a
      (for/vector ([r (in-range n)])
        (for/vector ([c (in-range (* 2 n))])
          (if (< c n) (inexact->exact (vector-ref v (+ (* r n) c)))
              (if (= (- c n) r) 1 0)))))
    (for ([c (in-range n)])
      (define pivot
        (for/first ([r (in-range c n)] #:unless (zero? (vector-ref (vector-ref a r) c))) r))
      (unless pivot (unavailable #f))
      (define old (vector-ref a c))
      (vector-set! a c (vector-ref a pivot)) (vector-set! a pivot old)
      (define row (vector-ref a c))
      (define divisor (vector-ref row c))
      (for ([k (in-range (* 2 n))]) (vector-set! row k (/ (vector-ref row k) divisor)))
      (for ([r (in-range n)] #:unless (= r c))
        (define target (vector-ref a r)) (define scale (vector-ref target c))
        (for ([k (in-range (* 2 n))])
          (vector-set! target k (- (vector-ref target k) (* scale (vector-ref row k)))))))
    (define result
      (for*/vector ([r (in-range n)] [c (in-range n)]) (vector-ref (vector-ref a r) (+ c n))))
    (and (for/and ([x (in-vector result)]) (<= (- limit) x limit)) result)))
(define (matrix3-invert m)
  (define v (inverse (matrix3->vector m) 3)) (and v (vector->matrix3 v)))
(define (matrix4-invert m)
  (define v (inverse (matrix4->vector m) 4)) (and v (vector->matrix4 v)))

(define (matrix3-perspective px py) (make-matrix3 1 0 0 0 1 0 px py 1))
(define (matrix3-affine? m)
  (define v (matrix3->vector m))
  (and (= (vector-ref v 6) 0) (= (vector-ref v 7) 0) (not (= (vector-ref v 8) 0))))
(define (matrix->matrix3 m)
  (checked 'matrix->matrix3 matrix? "matrix?" m)
  (make-matrix3 (matrix-xx m) (matrix-xy m) (matrix-x0 m)
                (matrix-yx m) (matrix-yy m) (matrix-y0 m) 0 0 1))
(define (matrix3->matrix m)
  (define v (matrix3->vector m))
  (and (matrix3-affine? m)
       (let ([xs (for/list ([i '(0 3 1 4 2 5)])
                   (/ (inexact->exact (vector-ref v i)) (inexact->exact (vector-ref v 8))))])
         (and (for/and ([x (in-list xs)]) (<= (- legacy-limit) x legacy-limit)) (apply make-matrix xs)))))
(define (matrix3->matrix4 m)
  (define v (matrix3->vector m))
  (define (at i) (vector-ref v i))
  (make-matrix4 (at 0) (at 1) 0 (at 2)
                (at 3) (at 4) 0 (at 5)
                0 0 1 0
                (at 6) (at 7) 0 (at 8)))
(define (matrix->matrix4 m) (matrix3->matrix4 (matrix->matrix3 m)))
(define (matrix4->matrix3 m)
  ;; Only a lossless embedding conversion. Use project-xy for an explicitly
  ;; lossy projection of a 3D transform onto the current drawing plane z=0.
  (define v (matrix4->vector m))
  (and (= (vector-ref v 2) 0) (= (vector-ref v 6) 0)
       (= (vector-ref v 8) 0) (= (vector-ref v 9) 0)
       (= (vector-ref v 10) 1) (= (vector-ref v 11) 0) (= (vector-ref v 14) 0)
       (matrix4-project-xy m)))
(define (matrix4-project-xy m)
  (define v (matrix4->vector m))
  (vector->matrix3 (for/vector ([i '(0 1 3 4 5 7 12 13 15)]) (vector-ref v i))))
(define (matrix4-affine-2d? m)
  (define p (matrix4->matrix3 m))
  (and p (= (matrix3-ref p 2 0) 0) (= (matrix3-ref p 2 1) 0) (= (matrix3-ref p 2 2) 1)))
(define (matrix4->matrix m)
  (and (matrix4-affine-2d? m) (matrix3->matrix (matrix4-project-xy m))))
(define (matrix4-translate x y [z 0]) (make-matrix4 1 0 0 x 0 1 0 y 0 0 1 z 0 0 0 1))
(define (matrix4-scale x [y x] [z 1]) (make-matrix4 x 0 0 0 0 y 0 0 0 0 z 0 0 0 0 1))
(define (rotation degrees)
  ;; Reuse affine angle normalization and its exact quarter turns.
  (define m (matrix-rotate-degrees degrees)) (values (matrix-xx m) (matrix-yx m)))
(define (matrix4-rotate-x-degrees degrees)
  (define-values (c s) (rotation degrees))
  (make-matrix4 1 0 0 0 0 c (- s) 0 0 s c 0 0 0 0 1))
(define (matrix4-rotate-y-degrees degrees)
  (define-values (c s) (rotation degrees))
  (make-matrix4 c 0 s 0 0 1 0 0 (- s) 0 c 0 0 0 0 1))
(define (matrix4-rotate-z-degrees degrees)
  (matrix->matrix4 (matrix-rotate-degrees degrees)))
(define (matrix4-perspective distance)
  (define d (component 'matrix4-perspective distance))
  (unless (> d 0) (raise-argument-error 'matrix4-perspective "positive representable distance" distance))
  ;; Camera at z=-distance, looking along +z. No near/far planes or depth buffer.
  ;; (x,y,z,1) maps to (x,y,z,1+z/distance).
  (make-matrix4 1 0 0 0 0 1 0 0 0 0 1 0 0 0 (/ 1 d) 1))

(define (map-raw who v coordinates)
  (define n (length coordinates))
  (define p (list->vector (map (lambda (x) (inexact->exact (component who x))) coordinates)))
  (define e (exact-vector v))
  (for/vector ([r (in-range n)])
    (for/sum ([c (in-range n)]) (* (vector-ref e (+ (* r n) c)) (vector-ref p c)))))
(define (finite-vector v)
  ;; Queries return double precision, not new native matrix coefficients.
  (define out (vector-map exact->inexact v))
  (and (for/and ([x (in-vector out)]) (and (not (nan? x)) (not (infinite? x))))
       (vector->immutable-vector out)))
(define (project p)
  (define last (sub1 (vector-length p)))
  (define w (vector-ref p last))
  (and (not (zero? w))
       (finite-vector (for/vector ([i (in-range last)]) (/ (vector-ref p i) w)))))
(define (matrix3-map-homogeneous m x y [w 1])
  (finite-vector (map-raw 'matrix3-map-homogeneous (matrix3->vector m) (list x y w))))
(define (matrix3-map-point m x y)
  (project (map-raw 'matrix3-map-point (matrix3->vector m) (list x y 1))))
(define (matrix4-map-homogeneous m x y [z 0] [w 1])
  (finite-vector (map-raw 'matrix4-map-homogeneous (matrix4->vector m) (list x y z w))))
(define (matrix4-map-point m x y [z 0])
  (project (map-raw 'matrix4-map-point (matrix4->vector m) (list x y z 1))))
(define (matrix3-map-rect m x y width height)
  (define who 'matrix3-map-rect)
  (define v (matrix3->vector m))
  (define sx (component who x)) (define sy (component who y))
  (define sw (component who width)) (define sh (component who height))
  (unless (and (>= sw 0) (>= sh 0))
    (raise-arguments-error who "rectangle extents must be nonnegative" "width" width "height" height))
  ;; Corner sums are validated by map-raw, just like point inputs.
  (define raw
    (for/list ([p (in-list (list (list sx sy 1) (list (+ sx sw) sy 1)
                                 (list (+ sx sw) (+ sy sh) 1) (list sx (+ sy sh) 1)))])
      (map-raw who v p)))
  (define ws (map (lambda (p) (vector-ref p 2)) raw))
  ;; W is affine on the rectangle: equal strict signs at all four corners are
  ;; necessary and sufficient for avoiding a horizon, including on its edges.
  (and (or (andmap positive? ws) (andmap negative? ws))
       (let* ([xs (map (lambda (p) (/ (vector-ref p 0) (vector-ref p 2))) raw)]
              [ys (map (lambda (p) (/ (vector-ref p 1) (vector-ref p 2))) raw)]
              [left (apply min xs)] [top (apply min ys)])
         (finite-vector (vector left top (- (apply max xs) left) (- (apply max ys) top))))))
(define (matrix4-map-rect m x y width height)
  (matrix3-map-rect (matrix4-project-xy m) x y width height))
