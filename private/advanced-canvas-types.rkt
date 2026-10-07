#lang racket/base
(require ffi/unsafe)
(provide (all-defined-out))
;; include/c/sk_types.h at 40f75dc0051d141913c07c20d4c19590c7da0cb7.
;; The C shim converts this C record to C++; it is NOT a C++ SaveLayerRec.
;; Three pointers followed by a C enum: 32 bytes on the supported 64-bit ABI.
(define-cstruct _sk-save-layer-rec
  ([bounds _pointer] [paint _pointer] [backdrop _pointer] [flags _int]))
