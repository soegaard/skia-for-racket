#lang racket/base
;; GUI initialization and synchronous handoff are explicit diagnostic operations.
;; Loading this helper does not itself initialize a display server.
(require racket/async-channel racket/runtime-path "../private/gpu-provider.rkt")
(provide call-on-presentation-handler)
(define-runtime-path widgets "../gpu-gui.rkt")
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
