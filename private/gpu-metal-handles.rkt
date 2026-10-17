#lang racket/base

;;;
;;; Metal Handle Ownership
;;;

;; Owns retained Metal devices and queues on their creator thread.
;; Shares native handle checks between Metal contexts and interoperation.

;; PRIVATE borrowed device/queue registry. Ganesh is the owner. No extra retain
;; is transferred to this table; entries are removed BEFORE its destructor.
;; Access must be nested in a validated live domain-pointer operation.
(require ffi/unsafe)
(provide register-metal-handles! forget-metal-handles! call-with-metal-handles)
(struct handles (owner device queue))
;; Fields:
;;   owner: creator Racket thread. device and queue: retained Objective-C Metal objects. Native use
;;   and release obey owner-thread access checks.

; registry : hash?
;;   Maps native context identities to their owner thread and retained Metal device/queue handles.
(define registry (make-hasheqv))
; key : cpointer? -> exact-positive-integer?
;;   Uses the numeric native address as the registry key, independently of pointer-wrapper identity.
(define (key p) (if (cpointer? p) (cast p _pointer _uintptr) p))
; register-metal-handles! : cpointer? cpointer? cpointer? -> void?
;;   Registers a context's retained device and queue together with their creator thread.
(define (register-metal-handles! context device queue)
  (when (hash-has-key? registry (key context))
    (error 'make-gpu-context "duplicate owned Metal context pointer"))
  (hash-set! registry (key context) (handles (current-thread) device queue)))
; forget-metal-handles! : cpointer? -> void?
;;   Removes the context's borrowed-handle registry entry during driver teardown.
(define (forget-metal-handles! context) (hash-remove! registry (key context)))
; call-with-metal-handles : cpointer? procedure? -> any
;;   Lends device and queue pointers only from the registered owning thread.
(define (call-with-metal-handles context proc)
  (define h (hash-ref registry (key context)
                      (lambda () (error 'gpu-presenter "not a live owned Metal context"))))
  (unless (eq? (handles-owner h) (current-thread))
    (error 'gpu-presenter "Metal command queue belongs to another execution owner"))
  (proc (handles-device h) (handles-queue h)))
