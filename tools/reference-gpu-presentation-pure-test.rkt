#lang racket/base

;;;
;;; Reference GPU Presentation Pure Test
;;;

;; Checks frame acquisition, generation tracking, redraw coalescing, and expiration using a fake
;; adapter.
;; These acceptance checks keep the Reference's documented contracts aligned with the public
;; implementation.

;;;
;;; Imports and Exports
;;;

;; Presenter state-machine checks with a synthetic adapter. No GUI, native GPU,
;; window, pixel readback, or physical presentation is created by this suite.
(require rackunit racket/list
         "../private/gpu-presenter.rkt"
         (submod "../private/gpu-presenter.rkt" adapter-internals))


;;;
;;; Diagnostic Operations
;;;

; make-fake-presenter : [procedure?] -> (values any/c box? box? box? box?)
;   Returns a presenter and mutable metrics, event log, callback queue, and failure switch for
;   deterministic lifecycle checks.
(define (make-fake-presenter [render void])
  (define metrics (box (presentation-metrics 100 80 50 40)))
  (define log (box '()))
  (define queued (box '()))
  (define fail (box #f))
  (define (emit value) (set-box! log (cons value (unbox log))))
  (define adapter
    (presentation-adapter
     'metal 'fake-context
     (lambda () (unbox metrics))
     (lambda (_metrics receive)
       (emit 'acquire)
       (if (eq? (unbox fail) 'no-target)
           #f
           (dynamic-wind
             void
             (lambda ()
               (receive 'fake-canvas
                        (hasheq 'backend "metal" 'target_identity "fake")
                        (lambda ()
                          (emit 'present)
                          (when (eq? (unbox fail) 'present)
                            (error 'fake-presenter "present failed")))))
             (lambda () (emit 'release)))))
     (lambda (thunk) (set-box! queued (append (unbox queued) (list thunk))))
     (lambda () (emit 'close))
     (lambda () (hasheq 'synthetic #t))))
  (values (make-presenter adapter render void) metrics log queued fail))


; dispatch! : box? -> void?
;   Drains the current callback batch before running it, keeping newly enqueued work for the next
;   dispatch.
(define (dispatch! queue)
  (for ([thunk (in-list (begin0 (unbox queue) (set-box! queue '())))]) (thunk)))

(module+ test
  (test-case "presenter diagnostics do not claim visible pixels"
    (define-values (p metrics log queue fail) (make-fake-presenter))
    (check-eq? (gpu-presenter-state p) 'ready)
    (check-false (hash-ref (gpu-presenter-info p) 'visible_pixels_verified))
    (gpu-presenter-close! p))

  (test-case "render acquires and presents once"
    (define-values (p metrics log queue fail) (make-fake-presenter))
    (check-eq? (gpu-presenter-render! p) 'present-requested)
    (check-equal? (reverse (unbox log)) '(acquire present release))
    (gpu-presenter-close! p))

  (test-case "hidden geometry skips target acquisition"
    (define-values (p metrics log queue fail) (make-fake-presenter))
    (set-box! metrics (presentation-metrics 100 80 50 40 #:visible? #f))
    (check-eq? (gpu-presenter-render! p) 'skipped)
    (check-equal? (unbox log) '())
    (gpu-presenter-close! p))

  (test-case "missing drawable is a skip rather than a present"
    (define-values (p metrics log queue fail) (make-fake-presenter))
    (set-box! fail 'no-target)
    (check-eq? (gpu-presenter-render! p) 'skipped)
    (check-false (member 'present (unbox log)))
    (gpu-presenter-close! p))

  (test-case "frame metadata survives expiration while canvas access does not"
    (define saved #f)
    (define-values (p metrics log queue fail)
      (make-fake-presenter (lambda (frame) (set! saved frame)
                             (check-false (gpu-frame-expired? frame)))))
    (gpu-presenter-render! p)
    (check-true (gpu-frame-expired? saved))
    (check-equal? (gpu-frame-width saved) 100)
    (check-equal? (gpu-frame-logical-width saved) 50)
    (check-exn exn:fail? (lambda () (gpu-frame-canvas saved)))
    (gpu-presenter-close! p))

  (test-case "unchanged target identity keeps generation and advances frame index"
    (define seen '())
    (define-values (p metrics log queue fail)
      (make-fake-presenter
       (lambda (frame)
         (set! seen (cons (list (gpu-frame-generation frame)
                                (gpu-frame-index frame)) seen)))))
    (gpu-presenter-render! p)
    (gpu-presenter-render! p)
    (check-equal? (reverse seen) '((1 1) (1 2)))
    (gpu-presenter-close! p))

  (test-case "geometry change advances target generation"
    (define seen '())
    (define-values (p metrics log queue fail)
      (make-fake-presenter (lambda (frame)
                             (set! seen (cons (gpu-frame-generation frame) seen)))))
    (gpu-presenter-render! p)
    (set-box! metrics (presentation-metrics 120 80 60 40))
    (gpu-presenter-render! p)
    (check-equal? (reverse seen) '(1 2))
    (gpu-presenter-close! p))

  (test-case "redraw requests coalesce"
    (define-values (p metrics log queue fail) (make-fake-presenter))
    (for ([i (in-range 8)]) (gpu-presenter-request-render! p))
    (check-equal? (length (unbox queue)) 1)
    (dispatch! queue)
    (check-equal? (count (lambda (v) (eq? v 'present)) (unbox log)) 1)
    (gpu-presenter-close! p))

  (test-case "replacement callback schedules the next frame"
    (define count 0)
    (define-values (p metrics log queue fail) (make-fake-presenter))
    (gpu-presenter-set-render! p (lambda (_frame) (set! count (add1 count))))
    (dispatch! queue)
    (check-equal? count 1)
    (gpu-presenter-close! p))

  (test-case "native present failure marks presenter failed"
    (define-values (p metrics log queue fail) (make-fake-presenter))
    (set-box! fail 'present)
    (check-exn exn:fail? (lambda () (gpu-presenter-render! p)))
    (check-eq? (gpu-presenter-state p) 'failed)
    (check-not-false (member 'release (unbox log)))
    (gpu-presenter-close! p))

  (test-case "close invalidates queued redraw and is idempotent"
    (define-values (p metrics log queue fail) (make-fake-presenter))
    (gpu-presenter-request-render! p)
    (gpu-presenter-close! p)
    (gpu-presenter-close! p)
    (dispatch! queue)
    (check-eq? (gpu-presenter-state p) 'closed)
    (check-equal? (count (lambda (v) (eq? v 'close)) (unbox log)) 1))

  (test-case "frame canvas rejects access from another thread"
    (define ch (make-channel))
    (define-values (p metrics log queue fail)
      (make-fake-presenter
       (lambda (frame)
         (thread
          (lambda ()
            (channel-put ch
                         (with-handlers ([exn:fail? values])
                           (gpu-frame-canvas frame))))))))
    (gpu-presenter-render! p)
    (check-true (exn:fail? (channel-get ch)))
    (gpu-presenter-close! p)))
