#lang racket/base
(require rackunit racket/list json
         "../portable-drawing.rkt" "../geometry-primitives.rkt" "../color.rkt"
         "../private/check.rkt" "../private/portable-util.rkt")
(provide portable-pure-tests)
(define (nine [w 30] [h 24]) (image-nine-plan 9 9 '(3 3 3 3) 0 0 w h))
(define (dst p i) (image-grid-cell-destination (list-ref p i)))
(define (src p i) (image-grid-cell-source (list-ref p i)))
(define (live-cell? c)
  (for/and ([v (in-list (list (image-grid-cell-source c) (image-grid-cell-destination c)))])
    (and (> (vector-ref v 2) 0) (> (vector-ref v 3) 0))))
(define portable-pure-tests
  (test-suite
   "Portable drawing: plans and validation"
   (test-case "nine cells are row-major"
     (define p (nine))
     (check-equal? (length p) 9)
     (check-equal? (map image-grid-cell-row p) '(0 0 0 1 1 1 2 2 2))
     (check-equal? (map image-grid-cell-column p) '(0 1 2 0 1 2 0 1 2)))
   (test-case "fixed borders do not stretch"
     (check-equal? (dst (nine) 0) '#(0.0 0.0 3.0 3.0))
     (check-equal? (dst (nine) 4) '#(3.0 3.0 24.0 18.0))
     (check-equal? (dst (nine) 8) '#(27.0 21.0 3.0 3.0)))
   (test-case "source rectangles are integer crops"
     (check-equal? (src (nine) 4) '#(3 3 3 3))
     (check-true (for/and ([c (in-list (nine))])
                   (for/and ([v (in-vector (image-grid-cell-source c))]) (exact-integer? v)))))
   (test-case "plan vectors are immutable"
     (check-true (immutable? (src (nine) 0)))
     (check-true (immutable? (dst (nine) 0)))
     (check-exn exn:fail? (lambda () (vector-set! (dst (nine) 0) 0 5))))
   (test-case "nonzero destination origin"
     (define p (image-nine-plan 9 9 '(3 3 3 3) -5 7 30 24))
     (check-equal? (dst p 4) '#(-2.0 10.0 24.0 18.0)))
   (test-case "small destination collapses stretch cells"
     (define p (nine 4 2))
     (check-equal? (dst p 4) '#(2.0 1.0 0.0 0.0))
     (check-equal? (length (filter live-cell? p)) 4))
   (test-case "asymmetric fixed strips shrink proportionally"
     (define p (image-nine-plan 12 10 '(2 3 6 5) 10 20 3 10))
     (check-equal? (dst p 0) '#(10.0 20.0 1.0 3.0))
     (check-equal? (dst p 2) '#(11.0 20.0 2.0 3.0)))
   (test-case "exact fixed extent produces zero center width"
     (check-equal? (vector-ref (dst (nine 6 24) 4) 2) 0.0))
   (test-case "center may touch image edges"
     (define p (image-nine-plan 9 9 '(0 0 9 9) 0 0 30 24))
     (check-equal? (length (filter live-cell? p)) 1)
     (check-equal? (dst p 4) '#(0.0 0.0 30.0 24.0)))
   (test-case "zero destination is a nonpainting plan"
     (check-equal? (length (filter live-cell? (nine 0 24))) 0))
   (test-case "empty source center rejected"
     (check-exn exn:fail? (lambda () (image-nine-plan 9 9 '(3 3 0 3) 0 0 30 24))))
   (test-case "source center outside image rejected"
     (check-exn exn:fail? (lambda () (image-nine-plan 9 9 '(8 3 3 3) 0 0 30 24))))
   (test-case "fractional source center rejected"
     (check-exn exn:fail? (lambda () (image-nine-plan 9 9 '(1/2 3 3 3) 0 0 30 24))))
   (test-case "source dimensions must be positive exact integers"
     (for ([n '(0 -1 9.0 3/2)])
       (check-exn exn:fail? (lambda () (image-nine-plan n 9 '(0 0 1 1) 0 0 30 24)))))
   (test-case "nonfinite destination rejected"
     (for ([n (list +inf.0 -inf.0 +nan.0)])
       (check-exn exn:fail? (lambda () (image-nine-plan 9 9 '(3 3 3 3) n 0 30 24)))))
   (test-case "negative destination extent rejected"
     (check-exn exn:fail? (lambda () (nine -1 24))))
   (test-case "plan budget is checked"
     (parameterize ([current-skia-byte-limit 64])
       (check-exn exn:fail? (lambda () (nine)))))
   (test-case "plan input is detached"
     (define center (vector 3 3 3 3))
     (define p (image-nine-plan 9 9 center 0 0 30 24))
     (vector-set! center 0 0)
     (check-equal? (src p 4) '#(3 3 3 3)))
   (test-case "ordinary lattice agrees with nine-patch"
     (define p (image-lattice-plan 9 9 (make-image-lattice '(3 6) '(3 6)) 0 0 30 24))
     (check-equal? p (nine)))
   (test-case "small lattice agrees with small nine-patch"
     (check-equal? (image-lattice-plan 9 9 (make-image-lattice '(3 6) '(3 6)) 0 0 4 2)
                   (nine 4 2)))
   (test-case "one undivided axis stretches as a whole"
     (define p (image-lattice-plan 9 9 (make-image-lattice '(3 6) '()) 5 7 30 24))
     (check-equal? (length p) 3)
     (check-equal? (dst p 1) '#(8.0 7.0 24.0 24.0)))
   (test-case "odd division count ends with a stretch span"
     (define p (image-lattice-plan 10 9 (make-image-lattice '(2 4 7) '()) 0 0 25 9))
     (check-equal? (map (lambda (c) (vector-ref (image-grid-cell-destination c) 2)) p)
                   '(2.0 8.0 3.0 12.0)))
   (test-case "subset lattice keeps source coordinates"
     (define l (make-image-lattice '(5 10) '(6 11) #:bounds '(2 3 12 12)))
     (define p (image-lattice-plan 20 20 l 0 0 30 30))
     (check-equal? (src p 0) '#(2 3 3 3))
     (check-equal? (src p 8) '#(10 11 4 4)))
   (test-case "divisions are checked against actual image bounds"
     (define l (make-image-lattice '(3 12) '(3 6)))
     (check-exn exn:fail? (lambda () (image-lattice-plan 9 9 l 0 0 30 24))))
   (test-case "transparent and fixed-color cells retain their kinds"
     (define l (make-image-lattice '(3 6) '() #:cell-types '(default transparent fixed-color)
                                   #:colors '(black black #x80ff0000)))
     (define p (image-lattice-plan 9 9 l 0 0 30 24))
     (check-equal? (map image-grid-cell-kind p) '(default transparent fixed-color))
     (check-equal? (image-grid-cell-color (list-ref p 2)) (rgba 255 0 0 128))
     (check-false (image-grid-cell-color (car p))))
   (test-case "fixed-color cannot be constructed without colors"
     (check-exn exn:fail? (lambda () (make-image-lattice '(3) '() #:cell-types '(fixed-color default)))))
   (test-case "wrong lattice value rejected"
     (check-exn exn:fail? (lambda () (image-lattice-plan 9 9 #f 0 0 30 24))))
   (test-case "cell destination edges join exactly"
     (define p (image-lattice-plan 10 9 (make-image-lattice '(2 4 7) '()) 0.25 0 24.7 9))
     (for ([a (in-list p)] [b (in-list (cdr p))])
       (define ad (image-grid-cell-destination a))
       (check-equal? (+ (vector-ref ad 0) (vector-ref ad 2))
                     (vector-ref (image-grid-cell-destination b) 0))))
   (test-case "plan serialization is JSON safe"
     (define data (image-grid-plan->jsexpr (nine)))
     (check-not-exn (lambda () (jsexpr->string data)))
     (check-equal? (hash-ref (car data) 'kind) "default"))
   (test-case "serializer rejects fabricated plans"
     (check-exn exn:fail? (lambda () (image-grid-plan->jsexpr '(#f)))))
   (test-case "empty serialized plan is allowed"
     (check-equal? (image-grid-plan->jsexpr '()) '()))
   (test-case "marker size describes centered geometry"
     (check-equal? (portable-marker-boxes 'test '((5 8)) 4 'circle) '(#(3.0 6.0 4.0 4.0))))
   (test-case "marker point vectors are copied"
     (define point (vector 5 8))
     (define boxes (portable-marker-boxes 'test (vector point) 4 'square))
     (vector-set! point 0 99)
     (check-equal? boxes '(#(3.0 6.0 4.0 4.0))))
   (test-case "marker unknown shape rejected"
     (check-exn exn:fail? (lambda () (portable-marker-boxes 'test '((0 0)) 4 'triangle))))
   (test-case "marker zero and negative sizes rejected"
     (for ([n '(0 -1)])
       (check-exn exn:fail? (lambda () (portable-marker-boxes 'test '((0 0)) n 'square)))))
   (test-case "marker malformed last point rejected"
     (check-exn exn:fail? (lambda () (portable-marker-boxes 'test '((0 0) (1 2 3)) 4 'circle))))
   (test-case "marker overflow rejected before drawing"
     (check-exn exn:fail? (lambda () (portable-marker-boxes 'test '((3.4e38 0)) 3.4e38 'circle))))
   (test-case "marker empty batch allowed"
     (check-equal? (portable-marker-boxes 'test '() 4 'circle) '()))
   (test-case "portable sampling rejects other modes"
     (check-eq? (portable-filter 'test 'nearest) 'nearest)
     (check-eq? (portable-filter 'test 'linear) 'linear)
     (check-exn exn:fail? (lambda () (portable-filter 'test 'cubic))))
   (test-case "portable alpha uses bytes not normalized floats"
     (check-equal? (portable-alpha 'test 128) 128)
     (for ([a '(256 -1 0.5 255.0)])
       (check-exn exn:fail? (lambda () (portable-alpha 'test a)))))))
