#lang racket/base

;;;
;;; GPU Render Pure Test
;;;

;; Covers one-shot GPU render: arguments and lifetime worker.
;; This source-only regression layer checks contracts and lifecycle rules before native rendering
;; is involved.

;;;
;;; Imports and Exports
;;;

(require rackunit
         rackunit/text-ui
         "../gpu.rkt"
         (only-in "../main.rkt" current-skia-byte-limit)
         "../private/gpu-render.rkt")

(provide gpu-render-pure-tests)

;; Test the same lifetime worker used by the public API, with no native driver.

;;;
;;; Fixtures and Assertions
;;;

; make-render-fixture : [#:fail any/c #:draw procedure?] -> any
;   Builds an instrumented one-shot renderer with failure injection at lifecycle steps.
(define (make-render-fixture #:fail [failure #f] #:draw [body void])
  (define events '())
  (define active? #f)
  (define image (box 'open))
  (define (record! event)
    (set! events (cons event events))
    (when (eq? failure event) (raise event)))
  (define (render)
    (call-with-rendered-gpu-image
     (lambda () (record! 'create-context) 'context)
     (lambda (context thunk)
       (check-eq? context 'context)
       (record! 'enter)
       (dynamic-wind
         (lambda () (set! active? #t))
         thunk
         (lambda () (set! active? #f) (record! 'leave))))
     (lambda (context)
       (check-eq? context 'context)
       (check-true active?)
       (record! 'create-surface)
       'surface)
     (lambda (context surface)
       (check-eq? context 'context)
       (check-eq? surface 'surface)
       (check-true active?)
       (record! 'draw)
       (body))
     (lambda (surface)
       (check-eq? surface 'surface)
       (check-true active?)
       (record! 'readback)
       image)
     (lambda (resource)
       (cond
         [(eq? resource 'surface)
          (check-true active?)
          (record! 'close-surface)]
         [else
          (check-eq? resource image)
          (check-false active?)
          (check-eq? (unbox image) 'open)
          (set-box! image 'closed)
          (record! 'close-image)]))
     (lambda (context)
       (check-eq? context 'context)
       (check-false active?)
       (record! 'close-context))))
  (values render (lambda () (reverse events)) image))


; normal-events : (listof symbol?)
;   Lists required context, surface, drawing, readback, and cleanup events in execution order.
(define normal-events
  '(create-context enter create-surface draw readback close-surface leave close-context))


; raises-value? : any/c -> (any/c -> boolean?)
;   Matches a deliberately raised value by identity during cleanup-precedence tests.
(define (raises-value? expected)
  (lambda (value) (eq? value expected)))


;;;
;;; Regression Suite
;;;

; gpu-render-pure-tests : test-suite?
;   Collects the regression cases for one-shot GPU render: arguments and lifetime worker.
(define gpu-render-pure-tests
  (test-suite
   "One-shot GPU render: arguments and lifetime worker"
   (test-case "the public call boundary is explicit and small"
     (define-values (required allowed) (procedure-keywords render-gpu->raster-image))
     (check-equal? (procedure-arity-mask render-gpu->raster-image) 8)
     (check-equal? required '(#:backend))
     (check-equal? allowed '(#:adapter #:adapter-index #:backend #:background #:provider)))
   (test-case "backend is required; automatic or unknown selection is rejected"
     (check-exn exn:fail:contract? (lambda () (render-gpu->raster-image 2 2 void)))
     (for ([backend '(auto raster vulkan #f 42)])
       (check-exn exn:fail:contract?
                  (lambda () (render-gpu->raster-image 2 2 void #:backend backend)))))
   (test-case "dimensions validate before native construction"
     (for ([bad '(0 -1 1.5 32769 +inf.0 +nan.0 "32")])
       (check-exn exn:fail:contract?
                  (lambda () (render-gpu->raster-image bad 2 void #:backend 'metal)))
       (check-exn exn:fail:contract?
                  (lambda () (render-gpu->raster-image 2 bad void #:backend 'metal)))))
   (test-case "RGBA allocation budget is checked before context creation"
     (parameterize ([current-skia-byte-limit 16])
       (check-exn exn:fail:contract?
                  (lambda () (render-gpu->raster-image 3 2 void #:backend 'metal)))))
   (test-case "callback must accept a canvas without required keywords"
     (for ([bad (list #f 42 (lambda () (void)) (lambda (a b) (void))
                      (lambda (canvas #:required value) (void)))])
       (check-exn exn:fail:contract?
                  (lambda () (render-gpu->raster-image 2 2 bad #:backend 'metal)))))
   (test-case "invalid background is rejected without loading a driver"
     (check-exn exn:fail:contract?
                (lambda ()
                  (render-gpu->raster-image 2 2 void #:backend 'metal #:background #f))))
   (test-case "OpenGL needs a host; owned backends do not accept providers"
     (define provider
       (make-gpu-provider #:name 'render-test #:backend 'opengl #:key (gensym)
                          #:call-as-current (lambda (thunk) (thunk))
                          #:current? (lambda () #t)))
     (check-exn exn:fail:contract?
                (lambda () (render-gpu->raster-image 2 2 void #:backend 'opengl)))
     (for ([backend '(metal direct3d)])
       (check-exn exn:fail:contract?
                  (lambda ()
                    (render-gpu->raster-image 2 2 void #:backend backend #:provider provider))))
     (check-exn exn:fail:contract?
                (lambda ()
                  (render-gpu->raster-image 2 2 void #:backend 'opengl #:provider 'invalid))))
   (test-case "adapter selection is validated without initializing Direct3D"
     (check-exn exn:fail:contract?
                (lambda ()
                  (render-gpu->raster-image 2 2 void #:backend 'metal #:adapter 'warp)))
     (check-exn exn:fail:contract?
                (lambda ()
                  (render-gpu->raster-image 2 2 void #:backend 'direct3d #:adapter 'auto)))
     (for ([index '(-1 1.5 4294967295)])
       (check-exn exn:fail:contract?
                  (lambda ()
                    (render-gpu->raster-image 2 2 void
                                             #:backend 'direct3d #:adapter-index index))))
     (check-exn exn:fail:contract?
                (lambda ()
                  (render-gpu->raster-image 2 2 void #:backend 'direct3d
                                           #:adapter 'warp #:adapter-index 1))))
   (test-case "return occurs after surface close, activation exit, and context close"
     (define-values (render events image) (make-render-fixture))
     (check-eq? (render) image)
     (check-equal? (events) normal-events)
     (check-eq? (unbox image) 'open))
   (test-case "zero, one, and multiple callback values are ignored"
     (for ([body (list (lambda () (values)) (lambda () 'ignored)
                       (lambda () (values 1 2 3)))])
       (define-values (render events image) (make-render-fixture #:draw body))
       (check-eq? (render) image)
       (check-equal? (events) normal-events)))
   (test-case "context creation failure does not attempt to close an absent context"
     (define-values (render events image) (make-render-fixture #:fail 'create-context))
     (check-exn (raises-value? 'create-context) render)
     (check-equal? (events) '(create-context)))
   (test-case "activation failure still closes the context"
     (define-values (render events image) (make-render-fixture #:fail 'enter))
     (check-exn (raises-value? 'enter) render)
     (check-equal? (events) '(create-context enter close-context)))
   (test-case "surface construction failure leaves activation before context close"
     (define-values (render events image) (make-render-fixture #:fail 'create-surface))
     (check-exn (raises-value? 'create-surface) render)
     (check-equal? (events) '(create-context enter create-surface leave close-context)))
   (test-case "arbitrary raised values propagate after GPU cleanup"
     (define token (box 'drawing-failure))
     (define-values (render events image) (make-render-fixture #:draw (lambda () (raise token))))
     (check-exn (raises-value? token) render)
     (check-equal? (events)
                   '(create-context enter create-surface draw close-surface leave close-context)))
   (test-case "readback failure still retires both GPU resources"
     (define-values (render events image) (make-render-fixture #:fail 'readback))
     (check-exn (raises-value? 'readback) render)
     (check-equal? (events) normal-events))
   (test-case "surface release failure still attempts context and image cleanup"
     (define-values (render events image) (make-render-fixture #:fail 'close-surface))
     (check-exn (raises-value? 'close-surface) render)
     (check-equal? (events) (append normal-events '(close-image)))
     (check-eq? (unbox image) 'closed))
   (test-case "activation exit failure closes the context and undeliverable image"
     (define-values (render events image) (make-render-fixture #:fail 'leave))
     (check-exn (raises-value? 'leave) render)
     (check-equal? (events) (append normal-events '(close-image)))
     (check-eq? (unbox image) 'closed))
   (test-case "context release failure closes the already detached image"
     (define-values (render events image) (make-render-fixture #:fail 'close-context))
     (check-exn (raises-value? 'close-context) render)
     (check-equal? (events) (append normal-events '(close-image)))
     (check-eq? (unbox image) 'closed))
   (test-case "prompt escape unwinds the same GPU scopes without a readback"
     (define tag (make-continuation-prompt-tag 'render-test))
     (define-values (render events image)
       (make-render-fixture #:draw (lambda () (abort-current-continuation tag 'escaped))))
     (check-eq? (call-with-continuation-prompt render tag (lambda (value) value)) 'escaped)
     (check-equal? (events)
                   '(create-context enter create-surface draw close-surface leave close-context)))
   (test-case "an escaped continuation cannot reenter a completed render"
     (define saved #f)
     (define-values (render events image)
       (make-render-fixture #:draw (lambda () (call/cc (lambda (k) (set! saved k))))))
     (check-eq? (render) image)
     (check-exn exn:fail:contract:continuation? (lambda () (saved (void))))
     (check-equal? (events) normal-events))
   (test-case "a callback break unwinds cleanup and propagates"
     (define interrupted? #f)
     (define-values (render events image)
       (make-render-fixture #:draw (lambda () (break-thread (current-thread)) (sleep 0))))
     (with-handlers ([exn:break? (lambda (exception) (set! interrupted? #t))])
       (parameterize-break #t (render)))
     (check-true interrupted?)
     (check-equal? (events)
                   '(create-context enter create-surface draw close-surface leave close-context)))
   (test-case "the callback inherits the caller's break setting"
     (for ([enabled? '(#t #f)])
       (define-values (render events image)
         (make-render-fixture #:draw (lambda () (check-eq? (break-enabled) enabled?))))
       (parameterize-break enabled? (check-eq? (render) image))))))

(module+ test
  (check-equal? (run-tests gpu-render-pure-tests) 0))

(module+ main
  (exit (run-tests gpu-render-pure-tests)))
