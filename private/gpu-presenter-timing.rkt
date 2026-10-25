#lang racket/base

;;;
;;; Metal Presenter Timing
;;;

;; Records optional CPU-side timing spans and layer-state observations through Racket's logger.
;; Lets GUI traces locate presenter stalls without changing frame scheduling or GPU work.

(provide with-metal-presenter-timing
         start-metal-presenter-timing finish-metal-presenter-timing!
         record-metal-presenter-state!)

;; This parameter is private test support, not a public rendering option. Read the environment
;; once on module loading; normal drawing does not consult the process environment per phase.

; current-metal-presenter-timing-enabled : (parameter/c boolean?)
;   Enables private timing and state observations only when explicitly requested.
(define current-metal-presenter-timing-enabled
  (make-parameter (equal? (getenv "SKIA_METAL_PRESENTER_TIMING") "1")))
(module+ test-support
  (provide current-metal-presenter-timing-enabled))

(struct gui-event (start end name) #:prefab)
;; Fields:
;;   start and end: epoch milliseconds, with end computed from monotonic elapsed time.
;;   name: phase symbol. Field order and prefab identity match Racket GUI timing events so
;;   existing GUI trace collectors can read these spans. A span records time, not success.

(struct metal-presenter-state (time host phase fields) #:prefab)
;; Fields:
;;   time: epoch milliseconds before observation. host: layer identity string, not a native pointer.
;;   phase: observation boundary symbol. fields: immutable hash of copied numbers, booleans, strings,
;;   and lists. observation_ms measures observer overhead; observation_error replaces failed data.
;;   This record uses a separate logger topic so existing GUI span consumers remain unchanged.

(struct timing-span (logger name start monotonic-start [finished? #:mutable]))
;; Fields:
;;   logger: logger captured at entry. name: phase symbol. start: epoch milliseconds at entry.
;;   monotonic-start: monotonic milliseconds at entry, used only for elapsed time.
;;   finished?: prevents duplicate events when both an explicit boundary and cleanup finish a
;;   span. Records contain no native resources and are used only on the calling thread.

; start-metal-presenter-timing : symbol? -> (or/c #f timing-span?)
;   Starts a span only when explicitly enabled and a debug receiver accepts its topic.
(define (start-metal-presenter-timing name)
  (and (current-metal-presenter-timing-enabled)
       (let ([logger (current-logger)])
         (and (log-level? logger 'debug 'skia-metal-presenter)
              (timing-span logger name (current-inexact-milliseconds)
                           (current-inexact-monotonic-milliseconds) #f)))))

; finish-metal-presenter-timing! : (or/c #f timing-span?) -> void?
;   Queues one completed span without file I/O or invoking a user callback.
(define (finish-metal-presenter-timing! span)
  (when (and span (not (timing-span-finished? span)))
    (define elapsed (- (current-inexact-monotonic-milliseconds)
                       (timing-span-monotonic-start span)))
    (set-timing-span-finished?! span #t)
    (log-message (timing-span-logger span) 'debug 'skia-metal-presenter
                 (format "~a: ~a ms" (timing-span-name span) elapsed)
                 (gui-event (timing-span-start span) (+ (timing-span-start span) elapsed)
                            (timing-span-name span)) #f)))

; record-metal-presenter-state! : string? symbol? (-> hash?) -> void?
;   Copies diagnostic state only with opt-in and a state receiver, without controlling rendering.
(define (record-metal-presenter-state! host phase observe)
  (when (and (current-metal-presenter-timing-enabled)
             (log-level? (current-logger) 'debug 'skia-metal-presenter-state))
    (define time (current-inexact-milliseconds))
    (define start (current-inexact-monotonic-milliseconds))
    ;; Only the diagnostic read is protected; rendering errors still propagate normally.
    (define fields
      (with-handlers ([exn:fail?
                       (lambda (e) (hasheq 'observation_error (exn-message e)))])
        (observe)))
    (define elapsed (- (current-inexact-monotonic-milliseconds) start))
    (log-message (current-logger) 'debug 'skia-metal-presenter-state
                 (format "~a: ~a" host phase)
                 (metal-presenter-state time host phase
                                        (hash-set fields 'observation_ms elapsed)) #f))
  (void))

; call-with-metal-presenter-timing : symbol? (-> any) -> any
;   Preserves results and escapes, recording a completed span on each dynamic exit.
(define (call-with-metal-presenter-timing name thunk)
  (define span (start-metal-presenter-timing name))
  (if span
      (dynamic-wind
        (lambda ()
          ;; A continuation may re-enter the body after an earlier completed span.
          (when (or (not span) (timing-span-finished? span))
            (set! span (start-metal-presenter-timing name))))
        thunk
        (lambda () (finish-metal-presenter-timing! span)))
      (thunk)))

; with-metal-presenter-timing : syntax
;   Times a body without changing its result values or control-flow exits.
(define-syntax-rule (with-metal-presenter-timing name body ...)
  (call-with-metal-presenter-timing name (lambda () body ...)))
