#lang racket/base
;; PRIVATE borrowed device/queue registry. Ganesh is the owner. No extra retain
;; is transferred to this table; entries are removed BEFORE its destructor.
;; Access must be nested in a validated live domain-pointer operation.
(require ffi/unsafe)
(provide register-metal-handles! forget-metal-handles! call-with-metal-handles)
(struct handles (owner device queue))
(define registry (make-hasheqv))
(define (key p) (if (cpointer? p) (cast p _pointer _uintptr) p))
(define (register-metal-handles! context device queue)
  (when (hash-has-key? registry (key context))
    (error 'make-gpu-context "duplicate owned Metal context pointer"))
  (hash-set! registry (key context) (handles (current-thread) device queue)))
(define (forget-metal-handles! context) (hash-remove! registry (key context)))
(define (call-with-metal-handles context proc)
  (define h (hash-ref registry (key context)
                      (lambda () (error 'gpu-presenter "not a live owned Metal context"))))
  (unless (eq? (handles-owner h) (current-thread))
    (error 'gpu-presenter "Metal command queue belongs to another execution owner"))
  (proc (handles-device h) (handles-queue h)))
