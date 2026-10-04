#lang racket/base
;; Shared callback state, independent of GUI classes and native rendering.
(require racket/future)
(provide check-render-callback make-render-session
         render-session-check! render-session-idle!
         render-session-current-dc render-session-set-callback!
         render-session-deliver! render-session-info)

(define (check-render-callback who proc arity)
  (unless (and (procedure? proc) (procedure-arity-includes? proc arity)
               (let-values ([(required _allowed) (procedure-keywords proc)]) (null? required)))
    (raise-argument-error who
      (format "procedure accepting ~a positional arguments with no required keywords" arity) proc)))

(struct render-session (owner [callback #:mutable] [active #:mutable]
                              [started #:mutable] [completed #:mutable]))
(define (make-render-session callback)
  (check-render-callback 'make-skia-render-canvas callback 2)
  (render-session (current-thread) callback #f 0 0))
(define (render-session-check! who session)
  (unless (and (eq? (current-thread) (render-session-owner session)) (not (current-future)))
    (error who "use the render canvas on its eventspace handler thread")))
(define (render-session-idle! who session)
  (render-session-check! who session)
  (when (render-session-active session)
    (error who "operation is not allowed during a paint callback; use refresh to request another frame")))
(define (render-session-current-dc session)
  (render-session-check! 'get-dc session)
  (render-session-active session))
(define (render-session-set-callback! session callback)
  (render-session-idle! 'set-paint-callback session)
  (check-render-callback 'set-paint-callback callback 2)
  (set-render-session-callback! session callback)
  (void))
(define (render-session-deliver! session canvas dc [one-shot #f])
  (render-session-idle! 'paint-callback session)
  (when one-shot (check-render-callback 'refresh-now one-shot 1))
  (unless dc (raise-argument-error 'paint-callback "non-false drawing context" dc))
  (call-with-continuation-barrier
   (lambda ()
     (dynamic-wind
      (lambda ()
        (render-session-idle! 'paint-callback session)
        (set-render-session-started! session (add1 (render-session-started session)))
        (set-render-session-active! session dc))
      (lambda ()
        ;; A paint result is ignored, including zero or multiple values.
        (call-with-values
         (lambda () (if one-shot (one-shot dc) ((render-session-callback session) canvas dc)))
         (lambda ignored (void)))
        (set-render-session-completed! session (add1 (render-session-completed session))))
      (lambda () (set-render-session-active! session #f)))))
  (void))
(define (render-session-info session)
  (render-session-check! 'get-render-info session)
  (hasheq 'painting (and (render-session-active session) #t)
          'callbacks_started (render-session-started session)
          ;; Callback completion is not a claim of presentation/display success.
          'callbacks_completed (render-session-completed session)))
