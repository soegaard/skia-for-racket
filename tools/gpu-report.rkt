#lang racket/base
(require json racket/file racket/path)
(provide write-gpu-json check-gpu-teardown! close-gpu-contexts!)
(define (write-gpu-json path value)
  (define directory (or (path-only path) (current-directory)))
  (make-directory* directory)
  (define temporary (make-temporary-file "gpu-report-~a.tmp" #f directory))
  (dynamic-wind void
    (lambda ()
      (call-with-output-file temporary
        (lambda (out) (write-json value out) (newline out)) #:exists 'truncate)
      (rename-file-or-directory temporary path #t))
    (lambda () (when (file-exists? temporary) (delete-file temporary)))))
(define (check-gpu-teardown! info)
  (unless (and (equal? (hash-ref info 'state) "closed")
               (zero? (hash-ref info 'live_children))
               (zero? (hash-ref info 'pending_releases))
               (zero? (hash-ref info 'failed_releases)))
    (error 'gpu-validation "incomplete context teardown: ~a" info)))
(define (close-gpu-contexts! contexts close!)
  ;; Attempt both cleanups, preserving the first error. Never retry a failed
  ;; native destructor or force abandonment of an unknown set of children.
  (define first #f)
  (for ([context (in-list contexts)] #:when context)
    (with-handlers ([exn:fail? (lambda (e) (unless first (set! first e)))])
      (close! context)))
  (when first (raise first)))
