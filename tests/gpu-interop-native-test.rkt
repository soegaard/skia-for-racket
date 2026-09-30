#lang racket/base
(require rackunit racket/list "../main.rkt" "../gpu.rkt" "../gpu-interop.rkt" "../unsafe/gpu-d3d12.rkt"
         "d3d12-interop-fixture.rkt" "../private/gpu-d3d12-interop-system.rkt")
(provide make-gpu-interop-native-tests gpu-interop-native-test-count interop-pattern interop-red
         interop-handoff with-interop-fixture draw-interop-red)
(define gpu-interop-native-test-count 29)
(define (interop-pattern w h)
  (apply bytes-append
    (for*/list ([y (in-range h)] [x (in-range w)])
      (if (zero? (modulo x 7)) (bytes 0 0 0 0)
        (bytes (modulo (+ (* x 17) (* y 3)) 256)
               (modulo (* (bitwise-xor x y) 13) 256)
               (modulo (+ (* x 5) (* y 11)) 256) 255)))))
(define (interop-red w h [x 1] [y 2] [width 5] [height 4])
  (define b (interop-pattern w h))
  (for* ([j (in-range y (+ y height))] [i (in-range x (+ x width))])
    (bytes-copy! b (* 4 (+ i (* j w))) (bytes 255 0 0 255))) b)
