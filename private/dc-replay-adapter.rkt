#lang racket/base
;; Isolate the private member identities used by racket/draw's replay and
;; pen/brush locking protocols. No Cairo context is created or borrowed here.
(require racket/class
         (only-in ffi/unsafe register-finalizer)
         (only-in ffi/unsafe/atomic call-as-atomic)
         (only-in racket/draw/private/dc
                  [do-set-pen! replay-set-pen!] [do-set-brush! replay-set-brush!])
         (only-in racket/draw/private/local adjust-lock))
(provide dc-replay-mixin make-dc-style-lease dc-style-select! dc-style-release!)
(define (dc-replay-mixin %)
  (class %
    (super-new)
    ;; These are the actual local-member identities, not public symbols with
    ;; the same spelling. Route replay through the normal validation/locking.
    (define/public (replay-set-pen! p) (send this set-pen p))
    (define/public (replay-set-brush! b) (send this set-brush b))))
(define (make-dc-style-lease dc)
  (define lease (vector #f #f))
  ;; Do not keep selected-object -> DC cycles alive through the finalizer.
  (register-finalizer dc (lambda (_dc) (dc-style-release! lease)))
  lease)
(define (selected lease slot)
  (define w (vector-ref lease slot)) (and w (weak-box-value w)))
(define (dc-style-select! lease slot object validate commit)
  (call-as-atomic
   (lambda ()
     (validate object) ; validation and locking cannot race a thread mutation
     (define old (selected lease slot))
     (unless (eq? old object)
       (send object adjust-lock 1)
       (when old (send old adjust-lock -1))
       (vector-set! lease slot (make-weak-box object)))
     (commit object)))
  (void))
(define (dc-style-release! lease)
  (call-as-atomic
   (lambda ()
     (for ([slot (in-range 2)])
       (define old (selected lease slot))
       (vector-set! lease slot #f)
       (when old (send old adjust-lock -1)))))
  (void))
