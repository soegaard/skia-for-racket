#lang racket/base
;; Driver-owned references only. The table is not an ownership transfer and
;; is removed immediately before the driver's one native context destruction.
(require ffi/unsafe racket/future)
(provide register-d3d12-handles! forget-d3d12-handles! call-with-d3d12-handles)
(struct handles (owner adapter device queue))
(define table (make-hasheqv))
(define (key p) (cast p _pointer _uintptr))
(define (register-d3d12-handles! p a d q)
  (when (hash-has-key? table (key p)) (error 'direct3d "duplicate native handle registration"))
  (hash-set! table (key p) (handles (current-thread) a d q)))
(define (forget-d3d12-handles! p) (hash-remove! table (key p)))
(define (call-with-d3d12-handles p proc)
  (define h (hash-ref table (key p) (lambda () (error 'd3d12-interop "context handles are unavailable"))))
  (unless (and (eq? (handles-owner h) (current-thread)) (not (current-future)))
    (error 'd3d12-interop "native handles belong to another execution owner"))
  (proc (handles-adapter h) (handles-device h) (handles-queue h)))
