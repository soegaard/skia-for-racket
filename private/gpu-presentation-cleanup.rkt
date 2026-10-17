#lang racket/base

;;;
;;; GPU Presentation Cleanup
;;;

;; Runs presentation cleanup steps without losing earlier failures.
;; Shares safe teardown behavior across window and presenter implementations.

;; Private, backend-independent exception-safe presentation lease. Metal uses
;; an explicit completion step ONLY on cancelled/failed frames: a drawable
;; must not return to its pool while unsubmitted Ganesh work still targets it.
;; Normal presented frames require no CPU completion wait.
(provide call-with-presentation-cleanup)

; call-with-presentation-cleanup : any/c any/c any/c any/c -> any
;   Orders abort, release, and quarantine actions without replacing the original presentation
;   failure.
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
