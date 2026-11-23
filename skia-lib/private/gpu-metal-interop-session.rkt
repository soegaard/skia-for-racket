#lang racket/base

;;;
;;; Metal Interoperation Sessions
;;;

;; Retains shared textures and coordinates producer completion with Skia work.
;; Owns the synchronization lifetime of one Metal interoperation session.

;; Native ownership state machine, with private operations injected for tests.
(require "gpu-metal-interop-policy.rkt")
(provide (struct-out metal-interop-ops) make-metal-session
         metal-session-description metal-session-texture metal-session-info
         metal-session-begin! metal-session-complete! metal-session-close!
         metal-session-quarantine! metal-session-rethrow!)

;;;
;;; Session State and Quarantine
;;;

(struct metal-interop-ops (inspect retain release status error new-tail commit))
;; Fields:
;;   inspect, retain, release, status, error, new-tail, and commit: injected native procedures.
;;   new-tail returns an owned uncommitted command buffer; retain/release balance ownership of
;;   shared texture and producer objects.

(struct session (ops owner texture producer description timeout
                     [texture-owned? #:mutable] [producer-owned? #:mutable]
                     [tail #:mutable] [state #:mutable] [waits #:mutable] [error #:mutable] [failure
                       #:mutable]))
;; Fields:
;;   ops: metal-interop-ops. owner: creator thread. texture and producer: retained Metal objects.
;;   description: checked texture metadata. timeout: completion-wait limit in milliseconds.
;;   texture-owned? and producer-owned?: mutable retained-reference flags. tail: owned completion
;;   command buffer or #f. state: lifecycle symbol. waits: completion reports, newest first.
;;   error: first diagnostic string or #f. failure: box of the originally raised value or #f.
;;   Ambiguous completion/cleanup failures quarantine the session rather than release objects still
;;   in use.

;; Indeterminate native references remain reachable, even if construction fails.

; quarantined : hash?
;   Keeps uncertain native sessions reachable rather than releasing objects that may remain in
;   flight.
(define quarantined (make-hasheq))

; owner! : session? -> void?
;   Rejects use of a native Metal sharing session from any other execution thread.
(define (owner! s)
  (unless (eq? (session-owner s) (current-thread))
    (error 'metal-interop "native session belongs to another execution owner")))

; metal-session-quarantine! : session? any/c -> void?
;   Records the first failure and retains all ambiguous session ownership for safe diagnostics.
(define (metal-session-quarantine! s e)
  (owner! s)
  (set-session-state! s 'quarantined)
  (unless (session-error s)
    (set-session-error! s (string->immutable-string
      (if (exn? e) (exn-message e) "non-exception native failure")))
    (set-session-failure! s (box e)))
  (hash-set! quarantined s #t)
  (void))

; metal-session-rethrow! : session? -> void?
;   Re-raises the original saved failure value rather than replacing it with a summary string.
(define (metal-session-rethrow! s)
  (owner! s)
  (when (session-failure s) (raise (unbox (session-failure s)))))

; guard : any/c procedure? -> any
;   Quarantines a session before propagating any exception or non-exception native failure.
(define (guard s thunk)
  (with-handlers ([(lambda (_) #t)
                   (lambda (e) (metal-session-quarantine! s e) (raise e))])
    (thunk)))

;;;
;;; Retained Producer and Texture References
;;;

; make-metal-session : metal-interop-ops? any/c any/c any/c -> session?
;   Validates a committed producer and retains its texture and command buffer with rollback on
;   failure.
(define (make-metal-session ops texture producer timeout)
  (metal-timeout! timeout)
  (unless (metal-interop-ops? ops) (raise-argument-error 'make-metal-session
    "private Metal operations" ops))
  (define d ((metal-interop-ops-inspect ops) texture producer))
  (metal-check-texture! d)
  (define status ((metal-interop-ops-status ops) producer))
  (unless (memv status '(2 3 4))
    (metal-interop-fail 'uncommitted "producer must be committed and not failed; status ~a" status))
  (define s (session ops (current-thread) texture producer d timeout #f #f #f 'ready '() #f #f))
  (with-handlers ([(lambda (_) #t)
                   (lambda (e) (guard s (lambda () (metal-session-close! s))) (raise e))])
    (parameterize-break #f
      ((metal-interop-ops-retain ops) texture) (set-session-texture-owned?! s #t)
      ((metal-interop-ops-retain ops) producer) (set-session-producer-owned?! s #t))
    s))

; metal-session-description : session? -> any
;   Returns the checked detached texture description after enforcing session ownership.
(define (metal-session-description s) (owner! s) (session-description s))

; metal-session-texture : session? -> any
;   Returns the retained texture only in a state whose ownership is still valid.
(define (metal-session-texture s)
  (owner! s)
  (unless (and (session-texture-owned? s) (memq (session-state s) '(ready active completed)))
    (error 'metal-interop "texture is not available"))
  (session-texture s))

;;;
;;; Producer Synchronization and Session Retirement
;;;

; wait! : session? any/c any/c -> any
;   Waits for one command buffer and records a phase-tagged completion report.
(define (wait! s command phase)
  (define ops (session-ops s))
  (define result (metal-wait-completed!
                 (lambda () ((metal-interop-ops-status ops) command))
                 (lambda () ((metal-interop-ops-error ops) command)) (session-timeout s)))
  (set-session-waits! s (cons (hash-set result 'phase phase) (session-waits s))))

; metal-session-begin! : session? -> any
;   Transitions a ready session to active only after beginning the guarded producer-completion
;   wait.
(define (metal-session-begin! s)
  (owner! s)
  (unless (eq? (session-state s) 'ready) (error 'metal-interop "native handoff is not ready"))
  (set-session-state! s 'active)
  (guard s (lambda () (wait! s (session-producer s) "producer"))))

; metal-session-complete! : session? -> any
;   Submits and waits for an owned queue-tail command buffer before marking shared work completed.
(define (metal-session-complete! s)
  (owner! s)
  (unless (eq? (session-state s) 'active) (error 'metal-interop "native handoff is not active"))
  (guard s
    (lambda ()
      (define ops (session-ops s))
      ;; new-tail returns an owned, uncommitted command buffer. Register it
      ;; before commit so every ambiguous failure can retain it safely.
      (parameterize-break #f
        (define tail ((metal-interop-ops-new-tail ops)))
        (unless tail (metal-interop-fail 'allocation "Metal completion buffer allocation failed"))
        (set-session-tail! s tail)
        ((metal-interop-ops-commit ops) tail))
      (wait! s (session-tail s) "ganesh-queue-tail")
      (parameterize-break #f
        (define tail (session-tail s))
        (set-session-tail! s #f) ; never retry a destructor
        ((metal-interop-ops-release ops) tail)
        (set-session-state! s 'completed)))))

; metal-session-close! : session? -> void?
;   Releases retained producer and texture references only from a safely releasable session state.
(define (metal-session-close! s)
  (owner! s)
  (unless (eq? (session-state s) 'closed)
    (unless (memq (session-state s) '(ready completed))
      (error 'metal-interop "cannot release a ~a session" (session-state s)))
    (guard s
      (lambda ()
        (parameterize-break #f
          (set-session-state! s 'closing)
          (define release (metal-interop-ops-release (session-ops s)))
          (when (session-producer-owned? s)
            (set-session-producer-owned?! s #f) (release (session-producer s)))
          (when (session-texture-owned? s)
            (set-session-texture-owned?! s #f) (release (session-texture s)))
          (set-session-state! s 'closed)))))
  (void))

; metal-session-info : session? -> hash?
;   Copies lifecycle, retained-reference, timeout, and wait diagnostics without exposing native
;   pointers.
(define (metal-session-info s)
  (owner! s)
  (hasheq 'state (symbol->string (session-state s))
          'quarantined (eq? (session-state s) 'quarantined) 'error (session-error s)
          'error_reason (and (session-failure s)
            (let ([e (unbox (session-failure s))])
              (if (exn:fail:metal-interop? e) (symbol->string (exn:fail:metal-interop-reason e))
                "native-failure")))
          'retained_texture (session-texture-owned? s)
          'retained_producer (session-producer-owned? s)
          'retained_completion_buffer (and (session-tail s) #t)
          'timeout_ms (session-timeout s) 'waits (reverse (session-waits s))))
