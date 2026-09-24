#lang racket/base
(require rackunit rackunit/text-ui racket/file racket/class racket/list
         (except-in racket/draw make-font)
         "../main.rkt" "../bitmap.rkt")
(provide native-tests)

(define white (rgb 255 255 255))
(define red (rgb 255 0 0))
(define blue (rgb 0 0 255))
(define transparent (rgba 0 0 0 0))

(define native-tests
  (test-suite
   "Live Skia rendering (requires the pinned native library)"
   (test-case "load and preflight every native symbol"
     (check-not-exn skia-check!)
     (check-regexp-match #rx"^119[.]" (skia-native-version)))
   (test-case "clear and channel order on an odd-width surface"
     (with-skia ([s (make-surface 7 3 #:background "#12AB34")])
       (check-equal? (surface-pixel s 6 2) (rgb 18 171 52))
       (check-equal? (bytes-length (surface->rgba-bytes s)) 84)))
   (test-case "transparent initial pixels"
     (with-skia ([s (make-surface 2 2)])
       (check-equal? (surface->rgba-bytes s) (make-bytes 16))))
   (test-case "straight and premultiplied pixel output"
     (with-skia ([s (make-surface 1 1 #:background (rgba 255 0 0 128))])
       (check-equal? (surface->rgba-bytes s) (bytes 255 0 0 128))
       (check-equal? (surface->rgba-bytes s #:premultiplied? #t) (bytes 128 0 0 128))))
   (test-case "pixel bounds checked"
     (with-skia ([s (make-surface 2 2)])
       (for ([xy '((-1 0) (0 -1) (2 0) (0 2) (0.5 0))])
         (check-exn exn:fail:contract? (lambda () (apply surface-pixel s xy))))))
   (test-case "rectangle fill and exact interior pixels"
     (with-skia ([s (make-surface 20 20 #:background 'white)]
                 [p (make-paint #:color 'red #:antialias? #f)])
       (draw-rect (surface-canvas s) 3 4 6 7 p)
       (check-equal? (surface-pixel s 5 6) red)
       (check-equal? (surface-pixel s 1 1) white)
       (check-equal? (surface-pixel s 9 6) white)))
   (test-case "circle, oval and rounded rectangle"
     (with-skia ([s (make-surface 80 30)] [p (make-paint #:color 'blue)])
       (define c (surface-canvas s))
       (draw-circle c 10 15 7 p)
       (draw-oval c 25 8 20 14 p)
       (draw-rounded-rect c 50 5 20 20 5 5 p)
       (for ([x '(10 35 60)]) (check-equal? (surface-pixel s x 15) blue))
       (check-equal? (surface-pixel s 0 0) transparent)))
   (test-case "stroke and line endpoints"
     (with-skia ([s (make-surface 20 20 #:background 'white)]
                 [p (make-paint #:color 'red #:style 'stroke #:stroke-width 4 #:antialias? #f)])
       (draw-line (surface-canvas s) 4 10 16 10 p)
       (check-equal? (surface-pixel s 10 10) red)
       (check-equal? (surface-pixel s 1 10) white)))
   (test-case "source-over composition"
     (with-skia ([s (make-surface 3 3 #:background 'white)]
                 [p (make-paint #:color (rgba 255 0 0 128))])
       (draw-paint (surface-canvas s) p)
       (define c (surface-pixel s 1 1))
       (check-equal? (rgba-red c) 255)
       (check-= (rgba-green c) 127 1)
       (check-= (rgba-blue c) 127 1)
       (check-equal? (rgba-alpha c) 255)))
   (test-case "paint copy and setters"
     (with-skia ([p (make-paint #:color 'red)] [q (paint-copy p)])
       (paint-set-color! p 'blue)
       (check-equal? (paint-color q) red)
       (check-equal? (paint-color p) blue)
       (paint-set-style! p 'stroke)
       (paint-set-stroke-width! p 2)
       (paint-set-antialias! p #f)
       (paint-set-cap! p 'round)
       (paint-set-join! p 'bevel)
       (paint-set-miter-limit! p 3)
       (paint-set-blend-mode! p 'multiply)))
   (test-case "path bounds versus tight cubic bounds"
     (with-skia ([p (make-path '((move 0 0) (cubic 0 100 100 100 100 0)))])
       (check-equal? (call-with-values (lambda () (path-bounds p)) list) '(0.0 0.0 100.0 100.0))
       (define bounds (call-with-values (lambda () (path-tight-bounds p)) list))
       (check-= (list-ref bounds 3) 75 0.001)))
   (test-case "imperative quadratic and cubic paths"
     (with-skia ([s (make-surface 32 32)] [p (make-paint #:color 'red)] [path (make-path)])
       (path-move-to! path 4 4)
       (path-quad-to! path 16 0 28 4)
       (path-cubic-to! path 30 16 30 24 28 28)
       (path-line-to! path 4 28)
       (path-close! path)
       (draw-path (surface-canvas s) path p)
       (check-equal? (surface-pixel s 16 16) red)))
   (test-case "even-odd fill creates a hole"
     (with-skia ([s (make-surface 30 30)] [p (make-paint #:color 'red)]
                 [path (make-path #:fill-rule 'even-odd)])
       (path-add-rect! path 2 2 26 26)
       (path-add-rect! path 10 10 10 10)
       (draw-path (surface-canvas s) path p)
       (check-equal? (surface-pixel s 5 5) red)
       (check-equal? (surface-pixel s 15 15) transparent)))
   (test-case "winding fill respects opposite contour directions"
     (with-skia ([path (make-path)])
       (path-add-rect! path 0 0 30 30 #:direction 'cw)
       (path-add-rect! path 10 10 10 10 #:direction 'ccw)
       (check-true (path-contains? path 5 5))
       (check-false (path-contains? path 15 15))))
   (test-case "path copies, fill rules and resets"
     (with-skia ([p (make-path)])
       (path-add-circle! p 10 10 4)
       (with-skia ([q (path-copy p)])
         (path-set-fill-rule! q 'even-odd)
         (path-reset! p)
         (check-false (path-contains? p 10 10))
         (check-true (path-contains? q 10 10))
         (check-eq? (path-fill-rule q) 'even-odd)
         (path-reset! q)
         (check-eq? (path-fill-rule q) 'winding))))
   (test-case "path oval and polygon drawing"
     (with-skia ([s (make-surface 30 30)] [p (make-paint #:color 'blue)] [path (make-path)])
       (path-add-oval! path 10 10 10 10)
       (check-true (path-contains? path 15 15))
       (draw-polygon (surface-canvas s) '((2 2) (8 2) (8 8) (2 8)) p)
       (check-equal? (surface-pixel s 5 5) blue)))
   (test-case "translation and scaling compose"
     (with-skia ([s (make-surface 30 30)] [p (make-paint #:color 'red #:antialias? #f)])
       (define c (surface-canvas s))
       (canvas-translate! c 10 10)
       (canvas-scale! c 2)
       (draw-rect c 1 1 3 3 p)
       (check-equal? (surface-pixel s 14 14) red)
       (check-equal? (surface-pixel s 5 5) transparent)))
   (test-case "positive rotation is clockwise in default coordinates"
     (with-skia ([s (make-surface 20 20)] [p (make-paint #:color 'red #:antialias? #f)])
       (define c (surface-canvas s))
       (canvas-translate! c 10 10)
       (canvas-rotate! c 90)
       (draw-rect c 0 0 4 2 p)
       (check-equal? (surface-pixel s 9 11) red)
       (check-equal? (surface-pixel s 11 9) transparent)))
   (test-case "radians, skew and reset are callable"
     (with-skia ([s (make-surface 20 20)] [p (make-paint #:color 'red)])
       (define c (surface-canvas s))
       (canvas-rotate-radians! c 1/3)
       (canvas-skew! c 1/2 0)
       (canvas-reset-transform! c)
       (draw-rect c 2 2 4 4 p)
       (check-equal? (surface-pixel s 3 3) red)))
   (test-case "rectangle clipping and difference"
     (with-skia ([s (make-surface 20 20)] [p (make-paint #:color 'red)])
       (define c (surface-canvas s))
       (canvas-clip-rect! c 2 2 16 16)
       (canvas-clip-rect! c 7 7 6 6 #:operation 'difference)
       (draw-paint c p)
       (check-equal? (surface-pixel s 3 3) red)
       (check-equal? (surface-pixel s 10 10) transparent)
       (check-equal? (surface-pixel s 0 0) transparent)))
   (test-case "path clipping"
     (with-skia ([s (make-surface 20 20)] [p (make-paint #:color 'red)] [path (make-path)])
       (path-add-circle! path 10 10 5)
       (canvas-clip-path! (surface-canvas s) path #:antialias? #t)
       (draw-paint (surface-canvas s) p)
       (check-equal? (surface-pixel s 10 10) red)
       (check-equal? (surface-pixel s 1 1) transparent)))
   (test-case "save and restore counts"
     (with-skia ([s (make-surface 4 4)])
       (define c (surface-canvas s))
       (check-equal? (canvas-save-count c) 1)
       (check-equal? (canvas-save! c) 1)
       (check-equal? (canvas-save! c) 2)
       (canvas-restore-to-count! c 2)
       (canvas-restore! c)
       (check-equal? (canvas-save-count c) 1)
       (check-exn #rx"base" (lambda () (canvas-restore! c)))))
   (test-case "scoped state restores transform and clip after an exception"
     (with-skia ([s (make-surface 20 20)] [p (make-paint #:color 'red)])
       (define c (surface-canvas s))
       (check-exn #rx"deliberate"
         (lambda ()
           (with-canvas-state c
             (canvas-translate! c 10 10)
             (canvas-clip-rect! c 0 0 1 1)
             (canvas-save! c)
             (error 'test "deliberate"))))
       (check-equal? (canvas-save-count c) 1)
       (draw-rect c 2 2 5 5 p)
       (check-equal? (surface-pixel s 3 3) red)))
   (test-case "protected state cannot be popped through another canvas alias"
     (with-skia ([s (make-surface 4 4)])
       (define c (surface-canvas s))
       (define alias (surface-canvas s))
       (with-canvas-state c
         (check-exn #rx"protected" (lambda () (canvas-restore! alias)))
         (check-exn #rx"protected" (lambda () (canvas-restore-to-count! alias 1))))
       (check-equal? (canvas-save-count c) 1)))
   (test-case "nested state scopes"
     (with-skia ([s (make-surface 4 4)])
       (define c (surface-canvas s))
       (with-canvas-state c
         (check-equal? (canvas-save-count c) 2)
         (with-canvas-state c (check-equal? (canvas-save-count c) 3))
         (check-equal? (canvas-save-count c) 2))
       (check-equal? (canvas-save-count c) 1)))
   (test-case "closing a surface inside a state scope is safe"
     (define s (make-surface 4 4))
     (define c (surface-canvas s))
     (check-not-exn (lambda () (with-canvas-state c (skia-close! s))))
     (check-true (skia-closed? c))
     (skia-close! s))
   (test-case "borrowed canvas keeps its surface alive across GC"
     (define-values (c weak)
       (let ([s (make-surface 4 4)])
         (values (surface-canvas s) (make-weak-box s))))
     (collect-garbage)
     (collect-garbage)
     (check-not-exn (lambda () (canvas-clear! c 'blue)))
     (check-not-false (weak-box-value weak))
     (skia-close! (weak-box-value weak)))
   (test-case "explicit closure invalidates borrowed canvases and is idempotent"
     (define s (make-surface 4 4))
     (define c (surface-canvas s))
     (skia-close! s)
     (skia-close! s)
     (check-exn #rx"closed" (lambda () (canvas-clear! c 'red)))
     (check-exn exn:fail:contract? (lambda () (skia-close! c))))
   (test-case "scoped resources close on exception and constructor failure"
     (define saved #f)
     (check-exn #rx"deliberate"
       (lambda ()
         (with-skia ([p (make-paint)])
           (set! saved p)
           (error 'test "deliberate"))))
     (check-true (skia-closed? saved))
     (define first #f)
     (check-exn exn:fail:contract?
       (lambda ()
         (with-skia ([p (let ([p (make-paint)]) (set! first p) p)]
                     [q (make-paint #:stroke-width -1)])
           (void))))
     (check-true (skia-closed? first)))
   (test-case "image snapshot survives source mutation and closure"
     (define s (make-surface 2 2 #:background 'red))
     (with-skia ([im (surface-snapshot s)] [dest (make-surface 4 4)])
       (canvas-clear! (surface-canvas s) 'blue)
       (skia-close! s)
       (draw-image (surface-canvas dest) im 1 1)
       (check-equal? (surface-pixel dest 1 1) red)
       (check-equal? (image->rgba-bytes im) (apply bytes (make-list-of-red-pixels 4)))))
   (test-case "RGBA input is copied, not borrowed"
     (define pixels (bytes 255 0 0 255 0 0 255 255))
     (with-skia ([im (rgba-bytes->image 2 1 pixels)] [s (make-surface 4 2)])
       (bytes-fill! pixels 0)
       (draw-image-rect (surface-canvas s) im 0 0 4 2 #:sampling 'nearest)
       (check-equal? (surface-pixel s 0 0) red)
       (check-equal? (surface-pixel s 3 1) blue)
       (check-equal? (image->rgba-bytes im) (bytes 255 0 0 255 0 0 255 255))))
   (test-case "native PNG signature, dimensions, decoding and repeatability"
     (with-skia ([s (make-surface 7 3 #:background 'red)])
       (define png (surface->png-bytes s))
       (check-equal? (subbytes png 0 8) #"\211PNG\r\n\032\n")
       (check-equal? (integer-bytes->integer png #f #t 16 20) 7)
       (check-equal? (integer-bytes->integer png #f #t 20 24) 3)
       (check-equal? png (surface->png-bytes s))
       (define bm (read-bitmap (open-input-bytes png) 'png/alpha))
       (check-true (send bm ok?))
       (define pixel (make-bytes 4))
       (send bm get-argb-pixels 0 0 1 1 pixel)
       (check-equal? pixel (bytes 255 255 0 0))))
   (test-case "PNG save refuses overwrite by default"
     (define file (make-temporary-file "racket-skia-test-~a.png"))
     (dynamic-wind void
       (lambda ()
         (with-skia ([s (make-surface 2 2)])
           (check-exn exn:fail:filesystem? (lambda () (save-png s file)))
           (save-png s file #:exists 'replace)
           (check-equal? (subbytes (file->bytes file) 0 8) #"\211PNG\r\n\032\n")))
       (lambda () (delete-file file))))
   (test-case "bitmap bridge preserves channel order and premultiplied alpha"
     (with-skia ([s (make-surface 1 1 #:background (rgba 255 0 0 128))])
       (define bm (surface->bitmap s))
       (define argb (make-bytes 4))
       (send bm get-argb-pixels 0 0 1 1 argb #f #t)
       (check-equal? argb (bytes 128 128 0 0))))
   (test-case "invalid coordinates and options do not reach native drawing"
     (with-skia ([s (make-surface 8 8)] [p (make-paint)])
       (define c (surface-canvas s))
       (check-exn exn:fail:contract? (lambda () (draw-circle c 1 1 -1 p)))
       (check-exn exn:fail:contract? (lambda () (draw-rect c +nan.0 0 1 1 p)))
       (check-exn exn:fail:contract? (lambda () (draw-rect c 0 0 -1 1 p)))
       (check-exn exn:fail:contract? (lambda () (canvas-clip-rect! c 0 0 1 1 #:antialias? 1)))
       (check-exn exn:fail:contract? (lambda () (surface->png-bytes s #:compression 10)))))
   (test-case "closed paints, paths, images and shaders reject use"
     (with-skia ([s (make-surface 8 8)] [p (make-paint)] [path (make-path)]
                 [im (rgba-bytes->image 1 1 (bytes 255 0 0 255))]
                 [sh (make-color-shader 'red)])
       (define c (surface-canvas s))
       (skia-close! p)
       (skia-close! path)
       (skia-close! im)
       (skia-close! sh)
       (check-exn #rx"closed" (lambda () (draw-circle c 2 2 1 p)))
       (check-exn #rx"closed" (lambda () (path-line-to! path 1 1)))
       (check-exn #rx"closed" (lambda () (draw-image c im 0 0)))
       (check-exn #rx"closed" (lambda () (make-paint #:shader sh)))))
   (test-case "cross-thread surface access is rejected before FFI"
     (with-skia ([s (make-surface 4 4)])
       (define results (make-channel))
       (define worker
         (thread
          (lambda ()
            (channel-put results
              (with-handlers ([exn:fail? exn-message])
                (surface-pixel s 0 0))))))
       (check-regexp-match #rx"another Racket thread" (channel-get results))
       (thread-wait worker)))
   (test-case "color shader paint attachment and reference ownership"
     (with-skia ([s (make-surface 12 4 #:background 'white)]
                 [sh (make-color-shader 'red)]
                 [p (make-paint #:shader sh #:antialias? #f)])
       ;; The native paint keeps its own shader reference.
       (skia-close! sh)
       (draw-rect (surface-canvas s) 0 0 6 4 p)
       (check-equal? (surface-pixel s 2 2) red)
       ;; The C getter returns a distinct owned reference; closing or
       ;; detaching the paint cannot invalidate this wrapper.
       (with-skia ([held (paint-shader p)])
         (check-true (shader? held))
         (paint-set-shader! p #f)
         (check-false (paint-shader p))
         (with-skia ([q (make-paint #:shader held #:antialias? #f)])
           (draw-rect (surface-canvas s) 6 0 6 4 q)
           (check-equal? (surface-pixel s 9 2) red)))))
   (test-case "linear gradient interpolates and accepts explicit stops"
     (with-skia ([s (make-surface 101 3 #:background 'white)]
                 [sh (make-linear-gradient-shader
                      0 0 100 0 '(red green blue)
                      #:positions '(0 1/2 1))]
                 [p (make-paint #:shader sh)])
       (draw-paint (surface-canvas s) p)
       (define left (surface-pixel s 5 1))
       (define middle (surface-pixel s 50 1))
       (define right (surface-pixel s 95 1))
       (check-true (> (rgba-red left) (rgba-blue left)))
       (check-true (> (rgba-green middle) (rgba-red middle)))
       (check-true (> (rgba-blue right) (rgba-red right)))))
   (test-case "radial and sweep gradients rasterize distinct regions"
     (with-skia ([radial-surface (make-surface 41 41)]
                 [radial (make-radial-gradient-shader
                          20 20 20 '(red blue))]
                 [radial-paint (make-paint #:shader radial)]
                 [sweep-surface (make-surface 41 41)]
                 [sweep (make-sweep-gradient-shader
                         20 20 '(red green blue red)
                         #:positions '(0 1/3 2/3 1))]
                 [sweep-paint (make-paint #:shader sweep)])
       (draw-paint (surface-canvas radial-surface) radial-paint)
       (define center (surface-pixel radial-surface 20 20))
       (define edge (surface-pixel radial-surface 39 20))
       (check-true (> (rgba-red center) (rgba-blue center)))
       (check-true (> (rgba-blue edge) (rgba-red edge)))
       (draw-paint (surface-canvas sweep-surface) sweep-paint)
       (define a (surface-pixel sweep-surface 39 20))
       (define b (surface-pixel sweep-surface 20 1))
       (define d (surface-pixel sweep-surface 1 20))
       (check-false (and (equal? a b) (equal? b d)))))
   (test-case "two-point conical gradient varies across its domain"
     (with-skia ([s (make-surface 121 81)]
                 [sh (make-two-point-conical-gradient-shader
                      20 40 2 100 40 28 '(red blue))]
                 [p (make-paint #:shader sh)])
       (draw-paint (surface-canvas s) p)
       (check-not-equal? (surface-pixel s 25 40)
                         (surface-pixel s 95 40))))
   (test-case "image shader tiles with nearest sampling"
     (with-skia ([s (make-surface 6 1)]
                 [im (rgba-bytes->image
                      2 1 (bytes 255 0 0 255 0 0 255 255))]
                 [sh (make-image-shader im #:tile-x 'repeat #:tile-y 'clamp
                                        #:sampling 'nearest)]
                 [p (make-paint #:shader sh #:antialias? #f)])
       (draw-paint (surface-canvas s) p)
       (for ([x (in-range 6)])
         (check-equal? (surface-pixel s x 0) (if (even? x) red blue)))))
   (test-case "blend shader composes two shaders"
     (with-skia ([s (make-surface 3 3 #:background 'white)]
                 [dst (make-color-shader 'red)]
                 [src (make-color-shader 'blue)]
                 [blend (make-blend-shader 'multiply dst src)]
                 [p (make-paint #:shader blend #:antialias? #f)])
       (draw-paint (surface-canvas s) p)
       (check-equal? (surface-pixel s 1 1) (rgb 0 0 0))))
   (test-case "PNG encoding, metadata probing, and encoded decode round trip"
     (with-skia ([im (rgba-bytes->image
                      2 2
                      (bytes 255 0 0 255   0 255 0 255
                             0 0 255 255   255 255 255 255))])
       (check-false (image-original-encoded-bytes im))
       (define png (image->png-bytes im))
       (check-equal? (subbytes png 0 8) #"\211PNG\r\n\032\n")
       (check-equal? (image->encoded-bytes im 'png) png)
       (check-exn exn:fail:contract?
                  (lambda () (image->encoded-bytes im 'bmp)))
       (check-exn exn:fail? (lambda () (image-from-bytes #"not an image")))
       (check-exn exn:fail?
                  (lambda () (encoded-image-info-from-bytes #"not an image")))
       (define info (encoded-image-info-from-bytes png))
       (check-true (encoded-image-info? info))
       (check-equal? (encoded-image-info-width info) 2)
       (check-equal? (encoded-image-info-height info) 2)
       (check-equal? (encoded-image-info-format info) 'png)
       (check-equal? (encoded-image-info-origin info) 'top-left)
       (check-true (exact-nonnegative-integer? (encoded-image-info-frame-count info)))
       (with-skia ([decoded (image-from-bytes png)])
         (check-equal? (image-width decoded) 2)
         (check-equal? (image-height decoded) 2)
         (check-true (symbol? (image-color-type decoded)))
         (check-not-false (memq (image-alpha-type decoded)
                                '(unknown opaque premul unpremul)))
         (check-equal? (image-original-encoded-bytes decoded) png)
         (check-equal? (image->rgba-bytes decoded)
                       (bytes 255 0 0 255   0 255 0 255
                              0 0 255 255   255 255 255 255)))))
   (test-case "JPEG encoding probes and decodes"
     (define pixels (make-bytes (* 8 8 4)))
     (for ([i (in-range 0 (bytes-length pixels) 4)])
       (bytes-set! pixels i 255)
       (bytes-set! pixels (+ i 3) 255))
     (with-skia ([im (rgba-bytes->image 8 8 pixels)])
       (define jpg (image->jpeg-bytes im #:quality 100 #:downsample 'yuv-444))
       (check-equal? (subbytes jpg 0 2) #"\377\330")
       (define info (encoded-image-info-from-bytes jpg))
       (check-equal? (encoded-image-info-format info) 'jpeg)
       (check-equal? (list (encoded-image-info-width info)
                           (encoded-image-info-height info))
                     '(8 8))
       (with-skia ([decoded (image-from-bytes jpg)])
         (define c (let ([bs (image->rgba-bytes decoded)])
                     (rgba (bytes-ref bs 0) (bytes-ref bs 1)
                           (bytes-ref bs 2) (bytes-ref bs 3))))
         (check-true (> (rgba-red c) 200))
         (check-true (< (rgba-green c) 80))
         (check-true (< (rgba-blue c) 80)))))
   (test-case "lossless WebP encoding probes and decodes"
     (with-skia ([im (rgba-bytes->image
                      2 1 (bytes 255 0 0 255 0 0 255 255))])
       (define webp (image->webp-bytes im #:quality 75 #:lossless? #t))
       (check-equal? (subbytes webp 0 4) #"RIFF")
       (check-equal? (subbytes webp 8 12) #"WEBP")
       (define info (encoded-image-info-from-bytes webp))
       (check-equal? (encoded-image-info-format info) 'webp)
       (check-equal? (list (encoded-image-info-width info)
                           (encoded-image-info-height info))
                     '(2 1))
       (with-skia ([decoded (image-from-bytes webp)])
         (check-equal? (image->rgba-bytes decoded)
                       (bytes 255 0 0 255 0 0 255 255)))))
   (test-case "encoded image files probe, decode, and save"
     (define file (make-temporary-file "racket-skia-codec-~a.png"))
     (dynamic-wind
       void
       (lambda ()
         (with-skia ([src (rgba-bytes->image
                           2 1 (bytes 255 0 0 255 0 0 255 255))])
           (save-image src file 'png #:exists 'replace)
           (define info (encoded-image-info-from-file file))
           (check-equal? (encoded-image-info-format info) 'png)
           (check-equal? (list (encoded-image-info-width info)
                               (encoded-image-info-height info))
                         '(2 1))
           (with-skia ([decoded (image-from-file file)])
             (check-equal? (image->rgba-bytes decoded)
                           (bytes 255 0 0 255 0 0 255 255)))))
       (lambda () (when (file-exists? file) (delete-file file)))))
   (test-case "image subsets copy the requested raster region"
     (with-skia ([im (rgba-bytes->image
                      4 2
                      (bytes 255 0 0 255 255 0 0 255 0 0 255 255 0 0 255 255
                             255 0 0 255 255 0 0 255 0 0 255 255 0 0 255 255))]
                 [sub (image-subset im 2 0 2 2)])
       (check-equal? (list (image-width sub) (image-height sub)) '(2 2))
       (check-equal? (image->rgba-bytes sub)
                     (bytes 0 0 255 255 0 0 255 255
                            0 0 255 255 0 0 255 255))
       (check-exn exn:fail? (lambda () (image-subset im 3 0 2 1)))))
   (test-case "source-rectangle image drawing selects only the requested pixels"
     (with-skia ([im (rgba-bytes->image
                      4 1
                      (bytes 255 0 0 255 255 0 0 255
                             0 0 255 255 0 0 255 255))]
                 [s (make-surface 4 1)])
       (draw-image-subrect (surface-canvas s) im
                           2 0 2 1
                           0 0 4 1
                           #:sampling 'nearest)
       (for ([x (in-range 4)])
         (check-equal? (surface-pixel s x 0) blue))
       (check-exn exn:fail?
                  (lambda ()
                    (draw-image-subrect (surface-canvas s) im
                                        3 0 2 1 0 0 4 1)))))
   (test-case "dash path effects attach to paints and getters own a reference"
     (define effect (make-dash-path-effect '(6 4)))
     (define paint (make-paint #:color 'black #:style 'stroke #:stroke-width 2
                               #:cap 'butt #:antialias? #f
                               #:path-effect effect))
     ;; A paint retains its own reference.
     (skia-close! effect)
     (define held (paint-path-effect paint))
     (check-true (path-effect? held))
     ;; The getter result owns a distinct reference and survives paint closure.
     (skia-close! paint)
     (with-skia ([s (make-surface 32 6 #:background 'white)]
                 [q (make-paint #:color 'black #:style 'stroke #:stroke-width 2
                                #:cap 'butt #:antialias? #f
                                #:path-effect held)])
       (draw-line (surface-canvas s) 0 3 31 3 q)
       (check-equal? (surface-pixel s 2 3) (rgb 0 0 0))
       (check-equal? (surface-pixel s 7 3) white)
       (check-equal? (surface-pixel s 12 3) (rgb 0 0 0)))
     (skia-close! held))
   (test-case "corner discrete trim compose and sum path effects construct and retain inputs"
     (define corner (make-corner-path-effect 5))
     (define discrete (make-discrete-path-effect 6 2 17))
     (define trim (make-trim-path-effect 1/4 3/4))
     (define composed (make-compose-path-effect corner trim))
     (define summed (make-sum-path-effect discrete trim))
     ;; Composite effects retain the native inputs they need.
     (skia-close! corner)
     (skia-close! discrete)
     (skia-close! trim)
     (with-skia ([s (make-surface 100 5 #:background 'white)]
                 [p (make-paint #:color 'black #:style 'stroke #:stroke-width 2
                                #:antialias? #f #:path-effect composed)])
       (draw-line (surface-canvas s) 0 2 99 2 p)
       (check-not-equal? (surface-pixel s 50 2) white)
       (paint-set-path-effect! p summed)
       (with-skia ([copy (paint-path-effect p)])
         (check-true (path-effect? copy)))
       (paint-set-path-effect! p #f)
       (check-false (paint-path-effect p)))
     (skia-close! composed)
     (skia-close! summed))
   (test-case "trim path effect keeps the requested middle fraction"
     (with-skia ([s (make-surface 101 5 #:background 'white)]
                 [e (make-trim-path-effect 1/4 3/4)]
                 [p (make-paint #:color 'black #:style 'stroke #:stroke-width 2
                                #:cap 'butt #:antialias? #f #:path-effect e)])
       (draw-line (surface-canvas s) 0 2 100 2 p)
       (check-equal? (surface-pixel s 10 2) white)
       (check-equal? (surface-pixel s 50 2) (rgb 0 0 0))
       (check-equal? (surface-pixel s 90 2) white)))
   (test-case "path measure samples a line and snapshots source geometry"
     (define source (make-path '((move 0 0) (line 100 0))))
     (define measure (make-path-measure source))
     (check-= (path-measure-length measure) 100.0 0.001)
     (check-false (path-measure-closed? measure))
     (define-values (x y tx ty) (path-measure-position+tangent measure 25))
     (check-= x 25.0 0.001)
     (check-= y 0.0 0.001)
     (check-= tx 1.0 0.001)
     (check-= ty 0.0 0.001)
     (with-skia ([segment (path-measure-segment measure 20 60)])
       (define-values (sx sy sw sh) (path-tight-bounds segment))
       (check-= sx 20.0 0.001)
       (check-= sy 0.0 0.001)
       (check-= sw 40.0 0.001)
       (check-= sh 0.0 0.001))
     ;; Mutating and then explicitly closing the original cannot alter the
     ;; measure: the Racket wrapper owns a private path snapshot.
     (path-reset! source)
     (path-move-to! source 0 0)
     (path-line-to! source 10 0)
     (skia-close! source)
     (check-= (path-measure-length measure) 100.0 0.001)
     (check-exn exn:fail? (lambda () (path-measure-position+tangent measure 101)))
     (skia-close! measure))
   (test-case "path measure traverses contours and safely replaces its snapshot"
     (define multi
       (make-path '((move 0 0) (line 10 0)
                    (move 0 20) (line 30 20))))
     (define measure (make-path-measure multi))
     (check-= (path-measure-length measure) 10.0 0.001)
     (check-true (path-measure-next-contour! measure))
     (check-= (path-measure-length measure) 30.0 0.001)
     (check-false (path-measure-next-contour! measure))
     (define replacement (make-path '((move 0 0) (line 3 4))))
     (path-measure-set-path! measure replacement #:force-closed? #t)
     (skia-close! replacement)
     (check-true (path-measure-closed? measure))
     (check-= (path-measure-length measure) 10.0 0.001)
     (path-measure-set-path! measure #f)
     (check-= (path-measure-length measure) 0.0 0.001)
     (define-values (x y tx ty) (path-measure-position+tangent measure 0))
     (check-false x) (check-false y) (check-false tx) (check-false ty)
     (skia-close! multi)
     (skia-close! measure))
   (test-case "boolean path operations produce expected filled regions"
     (with-skia ([a (make-path)] [b (make-path)])
       (path-add-rect! a 0 0 20 20)
       (path-add-rect! b 10 0 20 20)
       (with-skia ([u (path-union a b)]
                   [i (path-intersect a b)]
                   [d (path-difference a b)]
                   [x (path-xor a b)]
                   [r (path-reverse-difference a b)])
         (for ([px '(5 15 25)]) (check-true (path-contains? u px 10)))
         (check-false (path-contains? i 5 10))
         (check-true (path-contains? i 15 10))
         (check-false (path-contains? i 25 10))
         (check-true (path-contains? d 5 10))
         (check-false (path-contains? d 15 10))
         (check-false (path-contains? d 25 10))
         (check-true (path-contains? x 5 10))
         (check-false (path-contains? x 15 10))
         (check-true (path-contains? x 25 10))
         (check-false (path-contains? r 5 10))
         (check-false (path-contains? r 15 10))
         (check-true (path-contains? r 25 10)))))
   (test-case "path simplify and winding conversion preserve filled geometry"
     (with-skia ([p (make-path #:fill-rule 'even-odd)])
       (path-add-rect! p 0 0 30 30)
       (path-add-rect! p 10 10 10 10)
       (with-skia ([simple (path-simplify p)]
                   [winding (path-as-winding p)])
         (for ([q (in-list (list simple winding))])
           (check-true (path-contains? q 5 5))
           (check-false (path-contains? q 15 15)))
         (check-eq? (path-fill-rule winding) 'winding))))
   (test-case "closed path effects and measures reject native use"
     (define effect (make-dash-path-effect '(2 2)))
     (define path (make-path '((move 0 0) (line 10 0))))
     (define measure (make-path-measure path))
     (skia-close! effect)
     (skia-close! measure)
     (check-exn #rx"closed" (lambda () (make-paint #:path-effect effect)))
     (check-exn #rx"closed" (lambda () (path-measure-length measure)))
     (skia-close! path))
   (test-case "paint owns color, mask and image filters independently"
     (define swap
       '(0 0 1 0 0
         0 1 0 0 0
         1 0 0 0 0
         0 0 0 1 0))
     (define cf (make-color-matrix-filter swap))
     (define mf (make-blur-mask-filter 2))
     (define imf (make-blur-image-filter 1 1))
     (define p (make-paint #:color-filter cf #:mask-filter mf #:image-filter imf))
     ;; SkPaint retains each reference; caller wrappers may close immediately.
     (skia-close! cf)
     (skia-close! mf)
     (skia-close! imf)
     (define held-cf (paint-color-filter p))
     (define held-mf (paint-mask-filter p))
     (define held-imf (paint-image-filter p))
     (check-true (color-filter? held-cf))
     (check-true (mask-filter? held-mf))
     (check-true (image-filter? held-imf))
     (paint-set-color-filter! p #f)
     (paint-set-mask-filter! p #f)
     (paint-set-image-filter! p #f)
     (check-false (paint-color-filter p))
     (check-false (paint-mask-filter p))
     (check-false (paint-image-filter p))
     ;; Getter results remain independently usable after detaching from p.
     (with-skia ([q (make-paint #:color 'red
                                #:color-filter held-cf
                                #:mask-filter held-mf
                                #:image-filter held-imf)])
       (check-true (paint? q)))
     (skia-close! held-cf)
     (skia-close! held-mf)
     (skia-close! held-imf)
     (skia-close! p))
   (test-case "color matrix filter swaps red and blue channels"
     (with-skia ([s (make-surface 8 8)]
                 [cf (make-color-matrix-filter
                      '(0 0 1 0 0
                        0 1 0 0 0
                        1 0 0 0 0
                        0 0 0 1 0))]
                 [p (make-paint #:color 'red #:antialias? #f #:color-filter cf)])
       (draw-rect (surface-canvas s) 1 1 6 6 p)
       (check-equal? (surface-pixel s 4 4) blue)))
   (test-case "blend and composed color filters rasterize"
     (with-skia ([s (make-surface 16 8)]
                 [blue-src (make-blend-color-filter 'blue 'src)]
                 [swap-a (make-color-matrix-filter
                          '(0 0 1 0 0
                            0 1 0 0 0
                            1 0 0 0 0
                            0 0 0 1 0))]
                 [swap-b (make-color-matrix-filter
                          '(0 0 1 0 0
                            0 1 0 0 0
                            1 0 0 0 0
                            0 0 0 1 0))]
                 [twice (make-compose-color-filter swap-b swap-a)]
                 [blue-paint (make-paint #:color 'red #:antialias? #f
                                         #:color-filter blue-src)]
                 [red-paint (make-paint #:color 'red #:antialias? #f
                                        #:color-filter twice)])
       (define c (surface-canvas s))
       (draw-rect c 0 0 8 8 blue-paint)
       (draw-rect c 8 0 8 8 red-paint)
       (check-equal? (surface-pixel s 3 3) blue)
       (check-equal? (surface-pixel s 12 3) red)))
   (test-case "blur mask filter spreads alpha outside geometry"
     (with-skia ([s (make-surface 40 40)]
                 [mf (make-blur-mask-filter 4 #:style 'normal #:respect-ctm? #f)]
                 [p (make-paint #:color 'red #:mask-filter mf)])
       (draw-circle (surface-canvas s) 20 20 6 p)
       (check-true (> (rgba-alpha (surface-pixel s 20 20)) 100))
       ;; x=29 lies outside the unfiltered circle but inside the blur falloff.
       (check-true (> (rgba-alpha (surface-pixel s 29 20)) 0))))
   (test-case "blur image filter spreads rendered source"
     (with-skia ([s (make-surface 48 32)]
                 [imf (make-blur-image-filter 3 3 #:tile-mode 'decal)]
                 [p (make-paint #:color 'blue #:antialias? #f #:image-filter imf)])
       (draw-rect (surface-canvas s) 18 10 12 12 p)
       (check-true (> (rgba-alpha (surface-pixel s 24 16)) 100))
       ;; Outside the original x-range [18,30), but blur should reach here.
       (check-true (> (rgba-alpha (surface-pixel s 32 16)) 0))))
   (test-case "drop shadow and shadow-only image filters render offsets"
     (with-skia ([s (make-surface 80 36)]
                 [shadow (make-drop-shadow-image-filter 8 0 2 2 (rgba 0 0 0 200))]
                 [shadow-only (make-drop-shadow-only-image-filter 18 0 2 2 (rgba 0 0 0 200))]
                 [with-source (make-paint #:color 'red #:antialias? #f #:image-filter shadow)]
                 [only (make-paint #:color 'red #:antialias? #f #:image-filter shadow-only)])
       (define c (surface-canvas s))
       (draw-rect c 5 8 12 12 with-source)
       (draw-rect c 45 8 12 12 only)
       ;; DropShadow includes the original source.
       (check-true (> (rgba-red (surface-pixel s 10 13)) 180))
       ;; Offset shadow reaches beyond the original right edge.
       (check-true (> (rgba-alpha (surface-pixel s 23 13)) 0))
       ;; Shadow-only suppresses the original source at x=50.
       (check-true (< (rgba-alpha (surface-pixel s 50 13)) 20))
       (check-true (> (rgba-alpha (surface-pixel s 68 13)) 0))))
   (test-case "color-filter image filter and composition form a filter graph"
     (with-skia ([s (make-surface 48 32)]
                 [swap (make-color-matrix-filter
                        '(0 0 1 0 0
                          0 1 0 0 0
                          1 0 0 0 0
                          0 0 0 1 0))]
                 [color-if (make-color-filter-image-filter swap)]
                 [blur-if (make-blur-image-filter 2 2 #:input color-if)]
                 [composed (make-compose-image-filter color-if blur-if)]
                 [p1 (make-paint #:color 'red #:antialias? #f #:image-filter color-if)]
                 [p2 (make-paint #:color 'red #:antialias? #f #:image-filter composed)])
       (define c (surface-canvas s))
       (draw-rect c 2 8 12 12 p1)
       (draw-rect c 28 8 12 12 p2)
       (define left (surface-pixel s 8 14))
       (check-true (> (rgba-blue left) (rgba-red left)))
       (define right (surface-pixel s 34 14))
       (check-true (> (rgba-red right) (rgba-blue right)))
       (check-true (> (rgba-alpha (surface-pixel s 42 14)) 0))))
   (test-case "closed filter resources reject native use"
     (define cf (make-color-matrix-filter
                 '(0 0 1 0 0  0 1 0 0 0  1 0 0 0 0  0 0 0 1 0)))
     (define mf (make-blur-mask-filter 2))
     (define imf (make-blur-image-filter 2 2))
     (skia-close! cf)
     (skia-close! mf)
     (skia-close! imf)
     (check-exn #rx"closed" (lambda () (make-paint #:color-filter cf)))
     (check-exn #rx"closed" (lambda () (make-paint #:mask-filter mf)))
     (check-exn #rx"closed" (lambda () (make-paint #:image-filter imf))))
   (test-case "default typeface introspection"
     (with-skia ([tf (make-typeface)])
       (check-true (string? (typeface-family-name tf)))
       (check-true (<= 0 (typeface-weight tf) 1000))
       (check-true (<= 1 (typeface-width tf) 9))
       (check-not-false (memq (typeface-slant tf) '(upright italic oblique)))))
   (test-case "family typeface creation with style"
     (with-skia ([base (make-typeface)])
       (define family (typeface-family-name base))
       (unless (string=? family "")
         (with-skia ([tf (typeface-from-family family #:weight 'bold #:slant 'italic)])
           (check-true (typeface? tf))
           (check-true (string? (typeface-family-name tf)))
           (check-true (<= 0 (typeface-weight tf) 1000))
           (check-true (<= 1 (typeface-width tf) 9))))))
   (test-case "font constructor, getters and setters"
     (with-skia ([f (make-font #:size 24 #:scale-x 1.25 #:skew-x 0.1
                               #:edging 'antialias #:hinting 'normal)])
       (check-= (font-size f) 24.0 0.001)
       (check-= (font-scale-x f) 1.25 0.001)
       (check-= (font-skew-x f) 0.1 0.001)
       (check-equal? (font-edging f) 'antialias)
       (check-equal? (font-hinting f) 'normal)
       (font-set-size! f 31)
       (font-set-scale-x! f 0.9)
       (font-set-skew-x! f -0.2)
       (font-set-edging! f 'alias)
       (font-set-hinting! f 'slight)
       (font-set-subpixel! f #t)
       (font-set-linear-metrics! f #t)
       (font-set-embolden! f #t)
       (check-= (font-size f) 31.0 0.001)
       (check-= (font-scale-x f) 0.9 0.001)
       (check-= (font-skew-x f) -0.2 0.001)
       (check-equal? (font-edging f) 'alias)
       (check-equal? (font-hinting f) 'slight)
       (check-true (font-subpixel? f))
       (check-true (font-linear-metrics? f))
       (check-true (font-embolden? f))))
   (test-case "font metrics have a usable line spacing"
     (with-skia ([f (make-font #:size 32)])
       (define m (font-get-metrics f))
       (check-true (font-metrics? m))
       (check-true (real? (font-metrics-top m)))
       (check-true (<= (font-metrics-ascent m) 0))
       (check-true (>= (font-metrics-descent m) 0))
       (check-true (> (font-metrics-spacing m) 0))))
   (test-case "simple text measurement and bounds"
     (with-skia ([f (make-font #:size 32)] [p (make-paint #:style 'stroke #:stroke-width 2)])
       (check-true (> (measure-simple-text f "Hello") 0))
       (check-true (> (measure-simple-text f "Hello" #:paint p) 0))
       (define-values (x y w h) (simple-text-bounds f "Hello"))
       (for ([v (in-list (list x y w h))]) (check-true (real? v)))
       (check-true (> w 0))
       (check-true (> h 0))))
   (test-case "UTF-8 text maps to glyph ids"
     (with-skia ([f (make-font #:size 32)])
       (define glyphs (font-text->glyphs f "Hello"))
       (check-true (vector? glyphs))
       (check-equal? (vector-length glyphs) 5)
       (for ([g (in-vector glyphs)])
         (check-true (<= 0 g #xffff)))
       (check-equal? (font-char->glyph f #\H) (vector-ref glyphs 0))
       (check-equal? (vector-length (font-text->glyphs f "")) 0)))
   (test-case "glyph and simple-text outline paths are exposed"
     (with-skia ([f (make-font #:size 48)])
       (define gid (font-char->glyph f #\A))
       (define gp (font-glyph-path f gid))
       (when gp
         (define-values (_x _y w h) (path-tight-bounds gp))
         (check-true (> w 0))
         (check-true (> h 0))
         (skia-close! gp))
       (with-skia ([tp (simple-text-path f "ABC" 10 60)])
         (define-values (_x _y w h) (path-tight-bounds tp))
         (check-true (>= w 0))
         (check-true (>= h 0)))))
   (test-case "simple text drawing changes raster pixels"
     (with-skia ([s (make-surface 240 80 #:background 'white)]
                 [f (make-font #:size 40)]
                 [p (make-paint #:color 'black)])
       (draw-simple-text (surface-canvas s) "Skia" 12 55 f p)
       (define bs (surface->rgba-bytes s))
       (check-true
        (for/or ([i (in-range 0 (bytes-length bs) 4)])
          (or (< (bytes-ref bs i) 250)
              (< (bytes-ref bs (+ i 1)) 250)
              (< (bytes-ref bs (+ i 2)) 250))))))
   (test-case "font retains a user typeface after wrapper closure"
     (define tf (make-typeface))
     (define f (make-font tf #:size 28))
     (skia-close! tf)
     (check-true (> (measure-simple-text f "Hi") 0))
     (skia-close! f))
   (test-case "closed font and typeface reject use"
     (define tf (make-typeface))
     (define f (make-font tf))
     (skia-close! tf)
     (skia-close! f)
     (check-exn #rx"closed" (lambda () (typeface-family-name tf)))
     (check-exn #rx"closed" (lambda () (font-size f))))
   (test-case "repeated allocation, PNG encoding and deterministic cleanup"
     (for ([i (in-range 32)])
       (with-skia ([s (make-surface 16 16)] [p (make-paint #:color 'red)])
         (draw-circle (surface-canvas s) 8 8 5 p)
         (check-true (> (bytes-length (surface->png-bytes s)) 40)))))
   (test-case "call-with-picture records and replays"
     (with-skia ([pic (call-with-picture
                       40 40
                       (lambda (c)
                         (with-skia ([p (make-paint #:color 'red #:antialias? #f)])
                           (draw-rect c 10 10 20 20 p))))]
                 [s (make-surface 60 30)])
       (draw-picture (surface-canvas s) pic)
       (draw-picture (surface-canvas s) pic #:x 20)
       (check-equal? (surface-pixel s 15 15) red)
       (check-equal? (surface-pixel s 35 15) red)))
   (test-case "picture to image scales recorded content"
     (with-skia ([pic (call-with-picture
                       20 20
                       (lambda (c)
                         (with-skia ([p (make-paint #:color 'blue #:antialias? #f)])
                           (draw-rect c 0 0 20 20 p))))]
                 [img (picture->image pic 40 10)]
                 [s (make-surface 40 10)])
       (draw-image (surface-canvas s) img 0 0)
       (check-equal? (surface-pixel s 5 5) blue)
       (check-equal? (image-width img) 40)
       (check-equal? (image-height img) 10)))
   (test-case "explicit picture recorder toggles recording state"
     (with-skia ([rec (make-picture-recorder)])
       (check-false (picture-recorder-recording? rec))
       (define rc (picture-recorder-begin-recording! rec 0 0 30 30))
       (check-true (picture-recorder-recording? rec))
       (with-skia ([p (make-paint #:color 'red #:antialias? #f)])
         (draw-rect rc 5 5 20 20 p))
       (with-skia ([pic (picture-recorder-finish-recording! rec)]
                   [s (make-surface 30 30)])
         (check-false (picture-recorder-recording? rec))
         (draw-picture (surface-canvas s) pic)
         (check-equal? (surface-pixel s 15 15) red))))
   (test-case "recorder canvas becomes invalid after finish"
     (with-skia ([rec (make-picture-recorder)])
       (define rc (picture-recorder-begin-recording! rec 0 0 20 20))
       (with-skia ([pic (picture-recorder-finish-recording! rec)])
         (check-exn exn:fail? (lambda () (canvas-save-count rc))))))
   (test-case "draw-picture supports scaled placement"
     (with-skia ([pic (call-with-picture
                       10 10
                       (lambda (c)
                         (with-skia ([p (make-paint #:color 'red #:antialias? #f)])
                           (draw-rect c 0 0 10 10 p))))]
                 [s (make-surface 40 40)])
       (draw-picture (surface-canvas s) pic #:x 10 #:y 5 #:width 20 #:height 30)
       (check-equal? (surface-pixel s 20 20) red)
       (check-equal? (surface-pixel s 5 5) transparent)))

   (test-case "relative path commands and point queries"
     (with-skia ([p (make-path '((move 10 10) (rline 20 0) (rline 0 15) (close)))])
       (check-equal? (path-point-count p) 3)
       (check-equal? (call-with-values (lambda () (path-point-ref p 1)) list)
                     '(30.0 10.0))
       (check-equal? (call-with-values (lambda () (path-last-point p)) list)
                     '(30.0 25.0))
       (check-true (path-convex? p))
       (check-true (path-contains? p 20 15))))
   (test-case "conic paths and rounded rects render as expected"
     (with-skia ([p (make-path)] [rr (make-path)])
       (path-move-to! p 5 25)
       (path-conic-to! p 20 0 35 25 0.5)
       ;; SkPath stores the contour start, conic control, and endpoint.
       (check-equal? (path-point-count p) 3)
       (check-equal? (path-points p) '((5.0 25.0) (20.0 0.0) (35.0 25.0)))
       (path-add-rounded-rect! rr 0 0 30 20 5 5)
       (check-true (path-contains? rr 15 10))
       (check-false (path-contains? rr -1 -1))))
   (test-case "path add-path and reverse-add-path compose geometry"
     (with-skia ([base (make-path '((move 0 0) (line 10 0) (line 10 10) (close)))]
                 [dest (make-path)])
       (path-add-path! dest base #:dx 20 #:dy 0)
       (path-add-reversed-path! dest base)
       (check-true (path-contains? dest 25 5))
       (check-true (>= (path-point-count dest) 6))))
   (test-case "svg path parse and serialization round trip"
     (with-skia ([p (svg-path->path "M 0 0 L 20 0 L 20 10 Z")])
       (check-true (path-contains? p 10 5))
       (define s (path->svg-path p))
       (check-true (string? s))
       (check-true (> (string-length s) 0))
       (with-skia ([q (svg-path->path s)])
         (check-true (path-contains? q 10 5)))))
   (test-case "font managers enumerate families and own references"
     (with-skia ([fm (default-font-manager)]
                 [fresh (make-font-manager)])
       (define n (font-manager-family-count fm))
       (check-true (exact-nonnegative-integer? n))
       (check-true (exact-nonnegative-integer? (font-manager-family-count fresh)))
       (when (positive? n)
         (define first (font-manager-family-name fm 0))
         (check-true (string? first))
         (check-not-false (member first (font-manager-families fm)))
         (check-exn exn:fail? (lambda () (font-manager-family-name fm n))))))
   (test-case "font manager matches family styles and fallback characters"
     (with-skia ([fm (default-font-manager)])
       (define count (font-manager-family-count fm))
       (when (positive? count)
         (define family (font-manager-family-name fm 0))
         (define by-family (font-manager-match-family fm family))
         (when by-family
           (check-true (typeface? by-family))
           (check-true (string? (typeface-family-name by-family)))
           (skia-close! by-family)))
       (define by-char
         (font-manager-match-character fm #\A #:languages '("en")))
       (when by-char
         (check-true (typeface? by-char))
         (with-skia ([matched-font (make-font by-char)])
           (check-not-equal? (font-char->glyph matched-font #\A) 0))
         (skia-close! by-char))))
   (test-case "positioned text blob draws and reports bounds"
     (with-skia ([tf (make-typeface)]
                 [f (make-font tf #:size 30)]
                 [p (make-paint #:color 'black)]
                 [s (make-surface 160 60)])
       (define glyphs (font-text->glyphs f "AB"))
       (with-skia ([blob (make-positioned-text-blob f glyphs '((0 0) (36 0)))])
         (define-values (_x _y w h) (text-blob-bounds blob))
         (check-true (> w 0))
         (check-true (> h 0))
         (check-true (exact-nonnegative-integer? (text-blob-unique-id blob)))
         (draw-text-blob (surface-canvas s) blob 12 42 p)
         (define bs (surface->rgba-bytes s))
         (check-true
          (for/or ([i (in-range 3 (bytes-length bs) 4)])
            (> (bytes-ref bs i) 0))))))
   (test-case "text blob preserves explicit glyph positions"
     (with-skia ([tf (make-typeface)]
                 [f (make-font tf #:size 28)])
       (define g (font-char->glyph f #\X))
       (with-skia ([blob (make-positioned-text-blob f (vector g g) '((0 0) (100 0)))])
         (define-values (_x _y w _h) (text-blob-bounds blob))
         (check-true (> w 90)))))
   (test-case "text blob retains font data after font wrapper closure"
     (define tf (make-typeface))
     (define f (make-font tf #:size 30))
     (define glyphs (font-text->glyphs f "Hi"))
     (define blob (make-positioned-text-blob f glyphs '((0 0) (28 0))))
     (skia-close! f)
     (skia-close! tf)
     (with-skia ([s (make-surface 120 60)]
                 [p (make-paint #:color 'black)])
       (draw-text-blob (surface-canvas s) blob 10 42 p)
       (define bs (surface->rgba-bytes s))
       (check-true
        (for/or ([i (in-range 3 (bytes-length bs) 4)])
          (> (bytes-ref bs i) 0))))
     (skia-close! blob))
   (test-case "HarfBuzz shapes Latin text into glyph positions"
     (with-skia ([tf (make-typeface)]
                 [f (make-font tf #:size 36)]
                 [sh (make-shaper f)])
       (define run (shape-text sh "abc"))
       (check-equal? (shaped-run-glyph-count run) 3)
       (check-equal? (length (shaped-run-clusters run)) 3)
       (check-equal? (length (shaped-run-positions run)) 3)
       (check-true (> (abs (shaped-run-advance-x run)) 0))))
   (test-case "HarfBuzz shaping produces drawable positioned text"
     (with-skia ([tf (make-typeface)]
                 [f (make-font tf #:size 36)]
                 [sh (make-shaper f)]
                 [p (make-paint #:color 'black)]
                 [s (make-surface 180 70)])
       (define run (shape-text sh "Skia"))
       (draw-shaped-run (surface-canvas s) sh run 12 48 p)
       (define pixels (surface->rgba-bytes s))
       (check-true
        (for/or ([i (in-range 3 (bytes-length pixels) 4)])
          (> (bytes-ref pixels i) 0)))))
   (test-case "shaped runs can be retained as ordinary text blobs"
     (define tf (make-typeface))
     (define f (make-font tf #:size 32))
     (define sh (make-shaper f))
     (define run (shape-text sh "blob"))
     (define blob (shaped-run->text-blob sh run))
     (skia-close! sh)
     (skia-close! f)
     (skia-close! tf)
     (with-skia ([s (make-surface 150 60)]
                 [p (make-paint #:color 'blue)])
       (draw-text-blob (surface-canvas s) blob 8 42 p)
       (define-values (_x _y w h) (text-blob-bounds blob))
       (check-true (> w 0))
       (check-true (> h 0)))
     (skia-close! blob))
   (test-case "HarfBuzz accepts direction language script and feature controls"
     (with-skia ([tf (make-typeface)]
                 [f (make-font tf #:size 30)]
                 [sh (make-shaper f)])
       (define run (shape-text sh "office"
                               #:direction 'ltr
                               #:script 'latn
                               #:language "en"
                               #:features '("liga=0" "kern=1")))
       (check-true (positive? (shaped-run-glyph-count run)))
       (check-exn exn:fail? (lambda () (shape-text sh "office" #:features '("not a feature"))))))
   (test-case "HarfBuzz shapes RTL fallback text"
     (with-skia ([fm (default-font-manager)])
       (define face (font-manager-match-character fm #\م #:languages '("ar")))
       (when face
         (call-with-skia-resource
          face
          (lambda (tf)
            (with-skia ([f (make-font tf #:size 34)]
                        [sh (make-shaper f)])
              (define run (shape-text sh "مرحبا" #:direction 'rtl #:script 'arab #:language "ar"))
              (check-true (positive? (shaped-run-glyph-count run)))
              (check-equal? (length (shaped-run-glyphs run))
                            (length (shaped-run-positions run)))))))))
   (test-case "paragraph layout wraps and exposes line metrics"
     (with-skia ([tf (make-typeface)]
                 [f (make-font tf #:size 28)]
                 [sh (make-shaper f)])
       (define wide (layout-text sh "alpha beta gamma" #:width 500))
       (define narrow (layout-text sh "alpha beta gamma" #:width 100))
       (check-equal? (text-layout-line-count wide) 1)
       (check-true (> (text-layout-line-count narrow) 1))
       (check-true (>= (text-layout-width narrow) 100.0))
       (check-true (> (text-layout-height narrow) 0))
       (check-true (> (text-layout-line-height narrow) 0))
       (for ([line (in-list (text-layout-lines narrow))])
         (check-true (text-layout-line? line))
         (check-true (shaped-run? (text-layout-line-run line)))
         (check-true (>= (text-layout-line-width line) 0)))))
   (test-case "paragraph layout preserves explicit blank lines"
     (with-skia ([tf (make-typeface)]
                 [f (make-font tf #:size 24)]
                 [sh (make-shaper f)])
       (define layout (layout-text sh "first

third"))
       (check-equal? (text-layout-line-count layout) 3)
       (check-equal? (map text-layout-line-text (text-layout-lines layout))
                     '("first" "" "third"))
       (check-true (< (text-layout-line-baseline (first (text-layout-lines layout)))
                      (text-layout-line-baseline (third (text-layout-lines layout)))))))
   (test-case "paragraph alignment computes stable origins"
     (with-skia ([tf (make-typeface)]
                 [f (make-font tf #:size 24)]
                 [sh (make-shaper f)])
       (define left-layout (layout-text sh "abc" #:width 200 #:align 'left #:direction 'ltr))
       (define center-layout (layout-text sh "abc" #:width 200 #:align 'center #:direction 'ltr))
       (define right-layout (layout-text sh "abc" #:width 200 #:align 'right #:direction 'ltr))
       (define lx (text-layout-line-origin-x (first (text-layout-lines left-layout))))
       (define cx (text-layout-line-origin-x (first (text-layout-lines center-layout))))
       (define rx (text-layout-line-origin-x (first (text-layout-lines right-layout))))
       (check-= lx 0.0 0.001)
       (check-true (< lx cx rx))))
   (test-case "RTL paragraph layout uses right-edge origins"
     (with-skia ([fm (default-font-manager)])
       (define face (font-manager-match-character fm #\מ #:languages '("ar")))
       (when face
         (call-with-skia-resource
          face
          (lambda (tf)
            (with-skia ([f (make-font tf #:size 30)]
                        [sh (make-shaper f)])
              (define layout (layout-text sh "مرحبا بالعالم" #:width 240
                                          #:direction 'rtl #:script 'arab #:language "ar"))
              (define line (first (text-layout-lines layout)))
              (check-eq? (text-layout-line-direction line) 'rtl)
              (check-true (> (text-layout-line-origin-x line) 0))
              ;; Auto shaping still exposes descending HarfBuzz clusters for
              ;; this ordinary RTL run, which the paragraph layer uses for
              ;; start/end alignment direction.
              (define auto-layout (layout-text sh "مرحبا" #:width 240
                                               #:script 'arab #:language "ar"))
              (check-eq? (text-layout-line-direction
                          (first (text-layout-lines auto-layout)))
                         'rtl)))))))
   (test-case "paragraph layouts rasterize through shaped runs"
     (with-skia ([tf (make-typeface)]
                 [f (make-font tf #:size 28)]
                 [sh (make-shaper f)]
                 [p (make-paint #:color 'black)]
                 [surface (make-surface 220 140)])
       (define layout (layout-text sh "one two three four" #:width 150 #:align 'center))
       (draw-text-layout (surface-canvas surface) layout 20 10 p)
       (define pixels (surface->rgba-bytes surface))
       (check-true
        (for/or ([i (in-range 3 (bytes-length pixels) 4)])
          (> (bytes-ref pixels i) 0)))))
   (test-case "paragraph layout reports closed shaper on drawing"
     (with-skia ([tf (make-typeface)]
                 [f (make-font tf #:size 24)])
       (define sh (make-shaper f))
       (define layout (layout-text sh "retained layout"))
       (skia-close! sh)
       (with-skia ([surface (make-surface 200 70)]
                   [p (make-paint #:color 'black)])
         (check-exn #rx"closed"
                    (lambda () (draw-text-layout (surface-canvas surface) layout 0 0 p))))))
   (test-case "mixed text layout resolves visual bidi runs"
     (with-skia ([fm (default-font-manager)]
                 [tf (make-typeface)]
                 [f (make-font tf #:size 26)]
                 [sh (make-shaper f)])
       (define layout (layout-mixed-text sh fm "abc שלום 123" #:width 400))
       (check-equal? (mixed-text-layout-line-count layout) 1)
       (define line (first (mixed-text-layout-lines layout)))
       (check-eq? (mixed-text-line-direction line) 'ltr)
       (define dirs (map mixed-text-run-direction (mixed-text-line-runs line)))
       (check-not-false (memq 'ltr dirs))
       (check-not-false (memq 'rtl dirs))
       (check-true (for/and ([r (in-list (mixed-text-line-runs line))])
                     (>= (mixed-text-run-origin-x r) 0)))))
   (test-case "mixed text layout records font fallback"
     (with-skia ([fm (default-font-manager)]
                 [tf (make-typeface)]
                 [f (make-font tf #:size 28)]
                 [sh (make-shaper f)])
       (define missing? (zero? (font-char->glyph f #\界)))
       (define layout (layout-mixed-text sh fm "A界B" #:width 300 #:language "zh"))
       (define runs (mixed-text-line-runs (first (mixed-text-layout-lines layout))))
       (when missing?
         (check-not-false (for/or ([r (in-list runs)]) (mixed-text-run-family r))))))
   (test-case "mixed text layout preserves LTR number runs in RTL paragraphs"
     (with-skia ([fm (default-font-manager)]
                 [tf (make-typeface)]
                 [f (make-font tf #:size 28)]
                 [sh (make-shaper f)])
       (define layout (layout-mixed-text sh fm "שלום 123" #:width 300 #:direction 'rtl))
       (define line (first (mixed-text-layout-lines layout)))
       (check-eq? (mixed-text-line-direction line) 'rtl)
       (check-true (for/or ([r (in-list (mixed-text-line-runs line))])
                     (and (eq? (mixed-text-run-direction r) 'ltr)
                          (regexp-match? #rx"[0-9]" (mixed-text-run-text r)))))))
   (test-case "mixed text layout wraps and rasterizes"
     (with-skia ([fm (default-font-manager)]
                 [tf (make-typeface)]
                 [f (make-font tf #:size 27)]
                 [sh (make-shaper f)]
                 [p (make-paint #:color 'black)]
                 [surface (make-surface 300 180)])
       (define layout
         (layout-mixed-text sh fm "Racket שלום world مرحبا 123" #:width 190))
       (check-true (> (mixed-text-layout-line-count layout) 1))
       (draw-mixed-text-layout (surface-canvas surface) layout 20 10 p)
       (define pixels (surface->rgba-bytes surface))
       (check-true (for/or ([i (in-range 3 (bytes-length pixels) 4)])
                     (> (bytes-ref pixels i) 0)))))
   (test-case "mixed text layout reports closed dependencies"
     (define fm (default-font-manager))
     (with-skia ([tf (make-typeface)] [f (make-font tf #:size 24)])
       (define sh (make-shaper f))
       (define layout (layout-mixed-text sh fm "abc שלום"))
       (skia-close! fm)
       (with-skia ([surface (make-surface 200 80)] [p (make-paint #:color 'black)])
         (check-exn #rx"closed"
                    (lambda ()
                      (draw-mixed-text-layout (surface-canvas surface) layout 0 0 p))))
       (skia-close! sh)))
   (test-case "mixed layout wraps unspaced CJK at UAX #14 opportunities"
     (with-skia ([fm (default-font-manager)]
                 [tf (make-typeface)]
                 [f (make-font tf #:size 28)]
                 [sh (make-shaper f)])
       (define layout
         (layout-mixed-text sh fm "世界中文排版測試沒有空格"
                            #:width 90 #:language "zh"))
       (define lines (mixed-text-layout-lines layout))
       (check-true (> (length lines) 1))
       (check-true
        (for/and ([line (in-list lines)])
          (positive? (string-length (mixed-text-line-text line)))))))
   (test-case "mixed layout keeps CJK punctuation on the legal side of a break"
     (with-skia ([fm (default-font-manager)]
                 [tf (make-typeface)]
                 [f (make-font tf #:size 28)]
                 [sh (make-shaper f)])
       (define layout
         (layout-mixed-text sh fm "（世界）中文，標點測試。"
                            #:width 90 #:language "zh"))
       (for ([line (in-list (mixed-text-layout-lines layout))])
         (define text (mixed-text-line-text line))
         (check-false (regexp-match? #rx"^[），。]" text))
         (check-false (regexp-match? #rx"（$" text)))))
   (test-case "paragraph layout recognizes all Unicode hard line separators"
     (with-skia ([tf (make-typeface)]
                 [f (make-font tf #:size 24)]
                 [sh (make-shaper f)])
       (define text
         (string-append "one" (string #\u2028) "two"
                        (string #\u0085) "three"))
       (define layout (layout-text sh text))
       (check-equal? (map text-layout-line-text (text-layout-lines layout))
                     '("one" "two" "three"))))
   (test-case "closed shapers reject use"
     (with-skia ([tf (make-typeface)]
                 [f (make-font tf #:size 24)])
       (define sh (make-shaper f))
       (skia-close! sh)
       (check-exn #rx"closed" (lambda () (shape-text sh "x")))))
   (test-case "closed font-manager and text-blob resources reject use"
     (define fm (default-font-manager))
     (skia-close! fm)
     (check-exn #rx"closed" (lambda () (font-manager-family-count fm)))
     (with-skia ([tf (make-typeface)]
                 [f (make-font tf #:size 20)])
       (define blob (make-positioned-text-blob f (vector (font-char->glyph f #\A)) '((0 0))))
       (skia-close! blob)
       (check-exn #rx"closed" (lambda () (text-blob-bounds blob)))))
  ))

(define (make-list-of-red-pixels count)
  (if (zero? count) '() (append '(255 0 0 255) (make-list-of-red-pixels (sub1 count)))))

(module+ test
  (skia-check!)
  (harfbuzz-check!)
  (define failures (run-tests native-tests))
  (unless (zero? failures) (error 'native-tests "~a failures" failures)))
