#lang racket/base
(require rackunit racket/list "../main.rkt")
(provide advanced-canvas-native-tests)
(define (rectangle c x y w h color)
  (with-skia ([p (make-paint #:color color #:antialias? #f)]) (draw-rect c x y w h p)))
(define (scene c)
  (rectangle c 1 2 5 4 'red) (rectangle c 8 1 4 7 'blue))
(define (pixel-alpha s x y) (rgba-alpha (surface-pixel s x y)))
(define advanced-canvas-native-tests
  (test-suite
   "Advanced layers, native drawables and specialized canvases"
   (test-case "default record draws and restores the stack"
     (with-skia ([s (make-surface 16 12)])
       (define c (surface-canvas s))
       (call-with-canvas-layer-rec c (lambda () (rectangle c 1 1 4 4 'red)))
       (check-equal? (surface-pixel s 2 2) (rgb 255 0 0)) (check-equal? (canvas-save-count c) 1)))
   (test-case "unscoped layer returns previous save count"
     (with-skia ([s (make-surface 8 8)])
       (define c (surface-canvas s))
       (define count (canvas-save-layer-rec! c))
       (check-equal? count 1) (rectangle c 0 0 2 2 'red)
       (canvas-restore-to-count! c count) (check-equal? (pixel-alpha s 1 1) 255)))
   (test-case "layer paint modulates completed content"
     (with-skia ([s (make-surface 8 8 #:background 'white)]
                 [p (make-paint #:color (rgba 0 0 0 128))])
       (define c (surface-canvas s))
       (call-with-canvas-layer-rec c (lambda () (rectangle c 0 0 8 8 'red)) #:paint p)
       (check-= (rgba-green (surface-pixel s 4 4)) 127 1)))
   (test-case "explicit clip supplies actual bounded drawing"
     (with-skia ([s (make-surface 8 8)])
       (define c (surface-canvas s))
       (call-with-canvas-layer-rec c (lambda () (canvas-clear! c 'red)) #:clip '(2 2 3 3))
       (check-equal? (pixel-alpha s 0 0) 0) (check-equal? (pixel-alpha s 3 3) 255)))
   (test-case "clip and transform are restored"
     (with-skia ([s (make-surface 8 8)])
       (define c (surface-canvas s))
       (call-with-canvas-layer-rec c (lambda () (canvas-translate! c 5 5)) #:clip '(2 2 3 3))
       (rectangle c 0 0 1 1 'blue) (check-equal? (surface-pixel s 0 0) (rgb 0 0 255))))
   (test-case "initialize with previous retains existing pixels"
     (with-skia ([s (make-surface 8 8 #:background 'red)] [p (make-paint #:blend-mode 'src)])
       (call-with-canvas-layer-rec (surface-canvas s) void #:paint p
         #:options (make-layer-options #:initialize-with-previous? #t))
       (check-equal? (surface-pixel s 3 3) (rgb 255 0 0))))
   (test-case "backdrop field really filters previous contents"
     (with-skia ([s (make-surface 8 8 #:background 'red)]
                 [cf (make-color-matrix-filter '#(0 0 0 0 0  0 0 0 0 0  0 0 0 0 1  0 0 0 1 0))]
                 [f (make-color-filter-image-filter cf)] [p (make-paint #:blend-mode 'src)])
       (call-with-canvas-layer-rec (surface-canvas s) void #:backdrop f #:paint p)
       (check-equal? (surface-pixel s 3 3) (rgb 0 0 255))))
   (test-case "F16 layer retains extended samples within F16 compositing precision"
     (with-skia ([b (make-raster-buffer-from-info (make-image-info 4 4 #:color-type 'rgba-f16))])
       (call-with-raster-buffer-canvas b
         (lambda (c)
           (call-with-canvas-layer-rec c
             (lambda () (canvas-clear-color4f! c (make-color4f 0.5009765625 -0.125 1.25 1)))
             #:options (make-layer-options #:f16? #t))))
       (call-with-raster-buffer-pixmap b
         (lambda (v)
           (define sample (pixmap-sample v 1 1))
           ;; kF16ColorType selects an F16 intermediate, but raster layer
           ;; composition is not specified as a bit-preserving copy. m119 can
           ;; round this channel again on restore (observed two binary16 ULPs).
           ;; Keep the CPU oracle about bounded F16 precision and extended
           ;; range; the selected-GPU acceptance separately checks the two
           ;; close raw values remain distinct.
           (check-= (vector-ref sample 0) 0.5009765625 0.0011)
           (check-= (vector-ref sample 1) -0.125 0.0001)
           (check-= (vector-ref sample 2) 1.25 0.0001)
           (check-= (vector-ref sample 3) 1.0 0.0001)))))
   (test-case "LCD preservation flag can be requested without font claims"
     (with-skia ([s (make-surface 8 8)])
       (define c (surface-canvas s))
       (call-with-canvas-layer-rec c (lambda () (rectangle c 0 0 4 4 'red))
         #:options (make-layer-options #:preserve-lcd-text? #t))
       (check-equal? (pixel-alpha s 1 1) 255)))
   (test-case "exceptions restore and unpin the owner"
     (with-skia ([s (make-surface 8 8)])
       (define c (surface-canvas s))
       (check-exn #rx"body failure" (lambda ()
         (call-with-canvas-layer-rec c (lambda () (canvas-save! c) (error 'test "body failure")))))
       (check-equal? (canvas-save-count c) 1)
       (skia-close! s) (check-true (skia-closed? s))))
   (test-case "protected restore cannot pop the scoped layer"
     (with-skia ([s (make-surface 8 8)])
       (define c (surface-canvas s))
       (call-with-canvas-layer-rec c
         (lambda () (check-exn #rx"protected" (lambda () (canvas-restore-to-count! c 1)))))))
   (test-case "new layer scope pins CPU target against closure"
     (with-skia ([s (make-surface 8 8)])
       (define c (surface-canvas s))
       (call-with-canvas-layer-rec c
         (lambda () (check-exn #rx"pinned" (lambda () (skia-close! s)))
                    (rectangle c 0 0 2 2 'red)))
       (check-equal? (pixel-alpha s 1 1) 255)))
   (test-case "native layer retains supplied paint across its closure"
     (with-skia ([s (make-surface 8 8)] [p (make-paint #:color (rgba 0 0 0 128))])
       (define c (surface-canvas s))
       (call-with-canvas-layer-rec c
         (lambda () (skia-close! p) (rectangle c 0 0 8 8 'red)) #:paint p)
       (check-= (pixel-alpha s 4 4) 128 1)))
   (test-case "closed backdrop rejects before save count changes"
     (with-skia ([s (make-surface 8 8)] [f (make-offset-image-filter 0 0)])
       (skia-close! f) (define c (surface-canvas s))
       (check-exn exn:fail? (lambda () (canvas-save-layer-rec! c #:backdrop f)))
       (check-equal? (canvas-save-count c) 1)))
   (test-case "layer preserves multiple callback values"
     (with-skia ([s (make-surface 8 8)])
       (check-equal? (call-with-values
                      (lambda () (call-with-canvas-layer-rec (surface-canvas s) (lambda () (values 2 3)))) list)
                     '(2 3))))
   (test-case "discard does not prevent an explicit complete overwrite"
     (with-skia ([s (make-surface 8 8)])
       (define c (surface-canvas s)) (canvas-discard! c) (canvas-clear! c 'blue)
       (check-equal? (surface-pixel s 0 0) (rgb 0 0 255))))
   (test-case "drawable captures once and survives source closure"
     (define calls 0)
     (with-skia ([p (call-with-picture 16 12 (lambda (c) (set! calls (add1 calls)) (scene c)))]
                 [d (picture->drawable p)] [s (make-surface 16 12)])
       (skia-close! p)
       (for ([i (in-range 3)]) (draw-drawable (surface-canvas s) d))
       (check-equal? calls 1) (check-equal? (surface-pixel s 2 3) (rgb 255 0 0))))
   (test-case "retained and immediate drawable drawing agree"
     (with-skia ([d (call-with-drawable 16 12 scene)] [a (make-surface 16 12)] [b (make-surface 16 12)])
       (draw-drawable (surface-canvas a) d)
       (draw-drawable (surface-canvas b) d #:mode 'immediate)
       (check-equal? (surface->rgba-bytes a) (surface->rgba-bytes b))))
   (test-case "drawable snapshot remains usable after drawable close"
     (with-skia ([d (call-with-drawable 16 12 scene)] [p (drawable->picture d)] [s (make-surface 16 12)])
       (skia-close! d) (draw-picture (surface-canvas s) p)
       (check-equal? (surface-pixel s 9 2) (rgb 0 0 255))))
   (test-case "drawable metadata is detached and generation invalidation is explicit"
     (with-skia ([d (call-with-drawable 16 12 scene)])
       (define bounds (drawable-bounds d)) (check-true (immutable? bounds))
       (define id (drawable-generation-id d)) (check-true (positive? id))
       (check-true (exact-nonnegative-integer? (drawable-approximate-bytes-used d)))
       (drawable-notify-drawing-changed! d)
       (check-not-equal? id (drawable-generation-id d))
       (skia-close! d) (check-equal? (vector-length bounds) 4)))
   (test-case "recorded pictures retain drawn drawable dependencies"
     (with-skia ([d (call-with-drawable 16 12 scene)]
                 [p (call-with-picture 16 12 (lambda (c) (draw-drawable c d)))]
                 [s (make-surface 16 12)])
       (skia-close! d) (draw-picture (surface-canvas s) p)
       (check-equal? (surface-pixel s 2 3) (rgb 255 0 0))))
   (test-case "plain drawable stays vector-auditable in PDF and SVG"
     (with-skia ([d (call-with-drawable 16 12 scene)])
       (for ([kind '(pdf svg)])
         (define page (make-output-page 16 12 (lambda (c) (draw-drawable c d))))
         (define-values (bytes report) (output->bytes/audit page kind #:policy 'vector-only))
         (check-true (> (bytes-length bytes) 50)) (check-true (output-audit-report-vector-only? report)))))
   (test-case "backdrop provenance survives drawable and picture snapshots"
     (for ([mode '(backdrop initialization)])
       (with-skia ([filter (make-offset-image-filter 1 0)]
                   [d (call-with-drawable 8 8
                        (lambda (c)
                          (rectangle c 1 1 3 3 'red)
                          (call-with-canvas-layer-rec c void
                            #:backdrop (and (eq? mode 'backdrop) filter)
                            #:options (make-layer-options
                                        #:initialize-with-previous? (eq? mode 'initialization)))))]
                   [p (drawable->picture d)])
         (skia-close! d) (skia-close! filter)
         (for ([kind '(pdf svg)])
           (define page (make-output-page 8 8 (lambda (c) (draw-picture c p))))
           (check-exn exn:fail:output-audit?
             (lambda () (output->bytes/audit page kind #:policy 'error)))))))
   (test-case "NoDraw canvas is scoped and identifies nonrendering execution"
     (define escaped #f)
     (call-with-nodraw-canvas 16 12
       (lambda (c) (set! escaped c) (check-true (canvas? c))
                   (check-eq? (canvas-execution-backend c) 'nodraw) (scene c)))
     (check-true (skia-closed? escaped))
     (check-exn #rx"expired" (lambda () (canvas-clear! escaped 'red))))
   (test-case "NoDraw preserves callback values"
     (check-equal? (call-with-values
                    (lambda () (call-with-nodraw-canvas 8 8 (lambda (c) (values 1 2)))) list) '(1 2)))
   (test-case "NWay fans out once to identical raster targets"
     (define calls 0)
     (with-skia ([a (make-surface 16 12)] [b (make-surface 16 12)])
       (call-with-nway-canvas (list a b)
         (lambda (c) (set! calls (add1 calls)) (scene c)))
       (check-equal? calls 1) (check-equal? (surface->rgba-bytes a) (surface->rgba-bytes b))
       (check-equal? (surface-pixel b 9 2) (rgb 0 0 255))))
   (test-case "NWay targets are exclusively borrowed and not closeable"
     (with-skia ([a (make-surface 8 8)] [b (make-surface 8 8)])
       (call-with-nway-canvas (list a b)
         (lambda (c)
           (check-exn #rx"pinned" (lambda () (skia-close! a)))
           (check-exn #rx"borrowed" (lambda () (surface-canvas b)))
           (rectangle c 0 0 2 2 'red)))
       (check-equal? (canvas-save-count (surface-canvas a)) 1)))
   (test-case "NWay exception restores native state and releases borrow"
     (with-skia ([a (make-surface 8 8)] [b (make-surface 8 8)])
       (check-exn #rx"fanout failure" (lambda ()
         (call-with-nway-canvas (list a b)
           (lambda (c) (canvas-save! c) (canvas-translate! c 4 4) (error 'test "fanout failure")))))
       (for ([s (in-list (list a b))])
         (define c (surface-canvas s)) (check-equal? (canvas-save-count c) 1)
         (rectangle c 0 0 1 1 'blue) (check-equal? (surface-pixel s 0 0) (rgb 0 0 255)))))
   (test-case "duplicate and differently sized NWay targets reject"
     (with-skia ([a (make-surface 8 8)] [b (make-surface 9 8)])
       (check-exn #rx"duplicate" (lambda () (call-with-nway-canvas (list a a) void)))
       (check-exn #rx"identical dimensions" (lambda () (call-with-nway-canvas (list a b) void)))))
   (test-case "nonidentity target state rejects without altering it"
     (with-skia ([s (make-surface 8 8)])
       (define c (surface-canvas s)) (canvas-translate! c 1 0)
       (check-exn #rx"identity" (lambda () (call-with-nway-canvas (list s) void)))
       (canvas-reset-transform! c) (call-with-nway-canvas (list s) void)))
   (test-case "Overdraw Alpha8 output records one and two coverings"
     (with-skia ([s (make-surface-from-info (make-image-info 12 10 #:color-type 'alpha-8))])
       (call-with-overdraw-canvas s
         (lambda (c) (rectangle c 2 2 6 6 'red) (rectangle c 4 2 6 6 'blue)))
       (check-equal? (pixel-alpha s 0 0) 0) (check-equal? (pixel-alpha s 3 3) 1)
       (check-equal? (pixel-alpha s 5 3) 2)))
   (test-case "Overdraw refuses an ordinary color target"
     (with-skia ([s (make-surface 8 8)])
       (check-exn #rx"Alpha8" (lambda () (call-with-overdraw-canvas s void)))))
   (test-case "special canvas lease cannot move to another thread"
     (call-with-nodraw-canvas 8 8
       (lambda (c)
         (define result (make-channel))
         (thread (lambda ()
           (channel-put result (with-handlers ([exn:fail? (lambda (_) 'rejected)])
                                 (canvas-clear! c 'red) 'accepted))))
         (check-eq? (channel-get result) 'rejected))))))
