#lang racket/base
(require rackunit ffi/unsafe "../main.rkt" "../private/advanced-canvas-types.rkt"
         "../private/audit-trace.rkt"
         (only-in (submod "../private/audit-trace.rkt" testing) native-feature))
(provide advanced-canvas-pure-tests)
(define advanced-canvas-pure-tests
  (test-suite
   "Advanced canvases: pure argument, ABI and policy contracts"
   (test-case "default layer specification has no retained resources"
     (define v (make-layer-options))
     (check-true (layer-options? v)) (check-false (skia-resource? v))
     (check-false (layer-options-bounds v)) (check-equal? (layer-options-flags v) 0))
   (test-case "bounds are copied and immutable"
     (define b (vector 1 2 3 4)) (define v (make-layer-options #:bounds b))
     (vector-set! b 0 9)
     (check-true (immutable? (layer-options-bounds v)))
     (check-equal? (vector->list (layer-options-bounds v)) '(1.0 2.0 3.0 4.0)))
   (test-case "LCD flag uses the pinned value two"
     (define v (make-layer-options #:preserve-lcd-text? #t))
     (check-equal? (layer-options-flags v) 2) (check-true (layer-options-preserve-lcd-text? v)))
   (test-case "previous-content flag uses four"
     (define v (make-layer-options #:initialize-with-previous? #t))
     (check-equal? (layer-options-flags v) 4) (check-true (layer-options-initialize-with-previous? v)))
   (test-case "F16 flag uses sixteen"
     (define v (make-layer-options #:f16? #t))
     (check-equal? (layer-options-flags v) 16) (check-true (layer-options-f16? v)))
   (test-case "all flags compose to twenty-two"
     (check-equal? (layer-options-flags (make-layer-options #:preserve-lcd-text? #t
                                        #:initialize-with-previous? #t #:f16? #t)) 22))
   (test-case "nonboolean flags reject"
     (check-exn exn:fail? (lambda () (make-layer-options #:f16? 1)))
     (check-exn exn:fail? (lambda () (make-layer-options #:initialize-with-previous? 'yes))))
   (test-case "malformed rectangles reject"
     (for ([b (in-list (list '(0 0 1) '(0 0 1 2 3) '(0 0 -1 2) "bounds"))])
       (check-exn exn:fail? (lambda () (make-layer-options #:bounds b)))))
   (test-case "nonfinite bounds reject"
     (for ([x (in-list (list +nan.0 +inf.0 -inf.0))])
       (check-exn exn:fail? (lambda () (make-layer-options #:bounds (list x 0 1 1))))))
   (test-case "C layout is three pointers and an enum, rounded to pointer alignment"
     (define pointer (ctype-sizeof _pointer))
     (check-equal? (ctype-sizeof _sk-save-layer-rec) (* 4 pointer))
     (define record (make-sk-save-layer-rec #f #f #f 22))
     (check-equal? (ptr-ref (ptr-add record (* 3 pointer)) _int) 22))
   (test-case "bad layer options reject before native work"
     (check-exn exn:fail? (lambda () (canvas-save-layer-rec! #f #:options 3))))
   (test-case "bad paint and backdrop reject"
     (check-exn exn:fail? (lambda () (canvas-save-layer-rec! #f #:paint 'bad)))
     (check-exn exn:fail? (lambda () (canvas-save-layer-rec! #f #:backdrop 'bad))))
   (test-case "layer callback must have no required keyword"
     (check-exn exn:fail? (lambda () (call-with-canvas-layer-rec #f (lambda (#:x x) x)))))
   (test-case "discard rejects a noncanvas"
     (check-exn exn:fail? (lambda () (canvas-discard! #f))))
   (test-case "drawable predicates do not allocate"
     (check-false (drawable? #f)) (check-false (drawable? (make-layer-options))))
   (test-case "drawable metadata rejects wrong resources"
     (for ([f (in-list (list drawable->picture drawable-bounds drawable-generation-id
                            drawable-approximate-bytes-used drawable-notify-drawing-changed!))])
       (check-exn exn:fail? (lambda () (f #f)))))
   (test-case "picture conversion rejects wrong input"
     (check-exn exn:fail? (lambda () (picture->drawable #f))))
   (test-case "drawable mode and transform are explicit"
     (check-exn exn:fail? (lambda () (draw-drawable #f #f #:mode 'guess)))
     (check-exn exn:fail? (lambda () (draw-drawable #f #f #:matrix 12))))
   (test-case "NoDraw rejects nonpositive dimensions before loading Skia"
     (check-exn exn:fail? (lambda () (call-with-nodraw-canvas 0 8 void)))
     (check-exn exn:fail? (lambda () (call-with-nodraw-canvas 8 -1 void))))
   (test-case "NoDraw requires a canvas callback"
     (check-exn exn:fail? (lambda () (call-with-nodraw-canvas 8 8 (lambda () (void))))))
   (test-case "NWay requires an explicit nonempty target list"
     (for ([bad (in-list (list '() #f (list #f) 8))])
       (check-exn exn:fail? (lambda () (call-with-nway-canvas bad void)))))
   (test-case "Overdraw requires an owned surface"
     (check-exn exn:fail? (lambda () (call-with-overdraw-canvas #f void))))
   (test-case "backdrop and initialization require explicit document rasterization"
     (for* ([b '(pdf svg)] [f '(layer-backdrop layer-initialization layer-lcd-text)])
       (check-eq? (output-capability-status (output-capability-for b f)) 'needs-raster)))
   (test-case "drawable itself is vector but its dependencies remain separate"
     (for ([b '(pdf svg)])
       (check-eq? (output-capability-status (output-capability-for b 'drawable)) 'vector)))
   (test-case "discard is not portable document geometry"
     (check-eq? (output-capability-status (output-capability-for 'pdf 'discard-content)) 'discarded))
   (test-case "layer record flags contribute retained provenance"
     (define fs (call-with-audit-layer-rec 22 #t
                  (lambda () (native-feature 'sk_canvas_save_layer_rec '()))))
     (for ([f '(layer layer-backdrop layer-initialization layer-lcd-text float-pixels)])
       (check-not-false (memq f fs))))
   (test-case "default record does not acquire backdrop provenance"
     (check-equal? (call-with-audit-layer-rec 0 #f
                     (lambda () (native-feature 'sk_canvas_save_layer_rec '()))) '(layer)))
   (test-case "immediate and retained native draws are both recognized"
     (for ([n '(sk_canvas_draw_drawable sk_drawable_draw)])
       (check-equal? (native-feature n '()) '(drawable))))))
