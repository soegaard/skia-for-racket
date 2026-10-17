#lang racket/base

;;;
;;; GPU Interoperation Cleanup
;;;

;; Runs cleanup actions while preserving the operation's original exception.
;; Shares exception-safe unwinding across external texture backends.

;; Shared completion/retirement boundary for external native resources.
;; A cleanup failure supersedes the original exception and quarantines once.
(provide call-with-interop-cleanup)

; call-with-interop-cleanup : any/c any/c any/c -> any
;   Runs required interoperation cleanup while preserving the first error and quarantining
;   uncertain state.
(define (call-with-interop-cleanup body finish quarantine)
  (define entered? #f)
  (call-with-continuation-barrier
   (lambda ()
     (dynamic-wind
       (lambda ()
         (when entered? (error 'gpu-interop "external lease expired"))
         (set! entered? #t))
       body
       (lambda ()
         (parameterize-break #f
           (with-handlers ([(lambda (_) #t)
                            (lambda (e) (quarantine e) (raise e))])
             (finish))))))))
