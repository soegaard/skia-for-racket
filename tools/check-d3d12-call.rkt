#lang racket/base

;;;
;;; Direct3D By-Value ABI Probe
;;;

;; Compares a native fixture call with Racket's Direct3D structure-passing layout.
;; This executable supports the Windows ABI checks before full renderer integration.

;;;
;;; Imports and Exports
;;;
(require ffi/unsafe json "../private/gpu-d3d12-types.rkt")
(module+ main

  ;;;
  ;;; Command-Line Run
  ;;;

  ; args : (vectorof string?)
  ;   Supplies the ABI fixture library path to the by-value calling-convention probe.
  (define args (current-command-line-arguments))
  (unless (= (vector-length args) 1) (error 'check-d3d12-call "expected C fixture library path"))
  (check-d3d12-layouts!)

  ; library : ffi-lib?
  ;   Keeps the specified ABI fixture library loaded while its echo procedure is invoked.
  (define library (ffi-lib (vector-ref args 0)))

  ; echo : cpointer? -> exact-nonnegative-integer?
  ;   Calls the fixture's by-value Direct3D backend-context echo to verify field transport across
  ;   the FFI.
  (define echo (get-ffi-obj "d3d12_abi_echo" library (_fun _gr-d3d-backend-context -> _uint64)))
  (for ([protected? '(#f #t)] [expected '(15 31)])
    (define value (make-gr-d3d-backend-context (cast #x1110 _uintptr _pointer)
                                             (cast #x2220 _uintptr _pointer)
                                             (cast #x3330 _uintptr _pointer) #f protected?))
    (unless (= (echo value) expected) (error 'check-d3d12-call "by-value descriptor call failed")))
  (write-json (hasheq 'status "passed" 'by_value_call_verified #t 'gpu_execution_verified #f))
  (newline))
