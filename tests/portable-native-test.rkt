#lang racket/base
(require rackunit racket/list "../main.rkt" "portable-fixtures.rkt")
(provide portable-native-tests)
(define (render draw)
  (with-skia ([s (make-surface 40 32)])
    (draw (surface-canvas s))
    (surface->rgba-bytes s)))
(define (check-buffers-close a b tolerance)
  (check-equal? (bytes-length a) (bytes-length b))
  (check-true (for/and ([x (in-bytes a)] [y (in-bytes b)]) (<= (abs (- x y)) tolerance))))
(define (export draw [format 'svg] [policy 'error])
  (output->bytes/audit (make-output-page 40 32 draw) format #:policy policy))
(define (check-no-fallback report)
  (check-false (output-audit-report-blocking? report))
  (check-false (for/or ([e (in-list (output-audit-report-events report))])
                 (eq? (output-audit-event-feature e) 'raster-group))))
(define portable-native-tests
  (test-suite
   "Portable drawing: native resources and vector backends"
   (test-case "circle markers are centered and remain geometric"
     (with-skia ([s (make-surface 24 24)] [p (make-paint #:color 'blue)])
       (draw-markers (surface-canvas s) '((10 10)) 8 p)
       (check-equal? (surface-pixel s 10 10) (rgba 0 0 255 255))
       (check-equal? (rgba-alpha (surface-pixel s 5 10)) 0)
       (check-equal? (rgba-alpha (surface-pixel s 6 6)) 0)))
   (test-case "square markers use their explicit side length"
     (with-skia ([s (make-surface 24 24)] [p (make-paint #:color 'blue)])
       (draw-markers (surface-canvas s) '((10 10)) 8 p #:shape 'square)
       (check-equal? (surface-pixel s 6 6) (rgba 0 0 255 255))
       (check-equal? (rgba-alpha (surface-pixel s 5 6)) 0)))
   (test-case "marker paint style is retained"
     (with-skia ([s (make-surface 24 24)]
                 [p (make-paint #:color 'blue #:style 'stroke #:stroke-width 2)])
       (draw-markers (surface-canvas s) '((10 10)) 8 p #:shape 'square)
       (check-equal? (rgba-alpha (surface-pixel s 10 10)) 0)
       (check-true (> (rgba-alpha (surface-pixel s 6 10)) 0))))
   (test-case "overlapping markers composite in input order"
     (with-skia ([s (make-surface 24 24)] [p (make-paint #:color (rgba 255 0 0 128))])
       (draw-markers (surface-canvas s) '((10 10) (10 10)) 8 p)
       (check-= (rgba-alpha (surface-pixel s 10 10)) 192 1)))
   (test-case "all marker coordinates validate before painting"
     (with-skia ([s (make-surface 24 24)] [p (make-paint #:color 'blue)])
       (define before (surface->rgba-bytes s))
       (check-exn exn:fail? (lambda () (draw-markers (surface-canvas s) '((10 10) (bad 10)) 8 p)))
       (check-equal? (surface->rgba-bytes s) before)))
   (test-case "closed paint rejected for empty marker batch"
     (with-skia ([s (make-surface 24 24)] [p (make-paint)])
       (skia-close! p)
       (check-exn exn:fail? (lambda () (draw-markers (surface-canvas s) '() 8 p)))))
   (test-case "closed canvas rejected for markers"
     (with-skia ([s (make-surface 24 24)] [p (make-paint)])
       (define c (surface-canvas s)) (skia-close! s)
       (check-exn exn:fail? (lambda () (draw-markers c '((10 10)) 8 p)))))
   (test-case "cross-thread drawing is rejected"
     (with-skia ([s (make-surface 24 24)] [p (make-paint)])
       (define c (surface-canvas s)) (define result (make-channel))
       (thread (lambda ()
                 (channel-put result
                   (with-handlers ([exn:fail? (lambda (_) 'rejected)])
                     (draw-markers c '((10 10)) 8 p) 'accepted))))
       (check-eq? (sync/timeout 5 result) 'rejected)))
   (test-case "marker output group is vector-only in both formats"
     (for ([format '(pdf svg)])
       (with-skia ([p (make-paint #:color 'blue)])
         (define decision #f)
         (define-values (bs report)
           (export (lambda (c)
                     (set! decision (draw-output-group c 0 0 40 30
                       (lambda (local) (draw-markers local '((10 10) (25 10)) 8 p)))))
                   format 'vector-only))
         (check-eq? (output-group-report-strategy decision) 'native)
         (check-true (output-audit-report-vector-only? report))
         (when (eq? format 'svg) (check-false (regexp-match? #rx#"<image" bs))))))
   (test-case "markers do not hide an unsupported runtime paint"
     (with-skia ([effect (make-runtime-effect "half4 main(float2 p) { return half4(1,0,0,1); }")]
                 [shader (runtime-effect->shader effect)] [p (make-paint #:shader shader)])
       (define decision #f)
       (define-values (_ report)
         (export (lambda (c)
                   (set! decision (draw-output-group c 0 0 40 30
                     (lambda (local) (draw-markers local '((10 10)) 8 p)))))))
       (check-eq? (output-group-report-strategy decision) 'raster)
       (check-false (output-audit-report-blocking? report))))
   (test-case "nine-patch matches native on integral nearest samples"
     (with-skia ([im (make-portable-test-image)])
       (check-buffers-close
         (render (lambda (c) (draw-image-nine c im '(3 3 3 3) 2 2 18 15 #:sampling 'nearest)))
         (render (lambda (c) (draw-image-nine/portable c im '(3 3 3 3) 2 2 18 15 #:sampling 'nearest))) 0)))
   (test-case "small nine-patch matches native collapsed spans"
     (with-skia ([im (make-portable-test-image)])
       (check-buffers-close
         (render (lambda (c) (draw-image-nine c im '(3 3 3 3) 2 2 4 2 #:sampling 'nearest)))
         (render (lambda (c) (draw-image-nine/portable c im '(3 3 3 3) 2 2 4 2 #:sampling 'nearest))) 0)))
   (test-case "portable nine alpha matches native image opacity"
     (with-skia ([im (make-portable-test-image)] [p (make-paint #:color (rgba 0 0 0 128))])
       (check-buffers-close
         (render (lambda (c) (draw-image-nine c im '(3 3 3 3) 2 2 18 15 #:sampling 'nearest #:paint p)))
         (render (lambda (c) (draw-image-nine/portable c im '(3 3 3 3) 2 2 18 15 #:sampling 'nearest #:alpha 128))) 1)))
   (test-case "ordinary lattice matches native nearest samples"
     (with-skia ([im (make-portable-test-image)])
       (define l (make-image-lattice '(3 6) '(3 6)))
       (check-buffers-close
         (render (lambda (c) (draw-image-lattice c im l 2 2 18 15 #:sampling 'nearest)))
         (render (lambda (c) (draw-image-lattice/portable c im l 2 2 18 15 #:sampling 'nearest))) 0)))
   (test-case "lattice transparent and fixed-color cells match native"
     (with-skia ([im (make-portable-test-image)])
       (define l (make-image-lattice '(3 6) '(3 6)
                   #:cell-types '(default fixed-color default transparent default default default default default)
                   #:colors '(black #x80ff0000 black black black black black black black)))
       (check-buffers-close
         (render (lambda (c) (draw-image-lattice c im l 2 2 18 15 #:sampling 'nearest)))
         (render (lambda (c) (draw-image-lattice/portable c im l 2 2 18 15 #:sampling 'nearest))) 1)))
   (test-case "fixed-color and image alpha are both modulated"
     (with-skia ([im (make-portable-test-image)] [s (make-surface 30 24)])
       (define l (make-image-lattice '(3 6) '() #:cell-types '(default transparent fixed-color)
                                    #:colors '(black black #x80ff0000)))
       (draw-image-lattice/portable (surface-canvas s) im l 0 0 30 24 #:sampling 'nearest #:alpha 128)
       (check-= (rgba-alpha (surface-pixel s 1 1)) 128 1)
       (check-equal? (rgba-alpha (surface-pixel s 10 10)) 0)
       (check-= (rgba-alpha (surface-pixel s 28 10)) 64 1)))
   (test-case "image plans with zero destination paint nothing"
     (with-skia ([im (make-portable-test-image)] [s (make-surface 24 24)])
       (define before (surface->rgba-bytes s))
       (draw-image-nine/portable (surface-canvas s) im '(3 3 3 3) 0 0 0 20)
       (check-equal? (surface->rgba-bytes s) before)))
   (test-case "image-grid bad alpha rejected before painting"
     (with-skia ([im (make-portable-test-image)] [s (make-surface 24 24)])
       (define before (surface->rgba-bytes s))
       (check-exn exn:fail? (lambda () (draw-image-nine/portable (surface-canvas s) im '(3 3 3 3) 0 0 20 20 #:alpha 256)))
       (check-equal? (surface->rgba-bytes s) before)))
   (test-case "portable nine exports as image pieces without fallback"
     (with-skia ([im (make-portable-test-image)])
       (define decision #f)
       (define-values (bs report)
         (export (lambda (c)
                   (set! decision (draw-output-group c 0 0 40 30
                     (lambda (local) (draw-image-nine/portable local im '(3 3 3 3) 0 0 30 24)))))))
       (check-eq? (output-group-report-strategy decision) 'native)
       (check-not-false (regexp-match? #rx#"<image" bs))
       (check-false (output-audit-report-vector-only? report))
       (check-no-fallback report)))
   (test-case "portable lattice remains embedded-raster not vector geometry"
     (with-skia ([im (make-portable-test-image)])
       (define l (make-image-lattice '(3 6) '(3 6)))
       (define-values (_ report) (export (lambda (c) (draw-image-lattice/portable c im l 0 0 30 24))))
       (check-no-fallback report)
       (check-true (for/or ([e (in-list (output-audit-report-events report))])
                     (and (eq? (output-audit-event-feature e) 'image)
                          (eq? (output-audit-event-status e) 'embedded-raster))))))
   (test-case "vector-only policy still rejects cropped images"
     (with-skia ([im (make-portable-test-image)])
       (check-exn exn:fail:output-audit?
         (lambda () (export (lambda (c) (draw-image-nine/portable c im '(3 3 3 3) 0 0 30 24)) 'svg 'vector-only)))))
   (test-case "old native grid classification remains conservative"
     (with-skia ([im (make-portable-test-image)])
       (check-exn exn:fail:output-audit?
         (lambda () (export (lambda (c) (draw-image-nine c im '(3 3 3 3) 0 0 30 24)) 'svg 'error)))))
   (test-case "atlas local coordinates select the requested crop"
     (with-skia ([im (make-portable-test-image)])
       (check-buffers-close
         (render (lambda (c) (draw-image-subrect c im 3 0 3 3 5 7 3 3 #:sampling 'nearest)))
         (render (lambda (c) (draw-atlas/portable c im (list (make-atlas-transform 5 7)) '((3 0 3 3)) #:sampling 'nearest))) 0)))
   (test-case "atlas anchor is relative to its crop not the atlas origin"
     (with-skia ([im (make-portable-test-image)] [s (make-surface 24 24)])
       (draw-atlas/portable (surface-canvas s) im
         (list (make-atlas-transform 10 10 #:scale 2 #:anchor '(1 1))) '((6 0 3 3)) #:sampling 'nearest)
       (check-equal? (surface-pixel s 10 10) (rgba 0 0 255 255))
       (check-equal? (rgba-alpha (surface-pixel s 7 10)) 0)))
   (test-case "atlas restores the receiving canvas matrix and clip"
     (with-skia ([im (make-portable-test-image)] [s (make-surface 24 24)])
       (define c (surface-canvas s)) (canvas-translate! c 2 3)
       (canvas-clip-rect! c 0 0 15 15 #:antialias? #f)
       (define before (canvas-matrix4 c)) (define clip (canvas-device-clip-bounds c))
       (draw-atlas/portable c im (list (make-atlas-transform 5 7 #:rotation 30)) '((3 0 3 3)))
       (check-equal? (canvas-matrix4 c) before)
       (check-equal? (canvas-device-clip-bounds c) clip)))
   (test-case "atlas validates the full source batch before painting"
     (with-skia ([im (make-portable-test-image)] [s (make-surface 24 24)])
       (define before (surface->rgba-bytes s))
       (check-exn exn:fail? (lambda ()
         (draw-atlas/portable (surface-canvas s) im
           (list (make-atlas-transform 0 0) (make-atlas-transform 8 8)) '((0 0 3 3) (8 8 3 3)))))
       (check-equal? (surface->rgba-bytes s) before)))
   (test-case "atlas fractional source coordinates are rejected not rounded"
     (with-skia ([im (make-portable-test-image)] [s (make-surface 24 24)])
       (check-exn exn:fail? (lambda ()
         (draw-atlas/portable (surface-canvas s) im (list (make-atlas-transform 0 0)) '((1/2 0 3 3)))))))
   (test-case "atlas does not silently accept per-sprite tint"
     (with-skia ([im (make-portable-test-image)] [s (make-surface 24 24)])
       (check-exn exn:fail? (lambda ()
         (draw-atlas/portable (surface-canvas s) im (list (make-atlas-transform 0 0)) '((0 0 3 3)) #:colors '(red))))))
   (test-case "empty atlas still checks image lifetime"
     (with-skia ([im (make-portable-test-image)] [s (make-surface 24 24)])
       (skia-close! im)
       (check-exn exn:fail? (lambda () (draw-atlas/portable (surface-canvas s) im '() '())))))
   (test-case "zero atlas scale produces no painted pixels"
     (with-skia ([im (make-portable-test-image)] [s (make-surface 24 24)])
       (define before (surface->rgba-bytes s))
       (draw-atlas/portable (surface-canvas s) im (list (make-atlas-transform 10 10 #:scale 0)) '((0 0 3 3)))
       (check-equal? (surface->rgba-bytes s) before)))
   (test-case "atlas cropped images and placements export without panel fallback"
     (with-skia ([im (make-portable-test-image)])
       (define-values (bs report)
         (export (lambda (c) (draw-atlas/portable c im
                    (list (make-atlas-transform 10 10 #:scale 3 #:rotation 15)
                          (make-atlas-transform 25 10 #:scale 2)) '((0 0 3 3) (3 0 3 3))))))
       (check-not-false (regexp-match? #rx#"<image" bs))
       (check-no-fallback report)))
   (test-case "recorded portable slices survive original image closure"
     (with-skia ([im (make-portable-test-image)]
                 [p (call-with-picture 40 30 (lambda (c)
                      (draw-image-nine/portable c im '(3 3 3 3) 0 0 30 24)))])
       (skia-close! im)
       (define-values (_ report) (export (lambda (c) (draw-picture c p))))
       (check-no-fallback report)))
   (test-case "nested portable image group stays native"
     (with-skia ([im (make-portable-test-image)])
       (define outer #f)
       (define-values (_ report)
         (export (lambda (c)
           (set! outer (draw-output-group c 0 0 40 30
             (lambda (local)
               (draw-output-group local 0 0 30 24
                 (lambda (child) (draw-image-nine/portable child im '(3 3 3 3) 0 0 30 24)))))))))
       (check-eq? (output-group-report-strategy outer) 'native)
       (check-no-fallback report)))
   (test-case "SKP import cannot restore provenance of portable drawings"
     (with-skia ([im (make-portable-test-image)]
                 [p (call-with-picture 40 30 (lambda (c) (draw-image-nine/portable c im '(3 3 3 3) 0 0 30 24)))]
                 [loaded (picture-from-bytes (picture->bytes p) #:trusted? #t)])
       (check-exn exn:fail:output-audit? (lambda () (export (lambda (c) (draw-picture c loaded)))))))
))
