#lang racket/base
(require rackunit rackunit/text-ui racket/list "../matrix.rkt" "../projective-matrix.rkt"
         "../output-policy.rkt" "../private/audit-trace.rkt"
         (submod "../private/audit-trace.rkt" testing))
(provide projective-pure-tests)
(define (check-vector-close a b tolerance)
  (check-equal? (vector-length a) (vector-length b))
  (for ([x (in-vector a)] [y (in-vector b)]) (check-= x y tolerance)))
(define (capture backend policy thunk)
  (define-values (_ report) (call-with-audit-collector backend policy #f 1 thunk)) report)
(define (fake-matrix-call backend general? thunk)
  (define h (audit-allocate 'make-surface 'surface (lambda () (box 'surface))))
  (audit-on-canvas 'canvas-concat-matrix4! 'owner backend h '()
    (lambda () (call-with-audit-matrix general?
      (lambda () (audit-native-call 'sk_canvas_concat '() thunk))))))
(define projective-pure-tests
  (test-suite "Perspective and general matrices: pure values and audit policy"
   (test-case "new matrix types leave the affine type unchanged"
     (check-true (matrix3? matrix3-identity))
     (check-true (matrix4? matrix4-identity))
     (check-false (matrix? matrix3-identity))
     (check-false (matrix3? matrix4-identity))
   )
   (test-case "3x3 coefficients are row-major"
     (define m (apply make-matrix3 (range 1 10)))
     (check-equal? (matrix3->vector m) #(1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0))
     (check-equal? (matrix3-ref m 1 2) 6.0)
   )
   (test-case "4x4 coefficients are row-major"
     (define m (apply make-matrix4 (range 1 17)))
     (check-equal? (matrix4-ref m 0 3) 4.0)
     (check-equal? (matrix4-ref m 3 0) 13.0)
     (check-equal? (matrix4-ref m 2 3) 12.0)
   )
   (test-case "constructors detach mutable vectors"
     (define v (make-vector 9 1)) (define m (vector->matrix3 v))
     (vector-set! v 0 99) (check-equal? (matrix3-ref m 0 0) 1.0)
     (define w (make-vector 16 2)) (define n (vector->matrix4 w))
     (vector-set! w 0 99) (check-equal? (matrix4-ref n 0 0) 2.0)
   )
   (test-case "matrix inspection vectors are immutable"
     (check-true (immutable? (matrix3->vector matrix3-identity)))
     (check-true (immutable? (matrix4->vector matrix4-identity)))
     (check-exn exn:fail:contract? (lambda () (vector-set! (matrix4->vector matrix4-identity) 0 3)))
   )
   (test-case "vector lengths are checked"
     (for ([v (list #() #(1 2 3) (make-vector 16))])
       (check-exn exn:fail:contract? (lambda () (vector->matrix3 v))))
     (check-exn exn:fail:contract? (lambda () (vector->matrix4 (make-vector 9))))
   )
   (test-case "nonvector and wrong matrix types reject"
     (check-exn exn:fail:contract? (lambda () (vector->matrix3 '(1 2 3))))
     (check-exn exn:fail:contract? (lambda () (matrix3-compose matrix4-identity)))
     (check-exn exn:fail:contract? (lambda () (matrix4-invert matrix-identity)))
   )
   (test-case "NaN infinities complex and nonnumeric coefficients reject"
     (for ([x (list +nan.0 +inf.0 -inf.0 1+2i 'x #f)])
       (check-exn exn:fail:contract? (lambda () (make-matrix3 x)))
       (check-exn exn:fail:contract? (lambda () (make-matrix4 x))))
   )
   (test-case "coefficients outside the native float range reject"
     (check-exn exn:fail:contract? (lambda () (make-matrix3 1e39)))
     (check-exn exn:fail:contract? (lambda () (make-matrix4 -1e39)))
   )
   (test-case "coefficients snapshot native single precision"
     (check-equal? (matrix3-ref (make-matrix3 16777217) 0 0) 16777216.0)
     (check-equal? (matrix4-ref (make-matrix4 1/10) 0 0)
                   (floating-point-bytes->real (real->floating-point-bytes 1/10 4 #f) #f))
   )
   (test-case "largest finite native coefficient survives a second snapshot"
     (define m (make-matrix4 3.4028234663852886e38))
     (check-equal? (vector->matrix4 (matrix4->vector m)) m)
     (check-false (matrix4->matrix m)))
   (test-case "indices are exact integers in range"
     (for ([bad (list -1 3 1.0 'x)])
       (check-exn exn:fail:contract? (lambda () (matrix3-ref matrix3-identity bad 0))))
     (check-exn exn:fail:contract? (lambda () (matrix4-ref matrix4-identity 0 4)))
   )
   (test-case "empty composition is identity"
     (check-equal? (matrix3-compose) matrix3-identity)
     (check-equal? (matrix4-compose) matrix4-identity)
   )
   (test-case "3x3 composition applies rightmost first"
     (define t (matrix->matrix3 (matrix-translate 10 20)))
     (define s (matrix->matrix3 (matrix-scale 2 3)))
     (check-equal? (matrix3-map-point (matrix3-compose t s) 4 5) #(18.0 35.0))
     (check-equal? (matrix3-map-point (matrix3-compose s t) 4 5) #(28.0 75.0))
   )
   (test-case "4x4 composition applies rightmost first"
     (define t (matrix4-translate 10 20 30)) (define s (matrix4-scale 2 3 4))
     (check-equal? (matrix4-map-point (matrix4-compose t s) 4 5 6) #(18.0 35.0 54.0))
     (check-equal? (matrix4-map-point (matrix4-compose s t) 4 5 6) #(28.0 75.0 144.0))
   )
   (test-case "3x3 transpose is an involution"
     (define m (apply make-matrix3 (range 1 10)))
     (check-equal? (matrix3->vector (matrix3-transpose m)) #(1.0 4.0 7.0 2.0 5.0 8.0 3.0 6.0 9.0))
     (check-equal? (matrix3-transpose (matrix3-transpose m)) m)
   )
   (test-case "4x4 transpose is an involution"
     (define m (apply make-matrix4 (range 1 17)))
     (check-equal? (matrix4-ref (matrix4-transpose m) 1 0) 2.0)
     (check-equal? (matrix4-transpose (matrix4-transpose m)) m)
   )
   (test-case "3x3 inverse includes perspective coefficients"
     (define m (make-matrix3 2 1 4 0 3 5 0.125 0.25 1))
     (define inv (matrix3-invert m)) (check-true (matrix3? inv))
     (check-vector-close (matrix3->vector (matrix3-compose m inv)) (matrix3->vector matrix3-identity) 1e-5)
   )
   (test-case "4x4 inverse includes retained depth"
     (define m (matrix4-compose (matrix4-perspective 200) (matrix4-rotate-y-degrees 30)
                                (matrix4-translate 20 30 10) (matrix4-scale 2 3 4)))
     (define inv (matrix4-invert m)) (check-true (matrix4? inv))
     (check-vector-close (matrix4->vector (matrix4-compose m inv)) (matrix4->vector matrix4-identity) 1e-5)
   )
   (test-case "singular inverses return false"
     (check-false (matrix3-invert (make-matrix3 0 0 0 0 0 0 0 0 0)))
     (check-false (matrix4-invert (matrix4-scale 1 1 0)))
   )
   (test-case "unrepresentable inverses return false"
     (check-false (matrix3-invert (make-matrix3 1e-40)))
     (check-false (matrix4-invert (matrix4-scale 1e-40 1 1)))
   )
   (test-case "there is no arbitrary singularity epsilon"
     (check-true (matrix3? (matrix3-invert (make-matrix3 1e-20))))
     (check-true (matrix4? (matrix4-invert (matrix4-scale 1e-20 1 1))))
   )
   (test-case "matrix composition rejects result overflow"
     (check-exn exn:fail:contract? (lambda () (matrix3-compose (make-matrix3 1e30) (make-matrix3 1e30))))
     (check-exn exn:fail:contract? (lambda () (matrix4-compose (matrix4-scale 1e30) (matrix4-scale 1e30))))
   )
   (test-case "legacy six-coefficient conversion preserves order"
     (define m (make-matrix 2 3 4 5 6 7))
     (check-equal? (matrix3->vector (matrix->matrix3 m)) #(2.0 4.0 6.0 3.0 5.0 7.0 0.0 0.0 1.0))
     (check-equal? (matrix3->matrix (matrix->matrix3 m)) m)
   )
   (test-case "affine homogeneous scale can be normalized explicitly"
     (define m (make-matrix3 -2 0 -8 0 -4 -12 0 0 -2))
     (check-true (matrix3-affine? m))
     (check-equal? (matrix3->matrix m) (make-matrix 1 0 0 2 4 6))
   )
   (test-case "nonaffine and zero homogeneous scale do not convert to affine"
     (check-false (matrix3->matrix (matrix3-perspective 1 0)))
     (check-false (matrix3-affine? (make-matrix3 1 0 0 0 1 0 0 0 0)))
     (check-false (matrix3->matrix (make-matrix3 1 0 0 0 1 0 0 0 0)))
   )
   (test-case "legacy affine 4x4 round trip is lossless"
     (define a (make-matrix 2 3 4 5 6 7))
     (check-true (matrix4-affine-2d? (matrix->matrix4 a)))
     (check-equal? (matrix4->matrix (matrix->matrix4 a)) a)
   )
   (test-case "affine 4x4 conversion refuses retained depth"
     (check-false (matrix4->matrix (matrix4-translate 0 0 2)))
     (check-false (matrix4-affine-2d? (matrix4-rotate-y-degrees 30)))
     (check-false (matrix4->matrix (matrix4-perspective 100)))
   )
   (test-case "3x3 embedding preserves all nine coefficients"
     (define m (apply make-matrix3 (range 1 10)))
     (check-equal? (matrix4->vector (matrix3->matrix4 m))
                   #(1.0 2.0 0.0 3.0 4.0 5.0 0.0 6.0 0.0 0.0 1.0 0.0 7.0 8.0 0.0 9.0))
     (check-equal? (matrix4->matrix3 (matrix3->matrix4 m)) m)
   )
   (test-case "lossless 4x4 to 3x3 conversion rejects z changes"
     (check-false (matrix4->matrix3 (matrix4-translate 0 0 1)))
     (check-false (matrix4->matrix3 (matrix4-scale 1 1 2)))
     (check-false (matrix4->matrix3 (matrix4-perspective 100)))
   )
   (test-case "explicit plane projection selects the XYW rows and columns"
     (define m (apply make-matrix4 (range 1 17)))
     (check-equal? (matrix3->vector (matrix4-project-xy m)) #(1.0 2.0 4.0 5.0 6.0 8.0 13.0 14.0 16.0))
   )
   (test-case "homogeneous 3x3 mapping does not divide"
     (check-equal? (matrix3-map-homogeneous (matrix3-perspective 0.5 0) 2 6) #(2.0 6.0 2.0))
   )
   (test-case "projected 3x3 points divide by W"
     (check-equal? (matrix3-map-point (matrix3-perspective 0.5 0) 2 6) #(1.0 3.0))
     (check-true (immutable? (matrix3-map-point matrix3-identity 1 2)))
   )
   (test-case "homogeneous directions explicitly use w zero"
     (check-equal? (matrix3-map-homogeneous (matrix->matrix3 (matrix-translate 10 20)) 2 3 0) #(2.0 3.0 0.0))
     (check-equal? (matrix4-map-homogeneous (matrix4-translate 10 20 30) 2 3 4 0) #(2.0 3.0 4.0 0.0))
   )
   (test-case "points on a horizon return false"
     (check-false (matrix3-map-point (matrix3-perspective 0.5 0) -2 6))
   )
   (test-case "negative W is mathematically projectable not a visibility claim"
     (check-equal? (matrix3-map-point (matrix3-perspective 0.5 0) -4 2) #(4.0 -2.0))
   )
   (test-case "finite projected rectangle uses corner extrema"
     (check-equal? (matrix3-map-rect (matrix3-perspective 0.5 0) 0 0 2 2) #(0.0 0.0 1.0 2.0))
   )
   (test-case "horizon crossing rectangle has no finite bounds"
     (check-false (matrix3-map-rect (matrix3-perspective 0.5 0) -3 0 2 2))
   )
   (test-case "horizon touching rectangle is also unavailable"
     (check-false (matrix3-map-rect (matrix3-perspective 0.5 0) -2 0 1 2))
   )
   (test-case "rectangle entirely behind the horizon has mathematical bounds"
     (check-equal? (matrix3-map-rect (matrix3-perspective 0.5 0) -6 0 2 2) #(3.0 -2.0 1.0 2.0))
   )
   (test-case "negative rectangle extents reject"
     (check-exn exn:fail:contract? (lambda () (matrix3-map-rect matrix3-identity 0 0 -1 2)))
     (check-exn exn:fail:contract? (lambda () (matrix4-map-rect matrix4-identity 0 0 1 -2)))
   )
   (test-case "degenerate finite rectangles are allowed"
     (check-equal? (matrix3-map-rect matrix3-identity 1 2 0 0) #(1.0 2.0 0.0 0.0))
   )
   (test-case "full homogeneous 4x4 mapping retains depth"
     (check-equal? (matrix4-map-homogeneous (apply make-matrix4 (range 1 17)) 1 2 3) #(18.0 46.0 74.0 102.0))
   )
   (test-case "camera distance controls the homogeneous divide"
     (check-vector-close (matrix4-map-point (matrix4-perspective 10) 4 6 10) #(2.0 3.0 5.0) 1e-6)
   )
   (test-case "4x4 horizon points return false"
     (check-false (matrix4-map-point (matrix4-perspective 8) 4 6 -8))
   )
   (test-case "4x4 rectangle mapping means the drawing plane z zero"
     (define m (matrix4-compose (matrix4-perspective 100) (matrix4-rotate-y-degrees 30)))
     (check-equal? (matrix4-map-rect m 0 0 20 20) (matrix3-map-rect (matrix4-project-xy m) 0 0 20 20))
   )
   (test-case "quarter turns follow the documented axis signs"
     (check-equal? (matrix4-map-point (matrix4-rotate-x-degrees 90) 1 2 3) #(1.0 -3.0 2.0))
     (check-equal? (matrix4-map-point (matrix4-rotate-y-degrees 90) 1 2 3) #(3.0 2.0 -1.0))
     (check-equal? (matrix4-map-point (matrix4-rotate-z-degrees 90) 1 2 3) #(-2.0 1.0 3.0))
   )
   (test-case "2D convenience defaults do not change z"
     (check-equal? (matrix4-map-point (matrix4-scale 2) 1 2 3) #(2.0 4.0 3.0))
     (check-equal? (matrix4-map-point (matrix4-translate 2 3) 1 2 3) #(3.0 5.0 3.0))
   )
   (test-case "rotation angle normalization preserves quarter turns"
     (check-equal? (matrix4-rotate-y-degrees -90) (matrix4-rotate-y-degrees 270))
     (check-equal? (matrix4-rotate-x-degrees 450) (matrix4-rotate-x-degrees 90))
   )
   (test-case "camera distance must be positive with representable reciprocal"
     (for ([d (list 0 -1 +inf.0 1e-45)])
       (check-exn exn:fail:contract? (lambda () (matrix4-perspective d))))
   )
   (test-case "projecting before composition loses retained depth"
     (define a (matrix4-perspective 100)) (define b (matrix4-rotate-y-degrees 45))
     (define full (matrix4-project-xy (matrix4-compose a b)))
     (define early (matrix3-compose (matrix4-project-xy a) (matrix4-project-xy b)))
     (check-false (equal? (matrix3-map-point full 20 10) (matrix3-map-point early 20 10)))
   )
   (test-case "mapping inputs obey the same finite native coordinate contract"
     (check-exn exn:fail:contract? (lambda () (matrix3-map-point matrix3-identity +inf.0 0)))
     (check-exn exn:fail:contract? (lambda () (matrix4-map-homogeneous matrix4-identity 0 0 +nan.0)))
   )
   (test-case "affine normalization and canonical 4x4 recognition are distinct"
     (define p (make-matrix3 2 0 0 0 2 0 0 0 2))
     (check-true (matrix3-affine? p))
     (check-false (matrix4-affine-2d? (matrix3->matrix4 p)))
   )
   (test-case "general matrix feature is scoped to its native call"
     (check-equal? (call-with-audit-matrix #t (lambda () (native-feature 'sk_canvas_concat '()))) '(transform projective-transform))
     (check-equal? (native-feature 'sk_canvas_concat '()) '(transform))
     (check-equal? (native-feature 'sk_canvas_get_matrix '()) #f)
   )
   (test-case "general matrix policy blocks both document backends"
     (for ([backend '(pdf svg)])
       (check-eq? (output-capability-status (output-capability-for backend 'projective-transform)) 'needs-raster))
   )
   (test-case "strict matrix rejection occurs before the native call"
     (define ran? #f)
     (for ([backend '(pdf svg)])
       (check-exn exn:fail:output-audit?
         (lambda () (capture backend 'error
           (lambda () (fake-matrix-call backend #t (lambda () (set! ran? #t))))))))
     (check-false ran?)
   )
   (test-case "affine general-matrix calls remain vector-only"
     (define r (capture 'svg 'vector-only (lambda () (fake-matrix-call 'svg #f void))))
     (check-true (output-audit-report-vector-only? r))
   )
   (test-case "picture provenance records general matrices without a collector"
     (define h (audit-allocate 'make-picture-recorder 'picture-recorder (lambda () (box 'rec))))
     (audit-on-canvas 'canvas-concat-matrix4! 'owner 'recording h '()
       (lambda () (call-with-audit-matrix #t
         (lambda () (audit-native-call 'sk_canvas_concat '() void)))))
     (check-not-false (memq 'projective-transform (features h)))
   )
   (test-case "explicit raster scope classifies the matrix as rasterized"
     (define r (capture 'svg 'error
       (lambda () (call-with-audit-raster 'svg 40 40 (hasheq)
         (lambda () (fake-matrix-call 'raster #t void))))))
     (check-true (for/or ([e (in-list (output-audit-report-events r))])
                   (and (eq? (output-audit-event-feature e) 'projective-transform)
                        (eq? (output-audit-event-status e) 'rasterized))))
   )
))
(module+ test
  (unless (zero? (run-tests projective-pure-tests)) (error 'projective-pure-tests "test failure")))
