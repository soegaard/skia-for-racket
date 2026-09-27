#lang racket/base
(require rackunit racket/list "../main.rkt")
(provide geometry-native-tests)
(define triangle '((0 0) (30 0) (0 30)))
(define square-patch '((0 0) (10 0) (20 0) (30 0) (30 10) (30 20)
                       (30 30) (20 30) (10 30) (0 30) (0 20) (0 10)))
(define (page f) (make-output-page 100 80 f))
(define (has-feature? report feature status)
  (for/or ([e (in-list (output-audit-report-events report))])
    (and (eq? feature (output-audit-event-feature e)) (eq? status (output-audit-event-status e)))))
(define (test-image)
  (define b (make-bytes (* 24 24 4)))
  (for* ([y (in-range 24)] [x (in-range 24)])
    (define red? (or (< x 6) (>= x 18) (< y 6) (>= y 18)))
    (define at (* 4 (+ x (* y 24))))
    (bytes-set! b at (if red? 255 0)) (bytes-set! b (+ at 1) (if red? 0 255))
    (bytes-set! b (+ at 3) 255))
  (rgba-bytes->image 24 24 b))
(define geometry-native-tests
  (test-suite "Structured geometry and advanced image drawing: native backends"
   (test-case "empty region is an owned resource with empty snapshots"
     (with-skia ([r (make-region)])
       (check-true (region? r)) (check-true (skia-resource? r))
       (check-true (region-empty? r)) (check-false (region-rect? r))
       (check-equal? (region-bounds r) #(0 0 0 0))
       (check-equal? (region-rectangles r) '()))
   )
   (test-case "region point containment uses half-open integer rectangles"
     (with-skia ([r (make-region '((2 3 10 12)))])
       (check-true (region-rect? r))
       (check-true (region-contains-point? r 2 3))
       (check-true (region-contains-point? r 11 14))
       (check-false (region-contains-point? r 12 15)))
   )
   (test-case "region union preserves a hole and inputs"
     (with-skia ([a (make-region '((0 0 10 10)))] [b (make-region '((20 0 10 10)))]
                 [u (region-union a b)])
       (check-true (region-complex? u)) (check-false (region-contains-point? u 15 5))
       (check-equal? (region-bounds u) #(0 0 30 10))
       (check-equal? (region-bounds a) #(0 0 10 10)))
   )
   (test-case "intersection and difference return independent owned results"
     (with-skia ([a (make-region '((0 0 20 20)))] [b (make-region '((10 0 20 20)))]
                 [i (region-intersect a b)] [d (region-difference a b)])
       (check-equal? (region-bounds i) #(10 0 10 20))
       (check-equal? (region-bounds d) #(0 0 10 20)))
   )
   (test-case "xor reverse difference and replace use the correct op codes"
     (with-skia ([a (make-region '((0 0 20 20)))] [b (make-region '((10 0 20 20)))]
                 [x (region-xor a b)] [d (region-op a b 'reverse-difference)] [r (region-op a b 'replace)])
       (check-false (region-contains-point? x 15 10))
       (check-equal? (region-bounds d) #(20 0 10 20))
       (check-equal? (region-bounds r) (region-bounds b)))
   )
   (test-case "empty operation results are not allocation failures"
     (with-skia ([a (make-region '((0 0 10 10)))] [b (region-difference a a)])
       (check-true (region-empty? b)))
   )
   (test-case "translation copies and bounds overflow rejects"
     (with-skia ([r (make-region '((0 0 10 10)))] [q (region-translate r 7 -3)])
       (check-equal? (region-bounds q) #(7 -3 10 10))
       (check-equal? (region-bounds r) #(0 0 10 10))
       (check-exn exn:fail:contract? (lambda () (region-translate r 1073741823 0))))
   )
   (test-case "region containment and intersection queries are distinct"
     (with-skia ([a (make-region '((0 0 20 20)))] [b (make-region '((5 5 5 5)))] [c (make-region '((19 19 5 5)))])
       (check-true (region-contains-region? a b))
       (check-true (region-contains-rect? a '(5 5 5 5)))
       (check-true (region-intersects? a c))
       (check-false (region-contains-region? a c)))
   )
   (test-case "rectangle snapshot sequence survives source closure"
     (with-skia ([r (make-region '((0 0 5 5) (10 0 5 5)))])
       (define values (region-rectangles r)) (define seq (in-region-rectangles r))
       (skia-close! r)
       (check-equal? (for/list ([b seq]) b) values)
       (check-equal? (for/list ([b seq]) b) values)
       (for ([b values]) (check-true (immutable? b))))
   )
   (test-case "rectangle snapshots enforce output budget"
     (with-skia ([r (make-region '((0 0 5 5) (10 0 5 5)))])
       (parameterize ([current-skia-byte-limit 16])
         (check-exn exn:fail:contract? (lambda () (region-rectangles r)))))
   )
   (test-case "path conversion scan-converts within an explicit clip"
     (with-skia ([p (make-path '((move 0 0) (line 30 0) (line 0 30) (close)))]
                 [clip (make-region '((0 0 12 12)))] [r (path->region p clip)])
       (check-equal? (region-bounds r) #(0 0 12 12))
       (check-true (region-contains-point? r 2 2))
       (check-false (region-contains-point? r 20 2)))
   )
   (test-case "boundary path remains usable after closing region"
     (with-skia ([r (make-region '((3 4 10 10)))] [p (region->path r)])
       (skia-close! r)
       (check-true (path-contains? p 5 6))
       (check-false (path-contains? p 20 20)))
   )
   (test-case "draw-region follows the canvas transform and filled SVG regions have no rectangle seams"
     (with-skia ([s (make-surface 40 30)] [r (make-region '((0 0 10 10)))] [p (make-paint #:color 'red)])
       (define c (surface-canvas s)) (canvas-translate! c 15 5) (draw-region c r p)
       (check-equal? (surface-pixel s 18 8) (rgb 255 0 0))
       (check-equal? (rgba-alpha (surface-pixel s 3 3)) 0))
     ;; A complex filled region must serialize as one path, not as touching
     ;; SVG rectangles whose independently antialiased edges can show seams.
     (define svg
       (call-with-svg-string
        40 30
        (lambda (c)
          (with-skia ([r (make-region '((0 0 20 10) (0 10 10 10)))]
                      [p (make-paint #:color 'red)])
            (draw-region c r p)))))
     (check-true (regexp-match? #rx"<path" svg))
     (check-false (regexp-match? #rx"<rect" svg))
   )
   (test-case "region clipping is device-space even after translation"
     (with-skia ([s (make-surface 40 30)] [r (make-region '((5 5 10 10)))])
       (define c (surface-canvas s)) (canvas-translate! c 20 0)
       (with-canvas-state c (canvas-clip-region! c r) (draw-color c 'red))
       (check-equal? (surface-pixel s 8 8) (rgb 255 0 0))
       (check-equal? (rgba-alpha (surface-pixel s 28 8)) 0)
       (check-equal? (canvas-device-clip-bounds c) #(0 0 40 30)))
   )
   (test-case "region closure and thread affinity are enforced"
     (with-skia ([r (make-region '((0 0 10 10)))])
       (define ch (make-channel))
       (thread (lambda () (channel-put ch (with-handlers ([exn:fail? (lambda (_) #t)]) (region-bounds r) #f))))
       (check-true (channel-get ch))
       (skia-close! r) (check-true (skia-closed? r))
       (check-exn exn:fail? (lambda () (region-bounds r))))
   )
   (test-case "vertices own copies and expose detached snapshots"
     (define ps (vector (vector 0 0) #(30 0) #(0 30)))
     (with-skia ([v (make-vertices 'triangles ps #:colors '(red red red))])
       (vector-set! (vector-ref ps 0) 0 99)
       (check-true (vertices? v)) (check-true (skia-resource? v))
       (check-equal? (vertices-count v) 3) (check-eq? (vertices-mode v) 'triangles)
       (check-equal? (vector-ref (vertices-positions v) 0) #(0.0 0.0))
       (define snapshot (vertices-positions v)) (skia-close! v)
       (check-equal? (vertices-positions v) snapshot))
   )
   (test-case "triangle colors are interpolated using opaque white paint"
     (with-skia ([s (make-surface 40 40)] [v (make-vertices 'triangles triangle #:colors '(red red red))]
                 [p (make-paint #:color 'white)])
       (draw-vertices (surface-canvas s) v p)
       (check-equal? (surface-pixel s 4 4) (rgb 255 0 0))
       (check-equal? (rgba-alpha (surface-pixel s 35 35)) 0))
   )
   (test-case "mesh color blending is separate from framebuffer blending"
     (with-skia ([s (make-surface 40 40)] [v (make-vertices 'triangles triangle #:colors '(red red red))]
                 [p (make-paint #:color 'blue)])
       (draw-vertices (surface-canvas s) v p #:blend-mode 'src)
       (check-equal? (surface-pixel s 4 4) (rgb 0 0 255))
       (draw-vertices (surface-canvas s) v p #:blend-mode 'dst)
       (check-equal? (surface-pixel s 4 4) (rgb 255 0 0)))
   )
   (test-case "indexed triangles reuse their position array"
     (with-skia ([s (make-surface 40 40)]
                 [v (make-vertices 'triangles '((0 0) (30 0) (30 30) (0 30)) #:indices '(0 1 2 0 2 3))]
                 [p (make-paint #:color 'blue)])
       (draw-vertices (surface-canvas s) v p)
       (check-equal? (vertices-indices v) #(0 1 2 0 2 3))
       (check-equal? (surface-pixel s 5 20) (rgb 0 0 255)))
   )
   (test-case "triangle strip and fan render filled interiors"
     (for ([mode '(triangle-strip triangle-fan)]
           [ps '(((0 0) (30 0) (0 30) (30 30)) ((0 0) (30 0) (30 30) (0 30)))])
       (with-skia ([s (make-surface 40 40)] [v (make-vertices mode ps)] [p (make-paint #:color 'red)])
         (draw-vertices (surface-canvas s) v p)
         (check-equal? (surface-pixel s 10 15) (rgb 255 0 0))))
   )
   (test-case "mesh shader receives submitted texture coordinates"
     (with-skia ([s (make-surface 40 40)] [im (rgba-bytes->image 1 1 (bytes 0 255 0 255))]
                 [shader (make-image-shader im)] [p (make-paint #:shader shader)]
                 [v (make-vertices 'triangles triangle #:texture-coordinates '((0 0) (1 0) (0 1)))])
       (draw-vertices (surface-canvas s) v p)
       (check-equal? (surface-pixel s 4 4) (rgb 0 255 0)))
   )
   (test-case "closed mesh rejects drawing"
     (with-skia ([s (make-surface 40 40)] [v (make-vertices 'triangles triangle)] [p (make-paint)])
       (skia-close! v)
       (check-exn exn:fail? (lambda () (draw-vertices (surface-canvas s) v p))))
   )
   (test-case "recorded mesh survives closure of vertices and paint"
     (with-skia ([v (make-vertices 'triangles triangle #:colors '(red red red))] [p (make-paint #:color 'white)]
                 [pic (call-with-picture 40 40 (lambda (c) (draw-vertices c v p)))] [s (make-surface 40 40)])
       (skia-close! v) (skia-close! p)
       (draw-picture (surface-canvas s) pic)
       (check-equal? (surface-pixel s 4 4) (rgb 255 0 0)))
   )
   (test-case "nine-patch keeps border thickness and stretches the center"
     (with-skia ([im (test-image)] [s (make-surface 60 40)])
       (draw-image-nine (surface-canvas s) im '(6 6 12 12) 0 0 60 40 #:sampling 'nearest)
       (check-equal? (surface-pixel s 2 20) (rgb 255 0 0))
       (check-equal? (surface-pixel s 30 20) (rgb 0 255 0)))
   )
   (test-case "lattice and nine-patch agree for a three-by-three grid"
     (with-skia ([im (test-image)] [a (make-surface 60 40)] [b (make-surface 60 40)])
       (draw-image-nine (surface-canvas a) im '(6 6 12 12) 0 0 60 40 #:sampling 'nearest)
       (draw-image-lattice (surface-canvas b) im (make-image-lattice '(6 18) '(6 18)) 0 0 60 40 #:sampling 'nearest)
       (check-equal? (surface->rgba-bytes a) (surface->rgba-bytes b)))
   )
   (test-case "lattice uint8 cell kinds preserve default transparent and fixed cells"
     (define lattice (make-image-lattice '(6 18) '(6 18)
                       #:cell-types '(default transparent fixed-color default transparent default fixed-color default default)
                       #:colors '(white white blue white white white yellow white white)))
     (with-skia ([im (test-image)] [s (make-surface 60 60)])
       (draw-image-lattice (surface-canvas s) im lattice 0 0 60 60 #:sampling 'nearest)
       (check-equal? (surface-pixel s 2 2) (rgb 255 0 0))
       (check-equal? (surface-pixel s 58 2) (rgb 0 0 255))
       (check-equal? (surface-pixel s 2 58) (rgb 255 255 0))
       (check-equal? (rgba-alpha (surface-pixel s 30 2)) 0)
       (check-equal? (rgba-alpha (surface-pixel s 30 30)) 0)
       (canvas-clear! (surface-canvas s) 'transparent)
       (draw-image-lattice (surface-canvas s) im
         (make-image-lattice '(6 18) '(6 18)
           #:cell-types '(default transparent default default default default default default default))
         0 0 60 60 #:sampling 'nearest)
       (check-equal? (rgba-alpha (surface-pixel s 30 2)) 0)
       (check-equal? (surface-pixel s 30 30) (rgb 0 255 0)))
   )
   (test-case "lattice source subset uses absolute divisions"
     (with-skia ([im (test-image)] [s (make-surface 40 40)])
       (draw-image-lattice (surface-canvas s) im
         (make-image-lattice '(10 14) '(10 14) #:bounds '(6 6 12 12)) 0 0 40 40 #:sampling 'nearest)
       (check-equal? (surface-pixel s 20 20) (rgb 0 255 0)))
   )
   (test-case "image-relative lattice validation rejects outside divisions"
     (with-skia ([im (test-image)] [s (make-surface 40 40)])
       (check-exn exn:fail:contract?
         (lambda () (draw-image-lattice (surface-canvas s) im (make-image-lattice '(30) '(6)) 0 0 40 40)))
       (check-exn exn:fail:contract?
         (lambda () (draw-image-nine (surface-canvas s) im '(0 0 30 30) 0 0 40 40))))
   )
   (test-case "lattice draws after constructor input vectors change"
     (define xs (vector 6 18)) (define l (make-image-lattice xs '(6 18))) (vector-set! xs 0 100)
     (with-skia ([im (test-image)] [s (make-surface 40 40)])
       (draw-image-lattice (surface-canvas s) im l 0 0 40 40)
       (check-equal? (surface-pixel s 20 20) (rgb 0 255 0)))
   )
   (test-case "atlas sprite origin is relative to its selected source rectangle"
     (with-skia ([im (test-image)] [s (make-surface 50 40)])
       (draw-atlas (surface-canvas s) im (list (make-atlas-transform 20 10)) '((6 6 12 12)) #:sampling 'nearest)
       (check-equal? (surface-pixel s 22 12) (rgb 0 255 0))
       (check-equal? (rgba-alpha (surface-pixel s 10 10)) 0))
   )
   (test-case "atlas ninety-degree rotation follows y-down canvas coordinates"
     (with-skia ([im (test-image)] [s (make-surface 40 40)])
       (draw-atlas (surface-canvas s) im (list (make-atlas-transform 20 10 #:rotation 90)) '((0 0 8 4)) #:sampling 'nearest)
       (check-equal? (surface-pixel s 18 12) (rgb 255 0 0))
       (check-equal? (rgba-alpha (surface-pixel s 24 12)) 0))
   )
   (test-case "atlas tint uses image as source and per-sprite color as destination"
     (with-skia ([im (test-image)] [s (make-surface 40 40)])
       (draw-atlas (surface-canvas s) im (list (make-atlas-transform 2 2)) '((6 6 12 12))
                   #:colors '(blue) #:blend-mode 'dst #:sampling 'nearest)
       (check-equal? (surface-pixel s 5 5) (rgb 0 0 255)))
   )
   (test-case "atlas array counts and source bounds are checked"
     (with-skia ([im (test-image)] [s (make-surface 40 40)])
       (check-exn exn:fail:contract? (lambda () (draw-atlas (surface-canvas s) im (list (make-atlas-transform 0 0)) '())))
       (check-exn exn:fail:contract? (lambda () (draw-atlas (surface-canvas s) im (list (make-atlas-transform 0 0)) '((20 20 10 10))))))
   )
   (test-case "empty atlas still validates image lifetime"
     (with-skia ([im (test-image)] [s (make-surface 40 40)])
       (draw-atlas (surface-canvas s) im '() '())
       (skia-close! im)
       (check-exn exn:fail? (lambda () (draw-atlas (surface-canvas s) im '() '()))))
   )
   (test-case "Coons patch fills the shared-corner square"
     (with-skia ([s (make-surface 40 40)] [p (make-paint #:color 'white)])
       (draw-patch (surface-canvas s) (make-cubic-patch square-patch #:colors '(red red red red)) p)
       (check-equal? (surface-pixel s 12 14) (rgb 255 0 0))
       (check-equal? (rgba-alpha (surface-pixel s 35 35)) 0))
   )
   (test-case "Coons patch accepts shader texture coordinates"
     (with-skia ([im (rgba-bytes->image 1 1 (bytes 0 0 255 255))] [shader (make-image-shader im)]
                 [p (make-paint #:shader shader)] [s (make-surface 40 40)])
       (draw-patch (surface-canvas s) (make-cubic-patch square-patch #:texture-coordinates '((0 0) (1 0) (1 1) (0 1))) p)
       (check-equal? (surface-pixel s 12 14) (rgb 0 0 255)))
   )
   (test-case "PDF and SVG preflight flag direct meshes without executing them"
     (with-skia ([v (make-vertices 'triangles triangle)] [p (make-paint)])
       (for ([backend '(pdf svg)])
         (define r (analyze-output-page (page (lambda (c) (draw-vertices c v p))) backend))
         (check-true (has-feature? r 'vertices 'needs-raster))))
   )
   (test-case "strict document publication rejects direct mesh operations"
     (with-skia ([v (make-vertices 'triangles triangle)] [p (make-paint)])
       (check-exn exn:fail:output-audit?
         (lambda () (output->bytes/audit (page (lambda (c) (draw-vertices c v p))) 'svg #:policy 'error))))
   )
   (test-case "explicit mesh fallback resolves classification and emits PNG"
     (with-skia ([v (make-vertices 'triangles triangle #:colors '(red red red))] [p (make-paint #:color 'white)])
       (define-values (b r)
         (output->bytes/audit (page (lambda (c) (draw-rasterized c 0 0 40 40 (lambda (rc) (draw-vertices rc v p)))))
                             'svg #:policy 'error))
       (check-false (output-audit-report-blocking? r))
       (check-true (has-feature? r 'vertices 'rasterized))
       (check-true (regexp-match? #rx#"data:image/png;base64," b)))
   )
   (test-case "recording before auditing retains mesh and patch requirements"
     (with-skia ([pic (call-with-picture 40 40 (lambda (c)
                      (with-skia ([p (make-paint)] [v (make-vertices 'triangles triangle)])
                        (draw-vertices c v p) (draw-patch c (make-cubic-patch square-patch) p))))])
       (define r (analyze-output-page (page (lambda (c) (draw-picture c pic))) 'svg))
       (check-true (has-feature? r 'vertices 'needs-raster))
       (check-true (has-feature? r 'coons-patch 'needs-raster)))
   )
   (test-case "boundary-path clipping remains vector in SVG"
     (with-skia ([r (make-region '((0 0 20 20) (30 0 10 20)))] [p (region->path r)] [ink (make-paint)])
       (define-values (_b report)
         (output->bytes/audit (page (lambda (c) (canvas-clip-path! c p) (draw-rect c 0 0 50 30 ink))) 'svg #:policy 'vector-only))
       (check-true (output-audit-report-vector-only? report)))
   )
   (test-case "direct device-region clips are reported separately"
     (with-skia ([r (make-region '((0 0 20 20)))])
       (define report (analyze-output-page (page (lambda (c) (canvas-clip-region! c r))) 'svg))
       (check-true (has-feature? report 'device-region-clip 'needs-raster)))
   )
))
