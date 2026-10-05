#lang racket/base
(require rackunit rackunit/text-ui racket/list
         "../main.rkt" "geometry-completion-fixtures.rkt")
(provide geometry-completion-native-tests)
(define (point-close? a b)
  (and (= (length a) (length b)) (for/and ([x (in-list a)] [y (in-list b)]) (< (abs (- x y)) 0.01))))
;; Use the existing path segment snapshots for an independent endpoint oracle.
(define (last-xy p)
  (last (path-segment-points
         (last (filter (lambda (s) (pair? (path-segment-points s))) (path-segments p #:mode 'raw))))))
(define geometry-completion-native-tests
  (test-suite
   "0.67 native path, region, rounded-rectangle and paint geometry"
   (test-case "absolute arc reaches endpoint and emits conics"
     (with-skia ([p (make-path '((move 0 0)))])
       (path-arc-to! p 10 10 0 20 0)
       (check-true (point-close? (last-xy p) '(20 0)))
       (check-not-false (memq 'conic (path-segment-kinds p)))))
   (test-case "relative arc offsets the endpoint"
     (with-skia ([p (make-path '((move 5 8)))])
       (path-rarc-to! p 10 10 0 20 0 #:direction 'ccw)
       (check-true (point-close? (last-xy p) '(25 8)))))
   (test-case "zero-radius endpoint arc degenerates to a line"
     (with-skia ([p (make-path '((move 1 2)))])
       (path-arc-to! p 0 4 0 11 12)
       (check-true (point-close? (last-xy p) '(11 12)))
       (check-equal? (path-segment-kinds p) '(line))))
   (test-case "invalid arc cannot modify its destination"
     (with-skia ([p (make-path '((move 1 2)))])
       (define before (path->commands p))
       (check-exn exn:fail:contract? (lambda () (path-arc-to! p -1 4 0 11 12)))
       (check-equal? (path->commands p) before)))
   (test-case "oval arc force-move starts another contour"
     (with-skia ([p (make-path '((move 0 0) (line 1 1)))])
       (path-arc-to-oval! p 0 0 20 20 0 90 #:force-move? #t)
       (check-equal? (length (path-contours p #:mode 'raw)) 2)
       (check-true (point-close? (last-xy p) '(10 20)))))
   (test-case "tangent arc with zero radius reaches the corner"
     (with-skia ([p (make-path '((move 0 0)))])
       (path-tangent-arc-to! p 10 0 10 10 0)
       (check-true (point-close? (last-xy p) '(10 0)))))
   (test-case "add-arc starts a disconnected contour"
     (with-skia ([p (make-path '((move 0 0) (line 1 1)))])
       (path-add-arc! p 0 0 20 20 0 90)
       (check-equal? (length (path-contours p #:mode 'raw)) 2)))
   (test-case "rectangle start index and direction are retained"
     (with-skia ([p (make-path)])
       (path-add-rect-start! p 8 8 32 24 1 #:direction 'ccw)
       (define r (path-as-rectangle p))
       (check-true (path-rectangle? r))
       (check-equal? (path-rectangle-bounds r) '#(8.0 8.0 32.0 24.0))
       (check-true (path-rectangle-closed? r))
       (check-eq? (path-rectangle-direction r) 'ccw)
       (check-equal? (car (path-segment-points (car (path-segments p #:mode 'raw)))) '(40.0 8.0))))
   (test-case "line and oval recognition return detached values"
     (with-skia ([p (make-path '((move 1 2) (line 3 4)))] [o (make-path)])
       (define line (path-as-line p))
       (path-add-oval! o 0 0 20 10)
       (define oval (path-as-oval o))
       (skia-close! p) (skia-close! o)
       (check-equal? line '#(#(1.0 2.0) #(3.0 4.0)))
       (check-equal? oval '#(0.0 0.0 20.0 10.0))))
   (test-case "failed recognition returns false rather than uninitialized buffers"
     (with-skia ([p (make-path '((move 0 0) (cubic 0 10 10 10 10 0)))])
       (check-false (path-as-line p)) (check-false (path-as-rectangle p))
       (check-false (path-as-oval p)) (check-false (path-as-rounded-rect p))))
   (test-case "polygon snapshots its input and closes only when requested"
     (define points (vector (vector 0 0) (vector 10 0) (vector 10 10)))
     (with-skia ([p (make-path)])
       (path-add-polygon! p points #:closed? #t)
       (vector-set! (vector-ref points 0) 0 99)
       (check-equal? (path-verbs p) '(move line line close))))
   (test-case "empty polygon still validates a closed destination"
     (define p (make-path)) (skia-close! p)
     (check-exn exn:fail? (lambda () (path-add-polygon! p '()))))
   (test-case "transformed append does not modify the source"
     (with-skia ([source (make-path '((move 1 2) (line 3 4)))] [out (make-path)])
       (path-add-transformed! out source (make-matrix 2 0 0 3 5 6))
       (check-equal? (path-as-line out) '#(#(7.0 12.0) #(11.0 18.0)))
       (check-equal? (path-as-line source) '#(#(1.0 2.0) #(3.0 4.0)))))
   (test-case "rewind empties path but retained snapshots survive"
     (with-skia ([p (make-path '((move 1 2) (line 3 4)))])
       (define old (path-verbs p)) (path-rewind! p)
       (check-equal? (path-point-count p) 0) (check-equal? (path-verbs p) '())
       (check-equal? old '(move line))))
   (test-case "path-ops bounds returns checked rectangle"
     (with-skia ([p (make-path)])
       (path-add-rect! p 2 3 10 20)
       (check-equal? (path-fill-bounds p) '#(2.0 3.0 10.0 20.0))))
   (test-case "unit-weight conic at power zero is one exact quadratic"
     (check-equal? (conic->quadratics '(0 0) '(10 20) '(20 0) 1 #:subdivisions 0)
                   '(#(#(0.0 0.0) #(10.0 20.0) #(20.0 0.0)))))
   (test-case "conic subdivisions meet at shared endpoints"
     (define qs (conic->quadratics '(0 0) '(10 20) '(20 0) 0.75 #:subdivisions 3))
     (check-true (<= 1 (length qs) 8))
     (for ([a (in-list qs)] [b (in-list (cdr qs))])
       (check-equal? (vector-ref a 2) (vector-ref b 0))))
   (test-case "heterogeneous batch starts with empty and preserves inputs"
     (with-skia ([a (make-path)] [b (make-path)])
       (path-add-rect! a 0 0 20 20) (path-add-rect! b 5 5 10 10)
       (with-skia ([out (path-combine (list (list 'union a) (list 'difference b)))])
         (check-true (path-contains? out 2 2)) (check-false (path-contains? out 10 10))
         (check-true (path-contains? a 10 10)))))
   (test-case "empty batch returns an owned empty path"
     (with-skia ([p (path-combine '())]) (check-equal? (path-point-count p) 0)))
   (test-case "batch rejects closed sources before native builder construction"
     (define p (make-path)) (skia-close! p)
     (check-exn exn:fail? (lambda () (path-combine (list (list 'union p))))))
   (test-case "paint queries match supplied stroke state"
     (with-skia ([p (make-paint #:style 'stroke #:stroke-width 8)])
       (paint-set-cap! p 'round) (paint-set-join! p 'bevel) (paint-set-miter-limit! p 7)
       (check-eq? (paint-style p) 'stroke) (check-equal? (paint-stroke-width p) 8.0)
       (check-eq? (paint-cap p) 'round) (check-eq? (paint-join p) 'bevel)
       (check-equal? (paint-miter-limit p) 7.0)))
   (test-case "reset restores native defaults and clears effect slots"
     (with-skia ([s (make-color-shader 'red)] [p (make-paint #:shader s #:stroke-width 8)])
       (paint-set-dither! p #t) (check-true (paint-dither? p))
       (paint-reset! p)
       (check-false (paint-shader p)) (check-false (paint-dither? p))
       (check-false (paint-antialias? p)) (check-equal? (paint-stroke-width p) 0.0)
       (check-eq? (paint-style p) 'fill)
       (check-eq? (paint-blend-mode-or-src-over p) 'src-over)))
   (test-case "custom blend getter is explicitly SrcOver fallback"
     (with-skia ([b (make-arithmetic-blender 0 0.25 0.75 0)] [p (make-paint)])
       (paint-set-blender! p b)
       (check-eq? (paint-blend-mode-or-src-over p) 'src-over)))
   (test-case "stroke expansion gives fillable geometry"
     (with-skia ([src (make-path '((move 8 24) (line 56 24)))]
                 [paint (make-paint #:style 'stroke #:stroke-width 8)])
       (paint-set-cap! paint 'round)
       (define-values (p fillable?) (paint->fill-path paint src))
       (call-with-skia-resource p (lambda (p)
         (check-true fillable?) (check-true (path-contains? p 32 24))
         (check-false (path-contains? p 32 10))))))
   (test-case "hairline returns its path and false status"
     (with-skia ([src (make-path '((move 8 24) (line 56 24)))]
                 [paint (make-paint #:style 'stroke #:stroke-width 0)])
       (define-values (p fillable?) (paint->fill-path paint src))
       (call-with-skia-resource p (lambda (p)
         (check-false fillable?) (check-true (> (path-point-count p) 0))))))
   (test-case "span snapshots are half-open and survive close"
     (define r (make-region '((0 0 4 4) (8 0 4 4))))
     (define spans (region-spans r 2 0 12))
     (define sequence (in-region-spans r 2 1 10))
     (skia-close! r)
     (check-equal? spans '(#(0 4) #(8 12)))
     (check-equal? (for/list ([s sequence]) s) '(#(1 4) #(8 10))))
   (test-case "empty span and clipping windows return no rectangles"
     (with-skia ([r (make-region '((0 0 10 10)))])
       (check-equal? (region-spans r 2 4 4) '())
       (check-equal? (region-clipped-rectangles r '(0 0 0 0)) '())))
   (test-case "native clipped rectangles respect clip without source mutation"
     (with-skia ([r (make-region '((0 0 4 4) (8 0 4 4)))])
       (check-equal? (region-clipped-rectangles r '(2 1 8 2)) '(#(2 1 2 2) #(8 1 2 2)))
       (check-equal? (region-bounds r) '#(0 0 12 4))))
   (test-case "quick rejection is not an exact overlap decision"
     (with-skia ([r (make-region '((0 0 4 4) (8 0 4 4)))])
       (check-false (region-intersects-rect? r '(5 1 1 1)))
       (check-false (region-quick-reject-rect? r '(5 1 1 1)))
       (check-true (region-quick-reject-rect? r '(20 20 1 1)))))
   (test-case "rectangle boolean operation returns independent empty result"
     (with-skia ([r (make-region '((0 0 4 4)))])
       (with-skia ([out (region-op-rect r '(10 10 1 1) 'intersect)])
         (check-true (region-empty? out)) (check-false (region-empty? r)))))
   (test-case "region mutation does not rewrite detached snapshots"
     (with-skia ([r (make-region '((0 0 4 4)))])
       (define old (region-rectangles r))
       (region-clear! r) (check-true (region-empty? r))
       (region-set-rect! r '(1 2 3 4))
       (check-equal? (region-bounds r) '#(1 2 3 4))
       (check-equal? old '(#(0 0 4 4)))))
   (test-case "rounded rectangle normalization copies native fitted radii"
     (define rr (make-rounded-rect 0 0 40 20 #:radii 100))
     (define norm (rounded-rect-normalize rr))
     (check-equal? (vector-ref (rounded-rect-radii rr) 0) '#(100.0 100.0))
     (check-equal? (vector-ref (rounded-rect-radii norm) 0) '#(10.0 10.0)))
   (test-case "empty and nine-patch rounded rectangles are classified"
     (check-eq? (rounded-rect-type (make-empty-rounded-rect)) 'empty)
     (check-eq? (rounded-rect-type (make-nine-patch-rounded-rect 0 0 100 60 4 6 8 10)) 'nine-patch))
   (test-case "inset outset and offset leave input values unchanged"
     (define rr (make-rounded-rect 0 0 40 20 #:radii 4))
     (check-equal? (rounded-rect-bounds (rounded-rect-inset rr 2 2)) '#(2.0 2.0 36.0 16.0))
     (check-equal? (rounded-rect-bounds (rounded-rect-outset rr 2 2)) '#(-2.0 -2.0 44.0 24.0))
     (check-equal? (rounded-rect-bounds (rounded-rect-offset rr 5 6)) '#(5.0 6.0 40.0 20.0))
     (check-equal? (rounded-rect-bounds rr) '#(0.0 0.0 40.0 20.0)))
   (test-case "unrepresentable RRect shear is false, not an approximate shape"
     (check-false (rounded-rect-transform (make-rounded-rect 0 0 40 20 #:radii 4)
                                         (make-matrix 1 0 0.5 1 0 0))))
   (test-case "rrect append and recognition survive value transformation"
     (with-skia ([p (make-path)])
       (define rr (rounded-rect-transform (make-rounded-rect 0 0 40 20 #:radii 4)
                                          (make-matrix 1 0 0 1 5 6)))
       (path-add-rrect! p rr #:start-index 3)
       (check-true (rounded-rect? (path-as-rounded-rect p)))
       (check-equal? (rounded-rect-bounds (path-as-rounded-rect p)) '#(5.0 6.0 40.0 20.0))))
   (test-case "closed paths and paints reject all native queries"
     (define p (make-path)) (define paint (make-paint))
     (skia-close! p) (skia-close! paint)
     (check-exn exn:fail? (lambda () (path-as-rectangle p)))
     (check-exn exn:fail? (lambda () (paint-reset! paint))))
   (test-case "same source cannot be queried on another Racket thread"
     (with-skia ([p (make-path)])
       (define result (box #f))
       (thread-wait (thread (lambda ()
         (with-handlers ([exn:fail? (lambda (e) (set-box! result e))]) (path-verbs p)))))
       (check-true (exn:fail? (unbox result)))))
   (test-case "shared raster scenes have independent interior/exterior probes"
     (for ([scene (in-list geometry-scene-names)])
       (check-geometry-pixels scene (capture-geometry-scene scene))))))
(module+ main (exit (if (zero? (run-tests geometry-completion-native-tests)) 0 1)))
