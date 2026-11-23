#lang racket/base

;;;
;;; Render Canvas Session State
;;;

;; Tracks callback delivery, active drawing contexts, and session ownership.
;; Shares lifecycle checks across rendering canvas implementations.

;; Shared callback state, independent of GUI classes and native rendering.

;;;
;;; Imports and Exports
;;;

(require racket/future)
(provide check-render-callback make-render-session
         render-session-check! render-session-idle!
         render-session-current-dc render-session-set-callback!
         render-session-deliver! render-session-info)

;;;
;;; Callback Contracts and Session State
;;;

; check-render-callback : symbol? procedure? exact-nonnegative-integer? -> void?
;   Checks a rendering callback's positional arity and rejects required keyword arguments.
(define (check-render-callback who proc arity)
  (unless (and (procedure? proc) (procedure-arity-includes? proc arity)
               (let-values ([(required _allowed) (procedure-keywords proc)]) (null? required)))
    (raise-argument-error who
      (format "procedure accepting ~a positional arguments with no required keywords" arity) proc)))

(struct render-session (owner [callback #:mutable] [active #:mutable]
                              [started #:mutable] [completed #:mutable]))
;; Fields:
;;   owner: creator thread. callback: mutable procedure accepting canvas and DC, with no required
;;   keywords. active: currently delivered drawing context or #f when idle. started and completed:
;;   mutable exact nonnegative delivery counters; completed <= started and increases only after a
;;   normal callback return. The active DC is borrowed only for the callback's dynamic extent.

; make-render-session : procedure? -> render-session?
;   Creates an idle owner-thread session with a two-argument canvas/DC callback and zero delivery
;   counters.
(define (make-render-session callback)
  (check-render-callback 'make-skia-render-canvas callback 2)
  (render-session (current-thread) callback #f 0 0))

; render-session-check! : symbol? render-session? -> void?
;   Rejects foreign-thread and future access to an eventspace-owned render session.
(define (render-session-check! who session)
  (unless (and (eq? (current-thread) (render-session-owner session)) (not (current-future)))
    (error who "use the render canvas on its eventspace handler thread")))

; render-session-idle! : symbol? render-session? -> void?
;   Checks ownership and forbids lifecycle changes while a paint callback is active.
(define (render-session-idle! who session)
  (render-session-check! who session)
  (when (render-session-active session)
    (error who
      "operation is not allowed during a paint callback; use refresh to request another frame")))

; render-session-current-dc : render-session? -> any/c
;   Returns the owner thread's active drawing context, or #f outside callback delivery.
(define (render-session-current-dc session)
  (render-session-check! 'get-dc session)
  (render-session-active session))

; render-session-set-callback! : render-session? procedure? -> void?
;   Validates and replaces the two-argument callback only while the session is idle.
(define (render-session-set-callback! session callback)
  (render-session-idle! 'set-paint-callback session)
  (check-render-callback 'set-paint-callback callback 2)
  (set-render-session-callback! session callback)
  (void))

;;;
;;; Guarded Delivery and Counters
;;;

; render-session-deliver! : render-session? any/c any/c [(or/c #f procedure?)] -> void?
;   Scopes active-DC access around the regular or one-shot callback, counting normal completion and
;   clearing activity on every exit.
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

; render-session-info : render-session? -> hash?
;   Returns detached painting and delivery counters; completed callbacks do not by themselves certify
;   presentation success.
(define (render-session-info session)
  (render-session-check! 'get-render-info session)
  (hasheq 'painting (and (render-session-active session) #t)
          'callbacks_started (render-session-started session)
          ;; Callback completion is not a claim of presentation/display success.
          'callbacks_completed (render-session-completed session)))
