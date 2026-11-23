#lang racket/base

;;;
;;; Direct3D Handle Ownership
;;;

;; Owns retained adapter, device, and queue handles for one Racket thread.
;; Shares Direct3D lifetime checks between context creation and interoperation.

;; Driver-owned references only. The table is not an ownership transfer and
;; is removed immediately before the driver's one native context destruction.
(require ffi/unsafe racket/future)
(provide register-d3d12-handles! forget-d3d12-handles! call-with-d3d12-handles)
(struct handles (owner adapter device queue))
;; Fields:
;;   owner: creator Racket thread. adapter, device, and queue: retained COM interface pointers from
;;   the same Direct3D setup. Release and native use require owner-thread access.

; table : hash?
;   Registers retained adapter/device/queue handles by native context identity and creator thread.
(define table (make-hasheqv))

; key : cpointer? -> exact-positive-integer?
;   Uses the numeric native address rather than the Racket pointer wrapper as the registry
;   identity.
(define (key p) (cast p _pointer _uintptr))

; register-d3d12-handles! : cpointer? cpointer? cpointer? cpointer? -> void?
;   Associates a context with its retained adapter, device, queue, and owner thread.
(define (register-d3d12-handles! p a d q)
  (when (hash-has-key? table (key p)) (error 'direct3d "duplicate native handle registration"))
  (hash-set! table (key p) (handles (current-thread) a d q)))

; forget-d3d12-handles! : cpointer? -> void?
;   Removes borrowed device-handle access when the context driver is torn down.
(define (forget-d3d12-handles! p) (hash-remove! table (key p)))

; call-with-d3d12-handles : cpointer? procedure? -> any
;   Lends registered adapter, device, and queue pointers only on their owning thread.
(define (call-with-d3d12-handles p proc)
  (define h (hash-ref table (key p) (lambda () (error 'd3d12-interop
    "context handles are unavailable"))))
  (unless (and (eq? (handles-owner h) (current-thread)) (not (current-future)))
    (error 'd3d12-interop "native handles belong to another execution owner"))
  (proc (handles-adapter h) (handles-device h) (handles-queue h)))
