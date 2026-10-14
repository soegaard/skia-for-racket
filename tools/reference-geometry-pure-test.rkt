#lang racket/base

;; Public value/expansion tests. These cases do not load the Skia native library.
(require rackunit racket/list racket/vector skia)

(define-namespace-anchor expansion-anchor)
(define (expand-geometry-form form)
  (parameterize ([current-namespace (namespace-anchor->namespace expansion-anchor)])
    (expand (datum->syntax #f form))))

(module+ test
  (test-case "projective matrices copy row-major coefficients"
    (define source (vector 1 0 3 0 1 4 0 0 1))
    (define matrix (vector->matrix3 source))
    (vector-set! source 2 99)
    (check-equal? (matrix3-ref matrix 0 2) 3.0)
    (check-equal? (matrix3-map-point matrix 2 5) #(5.0 9.0))
    (check-true (immutable? (matrix3->vector matrix)))
    (check-false (matrix4? matrix))
    (check-exn exn:fail? (lambda () (matrix3-ref matrix 3 0))))

  (test-case "projective composition applies the rightmost transform first"
    (define shift (matrix4-translate 10 20))
    (define scale (matrix4-scale 2 3))
    (check-equal? (matrix4-map-point (matrix4-compose shift scale) 1 2) #(12.0 26.0 0.0))
    (check-equal? (matrix4-map-point (matrix4-compose scale shift) 1 2) #(22.0 66.0 0.0))
    (check-equal? (matrix3-compose) matrix3-identity)
    (check-equal? (matrix4-compose) matrix4-identity))

  (test-case "homogeneous mapping and horizon rejection are different queries"
    (define matrix (matrix3-perspective 1 0))
    (check-equal? (matrix3-map-point matrix 1 2) #(0.5 1.0))
    (check-equal? (matrix3-map-homogeneous matrix -1 2) #(-1.0 2.0 0.0))
    (check-false (matrix3-map-point matrix -1 2))
    (check-false (matrix3-map-rect matrix -2 0 2 1))
    (check-equal? (matrix3-map-point matrix -2 2) #(2.0 -2.0)))

  (test-case "lossless embedding differs from plane projection"
    (define matrix (matrix4-translate 3 4 5))
    (check-false (matrix4->matrix3 matrix))
    (check-false (matrix4->matrix matrix))
    (check-equal? (matrix3-map-point (matrix4-project-xy matrix) 0 0) #(3.0 4.0))
    (define p (matrix3-perspective 1/8 1/4))
    (check-equal? (matrix4->matrix3 (matrix3->matrix4 p)) p))

  (test-case "affine recognition includes nonunit homogeneous scale only where specified"
    (define matrix (make-matrix3 2 0 6 0 2 8 0 0 2))
    (check-true (matrix3-affine? matrix))
    (check-equal? (matrix3->matrix matrix) (matrix-translate 3 4))
    (check-false (matrix4-affine-2d? (matrix3->matrix4 matrix)))
    (check-false (matrix4->matrix (matrix3->matrix4 matrix))))

  (test-case "inversion is exact on stored inputs and bounded on output"
    (check-false (matrix3-invert (make-matrix3 0)))
    (check-false (matrix4-invert (matrix4-scale 0)))
    (check-false (matrix4-invert (matrix4-scale 1e-40)))
    (check-equal? (matrix4-invert (matrix4-translate 2 3 4)) (matrix4-translate -2 -3 -4))
    (check-equal? (matrix4-compose (matrix4-scale 2) (matrix4-invert (matrix4-scale 2)))
                  matrix4-identity))

  (test-case "binary32 storage and finite input rejection"
    (define rounded (floating-point-bytes->real (real->floating-point-bytes 1/10 4 #f) #f))
    (check-equal? (matrix3-ref (make-matrix3 1/10) 0 0) rounded)
    (for ([value (in-list (list +nan.0 +inf.0 -inf.0 1e100))])
      (check-exn exn:fail? (lambda () (make-matrix3 value))))
    (check-exn exn:fail? (lambda () (matrix4-perspective 1e-100)))
    (check-exn exn:fail? (lambda () (vector->matrix4 #(1 2 3)))))

  (test-case "rotation constructors preserve exact quarter turns"
    (check-equal? (matrix4-map-point (matrix4-rotate-z-degrees 90) 3 2) #(-2.0 3.0 0.0))
    (check-equal? (matrix4-map-point (matrix4-rotate-x-degrees 90) 0 1 0) #(0.0 0.0 1.0))
    (check-equal? (matrix4-map-point (matrix4-rotate-y-degrees 90) 1 0 0) #(0.0 0.0 -1.0)))

  (test-case "rounded rectangle specifications copy unnormalized radii"
    (define corner (vector 30 30))
    (define shape (make-rounded-rect 0 0 20 10 #:radii (vector corner corner corner corner)))
    (vector-set! corner 0 1)
    (check-equal? (vector-ref (rounded-rect-radii shape) 0) #(30.0 30.0))
    (check-true (immutable? (rounded-rect-radii shape)))
    (check-true (immutable? (vector-ref (rounded-rect-radii shape) 0)))
    (check-false (skia-resource? shape))
    (check-equal? (rounded-rect-bounds (make-empty-rounded-rect)) #(0.0 0.0 0.0 0.0)))

  (test-case "layer options are detached flags rather than resources"
    (define bounds (vector 1 2 3 4))
    (define options (make-layer-options #:bounds bounds #:preserve-lcd-text? #t
                                        #:initialize-with-previous? #t #:f16? #t))
    (vector-set! bounds 0 50)
    (check-equal? (layer-options-bounds options) #(1.0 2.0 3.0 4.0))
    (check-equal? (layer-options-flags options) 22)
    (check-false (skia-resource? options))
    (check-true (layer-options-f16? options))
    (check-exn exn:fail? (lambda () (make-layer-options #:f16? 'yes))))

  (test-case "grid plans keep fixed borders and share destination edges"
    (define plan (image-nine-plan 10 10 '(2 2 6 6) 0 0 20 20))
    (check-equal? (length plan) 9)
    (check-equal? (image-grid-cell-source (list-ref plan 4)) #(2 2 6 6))
    (check-equal? (image-grid-cell-destination (list-ref plan 4)) #(2.0 2.0 16.0 16.0))
    (check-equal? (image-grid-cell-row (list-ref plan 4)) 1)
    (check-equal? (image-grid-cell-column (list-ref plan 4)) 1)
    (define small (image-nine-plan 10 10 '(2 2 6 6) 0 0 2 2))
    (check-equal? (image-grid-cell-destination (list-ref small 4)) #(1.0 1.0 0.0 0.0)))

  (test-case "lattice cell styles cover the full grid"
    (define lattice (make-image-lattice '(2) '() #:cell-types '(fixed-color transparent)
                                       #:colors '(red blue)))
    (define plan (image-lattice-plan 4 4 lattice 0 0 8 8))
    (check-equal? (map image-grid-cell-kind plan) '(fixed-color transparent))
    (check-equal? (color->argb (image-grid-cell-color (car plan))) #xffff0000)
    (check-false (image-grid-cell-color (cadr plan)))
    (check-exn exn:fail?
               (lambda () (make-image-lattice '(2) '() #:cell-types '(fixed-color default))))
    (check-exn exn:fail? (lambda () (make-image-lattice '(2 2) '())))
    (check-exn exn:fail? (lambda () (make-image-lattice '() '()))))

  (test-case "cubic patch copies twelve points and four corner colors"
    (define point (vector 0 0))
    (define patch (make-cubic-patch (make-list 12 point) #:colors '(red green blue white)))
    (vector-set! point 0 99)
    (check-equal? (vector-ref (cubic-patch-points patch) 0) #(0.0 0.0))
    (check-true (immutable? (cubic-patch-points patch)))
    (check-exn exn:fail? (lambda () (make-cubic-patch (make-list 11 point))))
    (check-exn exn:fail?
               (lambda () (make-cubic-patch (make-list 12 point) #:colors '(red)))))

  (test-case "scoped macro grammars require nonempty expression-ending bodies"
    (for ([form (in-list
                 '((with-canvas-matrix (error 'not-run) matrix4-identity (void))
                   (with-canvas-matrix (error 'not-run) matrix4-identity #:replace? #t
                     (define n 2) (values n n))
                   (with-canvas-layer (error 'not-run) #:paint #f #:bounds '(0 0 2 2)
                     (define n 2) n)
                   (with-canvas-layer (error 'not-run) #:bounds #f #:paint #f (void))))])
      (check-not-exn (lambda () (expand-geometry-form form))))
    (for ([form (in-list '((with-canvas-matrix (error 'not-run) matrix4-identity)
                           (with-canvas-layer (error 'not-run))
                           (with-canvas-layer (error 'not-run) (define n 2))))])
      (check-exn exn:fail:syntax? (lambda () (expand-geometry-form form)))))

  (test-case "path operation limit rejects invalid settings without native calls"
    (parameterize ([current-path-operation-limit 2])
      (check-equal? (current-path-operation-limit) 2))
    (for ([bad '(0 -1 1.5 2147483648)])
      (check-exn exn:fail? (lambda () (current-path-operation-limit bad))))))
