#lang racket/base
;; Shared completion/retirement boundary for external native resources.
;; A cleanup failure supersedes the original exception and quarantines once.
(provide call-with-interop-cleanup)
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
