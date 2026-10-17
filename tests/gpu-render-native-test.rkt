#lang racket/base

;;;
;;; GPU Render Native Test
;;;

;; Covers one-shot GPU render on the explicitly selected backend.
;; This native regression layer checks behavior and resource ownership against the installed
;; implementation.

;;;
;;; Imports and Exports
;;;

(require rackunit
         "../main.rkt"
         "../gpu.rkt")

(provide make-gpu-render-native-tests)

;; No native initialization on import. A host provider, when supplied, must be
;; idle and must not already belong to a live Ganesh context. It remains borrowed.

;;;
;;; Fixtures and Assertions
;;;

; make-gpu-render-native-tests : #:backend symbol? [#:provider (or/c gpu-provider? #f) #:adapter
; (or/c symbol? #f)] -> test-suite?
;;   Builds the parameterized suite for one-shot GPU render on the explicitly selected backend.
(define (make-gpu-render-native-tests #:backend backend
                                      #:provider [provider #f]
                                      #:adapter [adapter #f])
  (define (render draw #:background [background 'transparent])
    (render-gpu->raster-image 32 24 draw
                             #:backend backend
                             #:provider provider
                             #:adapter adapter
                             #:background background))
  (define (pixel image x y)
    (define data (image->rgba-bytes image))
    (define start (* 4 (+ x (* y (image-width image)))))
    (bytes->list (subbytes data start (+ start 4))))
  (test-suite
   "One-shot GPU render on the explicitly selected backend"
   (test-case "ordinary canvas, one callback, exact solid pixels, detached PNG"
     (define calls 0)
     (define escaped #f)
     (with-skia
         ([image
           (render
            (lambda (canvas)
              (set! calls (add1 calls))
              (set! escaped canvas)
              (check-eq? (canvas-execution-backend canvas) backend)
              (with-skia ([paint (make-paint #:color (rgba 17 34 51 255))])
                (draw-rect canvas 6 5 12 10 paint)))
            #:background 'white)])
       (check-equal? calls 1)
       (check-true (image? image))
       (check-equal? (list (image-width image) (image-height image)) '(32 24))
       (check-equal? (pixel image 10 9) '(17 34 51 255))
       (check-equal? (pixel image 1 1) '(255 255 255 255))
       (check-true (skia-closed? escaped))
       (check-exn exn:fail? (lambda () (canvas-clear! escaped 'red)))
       ;; Encoding occurs only after the helper's context teardown.
       (check-equal? (subbytes (image->png-bytes image) 0 8) #"\211PNG\r\n\032\n")))
   (test-case "empty drawing preserves initialized transparent pixels"
     (with-skia ([image (render (lambda (canvas) (values)))])
       (check-equal? (image->rgba-bytes image) (make-bytes (* 32 24 4) 0))))
   (test-case "multiple callback values do not replace the detached image"
     (with-skia ([image (render (lambda (canvas) (values 'ignored 'values))
                               #:background (rgba 20 80 140 255))])
       (check-equal? (pixel image 0 0) '(20 80 140 255))))
   (test-case "raised callback value propagates and expires its canvas"
     (define token (box 'draw-failed))
     (define escaped #f)
     (check-exn
      (lambda (value) (eq? token value))
      (lambda ()
        (render (lambda (canvas) (set! escaped canvas) (raise token)))))
     (check-true (skia-closed? escaped))
     (check-exn exn:fail? (lambda () (canvas-clear! escaped 'blue)))
     ;; A borrowed OpenGL provider can be reused here only after domain teardown.
     (with-skia ([image (render void #:background 'white)])
       (check-equal? (pixel image 0 0) '(255 255 255 255))))
   (test-case "prompt escape retires the borrowed canvas and permits a later render"
     (define tag (make-continuation-prompt-tag 'native-render))
     (define escaped #f)
     (check-eq?
      (call-with-continuation-prompt
       (lambda ()
         (render (lambda (canvas)
                   (set! escaped canvas)
                   (abort-current-continuation tag 'cancelled))))
       tag
       (lambda (value) value))
      'cancelled)
     (check-true (skia-closed? escaped))
     (with-skia ([image (render void)])
       (check-equal? (pixel image 0 0) '(0 0 0 0))))
   (test-case "independent renders do not change a previously returned image"
     (with-skia ([first (render void #:background 'red)]
                 [second (render void #:background 'blue)])
       (check-equal? (pixel first 3 3) '(255 0 0 255))
       (check-equal? (pixel second 3 3) '(0 0 255 255))))))
