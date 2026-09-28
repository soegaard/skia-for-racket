#lang racket/base
;; Private, backend-independent exception-safe presentation lease. Metal uses
;; an explicit completion step ONLY on cancelled/failed frames: a drawable
;; must not return to its pool while unsubmitted Ganesh work still targets it.
;; Normal presented frames require no CPU completion wait.
(provide call-with-presentation-cleanup)
(define (call-with-presentation-cleanup proc abort! release! quarantine!)
  (define entered? #f) (define retired? #f) (define presented? #f)
  (define (mark-presented!)
    (when (or retired? presented?)
      (error 'gpu-presenter "presentation lease is retired or already presented"))
    (set! presented? #t))
  (call-with-continuation-barrier
   (lambda ()
     (dynamic-wind
       (lambda ()
         (when entered? (error 'gpu-presenter "presentation lease cannot be reentered"))
         (set! entered? #t))
       (lambda () (proc mark-presented!))
       (lambda ()
         (unless retired?
           (set! retired? #t)
           (parameterize-break #f
             (with-handlers ([(lambda (_) #t)
                              (lambda (e) (quarantine! e) (raise e))])
               (unless presented? (abort!))
               (release!)))))))))
