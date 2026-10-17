#lang racket/base

;;;
;;; GPU Presentation Eventspace Host
;;;

;; Loads presentation widgets and dispatches work on their GUI handler thread.
;; Presentation diagnostics use this boundary to preserve eventspace ownership while testing
;; windows.

;;;
;;; Imports and Exports
;;;
;; GUI initialization and synchronous handoff are explicit diagnostic operations.
;; Loading this helper does not itself initialize a display server.
(require racket/async-channel racket/runtime-path "../private/gpu-provider.rkt")
(provide call-on-presentation-handler)

;;;
;;; Diagnostic Operations
;;;

; widgets : path?
;   Locates ../gpu-gui.rkt relative to this module, independent of the invoking directory.
(define-runtime-path widgets "../gpu-gui.rkt")

; call-on-presentation-handler : procedure? -> any/c
;   Runs the callback with the window class and event-settling thunk on an owned GUI eventspace,
;   then shuts down that eventspace.
(define (call-on-presentation-handler proc)
  (define-values (current-space make-space handler-thread enqueue settle)
    (with-handlers ([exn:fail?
                    (lambda (e) (gpu-unavailable 'gui-initialization "~a" (exn-message e)))])
      (values (dynamic-require 'racket/gui/base 'current-eventspace)
              (dynamic-require 'racket/gui/base 'make-eventspace)
              (dynamic-require 'racket/gui/base 'eventspace-handler-thread)
              (dynamic-require 'racket/gui/base 'queue-callback)
              (dynamic-require 'racket/gui/base 'sleep/yield))))
  ;; Own module/class errors are implementation failures, NOT display absence.
  ;; Keep this load outside the GUI-initialization availability handler.
  (define window-class (dynamic-require widgets 'gpu-window%))
  (define custodian (make-custodian))
  (define space (parameterize ([current-custodian custodian]) (make-space)))
  (define result (make-async-channel))
  (dynamic-wind
    void
    (lambda ()
      (parameterize ([current-space space])
        (enqueue
         (lambda ()
           (async-channel-put result
             (with-handlers ([(lambda (_) #t) (lambda (e) (cons #f e))])
               (unless (eq? (current-thread) (handler-thread space))
                 (error 'gpu-presenter-doctor "wrong eventspace handler"))
               (cons #t (call-with-continuation-barrier
                 (lambda () (proc window-class (lambda () (settle 0.08))))))))) #f))
      (define answer (sync result))
      (if (car answer) (cdr answer) (raise (cdr answer))))
    ;; All normal native cleanup must already have run on the handler. An
    ;; exceptional failure remains a failure, not forced off-thread teardown.
    (lambda () (custodian-shutdown-all custodian))))
