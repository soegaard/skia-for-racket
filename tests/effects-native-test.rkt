#lang racket/base
(require rackunit rackunit/text-ui racket/list "../main.rkt" "effects-fixtures.rkt")
(provide effects-native-tests)
(define (near-pixel actual expected [tolerance 1])
  (check-true (for/and ([a (in-list actual)] [e (in-list expected)]) (<= (abs (- a e)) tolerance))))
(define (alphas bs) (for/list ([i (in-range 3 (bytes-length bs) 4)]) (bytes-ref bs i)))
(define (capture draw) ((current-effects-renderer) draw))
(define effects-native-tests
  (test-suite
   "0.66 actual effect pixels and retained inputs"
   (test-case "1D stamps retain copied geometry after reset and close"
     (define b (capture-effect-scene 'stamp-1d))
     (near-pixel (effect-pixel b 9 25) '(255 0 0 255))
     (near-pixel (effect-pixel b 21 25) '(255 0 0 255))
     (check-equal? (effect-pixel b 15 25) '(0 0 0 0)))
   (test-case "2D stamps repeat with empty space between them"
     (define a (alphas (capture-effect-scene 'stamp-2d)))
     (check-true (> (count positive? a) 20))
     (check-true (> (count zero? a) 1000)))
   (test-case "2D lines produce multiple sparse bands"
     (define b (capture-effect-scene 'line-2d))
     (define rows (for/list ([y (in-range effect-height)])
                    (for/sum ([x (in-range effect-width)]) (last (effect-pixel b x y)))))
     (check-true (>= (count positive? rows) 3))
     (check-true (>= (count zero? rows) 12)))
   (test-case "table mask snapshots bytes and modifies full coverage"
     (near-pixel (effect-pixel (capture-effect-scene 'table-mask) 24 20) '(64 0 0 64)))
   (test-case "gamma mask keeps the fully covered center and soft edges"
     (define b (capture-effect-scene 'gamma-mask))
     (near-pixel (effect-pixel b 24 20) '(255 0 0 255))
     (check-true (ormap (lambda (a) (< 0 a 255)) (alphas b))))
   (test-case "clip mask preserves interior and exterior"
     (define b (capture-effect-scene 'clip-mask))
     (near-pixel (effect-pixel b 24 20) '(255 0 0 255))
     (check-equal? (effect-pixel b 0 0) '(0 0 0 0)))
   (test-case "shader mask retains closed shader and modulates coverage"
     (near-pixel (effect-pixel (capture-effect-scene 'shader-mask) 24 20) '(128 0 0 128) 2))
   (test-case "Perlin families vary and repeat within this backend"
     (for ([name (in-list '(fractal-noise turbulence))])
       (define a (capture-effect-scene name))
       (check-equal? a (capture-effect-scene name))
       (check-true (> (length (remove-duplicates (bytes->list a))) 16)))
     (check-not-equal? (capture-effect-scene 'fractal-noise) (capture-effect-scene 'turbulence)))
   (test-case "shader color filter survives closure of both inputs"
     (near-pixel (effect-pixel (capture-effect-scene 'shader-color-filter) 30 20) '(255 0 0 255)))
   (test-case "shader arithmetic blend ordering"
     (near-pixel (effect-pixel (capture-effect-scene 'shader-blender) 30 20) '(64 0 191 255) 2))
   (test-case "runtime blender composition retains its effect and shaders"
     (near-pixel (effect-pixel (capture-effect-scene 'runtime-blender) 30 20) '(64 0 191 255) 2))
   (test-case "arithmetic paint blend includes the destination"
     (near-pixel (effect-pixel (capture-effect-scene 'arithmetic-blender) 30 20) '(64 0 191 255) 2))
   (test-case "custom image filter keeps background/foreground order"
     (near-pixel (effect-pixel (capture-effect-scene 'image-blender) 30 20) '(191 0 64 255) 2))
   (test-case "implicit image-filter slot is source, not transparent black"
     (define b (capture
                (lambda (c)
                  (with-skia ([blend (make-blend-mode-blender 'src)]
                              [f (make-blender-image-filter blend #f #f)]
                              [p (make-paint #:color 'red #:image-filter f)])
                    (draw-rect c 8 8 40 28 p)))))
     (near-pixel (effect-pixel b 24 20) '(255 0 0 255)))
   (test-case "picture target clips without scaling or relocation"
     (define b (capture-effect-scene 'picture-target))
     (near-pixel (effect-pixel b 12 12) '(255 0 0 255))
     (check-equal? (effect-pixel b 36 12) '(0 0 0 0))
     (check-equal? (effect-pixel b 4 4) '(0 0 0 0)))
   (test-case "empty shader leaves the destination untouched"
     (near-pixel (effect-pixel (capture-effect-scene 'empty-shader) 30 20) '(0 0 255 255)))
   (test-case "rotated and morphed asymmetric stamps are exercised"
     (define (sample style)
       (capture
        (lambda (c)
          (with-skia ([stamp (make-path '((move 0 -1) (line 7 0) (line 0 3) (close)))]
                      [e (make-1d-path-effect stamp 10 #:style style)]
                      [p (make-paint #:color 'red #:path-effect e)]
                      [line (make-path '((move 12 8) (line 12 40)))])
            (draw-path c line p)))))
     (define translated (sample 'translate))
     (define rotated (sample 'rotate))
     (define morphed (sample 'morph))
     (check-not-equal? translated rotated)
     (check-true (ormap positive? (alphas morphed))))
   (test-case "changed Perlin seed changes the image"
     (define (sample seed)
       (capture (lambda (c)
                  (with-skia ([s (make-fractal-noise-shader 0.09 0.07 3 seed)]
                              [p (make-paint #:shader s)])
                    (draw-rect c 0 0 64 48 p)))))
     (check-not-equal? (sample 7) (sample 11)))
   (test-case "coverage remapping is not silently ignored"
     (define (sample make-mask)
       (capture
        (lambda (c)
          (with-skia ([m (make-mask)] [p (make-paint #:color 'red #:mask-filter m)]
                      [shape (make-path '((move 8.25 6.25) (line 56.25 8.25)
                                          (line 48.25 40.25) (close)))])
            (draw-path c shape p)))))
     (define low (sample (lambda () (make-gamma-mask-filter 0.5))))
     (define high (sample (lambda () (make-gamma-mask-filter 2))))
     (check-not-equal? low high)
     (check-true (> (apply + (alphas low)) (apply + (alphas high))))
     (check-not-equal? (sample (lambda () (make-clip-mask-filter 20 120)))
                       (sample (lambda () (make-clip-mask-filter 180 240)))))
   (test-case "closed construction inputs reject"
     (with-skia ([s (make-color-shader 'red)] [f (make-blend-color-filter 'blue 'src)])
       (skia-close! s)
       (check-exn exn:fail? (lambda () (make-shader-mask-filter s)))
       (check-exn exn:fail? (lambda () (shader-with-color-filter s f)))))
   (test-case "empty stamp rejects before native effect allocation"
     (with-skia ([p (make-path)])
       (check-exn exn:fail? (lambda () (make-1d-path-effect p 4)))
       (check-exn exn:fail? (lambda () (make-2d-path-effect matrix-identity p)))))))
(module+ main (exit (if (zero? (run-tests effects-native-tests)) 0 1)))
