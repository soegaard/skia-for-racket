#lang racket/base

;;;
;;; Convertible Pure Test
;;;

;; Covers file/convertible dispatch without native loading.
;; This source-only regression layer checks contracts and lifecycle rules before native rendering
;; is involved.

;;;
;;; Imports and Exports
;;;

;; These checks exercise property dispatch and GPU affinity without loading the
;; native library. Native pixels, documents, pict, and Scribble live in the
;; companion native suite.
(require rackunit rackunit/text-ui file/convertible
         "gpu-fixtures.rkt"
         "../main.rkt"
         "../private/gpu-domain.rkt"
         (submod "../private/core.rkt" gpu-image-internals)
         (submod "../private/core.rkt" gpu-surface-internals))
(provide convertible-pure-tests)


;;;
;;; Fixtures and Assertions
;;;

; fake-gpu-surface : gpu-domain? box? box? -> gpu-surface?
;;   Wraps a mock owned surface so conversion dispatch can be checked without GPU allocation.
(define (fake-gpu-surface domain log abandoned?)
  (make-gpu-surface-record (mock-resource domain log abandoned? 'surface) 8 8 '()
                           'mock-context domain #f (hasheq 'storage "gpu")))


;;;
;;; Regression Suite
;;;

; convertible-pure-tests : test-suite?
;;   Collects the regression cases for file/convertible dispatch without native loading.
(define convertible-pure-tests
  (test-suite
   "file/convertible dispatch without native loading"
   (test-case "output pages preserve unknown defaults without drawing"
     (define calls 0)
     (define page (make-output-page 10 8 (lambda (_) (set! calls (add1 calls)))))
     (define opaque-default (box 'unchanged))
     (define procedure-default (lambda () (error 'default "must not run")))
     (check-true (convertible? page))
     (check-false (convert page 'jpeg-bytes))
     (check-eq? (convert page 'jpeg-bytes opaque-default) opaque-default)
     (check-eq? (convert page 'png@2x-bytes procedure-default) procedure-default)
     (check-equal? calls 0))
   (test-case "GPU image and surface keep their explicit transfer boundary"
     (call-with-mock
      (lambda (domain _provider _driver log abandoned?)
        (define image
          (domain-call domain
            (lambda ()
              (make-image-record (mock-resource domain log abandoned? 'image) 8 8))))
        (define surface
          (domain-call domain
            (lambda () (fake-gpu-surface domain log abandoned?))))
        (define fallback (lambda () (error 'fallback "must not run")))
        (define activations (event-count log 'activate))
        (check-true (convertible? image))
        (check-true (convertible? surface))
        (check-eq? (convert image 'svg-bytes fallback) fallback)
        (check-eq? (convert surface 'pdf-bytes fallback) fallback)
        (check-equal? (event-count log 'activate) activations)
        (check-exn #rx"GPU-dependent input"
                    (lambda () (convert image 'png-bytes fallback)))
        (check-exn #rx"GPU transfers are explicit"
                    (lambda () (convert surface 'png-bytes fallback)))
        ;; Neither rejected conversion activates a provider or starts a readback.
        (check-equal? (event-count log 'activate) activations)
        (skia-close! image)
        (skia-close! surface))))))

(module+ test

  ;;;
  ;;; Test Entry Point
  ;;;

  ; failures : exact-nonnegative-integer?
  ;;   Counts failed or errored RackUnit cases for the command-line exit status.
  (define failures (run-tests convertible-pure-tests))
  (unless (zero? failures) (error 'convertible-pure-test "~a failures" failures)))
