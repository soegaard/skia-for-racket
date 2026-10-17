#lang racket/base

;;;
;;; Native GPU Context Options
;;;

;; Builds the pinned native options record for Ganesh context creation.
;; Keeps context tuning values aligned with the native ABI.

(require ffi/unsafe "../gpu-context-options.rkt"
         (submod "../gpu-context-options.rkt" internals))
(provide context-options-abi call-with-native-context-options)
;; Pinned include/c/sk_types.h gr_context_options_t; no pointers are retained.
(define-cstruct _gr-context-options
  ([avoid-stencil _stdbool] [program-cache _int32] [glyph-bytes _size]
   [path-cache _stdbool] [manual-mipmaps _stdbool] [map-threshold _int32])
  #:malloc-mode 'atomic-interior)
;; Fields:
;;   avoid-stencil, path-cache, and manual-mipmaps: native C booleans controlling stencil avoidance,
;;   path caching, and manual mipmap generation. program-cache: signed program-cache limit.
;;   glyph-bytes: size_t glyph-cache budget. map-threshold: signed buffer-mapping threshold.
;;   Declaration order and padding match the pinned context-options ABI; option validation occurs
;;   before construction.

; context-options-abi : -> hash?
;;   Verifies reviewed 64-bit size, alignment, and scalar widths before constructing context
;;   options.
(define (context-options-abi)
  (unless (and (= (ctype-sizeof _pointer) 8) (= (ctype-sizeof _size) 8)
               (= (ctype-sizeof _int32) 4) (= (ctype-sizeof _stdbool) 1)
               (= (ctype-sizeof _gr-context-options) 24) (= (ctype-alignof _gr-context-options) 8))
    (error 'gpu-context-options
      "unsupported context-options ABI; expected reviewed 64-bit m119 layout"))
  (hasheq 'size (ctype-sizeof _gr-context-options) 'alignment (ctype-alignof _gr-context-options)
          'pointer_bytes (ctype-sizeof _pointer) 'bool_bytes (ctype-sizeof _stdbool)
          'offsets '(0 4 8 16 17 20)))
; call-with-native-context-options : symbol? any/c procedure? -> any
;;   Lends a pinned options record to one native constructor, preserving #f for native defaults.
(define (call-with-native-context-options who options proc)
  (check-optional-context-options who options)
  (unless (and (procedure? proc) (procedure-arity-includes? proc 1))
    (raise-argument-error who "one-argument native option consumer" proc))
  (cond
    [(not options) (proc #f)]
    [else
     (context-options-abi)
     (define record
       (make-gr-context-options
         (gpu-context-options-avoid-stencil-buffers? options)
         (gpu-context-options-runtime-program-cache-size options)
         (gpu-context-options-glyph-cache-texture-maximum-bytes options)
         (gpu-context-options-allow-path-mask-caching? options)
         (gpu-context-options-manual-mipmapping? options)
         (gpu-context-options-buffer-map-threshold options)))
     (begin0 (proc record) (void/reference-sink record options))]))
