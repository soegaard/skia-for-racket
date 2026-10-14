#lang racket/base

;; Native-free checks. Fake operations test the actual one-shot lifetime worker;
;; they do not establish GPU, pixel, driver, or platform acceptance.
(require rackunit racket/list skia skia/gpu
         "../private/gpu-format-util.rkt"
         "../private/gpu-cache-util.rkt"
         "../private/gpu-render.rkt")

(define (fake-render #:failure [failure #f] #:draw [draw (lambda () (values))])
  (define events '())
  (define (note name)
    (set! events (cons name events))
    (when (eq? name failure) (error 'fake-render "injected failure: ~a" name)))
  (define outcome
    (with-handlers ([exn:fail? (lambda (e) (list 'raised e))])
      (list 'returned
        (call-with-rendered-gpu-image
         (lambda () (note 'context) 'fake-context)
         (lambda (_ thunk)
           (dynamic-wind (lambda () (note 'enter)) thunk (lambda () (note 'exit))))
         (lambda (_) (note 'surface) 'fake-surface)
         (lambda (_context _surface) (note 'draw) (draw))
         (lambda (_) (note 'readback) 'fake-cpu-image)
         (lambda (value) (note (if (eq? value 'fake-surface) 'close-surface 'close-image)))
         (lambda (_) (note 'close-context))))))
  (values outcome (reverse events)))

(module+ test
  (test-case "surface format requests retain all supported descriptions"
    (for ([color '(rgba-8888 bgra-8888 rgba-f16 rgba-f32)])
      (define info (gpu-format-request 'test 3 2 color 'premul 0 (make-surface-properties)))
      (check-equal? (image-info-color-type info) color)
      (check-equal? (image-info-width info) 3)))

  (test-case "GPU drawing targets reject unpremultiplied alpha"
    (check-exn exn:fail?
      (lambda () (gpu-format-request 'test 1 1 'rgba-8888 'unpremul 0
                                      (make-surface-properties)))))

  (test-case "sample counts are exact and bounded before native allocation"
    (for ([bad '(-1 65 1.0 #f)])
      (check-exn exn:fail?
        (lambda () (gpu-format-request 'test 1 1 'rgba-8888 'premul bad
                                        (make-surface-properties))))))

  (test-case "opaque-only color formats reject premultiplied descriptions"
    (for ([color '(rgb-888x gray-8 rgb-565)])
      (check-exn exn:fail?
        (lambda () (gpu-format-request 'test 1 1 color 'premul 0
                                        (make-surface-properties))))))

  (test-case "float target budgets count the selected bytes per pixel"
    (parameterize ([current-skia-byte-limit 63])
      (check-exn exn:fail?
        (lambda () (gpu-format-request 'test 2 2 'rgba-f32 'premul 0
                                        (make-surface-properties))))))

  (test-case "zero target extents and unknown formats fail without a GPU"
    (check-exn exn:fail?
      (lambda () (gpu-format-request 'test 0 2 'rgba-8888 'premul 0
                                      (make-surface-properties))))
    (check-exn exn:fail? (lambda () (gpu-format-label 'invented))))

  (test-case "cache sizes accept zero but reject native overflow"
    (check-equal? (cache-size 'test 0) 0)
    (check-exn exn:fail? (lambda () (cache-size 'test -1)))
    (check-exn exn:fail? (lambda () (cache-size 'test (expt 2 (system-type 'word))))))

  (test-case "cleanup ages are milliseconds not delays"
    (check-equal? (cache-age 'test 0) 0)
    (check-equal? (cache-age 'test #x7fffffff) #x7fffffff)
    (check-exn exn:fail? (lambda () (cache-age 'test #x80000000))))

  (test-case "cache metadata does not claim total memory or a hard limit"
    (define report (cache-snapshot 'metal 1 100 2 80))
    (check-true (immutable? report))
    (check-equal? (hash-ref report 'budgeted_resources) 2)
    (check-false (hash-ref report 'total_gpu_bytes))
    (check-false (hash-ref report 'limit_is_hard_allocation_cap)))

  (test-case "one-shot public validation rejects malformed requests before construction"
    (check-exn exn:fail?
      (lambda () (render-gpu->raster-image 0 1 void #:backend 'metal)))
    (check-exn exn:fail?
      (lambda () (render-gpu->raster-image 1 1 void #:backend 'opengl)))
    (check-exn exn:fail?
      (lambda () (render-gpu->raster-image 1 1 void #:backend 'metal #:adapter 'warp)))
    (check-exn exn:fail?
      (lambda () (render-gpu->raster-image 1 1 (lambda () 1) #:backend 'metal))))

  (test-case "one-shot callback runs once and may return zero or multiple values"
    (for ([count '(0 3)])
      (define called 0)
      (define-values (out events)
        (fake-render #:draw (lambda () (set! called (add1 called))
                              (apply values (make-list count 'ignored)))))
      (check-equal? called 1)
      (check-equal? out '(returned fake-cpu-image))
      (check-equal? events '(context enter surface draw readback close-surface exit close-context))))

  (test-case "failed context construction does not run drawing or readback"
    (define-values (out events) (fake-render #:failure 'context))
    (check-equal? (car out) 'raised)
    (check-equal? events '(context)))

  (test-case "failed surface construction still closes its context"
    (define-values (out events) (fake-render #:failure 'surface))
    (check-equal? (car out) 'raised)
    (check-equal? events '(context enter surface exit close-context)))

  (test-case "drawing failure skips readback and closes both GPU resources"
    (define-values (out events) (fake-render #:failure 'draw))
    (check-equal? (car out) 'raised)
    (check-equal? events '(context enter surface draw close-surface exit close-context)))

  (test-case "readback failure does not publish a CPU image"
    (define-values (out events) (fake-render #:failure 'readback))
    (check-equal? (car out) 'raised)
    (check-equal? events '(context enter surface draw readback close-surface exit close-context)))

  (test-case "surface cleanup failure releases the undelivered CPU image"
    (define-values (out events) (fake-render #:failure 'close-surface))
    (check-equal? (car out) 'raised)
    (check-equal? events
      '(context enter surface draw readback close-surface exit close-context close-image)))

  (test-case "context cleanup failure releases the undelivered CPU image"
    (define-values (out events) (fake-render #:failure 'close-context))
    (check-equal? (car out) 'raised)
    (check-equal? events
      '(context enter surface draw readback close-surface exit close-context close-image)))

  (test-case "GPU predicates reject unrelated data without native initialization"
    (check-false (gpu-surface? #f))
    (check-false (gpu-image? '#(1 2 3)))
    (check-exn exn:fail? (lambda () (image-residency #f)))
    (check-exn exn:fail? (lambda () (skia-resource-gpu-context #f)))))
