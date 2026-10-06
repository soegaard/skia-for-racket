#lang racket/base
(require rackunit racket/list racket/vector "../main.rkt" "float-pixel-fixtures.rkt"
         "../private/float-pixel-util.rkt")
(provide float-pixel-native-tests)
(define (near actual expected [tolerance 0.002])
  (define a (if (vector? actual) (vector->list actual) actual))
  (define e (if (vector? expected) (vector->list expected) expected))
  (check-equal? (length a) (length e))
  (for ([x (in-list a)] [y (in-list e)]) (check-= x y tolerance)))
(define (sample b [x 0] [y 0]) (call-with-raster-buffer-pixmap b (lambda (p) (pixmap-sample p x y))))
(define (put b value [x 0] [y 0])
  (call-with-raster-buffer-pixmap b (lambda (p) (pixmap-set-sample! p x y value)) #:writable? #t))
(define (image-page im)
  (make-output-page 64 32 (lambda (c) (draw-image c im 0 0)) #:background 'white))
(define float-pixel-native-tests
  (test-suite
   "Floating pixels and colors (native)"
   (test-case "both float formats allocate initialized transparent storage"
     (for ([f (in-vector float-pixel-formats)])
       (with-float-buffer f (lambda (b) (near (sample b) '(0 0 0 0))))))
   (test-case "opaque F16 and F32 storage starts with alpha one"
     (for ([f (in-vector float-pixel-formats)])
       (with-float-buffer f (lambda (b) (near (sample b) '(0 0 0 1)) (check-true (raster-buffer-opaque? b)))
         #:alpha-type 'opaque)))
   (test-case "raw float samples retain negative extended and fractional channels"
     (for ([f (in-vector float-pixel-formats)])
       (with-float-buffer f (lambda (b) (put b '#(-0.25 1.5 0.5009765625 0.5))
                                      (near (sample b) '#(-0.25 1.5 0.5009765625 0.5) 0.000001)))))
   (test-case "native float storage distinguishes values below one byte step"
     (for ([f (in-vector float-pixel-formats)])
       (with-float-buffer f
         (lambda (b)
           (put b '#(0.5 0 0 1) 0) (put b '#(0.5009765625 0 0 1) 1)
           (check-true (> (vector-ref (sample b 1) 0) (vector-ref (sample b 0) 0)))))))
   (test-case "F32 storage preserves distinctions finer than half float"
     (with-float-buffer 'rgba-f32
       (lambda (b)
         (put b '#(0.5 0 0 1) 0) (put b '#(0.5000001192092896 0 0 1) 1)
         (check-= (- (vector-ref (sample b 1) 0) (vector-ref (sample b 0) 0)) (expt 2 -23) 1e-12))))
   (test-case "raw half subnormal storage does not use native flush-to-zero reads"
     (with-float-buffer 'rgba-f16
       (lambda (b) (put b (vector (expt 2 -24) 0 0 1))
                  (check-= (vector-ref (sample b) 0) (expt 2 -24) 1e-15))))
   (test-case "late invalid float storage input cannot partially overwrite a buffer"
     (with-float-buffer 'rgba-f32
       (lambda (b)
         (define before (raster-buffer->storage-bytes b))
         (define bad (bytes-copy before))
         (bytes-copy! bad (- (bytes-length bad) 16) (real->floating-point-bytes +inf.0 4 (system-big-endian?)))
         (check-exn exn:fail? (lambda () (raster-buffer-write-storage! b bad)))
         (check-equal? (raster-buffer->storage-bytes b) before))))
   (test-case "raw input is copied and full padding survives roundtrip"
     (define info (float-fixture-info 'rgba-f16 1 2))
     (with-skia ([b (make-raster-buffer-from-info info #:row-bytes 16)])
       (define pixel (float-sample->bytes 'test info '#(0.25 0.5 0.75 1)))
       (define bytes (bytes-append pixel (make-bytes 8 165) pixel (make-bytes 8 90)))
       (define before (bytes-copy bytes))
       (raster-buffer-write-storage! b bytes) (bytes-fill! bytes 0)
       (check-equal? (raster-buffer->storage-bytes b) before)))
   (test-case "native float fill preserves subset and row-padding canaries"
     (define info (float-fixture-info 'rgba-f32 2 2))
     (with-skia ([b (make-raster-buffer-from-info info #:row-bytes 48)])
       (define raw (make-bytes 96 0))
       (for ([i (in-list '(32 80))]) (bytes-copy! raw i (make-bytes 16 165)))
       (raster-buffer-write-storage! b raw)
       (call-with-raster-buffer-pixmap b
         (lambda (p) (pixmap-fill-color4f! (pixmap-subset p 1 0 1 2) (make-color4f 0.25 0.5 0.75))) #:writable? #t)
       (near (sample b 0 0) '(0 0 0 0)) (near (sample b 1 1) '(0.25 0.5 0.75 1))
       (define after (raster-buffer->storage-bytes b))
       (for ([i (in-list '(32 80))]) (check-equal? (subbytes after i (+ i 16)) (make-bytes 16 165)))) )
   (test-case "float getters expose unpremultiplied color separately from stored samples"
     (with-float-buffer 'rgba-f32
       (lambda (b)
         (put b '#(0.125 0.25 0.375 0.5))
         (call-with-raster-buffer-pixmap b
           (lambda (p)
             (near (color4f->vector (pixmap-color4f p 0 0)) '(0.25 0.5 0.75 0.5))
             (check-= (pixmap-alphaf p 0 0) 0.5 1e-6))))))
   (test-case "native eraseColor4f premultiplies and retains sub-byte precision"
     (for ([f (in-vector float-pixel-formats)])
       (with-float-buffer f
         (lambda (b)
           (call-with-raster-buffer-pixmap b
             (lambda (p) (pixmap-fill-color4f! p (make-color4f 0.5009765625 0.25 1 0.5))) #:writable? #t)
           (near (sample b) '(0.25048828125 0.125 0.5 0.5) 0.0001)))) )
   (test-case "native eraseColor4f interprets its input as sRGB"
     (with-float-buffer 'rgba-f32
       (lambda (b)
         (call-with-raster-buffer-pixmap b
           (lambda (p) (pixmap-fill-color4f! p (make-color4f 0.5 0.5 0.5))) #:writable? #t)
         (near (sample b) '(0.21404114 0.21404114 0.21404114 1) 0.001))
       #:color-space 'linear-srgb))
   (test-case "opaque float fill rejects translucent colors before mutation"
     (with-float-buffer 'rgba-f16
       (lambda (b)
         (define before (raster-buffer->storage-bytes b))
         (call-with-raster-buffer-pixmap b
           (lambda (p) (check-exn exn:fail? (lambda () (pixmap-fill-color4f! p (make-color4f 1 0 0 0.5))))) #:writable? #t)
         (check-equal? before (raster-buffer->storage-bytes b))) #:alpha-type 'opaque))
   (test-case "canvas Color4f clear uses the by-value four-float ABI"
     (for ([f (in-vector float-pixel-formats)])
       (with-float-buffer f
         (lambda (b)
           (call-with-raster-buffer-canvas b
             (lambda (c) (canvas-clear-color4f! c (make-color4f 0.125 0.375 0.625 0.875))))
           (near (sample b) '(0.109375 0.328125 0.546875 0.875) 0.0002)))) )
   (test-case "canvas Color4f Src drawing uses the by-value ABI and blend argument"
     (with-float-buffer 'rgba-f32
       (lambda (b)
         (call-with-raster-buffer-canvas b
           (lambda (c)
             (canvas-clear! c 'white)
             (draw-color4f c (make-color4f 0.125 0.375 0.625 0.5) #:blend-mode 'src)))
         (near (sample b) '(0.0625 0.1875 0.3125 0.5) 0.0001))))
   (test-case "paint Color4f keeps extended sRGB instead of packed bytes"
     (with-skia ([p (make-paint/color4f (make-color4f -0.25 1.5 0.5009765625) #:color-space 'srgb)])
       (near (color4f->vector (paint-color4f p)) '(-0.25 1.5 0.5009765625 1) 0.0001)))
   (test-case "paint source space converts to extended sRGB storage"
     (with-skia ([p (make-paint/color4f (make-color4f 0.5 0.5 0.5) #:color-space 'linear-srgb)])
       (near (color4f->vector (paint-color4f p)) '(0.73535698 0.73535698 0.73535698 1) 0.001)))
   (test-case "float paint draws fine color distinctions into a float raster target"
     (with-float-buffer 'rgba-f32
       (lambda (b)
         (with-skia ([p (make-paint/color4f (make-color4f 0.5009765625 0.25 0.75) #:color-space 'srgb)])
           (call-with-raster-buffer-canvas b (lambda (c) (draw-paint c p)))
           (near (sample b) '(0.5009765625 0.25 0.75 1) 0.00001)))))
   (test-case "all five float shader factories produce native pixels"
     (for ([f (in-vector float-pixel-formats)])
       (for ([name (in-list '(solid radial sweep conical))])
         (with-float-buffer f
           (lambda (b)
             (call-with-raster-buffer-canvas b (lambda (c) (draw-float-scene name c)))
             (near (sample b 12 12) '(0.125 0.375 0.625 1) 0.002)) #:width 64 #:height 32))
       (with-skia ([b (make-float-fixture-buffer f 'linear)])
         (near (sample b 16 8) (list (+ 0.25 (* 0.5 (/ 16.5 64))) 0.5 (- 0.75 (* 0.5 (/ 16.5 64))) 1) 0.002))))
   (test-case "linear gradient interpolates differences smaller than one byte step"
     (with-skia ([shader (make-linear-gradient-color4f-shader '(0 0) '(64 0)
                          (list (make-color4f 0.5 0.5 0.5) (make-color4f 0.501953125 0.5 0.5)) #:color-space 'srgb)]
                 [paint (make-paint #:shader shader)])
       (with-float-buffer 'rgba-f32
         (lambda (b)
           (call-with-raster-buffer-canvas b (lambda (c) (draw-paint c paint)))
           (check-true (> (- (vector-ref (sample b 56) 0) (vector-ref (sample b 8) 0)) 0.001)))
         #:width 64 #:height 32)))
   (test-case "paint clone retains precision provenance and reset clears only its own state"
     (with-skia ([p (make-paint/color4f (make-color4f 0.5 0.25 0.75) #:color-space 'srgb)] [q (paint-copy p)])
       (paint-reset! p)
       (define page (make-output-page 8 8 (lambda (c) (draw-rect c 0 0 8 8 q))))
       (check-exn exn:fail:output-audit? (lambda () (output->bytes/audit page 'pdf #:policy 'error)))
       (paint-set-color! q 'red)
       (define-values (_bytes report) (output->bytes/audit page 'pdf #:policy 'vector-only))
       (check-true (output-audit-report-vector-only? report))))
   (test-case "float image snapshots retain source format after buffer closes"
     (for ([f (in-vector float-pixel-formats)])
       (define im (with-float-buffer f (lambda (b) (put b '#(0.5 0.25 0.75 1)) (raster-buffer->image b))))
       (call-with-skia-resource im
         (lambda (image) (check-equal? (image-color-type image) f)
                         (check-equal? (image-info-color-type (image->image-info image)) f)))) )
   (test-case "direct document embedding of float images rejects before precision loss"
     (with-float-buffer 'rgba-f16
       (lambda (b)
         (with-skia ([im (raster-buffer->image b)])
           (for ([format (in-list '(pdf svg))])
             (check-exn exn:fail:output-audit? (lambda () (output->bytes/audit (image-page im) format #:policy 'error))))))))
   (test-case "float image subsets and image shaders retain the precision restriction"
     (with-float-buffer 'rgba-f32
       (lambda (b)
         (with-skia ([im (raster-buffer->image b)] [sub (image-subset im 0 0 1 1)]
                     [shader (make-image-shader sub)] [p (make-paint #:shader shader)])
           (check-exn exn:fail:output-audit? (lambda () (output->bytes/audit (image-page sub) 'pdf #:policy 'error)))
           (check-exn exn:fail:output-audit?
             (lambda () (output->bytes/audit (make-output-page 4 4 (lambda (c) (draw-paint c p))) 'pdf #:policy 'error)))))))
   (test-case "float surface snapshots preserve format and document precision tracking"
     (with-skia ([s (make-surface-from-info (float-fixture-info 'rgba-f32 4 2))])
       (canvas-clear-color4f! (surface-canvas s) (make-color4f 0.25 0.5 0.75))
       (with-skia ([im (surface-snapshot s)])
         (check-equal? (image-color-type im) 'rgba-f32)
         (check-exn exn:fail:output-audit? (lambda () (output->bytes/audit (image-page im) 'pdf #:policy 'error))))))
   (test-case "explicit RGBA conversion permits intentional document embedding"
     (with-skia ([im (make-float-fixture-image 'rgba-f32 'samples)])
       (for ([format (in-list '(pdf svg))])
         (define-values (bytes report) (output->bytes/audit (image-page im) format #:policy 'error))
         (check-true (> (bytes-length bytes) 0))
         (check-false (output-audit-report-blocking? report))
         (check-false (output-audit-report-vector-only? report)))) )
   (test-case "F16-to-F32 conversion retains values that an RGBA8 staging path would lose"
     (with-float-buffer 'rgba-f16
       (lambda (b)
         (put b '#(-0.25 1.5 0.5009765625 1))
         (with-skia ([out (raster-buffer-convert b (float-fixture-info 'rgba-f32 4 2))])
           (near (sample out) '(-0.25 1.5 0.5009765625 1) 0.00001)))))
   (test-case "sRGB-to-linear conversion changes samples, not just metadata"
     (with-float-buffer 'rgba-f32
       (lambda (b)
         (put b '#(0.5 0.5 0.5 1))
         (with-skia ([out (raster-buffer-convert b (float-fixture-info 'rgba-f32 4 2 'premul 'linear-srgb))])
           (near (sample out) '(0.21404114 0.21404114 0.21404114 1) 0.001)))))
   (test-case "tagged versus untagged conversion does not guess a source space"
     (with-float-buffer 'rgba-f32
       (lambda (b) (check-exn exn:fail? (lambda () (raster-buffer-convert b (make-image-info 4 2 #:color-type 'rgba-f32)))))))
   (test-case "float alpha extraction is an explicit Alpha8 quantization"
     (with-float-buffer 'rgba-f32
       (lambda (b)
         (put b '#(0.125 0.25 0.375 0.5))
         (with-skia ([alpha (raster-buffer-extract-alpha b)])
           (check-equal? (sample alpha) '#(128))))))
   (test-case "float views expire and reject cross-thread access"
     (with-float-buffer 'rgba-f32
       (lambda (b)
         (define saved #f)
         (call-with-raster-buffer-pixmap b
           (lambda (p)
             (set! saved p)
             (define ch (make-channel))
             (define t (thread (lambda () (channel-put ch (with-handlers ([exn:fail? (lambda (_) 'rejected)])
                                                                  (pixmap-color4f p 0 0) 'bad)))))
             (check-eq? (channel-get ch) 'rejected) (thread-wait t)))
         (check-exn exn:fail? (lambda () (pixmap-alphaf saved 0 0))))))
   (test-case "read-only float views do not permit erasure"
     (with-float-buffer 'rgba-f16
       (lambda (b) (call-with-raster-buffer-pixmap b
                     (lambda (p) (check-exn exn:fail? (lambda () (pixmap-fill-color4f! p (make-color4f 1 0 0)))))))))
   (test-case "outstanding canvas scopes prevent pixel borrowing and closure"
     (with-float-buffer 'rgba-f16
       (lambda (b)
         (call-with-raster-buffer-canvas b
           (lambda (_)
             (check-exn exn:fail? (lambda () (skia-close! b)))
             (check-exn exn:fail? (lambda () (call-with-raster-buffer-pixmap b void))))))))
   (test-case "explicit byte conversion clamps extended channels"
     (with-float-buffer 'rgba-f32
       (lambda (b)
         (put b '#(-0.25 1.5 0.5 1))
         (define rgba (raster-buffer->rgba-bytes b))
         (near (bytes->list (subbytes rgba 0 4)) '(0 255 128 255) 1))))
   (test-case "legacy image color conversion cannot silently reduce float precision"
     (with-float-buffer 'rgba-f16
       (lambda (b)
         (with-skia ([im (raster-buffer->image b)] [cs (make-linear-srgb-color-space)])
           (check-exn #rx"raster-buffer-convert" (lambda () (image-convert-color-space im cs)))))))
   (test-case "nonconstant radial sweep and conical shaders preserve float differences"
     (define stops (list (make-color4f 0.25 0.5 0.75) (make-color4f 0.75 0.5 0.25)))
     (for ([factory (in-list
                    (list (lambda () (make-radial-gradient-color4f-shader '(0 0) 64 stops #:color-space 'srgb))
                          (lambda () (make-sweep-gradient-color4f-shader '(32 16) stops #:color-space 'srgb))
                          (lambda () (make-two-point-conical-gradient-color4f-shader '(0 0) 0 '(0 0) 64 stops #:color-space 'srgb))))])
       (with-skia ([shader (factory)] [paint (make-paint #:shader shader)])
         (with-float-buffer 'rgba-f32
           (lambda (b)
             (call-with-raster-buffer-canvas b (lambda (c) (draw-paint c paint)))
             (define a (sample b 8 8)) (define z (sample b 56 8))
             (check-true (> (abs (- (vector-ref a 0) (vector-ref z 0))) 0.1))
             (check-= (vector-ref a 1) 0.5 0.002)
             (check-= (vector-ref z 3) 1 0.002))
           #:width 64 #:height 32))))
))
