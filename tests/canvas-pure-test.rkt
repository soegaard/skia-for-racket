#lang racket/base
(require rackunit racket/vector "../main.rkt")
(provide canvas-pure-tests)
(define canvas-pure-tests
  (test-suite
   "Canvas primitives: validation without native loading"
   (test-case "rounded rect is a pure immutable value"
     (define r (make-rounded-rect 1 2 30 40))
     (check-true (rounded-rect? r))
     (check-equal? (rounded-rect-bounds r) #(1.0 2.0 30.0 40.0))
     (check-true (immutable? (rounded-rect-bounds r))))
   (test-case "uniform scalar radii"
     (check-equal? (rounded-rect-radii (make-rounded-rect 0 0 20 30 #:radii 5))
                   #(#(5.0 5.0) #(5.0 5.0) #(5.0 5.0) #(5.0 5.0))))
   (test-case "corner order is TL TR BR BL"
     (check-equal? (rounded-rect-radii (make-rounded-rect 0 0 20 30 #:radii '((1 2) (3 4) (5 6) (7 8))))
                   #(#(1.0 2.0) #(3.0 4.0) #(5.0 6.0) #(7.0 8.0))))
   (test-case "input vectors are deeply copied"
     (define p (vector 1 2)) (define rs (vector p p p p))
     (define r (make-rounded-rect 0 0 20 30 #:radii rs))
     (vector-set! p 0 99) (vector-set! rs 1 #(8 9))
     (check-equal? (vector-ref (rounded-rect-radii r) 1) #(1.0 2.0))
     (check-true (immutable? (vector-ref (rounded-rect-radii r) 0))))
   (test-case "oversized radii preserved for native normalization"
     (check-equal? (vector-ref (rounded-rect-radii (make-rounded-rect 0 0 20 20 #:radii 100)) 0)
                   #(100.0 100.0)))
   (test-case "zero-area rounded rectangle is allowed"
     (check-true (rounded-rect? (make-rounded-rect 0 0 0 20))))
   (test-case "negative rectangle size rejected"
     (check-exn exn:fail:contract? (lambda () (make-rounded-rect 0 0 -1 20))))
   (test-case "non-finite bounds rejected"
     (check-exn exn:fail:contract? (lambda () (make-rounded-rect +nan.0 0 2 3))))
   (test-case "computed edge overflow rejected"
     (check-exn exn:fail:contract? (lambda () (make-rounded-rect 3e38 0 3e38 3))))
   (test-case "negative radius rejected"
     (check-exn exn:fail:contract? (lambda () (make-rounded-rect 0 0 20 20 #:radii -1))))
   (test-case "corner arity checked"
     (check-exn exn:fail:contract? (lambda () (make-rounded-rect 0 0 20 20 #:radii '((1 2) (3 4))))))
   (test-case "radius pair arity checked"
     (check-exn exn:fail:contract? (lambda () (make-rounded-rect 0 0 20 20 #:radii '((1) (2 3) (4 5) (6 7))))))
   (test-case "non-finite radius rejected"
     (check-exn exn:fail:contract? (lambda () (make-rounded-rect 0 0 20 20 #:radii +inf.0))))
   (test-case "point coordinates checked first"
     (check-exn exn:fail:contract? (lambda () (draw-point #f +nan.0 0 #f))))
   (test-case "point mode checked"
     (check-exn exn:fail:contract? (lambda () (draw-points #f '() #f #:mode 'triangle))))
   (test-case "independent line pairs cannot have odd count"
     (check-exn exn:fail:contract? (lambda () (draw-points #f '((0 0)) #f #:mode 'lines))))
   (test-case "point shape checked"
     (check-exn exn:fail:contract? (lambda () (draw-points #f '((0 0 1)) #f))))
   (test-case "point buffer limit checked before allocation"
     (parameterize ([current-skia-byte-limit 8])
       (check-exn exn:fail:contract? (lambda () (draw-points #f '((0 0) (1 1)) #f))))
     (parameterize ([current-skia-byte-limit 32])
       (check-exn exn:fail:contract?
         (lambda () (draw-points #f '((0 0) (1 1) (2 2) (3 3)) #f #:mode 'polygon)))))
   (test-case "invalid arc angle rejected"
     (check-exn exn:fail:contract? (lambda () (draw-arc #f 0 0 2 3 +inf.0 90 #f))))
   (test-case "arc center flag is boolean"
     (check-exn exn:fail:contract? (lambda () (draw-arc #f 0 0 2 3 0 90 #f #:use-center? 1))))
   (test-case "draw-rrect requires specification"
     (check-exn exn:fail:contract? (lambda () (draw-rrect #f '(0 0 1 1) #f))))
   (test-case "clip rounded rect requires specification"
     (check-exn exn:fail:contract? (lambda () (canvas-clip-rounded-rect! #f #f))))
   (test-case "draw color checks blend mode"
     (check-exn exn:fail:contract? (lambda () (draw-color #f 'red #:blend-mode 'nonsense))))
   (test-case "layer bounds arity checked"
     (check-exn exn:fail:contract? (lambda () (canvas-save-layer! #f #:bounds '(0 0 1)))))
   (test-case "layer bounds reject negative extent"
     (check-exn exn:fail:contract? (lambda () (canvas-save-layer! #f #:bounds '(0 0 -1 10)))))
   (test-case "query validation rejects bad canvas"
     (for ([query (in-list (list canvas-local-clip-bounds canvas-device-clip-bounds
                                 canvas-clip-empty? canvas-clip-rect?))])
       (check-exn exn:fail:contract? (lambda () (query #f)))))
   (test-case "points and layers have conservative output policies"
     (check-eq? (output-capability-status (output-capability-for 'svg 'point-sprites)) 'needs-raster)
     (check-eq? (output-capability-status (output-capability-for 'pdf 'layer)) 'native-expansion)
     (check-eq? (output-capability-status (output-capability-for 'svg 'layer)) 'needs-raster))
   (test-case "PDF text reason is backend-specific"
     (check-true (regexp-match? #rx"PDF" (output-capability-reason (output-capability-for 'pdf 'native-text)))))))
