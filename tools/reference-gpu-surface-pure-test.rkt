#lang racket/base

;;;
;;; Reference GPU Surface Pure Test
;;;

;; Checks format budgets and one-shot cleanup with fake resources, and compiles displayed GPU
;; helpers.
;; These acceptance checks keep the Reference's documented contracts aligned with the public
;; implementation.

;;;
;;; Imports and Exports
;;;

;; Native-free checks. Fake operations test the actual one-shot lifetime worker;
;; they do not establish GPU, pixel, driver, or platform acceptance.
(require rackunit racket/list racket/runtime-path syntax/modread skia skia/gpu
         "../private/gpu-format-util.rkt"
         "../private/gpu-cache-util.rkt"
         "../private/gpu-render.rkt")




;;;
;;; Diagnostic Operations
;;;

; reference-directory : path?
;   Locates ../scribblings/reference relative to this module, independent of the invoking
;   directory.
(define-runtime-path reference-directory "../scribblings/reference")


; displayed-blocks : path-string? -> (listof list?)
;   Extracts displayed racketblock bodies while excluding quoted forms and evaluated Scribble
;   examples.
(define (displayed-blocks path)
  (define (walk form)
    (cond [(not (pair? form)) '()]
          [(memq (car form) '(quote quasiquote examples)) '()]
          [(eq? (car form) 'racketblock) (list (cdr form))]
          [else (append-map walk form)]))
  (define document
    (call-with-input-file path
      (lambda (in)
        (with-module-reading-parameterization
          (lambda () (syntax->datum (read-syntax path in)))))))
  (walk document))


; compile-displayed-block : list? -> void?
;   Loads a displayed helper module in a fresh base namespace to check imports and expansion
;   without invoking its helpers.
(define (compile-displayed-block block)
  ;; A fresh base namespace deliberately inherits none of this test module's
  ;; skia/skia-gpu imports. The block must provide every binding it uses.
  (define namespace (make-base-namespace))
  (parameterize ([current-namespace namespace])
    (eval `(module displayed-gpu-example racket/base ,@block))
    (dynamic-require ''displayed-gpu-example #f)))


; fake-render : [#:failure (or/c symbol? #f) #:draw procedure?] -> (values list? list?)
;   Runs one-shot rendering with fake resources, returning the tagged outcome and chronological
;   lifecycle events.
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

  ;;;
  ;;; Surface Formats and Storage Budgets
  ;;;

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

  ;;;
  ;;; Cache and Cleanup Policies
  ;;;

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
    (check-false (hash-has-key? report 'total_gpu_bytes))
    (check-false (hash-has-key? report 'limit_is_hard_allocation_cap)))

  ;;;
  ;;; One-Shot Rendering and Failure Cleanup
  ;;;

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

  ;;;
  ;;; Displayed Helpers and Native-Free Predicates
  ;;;

  (test-case "displayed GPU helpers compile using only their shown imports"
    (define blocks
      (append*
       (for/list ([name '("gpu-surfaces.scrbl" "gpu-images.scrbl" "gpu-transfers.scrbl")])
         (displayed-blocks (build-path reference-directory name)))))
    (check-equal? (length blocks) 4)
    (for ([block (in-list blocks)])
      (check-equal? (car block) '(require skia skia/gpu))
      (check-not-exn (lambda () (compile-displayed-block block)))))

  (test-case "GPU predicates reject unrelated data without native initialization"
    (check-false (gpu-surface? #f))
    (check-false (gpu-image? '#(1 2 3)))
    (check-exn exn:fail? (lambda () (image-residency #f)))
    (check-exn exn:fail? (lambda () (skia-resource-gpu-context #f)))))
