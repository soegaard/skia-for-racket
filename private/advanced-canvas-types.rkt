#lang racket/base

;;;
;;; Advanced Canvas Layouts
;;;

;; Defines the native save-layer record passed to the pinned Skia ABI.
;; Supplies the low-level layout used by the public advanced-canvas operations.

(require ffi/unsafe)
(provide (all-defined-out))
;; include/c/sk_types.h at 40f75dc0051d141913c07c20d4c19590c7da0cb7.
;; The C shim converts this C record to C++; it is NOT a C++ SaveLayerRec.
;; Three pointers followed by a C enum: 32 bytes on the supported 64-bit ABI.
(define-cstruct _sk-save-layer-rec
  ([bounds _pointer] [paint _pointer] [backdrop _pointer] [flags _int]))
;; Fields:
;;   bounds: optional borrowed rectangle pointer. paint: optional layer paint pointer. backdrop:
;;   optional image-filter pointer. flags: native save-layer bitmask. Pointers remain live for the
;;   synchronous save-layer call; field order is the pinned C ABI.
