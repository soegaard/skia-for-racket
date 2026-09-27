#lang racket/base
(require rackunit rackunit/text-ui racket/file racket/list
         "../main.rkt" "../private/picture-util.rkt")
(provide picture-native-tests)
(define (test-picture #:spatial-index [index 'none])
  (call-with-picture 32 24
    (lambda (c)
      (with-skia ([red (make-paint #:color 'red #:antialias? #f)]
                  [blue (make-paint #:color 'blue #:antialias? #f)])
        (draw-rect c 0 0 16 24 red) (draw-rect c 16 0 16 24 blue)))
    #:spatial-index index))
(define (pixels pic [w 32] [h 24])
  (with-skia ([image (picture->image pic w h)]) (image->rgba-bytes image)))
(define (has? report feature status)
  (for/or ([e (in-list (output-audit-report-events report))])
    (and (eq? (output-audit-event-feature e) feature) (eq? (output-audit-event-status e) status))))
(define (temp-dir proc)
  (define dir (make-temporary-file "skia-picture-native-~a" 'directory))
  (dynamic-wind void (lambda () (proc dir)) (lambda () (delete-directory/files dir))))
(define (thread-rejects? thunk)
  (define ch (make-channel))
  (thread (lambda ()
            (channel-put ch (with-handlers ([exn:fail? (lambda (_) #t)]) (thunk) #f))))
  (channel-get ch))
(define (stripe-tile)
  (call-with-picture 8 4
    (lambda (c)
      (with-skia ([a (make-paint #:color 'red #:antialias? #f)]
                  [b (make-paint #:color 'blue #:antialias? #f)])
        (draw-rect c 0 0 4 4 a) (draw-rect c 4 0 4 4 b)))))
(define (runtime-picture #:spatial-index [index 'none])
  (with-skia ([effect (make-runtime-effect "uniform float r; half4 main(float2 p) { return half4(r, 0, 0, 1); }")]
              [shader (runtime-effect->shader effect #:uniforms (hash 'r 1))]
              [paint (make-paint #:shader shader)])
    (call-with-picture 32 24 (lambda (c) (draw-rect c 0 0 32 24 paint)) #:spatial-index index)))
(define picture-native-tests
  (test-suite "Persistent pictures: native streams, retained resources, spatial indexing, and audit"
   (test-case "roundtrip returns the ordinary owned picture type"
     (with-skia ([source (test-picture)]
                 [loaded (picture-from-bytes (picture->bytes source) #:trusted? #t)])
       (check-true (picture? loaded)) (check-true (skia-resource? loaded))
       (check-false (skia-closed? loaded))
       (check-= (picture-width loaded) 32 0) (check-= (picture-height loaded) 24 0)))
   (test-case "native roundtrip preserves geometry and retained depth under later projection"
     (with-skia ([source (test-picture)]
                 [loaded (picture-from-bytes (picture->bytes source) #:trusted? #t)])
       (check-equal? (pixels source) (pixels loaded)))
     ;; The native stream has CONCAT44 / SET_M44 opcodes. Compare under an
     ;; OUTER perspective transform, so early projection to 3x3 is observable.
     (define tilt (matrix4-rotate-y-degrees 35))
     (define (record m)
       (call-with-picture 80 80
         (lambda (c)
           (with-skia ([paint (make-paint #:color 'red #:antialias? #f)])
             (with-canvas-matrix c m (draw-rect c 16 16 32 32 paint))))))
     (define (projected p)
       (with-skia ([surface (make-surface 96 96)])
         (define c (surface-canvas surface))
         (canvas-concat-matrix4! c (matrix4-perspective 160))
         (draw-picture c p)
         (surface->rgba-bytes surface)))
     (with-skia ([source (record tilt)]
                 [flat (record (matrix4-project-xy tilt))]
                 [loaded (picture-from-bytes (picture->bytes source) #:trusted? #t)])
       (check-equal? (projected source) (projected loaded))
       (check-not-equal? (projected source) (projected flat))))
   (test-case "serialized byte results are independent snapshots"
     (with-skia ([source (test-picture)])
       (define a (picture->bytes source)) (define b (picture->bytes source))
       (check-false (eq? a b)) (check-false (immutable? a))
       (bytes-set! a 0 0) (check-equal? (subbytes b 0 8) #"skiapict")
       (with-skia ([loaded (picture-from-bytes b #:trusted? #t)])
         (check-equal? (pixels source) (pixels loaded)))))
   (test-case "loaded picture does not borrow the mutable input buffer"
     (with-skia ([source (test-picture)])
       (define bs (picture->bytes source))
       (with-skia ([loaded (picture-from-bytes bs #:trusted? #t)])
         (bytes-fill! bs 0) (collect-garbage)
         (check-equal? (pixels source) (pixels loaded)))))
   (test-case "loaded drawing survives closure of the original picture and paints"
     (define bs (with-skia ([source (test-picture)]) (picture->bytes source)))
     (with-skia ([loaded (picture-from-bytes bs #:trusted? #t)] [surface (make-surface 32 24)])
       (collect-garbage) (draw-picture (surface-canvas surface) loaded)
       (check-equal? (surface-pixel surface 2 2) (rgb 255 0 0))
       (check-equal? (surface-pixel surface 20 2) (rgb 0 0 255))))
   (test-case "file serialization and loading use the same stream"
     (temp-dir
      (lambda (dir)
        (with-skia ([source (test-picture)])
          (define file (build-path dir "drawing.skp")) (save-picture source file)
          (with-skia ([loaded (picture-from-file file #:trusted? #t)])
            (check-equal? (pixels source) (pixels loaded)))))))
   (test-case "save-picture refuses overwrite by default and supports explicit replacement"
     (temp-dir
      (lambda (dir)
        (with-skia ([source (test-picture)])
          (define file (build-path dir "drawing.skp")) (save-picture source file)
          (define old (file->bytes file))
          (check-exn exn:fail? (lambda () (save-picture source file)))
          (check-equal? (file->bytes file) old)
          (save-picture source file #:exists 'replace)
          (check-equal? (length (directory-list dir)) 1)))))
   (test-case "serialization failure cannot replace an existing destination"
     (temp-dir
      (lambda (dir)
        (with-skia ([source (test-picture)])
          (define file (build-path dir "drawing.skp")) (save-picture source file)
          (define old (file->bytes file))
          (parameterize ([current-skia-byte-limit 28])
            (check-exn exn:fail? (lambda () (save-picture source file #:exists 'replace))))
          (check-equal? (file->bytes file) old)
          (check-equal? (length (directory-list dir)) 1)))))
   (test-case "a valid header does not make a truncated payload valid"
     (with-skia ([source (test-picture)])
       (define bs (picture->bytes source))
       (check-exn #rx"decoder rejected" (lambda () (picture-from-bytes (subbytes bs 0 29) #:trusted? #t)))))
   (test-case "serial header version is distinct from native milestone"
     (with-skia ([source (test-picture)])
       (define-values (v b) (picture-header 'test (picture->bytes source)))
       (check-equal? v 103) (check-equal? b #(0.0 0.0 32.0 24.0))
       (check-equal? (picture-cull-bounds source) b)))
   (test-case "metadata IDs are stable within a live object and distinct in the same process"
     (with-skia ([source (test-picture)]
                 [loaded (picture-from-bytes (picture->bytes source) #:trusted? #t)])
       (check-true (exact-positive-integer? (picture-unique-id source)))
       (check-equal? (picture-unique-id source) (picture-unique-id source))
       (check-not-equal? (picture-unique-id source) (picture-unique-id loaded))))
   (test-case "operation and memory counters are approximate native metadata"
     (with-skia ([source (test-picture)]
                 [outer (call-with-picture 64 24
                          (lambda (c) (draw-picture c source) (draw-picture c source #:x 32)))])
       (check-true (exact-nonnegative-integer? (picture-approximate-op-count source)))
       (check-true (>= (picture-approximate-op-count outer #:nested? #t)
                      (picture-approximate-op-count outer)))
       (check-true (exact-positive-integer? (picture-approximate-bytes-used source)))))
   (test-case "native cull snapshots remain readable after closure, getters do not"
     (with-skia ([source (test-picture)])
       (define bounds (picture-cull-bounds source))
       (skia-close! source)
       (check-true (immutable? bounds)) (check-equal? bounds #(0.0 0.0 32.0 24.0))
       (for ([get (list picture-cull-bounds picture-unique-id picture-approximate-op-count picture-approximate-bytes-used)])
         (check-exn exn:fail? (lambda () (get source))))))
   (test-case "serialization and shader construction reject a closed source"
     (with-skia ([source (test-picture)])
       (skia-close! source)
       (check-exn exn:fail? (lambda () (picture->bytes source)))
       (check-exn exn:fail? (lambda () (make-picture-shader source)))))
   (test-case "metadata and serialization obey thread affinity"
     (with-skia ([source (test-picture)])
       (check-true (thread-rejects? (lambda () (picture-cull-bounds source))))
       (check-true (thread-rejects? (lambda () (picture->bytes source))))
       (check-true (thread-rejects? (lambda () (make-picture-shader source))))))
   (test-case "empty recordings serialize without invented nonzero extents"
     (with-skia ([source (call-with-picture 30 20 void)]
                 [loaded (picture-from-bytes (picture->bytes source) #:trusted? #t)]
                 [surface (make-surface 30 20)])
       ;; Serialization may add/elide bookkeeping operations. The counter is
       ;; an estimate, not a promise about the optimized empty stream.
       (check-true (exact-nonnegative-integer? (picture-approximate-op-count loaded)))
       (check-= (picture-width loaded) 0 0) (check-= (picture-height loaded) 0 0)
       (check-equal? (picture-cull-bounds loaded) #(0.0 0.0 0.0 0.0))
       (draw-picture (surface-canvas surface) loaded)
       (check-equal? (rgba-alpha (surface-pixel surface 5 5)) 0)))
   (test-case "nonzero cull origins are preserved rather than silently recentered"
     (with-skia ([rec (make-picture-recorder)] [paint (make-paint #:color 'red #:antialias? #f)])
       (define c (picture-recorder-begin-recording! rec 10 20 30 20))
       (draw-rect c 10 20 30 20 paint)
       (with-skia ([source (picture-recorder-finish-recording! rec)]
                   [loaded (picture-from-bytes (picture->bytes source) #:trusted? #t)]
                   [surface (make-surface 60 60)])
         (check-equal? (picture-cull-bounds loaded) #(10.0 20.0 30.0 20.0))
         (draw-picture (surface-canvas surface) loaded)
         (check-equal? (rgba-alpha (surface-pixel surface 3 3)) 0)
         (check-equal? (surface-pixel surface 12 22) (rgb 255 0 0)))))
   (test-case "a nominal extent override does not alter stored cull or drawing coordinates"
     (with-skia ([source (test-picture)]
                 [loaded (picture-from-bytes (picture->bytes source) #:trusted? #t #:width 64 #:height 48)])
       (check-= (picture-width loaded) 64 0) (check-= (picture-height loaded) 48 0)
       (check-equal? (picture-cull-bounds loaded) #(0.0 0.0 32.0 24.0))))
   (test-case "R-tree and ordinary recordings draw identical simple content"
     (with-skia ([normal (test-picture)] [indexed (test-picture #:spatial-index 'rtree)])
       (check-equal? (pixels normal) (pixels indexed))))
   (test-case "R-tree cull can tighten without changing the declared Racket extent"
     (with-skia ([p (call-with-picture 100 80
                     (lambda (c)
                       (with-skia ([paint (make-paint #:color 'red #:antialias? #f)])
                         (draw-rect c 12 15 10 8 paint))) #:spatial-index 'rtree)])
       (define b (picture-cull-bounds p))
       (check-= (picture-width p) 100 0) (check-= (picture-height p) 80 0)
       (check-true (< (vector-ref b 2) 100))
       (check-true (< (vector-ref b 3) 80))
       (with-skia ([loaded (picture-from-bytes (picture->bytes p) #:trusted? #t
                                             #:width (picture-width p) #:height (picture-height p))])
         (check-equal? (pixels p 100 80) (pixels loaded 100 80)))))
   (test-case "R-tree borrowed canvases expire after finish"
     (with-skia ([rec (make-picture-recorder)] [paint (make-paint)])
       (define c (picture-recorder-begin-recording! rec 0 0 32 24 #:spatial-index 'rtree))
       (draw-rect c 0 0 10 10 paint)
       (with-skia ([p (picture-recorder-finish-recording! rec)])
         (check-exn exn:fail? (lambda () (draw-rect c 0 0 1 1 paint))))))
   (test-case "protected canvas scopes still prevent finishing indexed recordings"
     (with-skia ([rec (make-picture-recorder)])
       (define c (picture-recorder-begin-recording! rec 0 0 32 24 #:spatial-index 'rtree))
       (with-canvas-state c
         (check-exn exn:fail? (lambda () (picture-recorder-finish-recording! rec))))
       (with-skia ([p (picture-recorder-finish-recording! rec)]) (check-true (picture? p)))))
   (test-case "indexed live runtime pictures retain their audit summary"
     (with-skia ([p (runtime-picture #:spatial-index 'rtree)])
       (define r (analyze-output-page (make-output-page 40 30 (lambda (c) (draw-picture c p))) 'svg))
       (check-true (has? r 'runtime-shader 'needs-raster))))
   (test-case "reusing a recorder with R-tree clears the preceding opaque summary"
     (with-skia ([source (test-picture)] [loaded (picture-from-bytes (picture->bytes source) #:trusted? #t)]
                 [rec (make-picture-recorder)] [paint (make-paint #:color 'red)])
       (draw-picture (picture-recorder-begin-recording! rec 0 0 32 24) loaded)
       (with-skia ([old (picture-recorder-finish-recording! rec)])
         (define c (picture-recorder-begin-recording! rec 0 0 32 24 #:spatial-index 'rtree))
         (draw-rect c 0 0 12 12 paint)
         (with-skia ([clean (picture-recorder-finish-recording! rec)])
           (define r (analyze-output-page (make-output-page 40 30 (lambda (out) (draw-picture out clean))) 'svg))
           (check-false (output-audit-report-blocking? r))
           (check-true (output-audit-report-vector-only? r))))))
   (test-case "loaded pixels may be correct while provenance remains unknown"
     (with-skia ([source (test-picture)] [loaded (picture-from-bytes (picture->bytes source) #:trusted? #t)])
       (for ([backend '(pdf svg)])
         (define-values (bs r)
           (output->bytes/audit (make-output-page 40 30 (lambda (c) (draw-picture c loaded)))
                               backend #:policy 'report))
         (check-true (> (bytes-length bs) 0))
         (check-true (has? r 'deserialized-picture 'unknown))
         (check-true (output-audit-report-blocking? r)))))
   (test-case "strict export of a loaded picture refuses publication"
     (temp-dir
      (lambda (dir)
        (with-skia ([source (test-picture)] [loaded (picture-from-bytes (picture->bytes source) #:trusted? #t)])
          (define target (build-path dir "keep.svg"))
          (call-with-output-file target (lambda (out) (write-bytes #"keep" out)))
          (check-exn exn:fail:output-audit?
            (lambda () (save-output/audit (make-output-page 40 30 (lambda (c) (draw-picture c loaded)))
                                         target 'svg #:exists 'replace #:policy 'error)))
          (check-equal? (file->bytes target) #"keep")))))
   (test-case "explicit rasterization cannot invent missing loaded-picture provenance"
     (with-skia ([source (test-picture)] [loaded (picture-from-bytes (picture->bytes source) #:trusted? #t)])
       (define page (make-output-page 40 30
                      (lambda (c) (draw-rasterized c 0 0 32 24 (lambda (r) (draw-picture r loaded))))))
       (for ([backend '(pdf svg)])
         (check-true (has? (analyze-output-page page backend) 'deserialized-picture 'unknown)))))
   (test-case "ordinary picture-shader tiling renders repeated local coordinates"
     (with-skia ([p (stripe-tile)] [shader (make-picture-shader p #:tile-x 'repeat #:tile-y 'repeat)]
                 [paint (make-paint #:shader shader)] [s (make-surface 24 12)])
       (draw-rect (surface-canvas s) 0 0 24 12 paint)
       (check-equal? (surface-pixel s 2 2) (rgb 255 0 0))
       (check-equal? (surface-pixel s 6 2) (rgb 0 0 255))
       (check-equal? (surface-pixel s 10 6) (rgb 255 0 0))))
   (test-case "mirror tiles reverse alternate repetitions"
     (with-skia ([p (stripe-tile)] [shader (make-picture-shader p #:tile-x 'mirror #:tile-y 'repeat)]
                 [paint (make-paint #:shader shader)] [s (make-surface 24 12)])
       (draw-rect (surface-canvas s) 0 0 24 12 paint)
       (check-equal? (surface-pixel s 10 2) (rgb 0 0 255))
       (check-equal? (surface-pixel s 14 2) (rgb 255 0 0))))
   (test-case "explicit tile extent can include transparent padding"
     (with-skia ([p (stripe-tile)]
                 [shader (make-picture-shader p #:tile-x 'repeat #:tile-y 'repeat #:tile-rect '(0 0 12 4))]
                 [paint (make-paint #:shader shader)] [s (make-surface 24 8)])
       (draw-rect (surface-canvas s) 0 0 24 8 paint)
       (check-equal? (rgba-alpha (surface-pixel s 10 2)) 0)
       (check-equal? (surface-pixel s 14 2) (rgb 255 0 0))))
   (test-case "picture shader local matrices change samples, not destination geometry"
     (with-skia ([p (stripe-tile)]
                 [shader (make-picture-shader p #:tile-x 'repeat #:local-matrix (matrix-translate 2 0))]
                 [paint (make-paint #:shader shader)] [s (make-surface 16 4)])
       (draw-rect (surface-canvas s) 0 0 16 4 paint)
       (check-equal? (surface-pixel s 5 2) (rgb 255 0 0))
       (check-equal? (surface-pixel s 7 2) (rgb 0 0 255))))
   (test-case "shader ownership survives closing the source picture"
     (define shader
       (with-skia ([p (stripe-tile)]) (make-picture-shader p #:tile-x 'repeat #:tile-y 'repeat)))
     (with-skia ([owned shader] [paint (make-paint #:shader owned)] [s (make-surface 16 8)])
       (collect-garbage) (draw-rect (surface-canvas s) 0 0 16 8 paint)
       (check-equal? (surface-pixel s 10 6) (rgb 255 0 0))))
   (test-case "picture-shader provenance survives paint copying and retained getters"
     (with-skia ([p (stripe-tile)] [shader (make-picture-shader p)]
                 [paint (make-paint #:shader shader)] [copy (paint-copy paint)]
                 [retained (paint-shader copy)] [final (make-paint #:shader retained)])
       (skia-close! p) (skia-close! shader) (skia-close! paint) (skia-close! copy)
       (define page (make-output-page 40 30 (lambda (c) (draw-rect c 0 0 32 24 final))))
       (check-true (has? (analyze-output-page page 'svg) 'picture-shader 'needs-raster))))
   (test-case "live picture shaders are accepted inside explicit fallback groups"
     (with-skia ([p (stripe-tile)] [shader (make-picture-shader p #:tile-x 'repeat)]
                 [paint (make-paint #:shader shader)])
       (for ([backend '(pdf svg)])
         (define-values (bs r)
           (output->bytes/audit
            (make-output-page 40 30
              (lambda (c) (draw-rasterized c 0 0 32 24 (lambda (r) (draw-rect r 0 0 32 24 paint)))))
            backend #:policy 'error))
         (check-true (> (bytes-length bs) 0)) (check-false (output-audit-report-blocking? r))
         (check-true (has? r 'picture-shader 'rasterized)))))
   (test-case "shader use of a loaded picture stays unknown after input closure"
     (with-skia ([source (test-picture)] [loaded (picture-from-bytes (picture->bytes source) #:trusted? #t)]
                 [shader (make-picture-shader loaded)] [paint (make-paint #:shader shader)])
       (skia-close! loaded)
       (define r (analyze-output-page
                  (make-output-page 40 30 (lambda (c) (draw-rect c 0 0 32 24 paint))) 'svg))
       (check-true (has? r 'deserialized-picture 'unknown))))
   (test-case "sampling a recorded URL reports discarded interactivity"
     (with-skia ([p (call-with-picture 16 16
                     (lambda (c)
                       (with-skia ([fill (make-paint #:color 'red)]) (draw-rect c 0 0 16 16 fill))
                       (canvas-annotate-url! c 0 0 16 16 "https://example.invalid/")))]
                 [shader (make-picture-shader p)] [paint (make-paint #:shader shader)])
       (for ([backend '(pdf svg)])
         (define r (analyze-output-page
                    (make-output-page 30 30 (lambda (c) (draw-rect c 0 0 16 16 paint))) backend))
         (check-true (has? r 'picture-shader-annotation 'discarded)))))
   (test-case "the pinned default decoder can compile embedded trusted SkSL"
     (with-skia ([source (runtime-picture)]
                 [loaded (picture-from-bytes (picture->bytes source) #:trusted? #t)])
       (check-equal? (pixels source) (pixels loaded))
       (check-true (has? (analyze-output-page
                         (make-output-page 40 30 (lambda (c) (draw-picture c loaded))) 'svg)
                        'deserialized-picture 'unknown))))
   (test-case "recorded images are retained through native encode and decode"
     (define source
       (with-skia ([s (make-surface 8 8 #:background 'green)] [im (surface-snapshot s)])
         (call-with-picture 32 24 (lambda (c) (draw-image-rect c im 0 0 32 24 #:sampling 'nearest)))))
     (with-skia ([p source] [loaded (picture-from-bytes (picture->bytes p) #:trusted? #t)])
       (collect-garbage) (check-equal? (pixels p) (pixels loaded))))
   (test-case "URLs in trusted streams are retained by the native decoder"
     (with-skia ([p (call-with-picture 40 30
                     (lambda (c)
                       (canvas-annotate-url! c 0 0 10 10 "https://example.invalid/cache")))]
                 [loaded (picture-from-bytes (picture->bytes p) #:trusted? #t)])
       (define svg (call-with-svg-string 40 30 (lambda (c) (draw-picture c loaded))))
       (check-not-false (regexp-match? #rx"example.invalid/cache" svg))))
   (test-case "repeated create serialize decode close cycles preserve rendering"
     (for ([i (in-range 12)])
       (with-skia ([source (test-picture #:spatial-index (if (even? i) 'rtree 'none))]
                   [loaded (picture-from-bytes (picture->bytes source) #:trusted? #t)])
         (check-equal? (pixels source) (pixels loaded)))))))
(module+ test (run-tests picture-native-tests))
