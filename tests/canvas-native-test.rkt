#lang racket/base
(require rackunit racket/list racket/file "../main.rkt")
(provide canvas-native-tests)
(define (page f) (make-output-page 100 80 f))
(define (has-feature? r feature [status #f])
  (for/or ([e (in-list (output-audit-report-events r))])
    (and (eq? feature (output-audit-event-feature e))
         (or (not status) (eq? status (output-audit-event-status e))))))
(define (opaque-pair c)
  (with-skia ([p (make-paint #:color 'red)] [q (make-paint #:color 'blue)])
    (draw-rect c 0 0 20 20 p) (draw-rect c 10 0 20 20 q)))
(define (layer-pair c)
  (with-skia ([p (make-paint #:color (rgba 0 0 0 128))])
    (with-canvas-layer c #:paint p (opaque-pair c))))
(define canvas-native-tests
  (test-suite
   "Canvas primitives: native geometry, queries, and layers"
   (test-case "round point paints its center"
     (with-skia ([s (make-surface 30 30)] [p (make-paint #:color 'red #:cap 'round #:stroke-width 8)])
       (draw-point (surface-canvas s) 10 10 p)
       (check-equal? (surface-pixel s 10 10) (rgb 255 0 0))))
   (test-case "point sets ignore fill style and use stroke width"
     (with-skia ([s (make-surface 30 30)] [p (make-paint #:color 'blue #:style 'fill #:stroke-width 6)])
       (draw-points (surface-canvas s) #(#(8 8) #(20 20)) p)
       (check-equal? (surface-pixel s 8 8) (rgb 0 0 255))
       (check-equal? (rgba-alpha (surface-pixel s 14 14)) 0)))
   (test-case "independent lines do not connect the pairs"
     (with-skia ([s (make-surface 40 40)] [p (make-paint #:color 'red #:stroke-width 3)])
       (draw-points (surface-canvas s) '((5 5) (30 5) (5 30) (30 30)) p #:mode 'lines)
       (check-equal? (surface-pixel s 15 5) (rgb 255 0 0))
       (check-equal? (rgba-alpha (surface-pixel s 18 18)) 0)))
   (test-case "polygon point mode leaves the last edge open"
     (with-skia ([s (make-surface 40 40)] [p (make-paint #:color 'red #:stroke-width 3)])
       (draw-points (surface-canvas s) '((5 5) (30 5) (30 30)) p #:mode 'polygon)
       (check-equal? (surface-pixel s 30 15) (rgb 255 0 0))
       (check-equal? (rgba-alpha (surface-pixel s 15 15)) 0)
       (define reference (surface->rgba-bytes s))
       (canvas-clear! (surface-canvas s) 'transparent)
       (draw-points (surface-canvas s) '((5 5) (30 5) (30 5) (30 30)) p #:mode 'lines)
       (check-equal? (surface->rgba-bytes s) reference)))
   (test-case "empty point list is a validated no-op"
     (with-skia ([s (make-surface 2 2)] [p (make-paint)])
       (draw-points (surface-canvas s) '() p)
       (check-equal? (rgba-alpha (surface-pixel s 0 0)) 0)
       (skia-close! p)
       (check-exn exn:fail? (lambda () (draw-points (surface-canvas s) '() p)))))
   (test-case "arc sector uses clockwise angles in y-down coordinates"
     (with-skia ([s (make-surface 40 40)] [p (make-paint #:color 'red)])
       (draw-arc (surface-canvas s) 10 10 20 20 0 90 p #:use-center? #t)
       (check-equal? (surface-pixel s 23 23) (rgb 255 0 0))
       (check-equal? (rgba-alpha (surface-pixel s 16 16)) 0)))
   (test-case "full sweep fills an oval"
     (with-skia ([s (make-surface 40 40)] [p (make-paint #:color 'red)])
       (draw-arc (surface-canvas s) 5 5 30 30 10 400 p)
       (check-equal? (surface-pixel s 20 20) (rgb 255 0 0))
       (check-equal? (rgba-alpha (surface-pixel s 5 5)) 0)))
   (test-case "zero sweep and empty oval have no pixels"
     (with-skia ([s (make-surface 20 20)] [p (make-paint #:color 'red)])
       (draw-arc (surface-canvas s) 0 0 20 20 0 0 p)
       (draw-arc (surface-canvas s) 0 0 0 20 0 90 p)
       (check-equal? (surface->rgba-bytes s) (make-bytes 1600 0))))
   (test-case "per-corner rounded rect has square and rounded corners"
     (with-skia ([s (make-surface 50 50)] [p (make-paint #:color 'red)])
       (draw-rrect (surface-canvas s) (make-rounded-rect 5 5 40 40 #:radii '((0 0) (15 15) (0 0) (15 15))) p)
       (check-equal? (surface-pixel s 6 6) (rgb 255 0 0))
       (check-equal? (rgba-alpha (surface-pixel s 43 6)) 0)))
   (test-case "oversized corner radii are normalized by Skia"
     (with-skia ([s (make-surface 30 30)] [p (make-paint #:color 'red)])
       (draw-rrect (surface-canvas s) (make-rounded-rect 5 5 20 20 #:radii 100) p)
       (check-equal? (surface-pixel s 15 15) (rgb 255 0 0))
       (check-equal? (rgba-alpha (surface-pixel s 5 5)) 0)))
   (test-case "double rounded rectangle leaves the inner hole"
     (with-skia ([s (make-surface 80 70)] [p (make-paint #:color 'red)])
       (draw-double-rounded-rect (surface-canvas s)
         (make-rounded-rect 5 5 70 60 #:radii 8) (make-rounded-rect 18 18 40 30 #:radii 4) p)
       (check-equal? (surface-pixel s 10 30) (rgb 255 0 0))
       (check-equal? (rgba-alpha (surface-pixel s 30 30)) 0)))
   (test-case "non-contained inner rectangle raises before drawing"
     (with-skia ([s (make-surface 20 20)] [p (make-paint)])
       (check-exn exn:fail:contract?
         (lambda () (draw-double-rounded-rect (surface-canvas s)
                      (make-rounded-rect 0 0 10 10) (make-rounded-rect 8 8 10 10) p)))))
   (test-case "draw-color obeys clipping and source blend"
     (with-skia ([s (make-surface 20 20 #:background 'white)])
       (define c (surface-canvas s))
       (canvas-clip-rect! c 0 0 10 20)
       (canvas-translate! c 100 70)
       (draw-color c 'red #:blend-mode 'src)
       (define-values (tx ty) (matrix-map-point (canvas-transform c) 0 0))
       (check-equal? (list tx ty) '(100.0 70.0))
       (check-equal? (surface-pixel s 5 5) (rgb 255 0 0))
       (check-equal? (surface-pixel s 15 5) (rgb 255 255 255))))
   (test-case "rounded clip affects geometry and clip classification"
     (with-skia ([s (make-surface 40 40)])
       (define c (surface-canvas s))
       (canvas-clip-rounded-rect! c (make-rounded-rect 5 5 30 30 #:radii 10))
       (check-false (canvas-clip-empty? c)) (check-false (canvas-clip-rect? c))
       (draw-color c 'red)
       (check-equal? (surface-pixel s 20 20) (rgb 255 0 0))
       (check-equal? (rgba-alpha (surface-pixel s 5 5)) 0))
     (define (clipped c)
       (canvas-clip-rounded-rect! c (make-rounded-rect 5 5 30 30
                                     #:radii '((0 0) (10 6) (5 10) (8 5))))
       (draw-color c 'red))
     (define bs (call-with-svg-bytes 40 40 clipped))
     ;; A native RRect clip would incorrectly serialize all corners as one pair.
     (check-true (regexp-match? #rx#"<clipPath[^>]*>[^<]*<path" bs))
     (with-skia ([pic (call-with-picture 40 40 clipped)])
       (define replay (call-with-svg-bytes 40 40 (lambda (c) (draw-picture c pic))))
       (check-true (regexp-match? #rx#"<clipPath[^>]*>[^<]*<path" replay))))
   (test-case "device clip bounds ignore later CTM changes"
     (with-skia ([s (make-surface 100 80)])
       (define c (surface-canvas s))
       (canvas-clip-rect! c 10 20 30 40)
       (define before (canvas-device-clip-bounds c))
       (check-equal? before #(10 20 30 40))
       (canvas-translate! c 100 100)
       (check-equal? (canvas-device-clip-bounds c) before)
       (check-true (immutable? before))))
   (test-case "local clip bounds follow the inverse transform conservatively"
     (with-skia ([s (make-surface 100 80)])
       (define c (surface-canvas s)) (canvas-clip-rect! c 10 20 30 40)
       (canvas-translate! c 5 7)
       (define b (canvas-local-clip-bounds c))
       (check-true (vector? b))
       (check-true (<= (vector-ref b 0) 5))
       (check-true (>= (+ (vector-ref b 0) (vector-ref b 2)) 35))))
   (test-case "empty clip has false bounds"
     (with-skia ([s (make-surface 20 20)])
       (define c (surface-canvas s)) (canvas-clip-rect! c 30 30 10 10)
       (check-true (canvas-clip-empty? c))
       (check-false (canvas-local-clip-bounds c)) (check-false (canvas-device-clip-bounds c))))
   (test-case "quick reject follows transform"
     (with-skia ([s (make-surface 20 20)])
       (define c (surface-canvas s))
       (check-false (canvas-quick-reject? c 1 1 5 5))
       (canvas-translate! c 100 0)
       (check-true (canvas-quick-reject? c 1 1 5 5))))
   (test-case "layer applies opacity once to the composite"
     (with-skia ([s (make-surface 40 25 #:background 'white)])
       (layer-pair (surface-canvas s))
       (define overlap (surface-pixel s 15 10))
       (check-= (rgba-red overlap) 127 1)
       (check-= (rgba-green overlap) 127 1)
       (check-equal? (rgba-blue overlap) 255)))
   (test-case "low-level layer returns the pre-save count"
     (with-skia ([s (make-surface 20 20)])
       (define c (surface-canvas s)) (define n (canvas-save-count c))
       (check-equal? (canvas-save-layer! c) n)
       (check-equal? (canvas-save-count c) (add1 n))
       (canvas-restore-to-count! c n) (check-equal? (canvas-save-count c) n)))
   (test-case "layer retains paint after closure"
     (with-skia ([s (make-surface 40 25 #:background 'white)] [p (make-paint #:color (rgba 0 0 0 128))])
       (define c (surface-canvas s)) (define n (canvas-save-layer! c #:paint p))
       (skia-close! p) (opaque-pair c) (canvas-restore-to-count! c n)
       (check-= (rgba-red (surface-pixel s 15 10)) 127 1)))
   (test-case "scoped layer preserves multiple results"
     (with-skia ([s (make-surface 20 20)])
       (check-equal? (call-with-values (lambda () (with-canvas-layer (surface-canvas s) (values 2 3))) list) '(2 3))))
   (test-case "scoped layer protects its frame against restore"
     (with-skia ([s (make-surface 20 20)])
       (define c (surface-canvas s))
       (with-canvas-layer c
         (check-exn exn:fail? (lambda () (canvas-restore! (surface-canvas s))))
         (check-exn exn:fail? (lambda () (canvas-restore-to-count! c 1))))
       (check-equal? (canvas-save-count c) 1)))
   (test-case "nested states and layers restore on arbitrary raised values"
     (with-skia ([s (make-surface 20 20)])
       (define c (surface-canvas s))
       (check-exn (lambda (e) (eq? e 'stop))
         (lambda () (with-canvas-state c (with-canvas-layer c (canvas-save! c) (raise 'stop)))))
       (check-equal? (canvas-save-count c) 1)))
   (test-case "continuation escape restores the layer"
     (with-skia ([s (make-surface 20 20)])
       (define c (surface-canvas s))
       (check-eq? (let/ec leave (with-canvas-layer c (leave 'done))) 'done)
       (check-equal? (canvas-save-count c) 1)))
   (test-case "owner may be closed inside scope"
     (with-skia ([s (make-surface 20 20)])
       (with-canvas-layer (surface-canvas s) (skia-close! s))
       (check-true (skia-closed? s))))
   (test-case "closed canvas rejects all new native operations"
     (define s (make-surface 20 20)) (define c (surface-canvas s)) (skia-close! s)
     (check-exn exn:fail? (lambda () (canvas-save-layer! c)))
     (check-exn exn:fail? (lambda () (canvas-device-clip-bounds c)))
     (check-exn exn:fail? (lambda () (draw-color c 'red))))
   (test-case "queries and layers enforce thread affinity"
     (with-skia ([s (make-surface 20 20)])
       (define c (surface-canvas s)) (define ch (make-channel))
       (define worker
         (thread (lambda ()
                   (channel-put ch (with-handlers ([exn:fail? (lambda (_) #t)]) (canvas-save-layer! c) #f))
                   (channel-put ch (with-handlers ([exn:fail? (lambda (_) #t)]) (canvas-local-clip-bounds c) #f)))))
       (check-true (channel-get ch)) (check-true (channel-get ch)) (thread-wait worker)))
   (test-case "expired document page is rejected"
     (with-skia ([d (make-pdf-document)])
       (define c (document-begin-page! d 100 80)) (document-end-page! d)
       (check-exn exn:fail? (lambda () (canvas-save-layer! c)))
       (check-exn exn:fail? (lambda () (canvas-clip-empty? c)))))
   (test-case "SVG native point sprites are a blocking audit feature"
     (define r (analyze-output-page (page (lambda (c) (with-skia ([p (make-paint #:stroke-width 5)]) (draw-point c 10 10 p)))) 'svg))
     (check-true (has-feature? r 'point-sprites 'needs-raster)))
   (test-case "SVG arcs and rounded geometry pass vector-only"
     (define-values (bs r)
       (output->bytes/audit (page (lambda (c) (with-skia ([p (make-paint)])
                                  (draw-arc c 5 5 30 30 0 160 p)
                                  (draw-rrect c (make-rounded-rect 45 5 35 30 #:radii 5) p)))) 'svg #:policy 'vector-only))
     (check-true (output-audit-report-vector-only? r)) (check-true (regexp-match? #rx#"<path" bs)))
   (test-case "SVG direct layers are rejected before the body runs"
     (define count 0)
     (check-exn exn:fail:output-audit?
       (lambda () (output->bytes/audit (page (lambda (c) (with-canvas-layer c (set! count 1)))) 'svg #:policy 'error)))
     (check-equal? count 0))
   (test-case "explicit SVG raster group resolves native layers"
     (define-values (bs r)
       (output->bytes/audit (page (lambda (c) (draw-rasterized c 0 0 40 25 layer-pair #:scale 2))) 'svg #:policy 'error))
     (check-true (has-feature? r 'layer 'rasterized))
     (check-false (output-audit-report-blocking? r)) (check-true (regexp-match? #rx#"<image" bs)))
   (test-case "PDF layers expose paint filters and native expansion"
     (define r (analyze-output-page
                (page (lambda (c) (with-skia ([f (make-blur-image-filter 2 2)] [p (make-paint #:image-filter f)])
                                   (with-canvas-layer c #:paint p (opaque-pair c))))) 'pdf))
     (check-true (has-feature? r 'layer 'native-expansion))
     (check-true (has-feature? r 'image-filter 'native-expansion)))
   (test-case "recorded layer provenance survives closure"
     (with-skia ([pic (call-with-picture 40 25 layer-pair)])
       (define r (analyze-output-page (page (lambda (c) (draw-picture c pic))) 'svg))
       (check-true (has-feature? r 'layer 'needs-raster))))
   (test-case "m119 unfiltered layer bounds may restrict the source"
     (with-skia ([s (make-surface 40 25)] [p (make-paint #:color 'red)])
       (define c (surface-canvas s))
       (with-canvas-layer c #:bounds '(15 8 5 5) (draw-rect c 3 3 30 18 p))
       (check-equal? (rgba-alpha (surface-pixel s 5 5)) 0)
       (check-equal? (surface-pixel s 17 10) (rgb 255 0 0))))
   (test-case "recording cannot finish inside protected layer scope"
     (with-skia ([rec (make-picture-recorder)])
       (define c (picture-recorder-begin-recording! rec 0 0 30 30))
       (with-canvas-layer c
         (check-exn exn:fail? (lambda () (picture-recorder-finish-recording! rec))))
       (with-skia ([pic (picture-recorder-finish-recording! rec)]) (check-true (picture? pic)))))
   (test-case "PDF page cannot end inside layer scope"
     (with-skia ([d (make-pdf-document)])
       (define c (document-begin-page! d 30 30))
       (with-canvas-layer c (check-exn exn:fail? (lambda () (document-end-page! d))))
       (document-end-page! d) (check-equal? (document-page-count d) 1)))
   (test-case "recorded point arrays do not borrow caller vectors"
     (define xy (vector (vector 10 10) (vector 20 20)))
     (with-skia ([p (make-paint #:color 'red #:stroke-width 6)]
                 [pic (call-with-picture 30 30 (lambda (c) (draw-points c xy p)))]
                 [s (make-surface 30 30)])
       (vector-set! (vector-ref xy 0) 0 999)
       (skia-close! p) (draw-picture (surface-canvas s) pic)
       (check-equal? (surface-pixel s 10 10) (rgb 255 0 0))))
   (test-case "non-default color blend and unbounded recorded fills are audited"
     (check-true (has-feature? (analyze-output-page (page (lambda (c) (draw-color c 'red #:blend-mode 'multiply))) 'svg)
                              'blend-mode 'needs-raster))
     (with-skia ([pic (call-with-picture 20 20 (lambda (c) (draw-color c 'red)))])
       (check-true (has-feature? (analyze-output-page (page (lambda (c) (draw-picture c pic))) 'svg)
                                'recorded-color-fill 'needs-raster))))))