(define (draw-interop-red c)
  (with-skia ([p (make-paint #:color 'red #:antialias? #f)]) (draw-rect c 1 2 5 4 p)))
(define (interop-handoff c f #:incoming [incoming 'pixel-shader-resource] #:premultiplied? [pm? #t])
  (make-d3d12-external-texture c (fixture-texture f)
    #:producer-fence (fixture-fence f) #:producer-value 1
    #:incoming-state incoming #:outgoing-state 'copy-source #:premultiplied? pm?))
(define (with-interop-fixture c proc [kind 0] [w 37] [h 29])
  (define f (make-fixture c w h kind))
  (dynamic-wind void (lambda () (proc f)) (lambda () (close-fixture f))))
(define (make-gpu-interop-native-tests c other)
  (define (using proc [kind 0]) (call-with-gpu-context c (lambda () (with-interop-fixture c proc kind))))
  (define (pixels im) (gpu-image->rgba-bytes im))
  (test-suite "Real D3D12 producer, Skia handoff, independent consumer"
    (test-case "MS x64 aggregate-return call agrees with SDK C++ GetDesc"
      (using (lambda (f)
        (define d (resource-description/native (fixture-texture f)))
        (check-equal? (map (lambda (k) (hash-ref d k)) '(dimension width height depth levels format samples quality flags))
                      (fixture-description f)))))
    (test-case "owned image outlives the producer reference"
      (using (lambda (f)
        (define t (interop-handoff c f)) (drop-fixture-texture f)
        (with-skia ([im (gpu-import-image c t)])
          (check-true (hash-ref (gpu-image-info im) 'texture_backed))
          (check-equal? (pixels im) (interop-pattern 37 29))))))
    (test-case "copied pixels do not alias later external writes"
      (using (lambda (f)
        (with-skia ([im (gpu-import-image c (interop-handoff c f))])
          (call-with-gpu-external-surface c (interop-handoff c f #:incoming 'copy-source) draw-interop-red)
          (check-equal? (fixture-readback f #x800 37 29) (interop-red 37 29))
          (check-equal? (pixels im) (interop-pattern 37 29))))))
    (test-case "retained picture keeps an imported image after original wrapper closure"
      (using (lambda (f)
        (with-skia ([im (gpu-import-image c (interop-handoff c f))]
                    [pic (call-with-picture 37 29 (lambda (canvas) (draw-image canvas im 0 0 #:sampling 'nearest)))]
                    [s (make-gpu-surface c 37 29)])
          (skia-close! im) (drop-fixture-texture f)
          (draw-picture (surface-canvas s) pic)
          (check-equal? (gpu-surface->rgba-bytes s) (interop-pattern 37 29))))))
    (test-case "external surface preserves pixels outside drawn geometry"
      (using (lambda (f)
        (call-with-gpu-external-surface c (interop-handoff c f) draw-interop-red)
        (check-equal? (fixture-readback f #x800 37 29) (interop-red 37 29)))))
    (test-case "empty drawing callback preserves all original pixels"
      (using (lambda (f)
        (call-with-gpu-external-surface c (interop-handoff c f) void)
        (check-equal? (fixture-readback f #x800 37 29) (interop-pattern 37 29)))))
    (test-case "callback transforms and clip cannot affect normalization"
      (using (lambda (f)
        (call-with-gpu-external-surface c (interop-handoff c f)
          (lambda (canvas)
            (canvas-translate! canvas 4 5) (canvas-clip-rect! canvas 0 0 4 3)
            (with-skia ([p (make-paint #:color 'red #:antialias? #f)]) (draw-rect canvas 0 0 20 20 p))))
        (check-equal? (fixture-readback f #x800 37 29) (interop-red 37 29 4 5 4 3)))))
    (test-case "ordinary callback exception returns state before propagating"
      (using (lambda (f)
        (check-exn #rx"author-error" (lambda ()
          (call-with-gpu-external-surface c (interop-handoff c f)
            (lambda (canvas) (draw-interop-red canvas) (error 'test "author-error")))))
        (check-equal? (fixture-readback f #x800 37 29) (interop-red 37 29)))))
    (test-case "arbitrary raised value also completes the handoff"
      (using (lambda (f)
        (check-exn not (lambda () (call-with-gpu-external-surface c (interop-handoff c f)
          (lambda (canvas) (draw-interop-red canvas) (raise #f)))))
        (check-equal? (fixture-readback f #x800 37 29) (interop-red 37 29)))))
    (test-case "unbalanced saves are restored and rejected"
      (using (lambda (f)
        (check-exn #rx"unbalanced" (lambda () (call-with-gpu-external-surface c (interop-handoff c f)
          (lambda (canvas) (canvas-save! canvas) (draw-interop-red canvas)))))
        (check-equal? (fixture-readback f #x800 37 29) (interop-red 37 29)))))
    (test-case "borrowed canvas expires within a surviving outer context activation"
      (using (lambda (f)
        (define canvas #f)
        (call-with-gpu-external-surface c (interop-handoff c f) (lambda (v) (set! canvas v)))
        (check-exn exn:fail? (lambda () (draw-interop-red canvas))))))
    (test-case "no borrowed surface or image escapes through the generic API"
      (using (lambda (f)
        (call-with-gpu-external-surface c (interop-handoff c f)
          (lambda (v) (check-true (canvas? v)) (check-false (surface? v)) (check-false (image? v)))))))
    (test-case "consumed handoff is not reusable"
      (using (lambda (f)
        (define t (interop-handoff c f))
        (with-skia ([im (gpu-import-image c t)])
          (check-exn #rx"consumed" (lambda () (gpu-import-image c t)))))))
    (test-case "active handoff cannot be retired by its callback"
      (using (lambda (f)
        (define t (interop-handoff c f))
        (call-with-gpu-external-surface c t (lambda (_) (check-exn #rx"in use" (lambda () (gpu-external-texture-close! t))))))))
    (test-case "external handoffs reject the other Ganesh context"
      (using (lambda (f)
        (define t (interop-handoff c f))
        (check-exn #rx"another GPU context" (lambda () (gpu-import-image other t)))
        (with-skia ([im (gpu-import-image c t)]) (check-true (hash-ref (gpu-image-info im) 'texture_backed))))))
    (test-case "non-RT texture copy is supported but rendering is rejected"
      (using (lambda (f)
        (define t (interop-handoff c f))
        (check-exn #rx"ALLOW_RENDER_TARGET" (lambda () (call-with-gpu-external-surface c t void)))
        (with-skia ([im (gpu-import-image c t)]) (check-equal? (pixels im) (interop-pattern 37 29)))) 1))
    (test-case "real mipmapped resource is rejected before graphics handoff"
      (using (lambda (f) (check-exn exn:fail? (lambda () (interop-handoff c f)))) 2))
    (test-case "real texture array is rejected before graphics handoff"
      (using (lambda (f) (check-exn exn:fail? (lambda () (interop-handoff c f)))) 3))
    (test-case "real unsupported BGRA format is rejected before graphics handoff"
      (using (lambda (f) (check-exn exn:fail? (lambda () (interop-handoff c f)))) 4))
    (test-case "null pointer is rejected before COM dereference"
      (using (lambda (f) (check-exn exn:fail? (lambda ()
        (make-d3d12-external-texture c #f #:producer-fence (fixture-fence f) #:producer-value 1
          #:incoming-state 'pixel-shader-resource #:outgoing-state 'copy-source))))))
    (test-case "foreign canonical device is rejected before descriptor query"
      (using (lambda (f)
        (define r (fixture-foreign))
        (dynamic-wind void
          (lambda () (check-exn #rx"exact context device" (lambda ()
            (make-d3d12-external-texture c r #:producer-fence (fixture-fence f) #:producer-value 1
              #:incoming-state 'pixel-shader-resource #:outgoing-state 'copy-source))))
          (lambda () (fixture-release r)))
        (check-equal? (fixture-foreign-live) 0) (check-equal? (fixture-foreign-desc-calls) 0))))
    (test-case "premultiplied translucent image imports with correct alpha"
      (using (lambda (f)
        (with-skia ([im (gpu-import-image c (interop-handoff c f))])
          (check-equal? (pixels im)
            (apply bytes-append (for*/list ([y (in-range 29)] [x (in-range 37)])
              (if (zero? (modulo x 7)) (bytes 0 0 0 0) (bytes 255 0 0 128))))))) 5))
    (test-case "straight-alpha translucent image imports with correct conversion"
      (using (lambda (f)
        (with-skia ([im (gpu-import-image c (interop-handoff c f #:premultiplied? #f))])
          (check-equal? (pixels im)
            (apply bytes-append (for*/list ([y (in-range 29)] [x (in-range 37)])
              (if (zero? (modulo x 7)) (bytes 0 0 0 0) (bytes 255 0 0 128))))))) 6))
    (test-case "borrow normalization preserves translucent premultiplied storage"
      (using (lambda (f)
        (call-with-gpu-external-surface c (interop-handoff c f) void)
        (check-equal? (fixture-readback f #x800 37 29)
          (apply bytes-append (for*/list ([y (in-range 29)] [x (in-range 37)])
            (if (zero? (modulo x 7)) (bytes 0 0 0 0) (bytes 128 0 0 128)))))) 5))
    (test-case "unpremultiplied input is copy-only"
      (using (lambda (f)
        (define t (interop-handoff c f #:premultiplied? #f))
        (check-exn #rx"premultiplied" (lambda () (call-with-gpu-external-surface c t void)))
        (with-skia ([im (gpu-import-image c t)]) (check-equal? (pixels im) (interop-pattern 37 29))))))
    (test-case "unsafe device callback cannot reenter Skia GPU execution"
      (call-with-gpu-context c (lambda ()
        (call-with-gpu-d3d12-device c (lambda (_)
          (check-exn #rx"native" (lambda () (gpu-flush-and-submit! c))))))))
    (test-case "unused descriptor retirement waits for producer and releases its pin"
      (using (lambda (f)
        (define t (interop-handoff c f)) (gpu-external-texture-close! t) (gpu-drain-releases! c)
        (check-equal? (hash-ref (hash-ref (gpu-external-texture-info t) 'native) 'state) "closed")
        (check-false (hash-ref (hash-ref (gpu-external-texture-info t) 'native) 'external_state_returned)))))
    (test-case "closed-session diagnostics do not pretend the state was queried"
      (using (lambda (f)
        (define t (interop-handoff c f))
        (with-skia ([im (gpu-import-image c t)])
          (define n (hash-ref (gpu-external-texture-info t) 'native))
          (check-true (hash-ref n 'same_device_verified))
          (check-true (hash-ref n 'producer_completion_verified))
          (check-true (hash-ref n 'external_state_returned))
          (check-false (hash-ref n 'state_declaration_verified_by_runtime))))))
    (test-case "nested borrowing rejected before native submission"
      (using (lambda (f)
        (define t (interop-handoff c f))
        (call-with-gpu-external-surface c t
          (lambda (_) (check-exn #rx"nested" (lambda () (call-with-gpu-d3d12-device c void))))))))))
