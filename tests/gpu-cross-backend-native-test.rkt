#lang racket/base
(require rackunit "../main.rkt" "../gpu.rkt" "../examples/gpu-images.rkt")
(provide make-gpu-cross-backend-native-tests gpu-cross-backend-native-test-count)
(define gpu-cross-backend-native-test-count 9)
(define (under c thunk) (call-with-gpu-context c thunk))
(define (source-image c)
  (under c (lambda () (with-skia ([cpu (make-image-workflow-source)]) (gpu-upload-image c cpu)))))
(define (make-gpu-cross-backend-native-tests gl metal)
  (define (both proc)
    (for ([a (in-list (list gl metal))] [b (in-list (list metal gl))])
      (proc a b)
      (under a (lambda () (gpu-drain-releases! a)))
      (under b (lambda () (gpu-drain-releases! b)))))
  (test-suite
   "Actual OpenGL/Metal separation and explicit two-way transfer"
   (test-case "contexts identify distinct native backends"
     (check-eq? (gpu-context-backend gl) 'opengl)
     (check-eq? (gpu-context-backend metal) 'metal)
     (check-equal? (hash-ref (gpu-context-info gl) 'native_backend) 0)
     (check-equal? (hash-ref (gpu-context-info metal) 'native_backend) 2)
     (check-false (= (gpu-context-generation gl) (gpu-context-generation metal))))
   (test-case "GPU images cannot draw into the other backend"
     (both (lambda (a b)
       (with-skia ([im (source-image a)])
         (under b (lambda () (with-skia ([s (make-gpu-surface b 8 8)])
           (check-exn exn:fail? (lambda () (draw-image (surface-canvas s) im 0 0))))))))))
   (test-case "retained shader and paint cannot cross backends"
     (both (lambda (a b)
       (with-skia ([paint (under a (lambda () (with-skia ([im (source-image a)] [sh (make-image-shader im)])
                                               (make-paint #:shader sh))))])
         (under a (lambda () (gpu-drain-releases! a)))
         (check-eq? (skia-resource-gpu-context paint) a)
         (under b (lambda () (with-skia ([s (make-gpu-surface b 8 8)])
           (check-exn exn:fail? (lambda () (draw-paint (surface-canvas s) paint))))))))))
   (test-case "recorded images retain backend affinity after source closure"
     (both (lambda (a b)
       (with-skia ([pic (under a (lambda () (with-skia ([im (source-image a)])
                           (call-with-picture 8 8 (lambda (c) (draw-image c im 0 0))))))])
         (under a (lambda () (gpu-drain-releases! a)))
         (check-eq? (skia-resource-gpu-context pic) a)
         (under b (lambda () (with-skia ([s (make-gpu-surface b 8 8)])
           (check-exn exn:fail? (lambda () (draw-picture (surface-canvas s) pic))))))))))
   (test-case "GPU subset creation rejects the other backend activation"
     (both (lambda (a b) (with-skia ([im (source-image a)])
       (under b (lambda () (check-exn exn:fail? (lambda () (gpu-image-subset im 0 0 2 2)))))))))
   (test-case "GPU surfaces cannot lend a canvas to the other backend"
     (both (lambda (a b) (with-skia ([s (under a (lambda () (make-gpu-surface a 8 8)))])
       (under b (lambda () (check-exn exn:fail? (lambda () (surface-canvas s)))))))))
   (test-case "nested foreign backend activation is rejected without changing the outer scope"
     (both (lambda (a b)
       (under a (lambda ()
         (check-exn exn:fail? (lambda () (under b void)))
         (with-skia ([s (make-gpu-surface a 4 4)]) (canvas-clear! (surface-canvas s) 'blue)))))))
   (test-case "explicit CPU detachment then upload works in both directions"
     (both (lambda (a b)
       (with-skia ([cpu (under a (lambda () (with-skia ([im (source-image a)]) (gpu-image->raster-image im))))])
         (check-eq? (image-residency cpu) 'cpu)
         (check-false (skia-resource-gpu-context cpu))
         (under b (lambda () (with-skia ([im (gpu-upload-image b cpu)])
           (check-equal? (gpu-image->rgba-bytes im) image-workflow-pixels))))))))
   (test-case "failed foreign attachment leaves the existing paint affinity intact"
     (both (lambda (a b)
       (with-skia ([paint (under a (lambda () (with-skia ([im (source-image a)] [sh (make-image-shader im)])
                                               (make-paint #:shader sh))))]
                   [foreign (under b (lambda () (with-skia ([im (source-image b)]) (make-image-shader im))))])
         (under a (lambda () (check-exn exn:fail? (lambda () (paint-set-shader! paint foreign)))))
         (check-eq? (skia-resource-gpu-context paint) a)))))))
