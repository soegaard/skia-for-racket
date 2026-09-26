#lang racket/base
(require rackunit rackunit/text-ui racket/list
         "../main.rkt")
(provide filter-graph-native-tests)
(define W 40)
(define H 32)
(define (source c p) (draw-rect c 8 8 8 8 p))
(define (render f [draw source])
  (with-skia ([s (make-surface W H)]
              [p (make-paint #:color 'red #:antialias? #f #:image-filter f)])
    (draw (surface-canvas s) p)
    (surface->rgba-bytes s)))
(define (px bs x y)
  (define i (* 4 (+ x (* W y))))
  (bytes->list (subbytes bs i (+ i 4))))
(define (alpha bs x y) (list-ref (px bs x y) 3))
(define (all-clear-outside? bs x y w h)
  (for*/and ([py (in-range H)] [px (in-range W)])
    (or (and (<= x px) (< px (+ x w)) (<= y py) (< py (+ y h)))
        (= (alpha bs px py) 0))))
(define (solid color crop)
  (with-skia ([s (make-color-shader color)]) (make-shader-image-filter s #:crop crop)))
(define (make-source-image)
  (with-skia ([s (make-surface 8 8 #:background 'blue)]) (surface-snapshot s)))
(define (foreign-error thunk)
  (define ch (make-channel))
  (define t (thread (lambda () (with-handlers ([exn? (lambda (e) (channel-put ch e))])
                                (thunk) (channel-put ch #f)))))
  (define e (channel-get ch)) (thread-wait t) e)
(define filter-graph-native-tests
  (test-suite
   "Advanced filter graphs: native pixels, retention, output"
   (test-case "offset moves dynamic source"
     (with-skia ([f (make-offset-image-filter 4 -2)])
       (define bs (render f))
       (check-equal? (px bs 13 7) '(255 0 0 255))
       (check-equal? (alpha bs 8 8) 0)))
   (test-case "identity offset is an owned filter"
     (with-skia ([f (make-offset-image-filter 0 0)])
       (check-true (skia-resource? f))
       (check-equal? (render f) (render #f))))
   (test-case "standalone crop has xywh geometry"
     (with-skia ([f (make-crop-image-filter '(10 10 3 4))])
       (define bs (render f))
       (check-equal? (px bs 11 11) '(255 0 0 255))
       (check-true (all-clear-outside? bs 10 10 3 4))))
   (test-case "zero-width crop is transparent rather than identity"
     (with-skia ([f (make-crop-image-filter '(10 8 0 8))])
       (check-equal? (render f) (make-bytes (* W H 4)))))
   (test-case "blur crop limits its output"
     (with-skia ([f (make-blur-image-filter 2 2 #:crop '(9 9 5 5))])
       (define bs (render f))
       (check-true (> (alpha bs 11 11) 100))
       (check-true (all-clear-outside? bs 9 9 5 5))))
   (test-case "crop after blur differs from cropping its input first"
     (with-skia ([cut (make-crop-image-filter '(8 8 4 8))]
                 [before (make-blur-image-filter 2 2 #:input cut)]
                 [after (make-blur-image-filter 2 2 #:crop '(8 8 4 8))])
       (check-true (> (alpha (render before) 12 11) 0))
       (check-equal? (alpha (render after) 12 11) 0)))
   (test-case "clamp blur with a crop is supported"
     (with-skia ([f (make-blur-image-filter 2 2 #:tile-mode 'clamp #:crop '(8 8 8 8))])
       (check-true (> (alpha (render f) 11 11) 0))))
   (test-case "both shadow constructors accept crop"
     (for ([ctor (in-list (list make-drop-shadow-image-filter make-drop-shadow-only-image-filter))])
       (with-skia ([f (ctor 3 2 1 1 'black #:crop '(9 9 10 9))])
         (check-true (all-clear-outside? (render f) 9 9 10 9)))))
   (test-case "color-filter node keeps native input reference and crop"
     (define cf (make-color-matrix-filter '(0 0 1 0 0  0 1 0 0 0  1 0 0 0 0  0 0 0 1 0)))
     (with-skia ([f (make-color-filter-image-filter cf #:crop '(10 10 3 3))])
       (skia-close! cf)
       (define bs (render f))
       (check-equal? (px bs 11 11) '(0 0 255 255))
       (check-true (all-clear-outside? bs 10 10 3 3))))
   (test-case "composition evaluates inner then outer with an output crop"
     (with-skia ([a (make-offset-image-filter 2 0)] [b (make-offset-image-filter 3 0)]
                 [f (make-compose-image-filter a b #:crop '(14 8 4 8))])
       (define bs (render f))
       (check-equal? (px bs 15 10) '(255 0 0 255))
       (check-true (all-clear-outside? bs 14 8 4 8))))
   (test-case "merge preserves source-over input order"
     (with-skia ([bg (solid 'blue '(4 4 12 12))] [fg (solid 'red '(10 10 12 12))]
                 [f (make-merge-image-filter (list bg fg))])
       (define bs (render f draw-paint))
       (check-equal? (px bs 6 6) '(0 0 255 255))
       (check-equal? (px bs 11 11) '(255 0 0 255))))
   (test-case "merge allows a repeated child and a dynamic source slot"
     (with-skia ([a (make-offset-image-filter 12 0)]
                 [f (make-merge-image-filter (vector #f a a))])
       (define bs (render f))
       (check-equal? (alpha bs 10 10) 255)
       (check-equal? (alpha bs 22 10) 255)))
   (test-case "merge copies caller vector and retains closed inputs"
     (define child (make-offset-image-filter 4 0))
     (define inputs (vector child))
     (with-skia ([f (make-merge-image-filter inputs)])
       (vector-set! inputs 0 #f) (skia-close! child) (collect-garbage)
       (check-equal? (alpha (render f) 18 10) 255)))
   (test-case "blend source-over and crop"
     (with-skia ([b (solid 'blue '(0 0 30 24))] [f (solid 'red '(10 0 20 24))]
                 [blend (make-blend-image-filter 'src-over b f #:crop '(4 4 20 16))])
       (define bs (render blend draw-paint))
       (check-equal? (px bs 6 8) '(0 0 255 255))
       (check-equal? (px bs 16 8) '(255 0 0 255))
       (check-true (all-clear-outside? bs 4 4 20 16))))
   (test-case "optimized Src and Dst with implicit input stay owned"
     (for ([mode '(src dst)])
       (with-skia ([f (make-blend-image-filter mode #f #f)])
         (check-true (image-filter? f))
         (check-equal? (render f) (render #f)))))
   (test-case "clear blend means empty pixels, not implicit source"
     (with-skia ([f (make-blend-image-filter 'clear #f #f)])
       (check-equal? (render f) (make-bytes (* W H 4)))))
   (test-case "arithmetic averages opaque red and blue"
     (with-skia ([b (solid 'blue '(0 0 30 24))] [f (solid 'red '(0 0 30 24))]
                 [mix (make-arithmetic-image-filter 0 1/2 1/2 0 b f)])
       (define v (px (render mix draw-paint) 12 12))
       (check-= (car v) 128 2) (check-equal? (cadr v) 0)
       (check-= (caddr v) 128 2) (check-equal? (cadddr v) 255)))
   (test-case "optimized arithmetic identity with dynamic source"
     (with-skia ([f (make-arithmetic-image-filter 0 1 0 0 #f #f)])
       (check-equal? (render f) (render #f))))
   (test-case "dilation expands the source alpha"
     (with-skia ([f (make-dilate-image-filter 2 1)])
       (define bs (render f))
       (check-equal? (alpha bs 6 7) 255)
       (check-equal? (alpha bs 5 7) 0)))
   (test-case "erosion shrinks the source alpha"
     (with-skia ([f (make-erode-image-filter 2 1)])
       (define bs (render f))
       (check-equal? (alpha bs 10 9) 255)
       (check-equal? (alpha bs 9 9) 0)))
   (test-case "zero-radius morphology is safe identity"
     (for ([ctor (list make-dilate-image-filter make-erode-image-filter)])
       (with-skia ([f (ctor 0 0)]) (check-equal? (render f) (render #f)))))
   (test-case "morphology applies an output crop"
     (with-skia ([f (make-dilate-image-filter 5 5 #:crop '(8 8 4 4))])
       (check-true (all-clear-outside? (render f) 8 8 4 4))))
   (test-case "identity convolution and copied kernel storage"
     (define kernel (vector 0 0 0 0 1 0 0 0 0))
     (with-skia ([f (make-matrix-convolution-image-filter 3 3 kernel)])
       (vector-set! kernel 4 0) (collect-garbage)
       (check-equal? (render f) (render #f))))
   (test-case "convolution kernel offset controls spatial sampling"
     (with-skia ([f (make-matrix-convolution-image-filter 3 1 '(1 0 0) #:offset '(1 0))])
       (define bs (render f))
       ;; Asymmetric kernel must shift, not mirror or average, the source.
       (check-not-equal? bs (render #f))
       (check-equal? (alpha bs 12 12) 255)))
   (test-case "convolve-alpha false preserves the source alpha"
     (with-skia ([f (make-matrix-convolution-image-filter 3 3 (make-list 9 1)
                     #:gain 1/9 #:convolve-alpha? #f)])
       (define bs (render f))
       (check-equal? (alpha bs 8 8) 255)
       (check-equal? (alpha bs 7 8) 0)))
   (test-case "convolution crop and repeat edge policy"
     (with-skia ([f (make-matrix-convolution-image-filter 3 3 (make-list 9 1)
                     #:gain 1/9 #:tile-mode 'repeat #:crop '(8 8 8 8))])
       (define bs (render f))
       (check-true (> (alpha bs 10 10) 0))
       (check-true (all-clear-outside? bs 8 8 8 8))))
   (test-case "zero displacement preserves the color input"
     (with-skia ([f (make-displacement-map-image-filter 'red 'green 0 #f #f)])
       (check-equal? (render f) (render #f))))
   (test-case "nonzero displacement with independent map and crop"
     (with-skia ([map-filter (solid (rgb 255 128 0) '(0 0 40 32))]
                 [f (make-displacement-map-image-filter 'red 'green 8 map-filter #f #:crop '(4 4 24 24))])
       (define bs (render f))
       (check-not-equal? bs (render #f))
       (check-true (all-clear-outside? bs 4 4 24 24))))
   (test-case "matrix translation agrees with offset"
     (with-skia ([a (make-offset-image-filter 4 2)]
                 [b (make-matrix-transform-image-filter (matrix-translate 4 2) #:sampling 'nearest)])
       (check-equal? (render a) (render b))))
   (test-case "matrix filter supports identity and explicit crop"
     (with-skia ([a (make-matrix-transform-image-filter matrix-identity #:sampling 'nearest)]
                 [b (make-matrix-transform-image-filter matrix-identity #:crop '(10 10 2 2))])
       (check-equal? (render a) (render #f))
       (check-true (all-clear-outside? (render b) 10 10 2 2))))
   (test-case "image source ignores drawn source and retains closed image"
     (define im (make-source-image))
     (with-skia ([f (make-image-source-filter im #:destination '(8 8 16 16) #:sampling 'nearest)])
       (skia-close! im) (collect-garbage)
       (check-equal? (px (render f draw-paint) 12 12) '(0 0 255 255))))
   (test-case "image source validates subsets and supports cropping"
     (with-skia ([im (make-source-image)])
       (check-exn exn:fail:contract? (lambda () (make-image-source-filter im #:source '(7 0 2 1))))
       (with-skia ([f (make-image-source-filter im #:source '(0 0 4 4)
                       #:destination '(4 4 12 12) #:crop '(5 5 4 4))])
         (check-true (all-clear-outside? (render f draw-paint) 5 5 4 4)))))
   (test-case "shader source owns its input and does not inherit paint color"
     (define sh (make-color-shader 'blue))
     (with-skia ([f (make-shader-image-filter sh #:crop '(4 4 8 8))])
       (skia-close! sh)
       (check-equal? (px (render f draw-paint) 6 6) '(0 0 255 255))))
   (test-case "picture source retains the recorded drawing"
     (define pic (call-with-picture 20 20
                   (lambda (c) (with-skia ([p (make-paint #:color 'blue)])
                                 (draw-rect c 4 4 8 8 p)))))
     (with-skia ([f (make-picture-image-filter pic #:crop '(5 5 4 4))])
       (skia-close! pic)
       (check-equal? (px (render f draw-paint) 6 6) '(0 0 255 255))))
   (test-case "tile repeats explicit source subset"
     (with-skia ([s (solid 'blue '(0 0 4 4))]
                 [f (make-tile-image-filter '(0 0 8 8) '(0 0 32 24) #:input s)])
       (define bs (render f draw-paint))
       (check-equal? (px bs 9 9) '(0 0 255 255))
       (check-equal? (alpha bs 6 6) 0)))
   (test-case "magnifier accepts unity and zoomed lens"
     (with-skia ([a (make-magnifier-image-filter '(0 0 32 24) 1)]
                 [b (make-magnifier-image-filter '(0 0 32 24) 2 #:inset 2 #:crop '(0 0 32 24))])
       (check-true (> (alpha (render a) 12 12) 0))
       (check-equal? (bytes-length (render b)) (* W H 4))))
   (test-case "all six lighting nodes construct and respect crop"
     (define constructors
       (list
        (lambda () (make-distant-lit-diffuse-image-filter '(0 0 1) 'white #:crop '(4 4 24 24)))
        (lambda () (make-point-lit-diffuse-image-filter '(12 12 40) 'white #:crop '(4 4 24 24)))
        (lambda () (make-spot-lit-diffuse-image-filter '(12 12 40) '(12 12 0) 'white #:crop '(4 4 24 24)))
        (lambda () (make-distant-lit-specular-image-filter '(0 0 1) 'white #:crop '(4 4 24 24)))
        (lambda () (make-point-lit-specular-image-filter '(12 12 40) 'white #:crop '(4 4 24 24)))
        (lambda () (make-spot-lit-specular-image-filter '(12 12 40) '(12 12 0) 'white #:crop '(4 4 24 24)))))
     (for ([ctor (in-list constructors)])
       (with-skia ([f (ctor)])
         (define bs (render f))
         (check-true (image-filter? f))
         (check-true (> (alpha bs 12 12) 0))
         (check-true (all-clear-outside? bs 4 4 24 24)))))
   (test-case "parent graph survives all child wrapper closures"
     (define a (make-offset-image-filter 2 0))
     (define b (make-dilate-image-filter 1 1 #:input a))
     (define f (make-blend-image-filter 'src-over a b))
     (with-skia ([parent f])
       (skia-close! a) (skia-close! b) (collect-garbage)
       (check-true (> (alpha (render parent) 12 12) 0))))
   (test-case "paint retains graph after graph wrapper closure"
     (define f (make-offset-image-filter 4 0))
     (with-skia ([s (make-surface W H)] [p (make-paint #:color 'blue #:image-filter f)])
       (skia-close! f) (source (surface-canvas s) p)
       (check-equal? (surface-pixel s 18 10) (rgb 0 0 255))))
   (test-case "closed inputs and foreign-thread inputs are rejected"
     (define f (make-offset-image-filter 1 0))
     (check-true (exn? (foreign-error (lambda () (make-merge-image-filter (list f))))))
     (skia-close! f)
     (check-exn #rx"closed" (lambda () (make-merge-image-filter (list f)))))
   (test-case "repeated construction and GC with arrays"
     (for ([i (in-range 30)])
       (with-skia ([f (make-matrix-convolution-image-filter 1 1 '(1))]
                   [g (make-merge-image-filter (list f f))])
         (collect-garbage)
         (check-equal? (render g) (render #f)))))
   (test-case "native PDF filter path produces a complete document"
     (define bs (call-with-pdf-bytes
                 (lambda (d)
                   (with-document-page (c d 40 32)
                     (with-skia ([f (make-dilate-image-filter 2 2)]
                                 [p (make-paint #:color 'blue #:image-filter f)])
                       (source c p))))))
     (check-true (regexp-match? #rx#"^%PDF-" bs))
     (check-true (regexp-match? #rx#"%%EOF" bs)))
   (test-case "explicit SVG raster group embeds filtered pixels"
     (define bs
       (call-with-svg-bytes 40 32
         (lambda (c)
           (draw-rasterized c 0 0 40 32
             (lambda (rc)
               (with-skia ([f (make-dilate-image-filter 2 2)]
                           [p (make-paint #:color 'blue #:image-filter f)])
                 (source rc p))) #:scale 2))))
     (check-true (regexp-match? #rx#"data:image/png;base64," bs))
     (check-true (regexp-match? #rx#"</svg>" bs)))
   (test-case "crop follows local coordinates under canvas scaling"
     (with-skia ([s (make-surface 40 32)]
                 [f (make-crop-image-filter '(4 4 4 4))]
                 [p (make-paint #:color 'red #:image-filter f)])
       (canvas-scale! (surface-canvas s) 2)
       (draw-rect (surface-canvas s) 0 0 16 16 p)
       (check-equal? (surface-pixel s 10 10) (rgb 255 0 0))
       (check-equal? (rgba-alpha (surface-pixel s 6 10)) 0)))))
(module+ test (run-tests filter-graph-native-tests))
