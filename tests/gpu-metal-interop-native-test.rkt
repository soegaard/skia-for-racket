#lang racket/base
(require rackunit racket/list "../main.rkt" "../gpu.rkt" "../gpu-interop.rkt" "../unsafe/gpu-metal.rkt"
         "metal-interop-fixture.rkt" "../private/gpu-metal-interop-policy.rkt")
(provide make-gpu-metal-interop-native-tests gpu-metal-interop-native-test-count
         metal-pattern draw-metal-overlay metal-handoff with-metal-fixture)
(define gpu-metal-interop-native-test-count 33)
(define (metal-pattern [painted? #f] [rect '(3 4 6 5)])
  (define x0 (car rect)) (define y0 (cadr rect)) (define w (caddr rect)) (define h (cadddr rect))
  (apply bytes-append
    (for*/list ([y (in-range 29)] [x (in-range 37)])
      (cond
        [(and painted? (<= x0 x) (< x (+ x0 w)) (<= y0 y) (< y (+ y0 h))) (bytes 128 0 128 128)]
        [(= x 18) (bytes 0 0 0 0)]
        [else
         (define a (if (zero? (modulo x 7)) 128 255))
         (define right? (> x 18)) (define bottom? (>= y 14))
         (bytes (if (or (and (not right?) (not bottom?)) (and right? bottom?)) a 0)
                (if right? a 0) (if (and (not right?) bottom?) a 0) a)]))))
(define (draw-metal-overlay canvas)
  (with-skia ([p (make-paint #:color (rgba 255 0 255 128) #:blend-mode 'src #:antialias? #f)])
    (draw-rect canvas 3 4 6 5 p)))
(define (metal-handoff context f #:premultiplied? [pm? #t] #:timeout-ms [timeout 5000])
  (make-metal-external-texture context (metal-fixture-texture f)
    #:producer-command-buffer (metal-fixture-producer f) #:premultiplied? pm? #:timeout-ms timeout))
(define (with-metal-fixture context proc [variant 0])
  (define f (make-metal-fixture context variant))
  (dynamic-wind void (lambda () (proc f)) (lambda () (close-metal-fixture! f))))
(define ((interop-error-reason? reason) e)
  (and (exn:fail:metal-interop? e) (eq? (exn:fail:metal-interop-reason e) reason)))
(define (make-gpu-metal-interop-native-tests context other)
  (define (using proc [variant 0])
    (call-with-gpu-context context (lambda () (with-metal-fixture context proc variant))))
  (define (pixels image) (gpu-image->rgba-bytes image #:premultiplied? #t))
  (test-suite "Independent Metal producer, Skia handoff and consumer"
    (test-case "native getters and typed swizzle agree with Objective-C SDK"
      (using (lambda (f)
        (define t (metal-handoff context f)) (define d (gpu-external-texture-info t))
        (check-equal?
          (append (map (lambda (k) (hash-ref d k)) '(width height depth levels array_length samples format texture_type usage storage_mode hazard_tracking_mode))
                  (map (lambda (k) (if (hash-ref d k) 1 0)) '(framebuffer_only shareable producer_retained_references))
                  (hash-ref d 'swizzle) '(1))
          (metal-fixture-description f))
        (gpu-external-texture-close! t) (gpu-drain-releases! context))))
    (test-case "copy survives producer and external texture retirement"
      (using (lambda (f)
        (with-skia ([im (gpu-import-image context (metal-handoff context f))])
          (close-metal-fixture! f)
          (check-true (hash-ref (gpu-image-info im) 'texture_backed))
          (check-equal? (pixels im) (metal-pattern))))))
    (test-case "copy does not alias later external drawing"
      (using (lambda (f)
        (with-skia ([im (gpu-import-image context (metal-handoff context f))])
          (call-with-gpu-external-surface context (metal-handoff context f) draw-metal-overlay)
          (check-equal? (metal-fixture-readback f) (metal-pattern #t))
          (check-equal? (pixels im) (metal-pattern))))))
    (test-case "retained picture owns imported image after wrapper closure"
      (using (lambda (f)
        (with-skia ([im (gpu-import-image context (metal-handoff context f))]
                    [pic (call-with-picture 37 29 (lambda (canvas) (draw-image canvas im 0 0 #:sampling 'nearest)))]
                    [surface (make-gpu-surface context 37 29)])
          (skia-close! im) (close-metal-fixture! f)
          (draw-picture (surface-canvas surface) pic)
          (check-equal? (gpu-surface->rgba-bytes surface #:premultiplied? #t) (metal-pattern))))))
    (test-case "borrow draws directly into externally allocated pixels"
      (using (lambda (f)
        (call-with-gpu-external-surface context (metal-handoff context f) draw-metal-overlay)
        (check-equal? (metal-fixture-readback f) (metal-pattern #t)))))
    (test-case "empty callback preserves translucent external contents"
      (using (lambda (f)
        (call-with-gpu-external-surface context (metal-handoff context f) void)
        (check-equal? (metal-fixture-readback f) (metal-pattern)))))
    (test-case "callback failure completes drawing before propagating"
      (using (lambda (f)
        (check-exn #rx"author-error" (lambda ()
          (call-with-gpu-external-surface context (metal-handoff context f)
            (lambda (canvas) (draw-metal-overlay canvas) (error 'test "author-error")))))
        (check-equal? (metal-fixture-readback f) (metal-pattern #t)))))
    (test-case "arbitrary raised value still retires the handoff"
      (using (lambda (f)
        (check-exn not (lambda ()
          (call-with-gpu-external-surface context (metal-handoff context f)
            (lambda (canvas) (draw-metal-overlay canvas) (raise #f)))))
        (check-equal? (metal-fixture-readback f) (metal-pattern #t)))))
    (test-case "unbalanced canvas saves are restored and rejected"
      (using (lambda (f)
        (check-exn #rx"unbalanced" (lambda ()
          (call-with-gpu-external-surface context (metal-handoff context f)
            (lambda (canvas) (canvas-save! canvas) (draw-metal-overlay canvas)))))
        (check-equal? (metal-fixture-readback f) (metal-pattern #t)))))
    (test-case "borrowed canvas expires inside surviving outer activation"
      (using (lambda (f)
        (define escaped #f)
        (call-with-gpu-external-surface context (metal-handoff context f) (lambda (v) (set! escaped v)))
        (check-exn exn:fail? (lambda () (draw-metal-overlay escaped))))))
    (test-case "callback receives canvas only"
      (using (lambda (f)
        (call-with-gpu-external-surface context (metal-handoff context f)
          (lambda (v) (check-true (canvas? v)) (check-false (surface? v)) (check-false (image? v)))))))
    (test-case "multiple callback values survive cleanup"
      (using (lambda (f)
        (check-equal? (call-with-values (lambda ()
          (call-with-gpu-external-surface context (metal-handoff context f) (lambda (_) (values 1 2 3)))) list)
          '(1 2 3)))))
    (test-case "consumed token cannot be reused"
      (using (lambda (f)
        (define t (metal-handoff context f))
        (with-skia ([im (gpu-import-image context t)])
          (check-exn #rx"consumed" (lambda () (gpu-import-image context t)))))))
    (test-case "foreign Ganesh context rejects before native handoff"
      (using (lambda (f)
        (define t (metal-handoff context f))
        (check-exn #rx"another GPU context" (lambda () (gpu-import-image other t)))
        (with-skia ([im (gpu-import-image context t)]) (check-equal? (pixels im) (metal-pattern))))))
    (test-case "active token cannot be closed by its callback"
      (using (lambda (f)
        (define t (metal-handoff context f))
        (call-with-gpu-external-surface context t
          (lambda (_) (check-exn #rx"in use" (lambda () (gpu-external-texture-close! t))))))))
    (test-case "nonrenderable texture can be copied but not drawn into"
      (using (lambda (f)
        (define t (metal-handoff context f))
        (check-exn #rx"RenderTarget" (lambda () (call-with-gpu-external-surface context t void)))
        (with-skia ([im (gpu-import-image context t)]) (check-equal? (pixels im) (metal-pattern)))) 2))
    (test-case "straight alpha import converts to premultiplied storage"
      (using (lambda (f)
        (with-skia ([im (gpu-import-image context (metal-handoff context f #:premultiplied? #f))])
          (check-equal? (pixels im) (metal-pattern)))) 1))
    (test-case "straight alpha texture is copy only"
      (using (lambda (f)
        (define t (metal-handoff context f #:premultiplied? #f))
        (check-exn #rx"premultiplied" (lambda () (call-with-gpu-external-surface context t void)))
        (with-skia ([im (gpu-import-image context t)]) (check-equal? (pixels im) (metal-pattern)))) 1))
    (test-case "reject real BGRA format"
      (using (lambda (f) (check-exn (interop-error-reason? 'descriptor) (lambda () (metal-handoff context f)))) 3))
    (test-case "reject real mipmapped texture"
      (using (lambda (f) (check-exn (interop-error-reason? 'descriptor) (lambda () (metal-handoff context f)))) 4))
    (test-case "reject real texture array"
      (using (lambda (f) (check-exn (interop-error-reason? 'descriptor) (lambda () (metal-handoff context f)))) 5))
    (test-case "reject real untracked resource"
      (using (lambda (f) (check-exn (interop-error-reason? 'descriptor) (lambda () (metal-handoff context f)))) 6))
    (test-case "reject real uncommitted command buffer"
      (using (lambda (f) (check-exn (interop-error-reason? 'uncommitted) (lambda () (metal-handoff context f)))) 7))
    (test-case "reject real unretained producer references"
      (using (lambda (f) (check-exn (interop-error-reason? 'descriptor) (lambda () (metal-handoff context f)))) 8))
    (test-case "reject real nonidentity swizzle"
      (using (lambda (f) (check-exn (interop-error-reason? 'descriptor) (lambda () (metal-handoff context f)))) 9))
    (test-case "reject real texture view"
      (using (lambda (f) (check-exn (interop-error-reason? 'descriptor) (lambda () (metal-handoff context f)))) 10))
    (test-case "reject real shader-write usage"
      (using (lambda (f) (check-exn (interop-error-reason? 'descriptor) (lambda () (metal-handoff context f)))) 12))
    (test-case "null texture is rejected before messaging"
      (using (lambda (f)
        (check-exn exn:fail? (lambda () (make-metal-external-texture context #f
          #:producer-command-buffer (metal-fixture-producer f)))))))
    (test-case "live wrong protocol object is rejected"
      (using (lambda (f)
        (check-exn #rx"MTLTexture" (lambda () (make-metal-external-texture context (metal-fixture-producer f)
          #:producer-command-buffer (metal-fixture-producer f)))))))
    (test-case "device callback cannot reenter Skia GPU code"
      (call-with-gpu-context context (lambda ()
        (call-with-gpu-metal-device context (lambda (_)
          (check-exn #rx"native" (lambda () (gpu-flush-and-submit! context))))))))
    (test-case "unused handoff retirement releases its pin"
      (using (lambda (f)
        (define t (metal-handoff context f))
        (gpu-external-texture-close! t) (gpu-drain-releases! context)
        (check-equal? (hash-ref (hash-ref (gpu-external-texture-info t) 'native) 'state) "closed")
        (check-equal? (hash-ref (gpu-context-info context) 'live_children) 0))))
    (test-case "successful handoff reports two completed boundaries"
      (using (lambda (f)
        (define t (metal-handoff context f))
        (call-with-gpu-external-surface context t void)
        (define d (gpu-external-texture-info t)) (define n (hash-ref d 'native))
        (check-false (hash-ref d 'producer_coverage_verified))
        (check-false (hash-ref n 'quarantined))
        (check-equal? (map (lambda (r) (hash-ref r 'status)) (hash-ref n 'waits)) '(4 4)))))
    (test-case "nested device handoff is rejected"
      (using (lambda (f)
        (call-with-gpu-external-surface context (metal-handoff context f)
          (lambda (_) (check-exn #rx"nested" (lambda () (call-with-gpu-metal-device context void))))))))
))
