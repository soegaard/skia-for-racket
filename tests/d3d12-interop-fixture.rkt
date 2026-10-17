#lang racket/base

;;;
;;; Direct3D Interop Fixture Bindings
;;;

;; Loads the independent Windows texture producer and exposes its checked C entry points.
;; These bindings let interop tests distinguish external COM ownership from Skia ownership.

;;;
;;; Imports and Exports
;;;

;; Test-only independent native producer/consumer. The runtime library never
;; imports this file or builds/loads this DLL.
(require ffi/unsafe "../gpu.rkt" "../unsafe/gpu-d3d12.rkt")
(provide load-interop-fixture make-fixture fixture-texture fixture-fence close-fixture
         drop-fixture-texture fixture-description fixture-readback fixture-unsignaled
         fixture-release fixture-foreign fixture-foreign-live fixture-foreign-desc-calls)

;;;
;;; Fixture Library Loading and Native Calls
;;;

; library : (or/c ffi-lib? #f)
;   Retains the explicitly loaded independent Windows fixture library.
(define library #f)

; load-interop-fixture : path-string? -> void?
;   Loads a fixture and rejects non-Windows-SDK builds before any texture calls.
(define (load-interop-fixture path)
  (set! library (ffi-lib path))
  (unless (= ((get-ffi-obj "interop_fixture_kind" library (_fun -> _uint32))) 1)
    (error 'interop-fixture "requires the real Windows SDK build")))

; function : string? ctype? -> procedure?
;   Resolves an entry point only after the fixture library has been loaded.
(define (function name type)
  (unless library (error 'interop-fixture "fixture is not loaded"))
  (get-ffi-obj name library type))

; checked : exact-integer? -> void?
;   Rejects a failed HRESULT and prints its unsigned hexadecimal representation.
(define (checked code)
  (unless (zero? code)
    (error 'interop-fixture "HRESULT 0x~a" (number->string (bitwise-and code #xffffffff) 16))))

; out-pointer : procedure? -> cpointer?
;   Initializes an out-pointer, checks the HRESULT, and rejects a null success result.
(define (out-pointer call)
  (define out (malloc _pointer 'atomic)) (ptr-set! out _pointer #f)
  (checked (call out)) (or (ptr-ref out _pointer) (error 'interop-fixture "null result")))

;;;
;;; Texture, Fence, and Foreign-Device Fixtures
;;;

; make-fixture : gpu-context? [exact-positive-integer? exact-positive-integer?
; exact-nonnegative-integer?] -> cpointer?
;   Creates an independently owned texture fixture on the context's device.
(define (make-fixture c [w 37] [h 29] [kind 0])
  (call-with-gpu-d3d12-device c
    (lambda (device) (out-pointer (lambda (out)
      ((function "interop_fixture_create" (_fun _pointer _uint32 _uint32 _uint32 _pointer -> _int32))
       device w h kind out))))))

; fixture-texture : cpointer? -> cpointer?
;   Borrows the fixture's external texture pointer for Skia handoff.
(define (fixture-texture f) ((function "interop_fixture_texture" (_fun _pointer -> _pointer)) f))

; fixture-fence : cpointer? -> cpointer?
;   Borrows the fixture's synchronization fence.
(define (fixture-fence f) ((function "interop_fixture_fence" (_fun _pointer -> _pointer)) f))

; close-fixture : cpointer? -> void?
;   Closes the native fixture and checks teardown status.
(define (close-fixture f) (checked ((function "interop_fixture_close" (_fun _pointer -> _int32)) f)))

; drop-fixture-texture : cpointer? -> void?
;   Drops the producer's texture reference to test retention by the imported wrapper.
(define (drop-fixture-texture f)
  (checked ((function "interop_fixture_drop_texture" (_fun _pointer -> _int32)) f)))

; fixture-description : cpointer? -> (listof exact-nonnegative-integer?)
;   Copies the nine native descriptor words in the fixture ABI's declared order.
(define (fixture-description f)
  (define p (malloc (* 9 8) 'atomic))
  (checked ((function "interop_fixture_descriptor" (_fun _pointer _pointer _size -> _int32)) f p 9))
  (for/list ([i (in-range 9)]) (ptr-ref p _uint64 i)))

; fixture-readback : cpointer? exact-nonnegative-integer? exact-positive-integer?
; exact-positive-integer? -> bytes?
;   Reads RGBA bytes after handing the resource back in the specified native state.
(define (fixture-readback f state w h)
  (define bytes (make-bytes (* w h 4)))
  (checked ((function "interop_fixture_readback" (_fun _pointer _uint32 _bytes _size -> _int32))
            f state bytes (bytes-length bytes))) bytes)

; fixture-unsignaled : cpointer? -> cpointer?
;   Creates an owned unsignaled fence for timeout tests; the caller releases it.
(define (fixture-unsignaled f)
  (out-pointer (lambda (out)
                 ((function "interop_fixture_unsignaled_fence" (_fun _pointer _pointer -> _int32))
                   f out))))

; fixture-release : cpointer? -> void?
;   Releases an independently acquired COM reference through the fixture ABI.
(define (fixture-release p) ((function "interop_fixture_release" (_fun _pointer -> _void)) p))

; fixture-foreign : -> cpointer?
;   Creates a foreign resource used to test rejection before descriptor access.
(define (fixture-foreign) ((function "interop_fixture_foreign_resource" (_fun -> _pointer))))

; fixture-foreign-live : -> exact-nonnegative-integer?
;   Reports outstanding foreign-resource instances for cleanup assertions.
(define (fixture-foreign-live) ((function "interop_fixture_foreign_live" (_fun -> _uint32))))

; fixture-foreign-desc-calls : -> exact-nonnegative-integer?
;   Reports descriptor accesses so rejection-before-use can be verified.
(define (fixture-foreign-desc-calls)
  ((function "interop_fixture_foreign_desc_calls" (_fun -> _uint32))))
