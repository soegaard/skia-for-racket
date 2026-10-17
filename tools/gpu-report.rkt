#lang racket/base

;;;
;;; GPU Evidence and Teardown
;;;

;; Writes GPU JSON receipts and checks that context teardown leaves no owned resources behind.
;; GPU diagnostics share this layer so evidence is published only with verified cleanup.

;;;
;;; Imports and Exports
;;;
(require json racket/file racket/path)
(provide write-gpu-json check-gpu-teardown! close-gpu-contexts!)

;;;
;;; Diagnostic Operations
;;;

; write-gpu-json : path-string? jsexpr? -> void?
;;   Publishes JSON by renaming a same-directory temporary file, so readers never see a partial
;;   report.
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

; check-gpu-teardown! : hash? -> void?
;;   Rejects teardown reports with a nonclosed context or outstanding, pending, or failed child
;;   releases.
(define (check-gpu-teardown! info)
  (unless (and (equal? (hash-ref info 'state) "closed")
               (zero? (hash-ref info 'live_children))
               (zero? (hash-ref info 'pending_releases))
               (zero? (hash-ref info 'failed_releases)))
    (error 'gpu-validation "incomplete context teardown: ~a" info)))

; close-gpu-contexts! : list? procedure? -> void?
;;   Attempts cleanup for every nonfalse context, then re-raises the first cleanup failure.
(define (close-gpu-contexts! contexts close!)
  ;; Attempt both cleanups, preserving the first error. Never retry a failed
  ;; native destructor or force abandonment of an unknown set of children.
  (define first #f)
  (for ([context (in-list contexts)] #:when context)
    (with-handlers ([exn:fail? (lambda (e) (unless first (set! first e)))])
      (close! context)))
  (when first (raise first)))
