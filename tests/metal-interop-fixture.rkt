#lang racket/base

;;;
;;; Metal Interop Fixture Bindings
;;;

;; Wraps the independent Objective-C texture producer, including readback and explicit closure.
;; These bindings provide an external ownership boundary for Metal interop regression tests.

;;;
;;; Imports and Exports
;;;
(require ffi/unsafe "../unsafe/gpu-metal.rkt")
(provide load-metal-fixture! make-metal-fixture close-metal-fixture!
         metal-fixture-texture metal-fixture-producer metal-fixture-description
         metal-fixture-readback metal-fixture-unblock!)

;;;
;;; Fixtures and Assertions
;;;

; library : (or/c ffi-lib? #f)
;   Retains the explicitly loaded independent Metal fixture library.
(define library #f)

; load-metal-fixture! : path-string? -> void?
;   Loads the Objective-C fixture without importing it as part of ordinary test-module loading.
(define (load-metal-fixture! path) (set! library (ffi-lib path)))

; define-call : syntax
;   Defines a lazily resolved native fixture call that requires explicit library loading.
(define-syntax-rule (define-call name type)
  (define (name . args)
    (unless library (error 'metal-fixture "fixture library was not explicitly loaded"))
    (apply (get-ffi-obj 'name library type) args)))

; smi_new : cpointer? exact-integer? -> (or/c cpointer? #f)
;   Creates an owned native producer variant using the borrowed Metal device.
(define-call smi_new (_fun _pointer _int -> _pointer))

; smi_texture : cpointer? -> cpointer?
;   Borrows the producer's retained Metal texture while the fixture remains live.
(define-call smi_texture (_fun _pointer -> _pointer))

; smi_producer : cpointer? -> cpointer?
;   Borrows the producer command buffer used for completion synchronization.
(define-call smi_producer (_fun _pointer -> _pointer))

; smi_describe : cpointer? cpointer? exact-nonnegative-integer? -> exact-integer?
;   Copies descriptor words into caller-owned storage and returns the native success code.
(define-call smi_describe (_fun _pointer _pointer _size -> _int))

; smi_read : cpointer? bytes? exact-nonnegative-integer? -> exact-integer?
;   Copies consumer-observed pixels into the supplied byte buffer and returns a success code.
(define-call smi_read (_fun _pointer _bytes _size -> _int))

; smi_unblock : cpointer? -> exact-integer?
;   Releases a deliberately stalled producer and returns the native success code.
(define-call smi_unblock (_fun _pointer -> _int))

; smi_close : cpointer? -> exact-integer?
;   Releases the producer's native references; the wrapper must retire its pointer first.
(define-call smi_close (_fun _pointer -> _int))

; smi_error : -> string?
;   Copies the fixture's last native error message for diagnostic failures.
(define-call smi_error (_fun -> _string/utf-8))
(struct fixture ([pointer #:mutable]))
;; pointer: mutable native fixture pointer, or #f once closed. The fixture owns
;; the producer's texture and command-buffer references; accessors lend those
;; pointers without transferring ownership. Closure clears this field before
;; calling the native destructor so the wrapper cannot be closed twice.

; check : any/c -> void?
;   Requires the fixture's success code and reports its native error message otherwise.
(define (check result)
  (unless (equal? result 1) (error 'metal-fixture "~a" (smi_error))))

; live : fixture? -> cpointer?
;   Returns the owned fixture pointer, rejecting use after closure.
(define (live f) (or (fixture-pointer f) (error 'metal-fixture "fixture is closed")))

; make-metal-fixture : gpu-context? [exact-nonnegative-integer?] -> fixture?
;   Creates an independent producer on the context's borrowed Metal device.
(define (make-metal-fixture context [variant 0])
  (define p (call-with-gpu-metal-device context (lambda (device) (smi_new device variant))))
  (unless p (error 'metal-fixture "~a" (smi_error)))
  (fixture p))

; close-metal-fixture! : fixture? -> void?
;   Clears the wrapper pointer before closing its native producer, making repeated closure
;   harmless.
(define (close-metal-fixture! f)
  (when (fixture-pointer f)
    (define p (fixture-pointer f)) (set-fixture-pointer! f #f)
    (check (smi_close p))))

; metal-fixture-texture : fixture? -> cpointer?
;   Borrows the producer texture pointer while the fixture remains live.
(define (metal-fixture-texture f) (smi_texture (live f)))

; metal-fixture-producer : fixture? -> cpointer?
;   Borrows the producer command buffer used to declare completion dependencies.
(define (metal-fixture-producer f) (smi_producer (live f)))

; metal-fixture-description : fixture? -> (listof exact-nonnegative-integer?)
;   Copies the nineteen descriptor words in the independent fixture ABI's declared order.
(define (metal-fixture-description f)
  (define buf (malloc _uint64 19))
  (check (smi_describe (live f) buf 19))
  (for/list ([i (in-range 19)]) (ptr-ref buf _uint64 i)))

; metal-fixture-readback : fixture? -> bytes?
;   Reads the producer's 37-by-29-pixel RGBA texture through the independent consumer.
(define (metal-fixture-readback f)
  (define bytes (make-bytes (* 37 29 4)))
  (check (smi_read (live f) bytes (bytes-length bytes))) bytes)

; metal-fixture-unblock! : fixture? -> void?
;   Releases the deliberately stalled producer used by synchronization tests.
(define (metal-fixture-unblock! f) (check (smi_unblock (live f))))
