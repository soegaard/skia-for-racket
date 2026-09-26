#lang racket/base
(require rackunit rackunit/text-ui racket/list "../main.rkt")
(provide path-matrix-native-tests)
(define (verbs segments) (map path-segment-verb segments))
(define (matrix-near a b)
  (for ([x (in-vector (matrix->vector a))] [y (in-vector (matrix->vector b))])
    (check-= x y 0.0001)))
(define (foreign-error proc)
  (define ch (make-channel))
  (define worker (thread (lambda ()
                           (with-handlers ([exn? (lambda (e) (channel-put ch e))])
                             (proc) (channel-put ch #f)))))
  (define v (channel-get ch))
  (thread-wait worker)
  v)
(define all-commands
  '((move 0.0 0.0) (line 20.0 0.0) (quad 30.0 10.0 40.0 0.0)
    (conic 50.0 -10.0 60.0 0.0 0.5) (cubic 70.0 20.0 80.0 -20.0 90.0 0.0)
    (close)))

(define path-matrix-native-tests
  (test-suite
   "Path inspection and affine native boundaries"
   (test-case "read independently-created native translate matrix (M44 order)"
     (with-skia ([s (make-surface 40 40)])
       (define c (surface-canvas s))
       (canvas-translate! c 17 23)
       (check-equal? (canvas-transform c) (matrix-translate 17 23))))
   (test-case "native asymmetric shear readback and matrix setter"
     (with-skia ([s (make-surface 40 40)])
       (define c (surface-canvas s))
       (canvas-skew! c 2 3)
       (check-equal? (canvas-transform c) (matrix-skew 2 3))
       (define m (make-matrix 2 3 5 7 11 13))
       (canvas-set-transform! c m)
       (check-equal? (canvas-transform c) m)))
   (test-case "concat agrees with ordinary translate then scale"
     (with-skia ([s (make-surface 40 40)])
       (define c (surface-canvas s))
       (canvas-translate! c 10 20)
       (canvas-concat! c (matrix-scale 2 3))
       (check-equal? (canvas-transform c) (make-matrix 2 0 0 3 10 20))
       (canvas-reset-transform! c)
       (check-equal? (canvas-transform c) matrix-identity)))
   (test-case "matrix setter controls raster coordinates"
     (with-skia ([s (make-surface 60 50)] [p (make-paint #:color 'red #:antialias? #f)])
       (define c (surface-canvas s))
       (canvas-set-transform! c (make-matrix 2 0 0 3 10 5))
       (draw-rect c 0 0 10 10 p)
       (check-equal? (surface-pixel s 15 10) (rgb 255 0 0))
       (check-equal? (rgba-alpha (surface-pixel s 5 5)) 0)))
   (test-case "protected state restores matrix on normal return and error"
     (with-skia ([s (make-surface 20 20)])
       (define c (surface-canvas s))
       (canvas-translate! c 1 2)
       (with-canvas-state c (canvas-set-transform! c (matrix-scale 3)))
       (check-equal? (canvas-transform c) (matrix-translate 1 2))
       (check-exn #rx"stop" (lambda () (with-canvas-state c
                                        (canvas-concat! c (matrix-skew 1 0))
                                        (error 'test "stop"))))
       (check-equal? (canvas-transform c) (matrix-translate 1 2))))
   (test-case "setting a matrix does not remove the current clip"
     (with-skia ([s (make-surface 30 30)] [p (make-paint #:color 'red)])
       (define c (surface-canvas s))
       (canvas-clip-rect! c 0 0 10 10)
       (canvas-set-transform! c (matrix-translate 5 0))
       (draw-rect c 0 0 25 25 p)
       (check-equal? (surface-pixel s 7 5) (rgb 255 0 0))
       (check-equal? (rgba-alpha (surface-pixel s 15 5)) 0)))
   (test-case "foreign-thread canvas operations are rejected"
     (with-skia ([s (make-surface 10 10)])
       (define c (surface-canvas s))
       (for ([proc (in-list (list (lambda () (canvas-transform c))
                                  (lambda () (canvas-set-transform! c matrix-identity))
                                  (lambda () (canvas-concat! c matrix-identity))))])
         (check-true (exn:fail? (foreign-error proc))))))
   (test-case "expired SVG canvas stays invalid"
     (define stale #f)
     (call-with-svg-bytes 40 30 (lambda (c) (set! stale c)))
     (check-exn #rx"closed" (lambda () (canvas-transform stale)))
     (check-exn #rx"closed" (lambda () (canvas-concat! stale matrix-identity))))
   (test-case "ended PDF canvas cannot affect the next page"
     (with-skia ([doc (make-pdf-document)])
       (define old (document-begin-page! doc 50 40))
       (canvas-concat! old (matrix-translate 10 5))
       (document-end-page! doc)
       (define current (document-begin-page! doc 60 40))
       (check-exn #rx"closed" (lambda () (canvas-set-transform! old matrix-identity)))
       (check-true (matrix? (canvas-transform current)))
       (document-end-page! doc)
       (document-finish! doc)))
   (test-case "SVG and PDF accept ordinary affine matrix drawing"
     (define (drawing c)
       (with-skia ([p (make-paint #:color 'blue)])
         (with-canvas-state c
           (canvas-concat! c (matrix-compose (matrix-translate 30 20) (matrix-rotate-degrees 30)))
           (draw-rect c 0 0 12 8 p))))
     (define svg (call-with-svg-bytes 70 60 drawing))
     (check-true (regexp-match? #rx#"transform=" svg))
     (check-false (regexp-match? #rx#"data:image/" svg))
     (check-true (regexp-match? #rx#"^%PDF-"
                               (call-with-pdf-bytes
                                (lambda (d) (call-with-document-page d 70 60 drawing))))))
   (test-case "raw commands preserve all verbs, control points and conic weight"
     (with-skia ([p (make-path all-commands)])
       (check-equal? (path->commands p) all-commands)
       (define s (path-segments p #:mode 'raw))
       (check-equal? (verbs s) '(move line quad conic cubic close))
       (check-equal? (map (lambda (x) (length (path-segment-points x))) s) '(1 2 3 3 4 0))
       (check-equal? (path-segment-conic-weight (list-ref s 3)) 0.5)))
   (test-case "normal iterator marks the generated closing line"
     (with-skia ([p (make-path '((move 0 0) (line 20 0) (line 20 10) (close)))])
       (define raw (path-segments p #:mode 'raw))
       (define normal (path-segments p))
       (check-equal? (verbs raw) '(move line line close))
       (check-equal? (verbs normal) '(move line line line close))
       (check-true (path-segment-closing-line? (list-ref normal 3)))
       (check-equal? (path-segment-points (list-ref normal 3)) '((20.0 10.0) (0.0 0.0)))
       (check-false (ormap path-segment-closing-line? raw))))
   (test-case "forced closure is a view, not a path mutation"
     (with-skia ([p (make-path '((move 0 0) (line 20 10)))])
       (define before (path->commands p))
       (check-equal? (verbs (path-segments p #:force-closed? #t)) '(move line line close))
       (check-equal? (path->commands p) before)))
   (test-case "raw iteration rejects force closure and invalid modes"
     (with-skia ([p (make-path)])
       (check-exn exn:fail? (lambda () (path-segments p #:mode 'raw #:force-closed? #t)))
       (check-exn exn:fail? (lambda () (path-segments p #:mode 'wrong)))
       (check-exn exn:fail? (lambda () (in-path-segments p #:force-closed? 1)))))
   (test-case "empty paths yield empty snapshots"
     (with-skia ([p (make-path)])
       (check-equal? (path-segments p) '())
       (check-equal? (path->commands p) '())
       (check-equal? (path-contours p) '())))
   (test-case "raw iteration preserves a move-only contour"
     (with-skia ([p (make-path '((move 3 7)))])
       (check-equal? (path->commands p) '((move 3.0 7.0)))
       (define cs (path-contours p #:mode 'raw))
       (check-equal? (length cs) 1)
       (check-false (path-contour-closed? (car cs)))))
   (test-case "contours distinguish open, closed and move-only contours"
     (with-skia ([p (make-path '((move 0 0) (line 10 0) (close)
                                (move 20 0) (line 30 10) (move 99 99)))])
       (define cs (path-contours p #:mode 'raw))
       (check-equal? (length cs) 3)
       (check-equal? (map path-contour-closed? cs) '(#t #f #f))))
   (test-case "sequence snapshots outlive source and are repeatable"
     (define p (make-path all-commands))
     (define seq (in-path-segments p #:mode 'raw))
     (path-reset! p)
     (skia-close! p)
     (check-equal? (for/list ([s seq]) (path-segment-verb s)) '(move line quad conic cubic close))
     (check-equal? (for/list ([s seq]) (path-segment-verb s)) '(move line quad conic cubic close)))
   (test-case "snapshot control points stay detached after mutation"
     (with-skia ([p (make-path all-commands)])
       (define old (path-segments p #:mode 'raw))
       (path-transform! p (matrix-translate 100 200))
       (check-equal? (path-segment-points (car old)) '((0.0 0.0)))
       (check-equal? (path-segment-points (car (path-segments p #:mode 'raw))) '((100.0 200.0)))))
   (test-case "command round trip preserves native structure and fill rule"
     (with-skia ([p (make-path all-commands #:fill-rule 'even-odd)]
                 [copy (make-path (path->commands p) #:fill-rule (path-fill-rule p))])
       (check-equal? (path->commands copy) (path->commands p))
       (check-equal? (path-fill-rule copy) 'even-odd)))
   (test-case "transformed copy preserves source and fill rule"
     (with-skia ([p (make-path '((move 1 2) (line 3 4)) #:fill-rule 'even-odd)]
                 [q (path-transform p (make-matrix 2 0 0 3 10 20))])
       (check-equal? (path->commands p) '((move 1.0 2.0) (line 3.0 4.0)))
       (check-equal? (path->commands q) '((move 12.0 26.0) (line 16.0 32.0)))
       (check-equal? (path-fill-rule q) 'even-odd)))
   (test-case "raster path transform agrees with canvas transform"
     (define m (make-matrix 2 0 0 3 10 5))
     (with-skia ([p (make-path '((move 0 0) (line 10 0) (line 10 10) (close)))]
                 [q (path-transform p m)]
                 [s1 (make-surface 50 50)] [s2 (make-surface 50 50)]
                 [paint (make-paint #:color 'blue #:antialias? #f)])
       (canvas-concat! (surface-canvas s1) m)
       (draw-path (surface-canvas s1) p paint)
       (draw-path (surface-canvas s2) q paint)
       (check-equal? (surface->rgba-bytes s1) (surface->rgba-bytes s2))))
   (test-case "measurement matrices agree with position and tangent"
     (with-skia ([p (make-path '((move 10 20) (line 40 60)))] [m (make-path-measure p)])
       (define-values (x y tx ty) (path-measure-position+tangent m 25))
       (define combined (path-measure-matrix m 25))
       (matrix-near combined (make-matrix tx ty (- ty) tx x y))
       (matrix-near (path-measure-matrix m 25 #:mode 'position) (matrix-translate x y))
       (matrix-near (path-measure-matrix m 25 #:mode 'tangent) (make-matrix tx ty (- ty) tx))))
   (test-case "measurement distance is clamped at the contour end"
     (with-skia ([p (make-path '((move 0 0) (line 10 0)))] [m (make-path-measure p)])
       (matrix-near (path-measure-matrix m 100) (matrix-translate 10 0))
       (check-exn exn:fail? (lambda () (path-measure-matrix m -1)))
       (check-exn exn:fail? (lambda () (path-measure-matrix m 0 #:mode 'wrong)))))
   (test-case "empty and zero-length measured paths return false"
     (for ([commands (in-list '(() ((move 0 0) (line 0 0))))])
       (with-skia ([p (make-path commands)] [m (make-path-measure p)])
         (check-false (path-measure-matrix m 0)))))
   (test-case "measurement keeps its snapshot through transform and close"
     (define p (make-path '((move 0 0) (line 10 0))))
     (with-skia ([m (make-path-measure p)])
       (path-transform! p (matrix-translate 300 400))
       (skia-close! p)
       (matrix-near (path-measure-matrix m 5) (matrix-translate 5 0))))
   (test-case "shader-local transform changes shading, not geometry"
     (define base (make-linear-gradient-shader 0 0 10 0 '(red blue)))
     (with-skia ([local (shader-with-local-matrix base (matrix-translate 20 0))]
                 [p (make-paint #:shader local)] [s (make-surface 40 4)])
       (skia-close! base)
       (draw-paint (surface-canvas s) p)
       (check-equal? (surface-pixel s 5 2) (rgb 255 0 0))
       (check-equal? (surface-pixel s 35 2) (rgb 0 0 255))
       (check-true (> (rgba-red (surface-pixel s 21 2)) (rgba-blue (surface-pixel s 21 2))))))
   (test-case "snapshot byte limits apply before returning data"
     (with-skia ([p (make-path all-commands)])
       (parameterize ([current-skia-byte-limit 1])
         (check-exn #rx"byte-limit" (lambda () (path-segments p)))
         (check-exn #rx"byte-limit" (lambda () (path->commands p))))))
   (test-case "closed and foreign-thread paths are rejected"
     (define p (make-path all-commands))
     (check-true (exn:fail? (foreign-error (lambda () (path-segments p)))))
     (check-true (exn:fail? (foreign-error (lambda () (path-transform! p matrix-identity)))))
     (skia-close! p)
     (check-exn #rx"closed" (lambda () (path->commands p)))
     (check-exn #rx"closed" (lambda () (path-transform p matrix-identity))))
   (test-case "repeated snapshots leave no escaped native iterator"
     (with-skia ([p (make-path all-commands)])
       (for ([i (in-range 50)])
         (check-equal? (length (path-segments p #:mode 'raw)) 6))
       (path-reset! p)
       (check-equal? (path-segments p) '())))))
(module+ test (run-tests path-matrix-native-tests))
