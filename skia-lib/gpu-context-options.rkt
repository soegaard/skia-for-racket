#lang racket/base

;;;
;;; GPU Context Options
;;;

;; Validates detached options used to construct native GPU contexts.
;; This public metadata module provides reusable context configuration and report serialization
;; independently of GPU initialization.

;;;
;;; Exports
;;;

;; Pure detached configuration. Import performs no native initialization.
(provide gpu-context-options? make-gpu-context-options
         gpu-context-options-avoid-stencil-buffers?
         gpu-context-options-runtime-program-cache-size
         gpu-context-options-glyph-cache-texture-maximum-bytes
         gpu-context-options-allow-path-mask-caching?
         gpu-context-options-manual-mipmapping?
         gpu-context-options-buffer-map-threshold gpu-context-options->jsexpr)

;;;
;;; Context Option Values and Validation
;;;

(struct gpu-context-options
  (avoid-stencil-buffers? runtime-program-cache-size glyph-cache-texture-maximum-bytes
   allow-path-mask-caching? manual-mipmapping? buffer-map-threshold)
  #:transparent #:constructor-name make-options-record)
;; A gpu-context-options value contains immutable requests for native creation.
;;  - avoid-stencil-buffers?             boolean?  Requests stencil avoidance.
;;  - runtime-program-cache-size        integer?  Program-entry limit, 1..2^31-1.
;;  - glyph-cache-texture-maximum-bytes  integer?  Glyph-texture bytes, 1..2^64-1.
;;  - allow-path-mask-caching?          boolean?  Permits path-mask caching.
;;  - manual-mipmapping?                boolean?  Requests manual mipmap handling.
;;  - buffer-map-threshold              integer?  Native threshold, -1..2^31-1;
;;                                               -1 leaves the native default.
;; Integer fields are exact. Requests are copied during context construction;
;; the value neither owns a GPU context nor reports the driver's effective state.

; boolean! : symbol? boolean? -> void?
;   Rejects a nonboolean option before native context creation is attempted.
(define (boolean! who value)
  (unless (boolean? value) (raise-argument-error who "boolean?" value)))

; integer! : symbol? exact-integer? exact-integer? exact-integer? string? -> void?
;   Checks an exact option value against inclusive native integer bounds.
(define (integer! who value lower upper description)
  (unless (and (exact-integer? value) (<= lower value upper))
    (raise-argument-error who description value)))

; make-gpu-context-options : [#:avoid-stencil-buffers? boolean?] [#:runtime-program-cache-size
;   (integer-in 1 2147483647)] [#:glyph-cache-texture-maximum-bytes (integer-in 1
;   18446744073709551615)] [#:allow-path-mask-caching? boolean?] [#:manual-mipmapping? boolean?]
;   [#:buffer-map-threshold (integer-in -1 2147483647)] -> gpu-context-options?
;   Creates validated immutable requests to be copied during native context construction.
(define (make-gpu-context-options
         #:avoid-stencil-buffers? [stencil? #f]
         #:runtime-program-cache-size [programs 256]
         #:glyph-cache-texture-maximum-bytes [glyphs 8388608]
         #:allow-path-mask-caching? [paths? #t]
         #:manual-mipmapping? [mipmaps? #f]
         #:buffer-map-threshold [threshold -1])
  (define who 'make-gpu-context-options)
  (for ([v (in-list (list stencil? paths? mipmaps?))]) (boolean! who v))
  (integer! who programs 1 #x7fffffff "positive exact program-cache entry count <= 2147483647")
  (integer! who glyphs 1 #xffffffffffffffff "positive exact 64-bit glyph-texture byte budget")
  (integer! who threshold -1 #x7fffffff "exact buffer-map threshold -1 through 2147483647")
  (make-options-record stencil? programs glyphs paths? mipmaps? threshold))

;;;
;;; Detached Option Reports
;;;

; gpu-context-options->jsexpr : gpu-context-options? -> (and/c hash? immutable?)
;   Returns an immutable JSON-compatible hash with keys 'avoid_stencil_buffers,
;   'runtime_program_cache_size, 'glyph_cache_texture_maximum_bytes, 'allow_path_mask_caching,
;   'manual_mipmapping, and 'buffer_map_threshold.
(define (gpu-context-options->jsexpr value)
  (unless (gpu-context-options? value)
    (raise-argument-error 'gpu-context-options->jsexpr "gpu-context-options?" value))
  (hasheq 'avoid_stencil_buffers (gpu-context-options-avoid-stencil-buffers? value)
          'runtime_program_cache_size (gpu-context-options-runtime-program-cache-size value)
          'glyph_cache_texture_maximum_bytes
          (gpu-context-options-glyph-cache-texture-maximum-bytes value)
          'allow_path_mask_caching (gpu-context-options-allow-path-mask-caching? value)
          'manual_mipmapping (gpu-context-options-manual-mipmapping? value)
          'buffer_map_threshold (gpu-context-options-buffer-map-threshold value)))

;;;
;;; Internal Option Encoding
;;;

(module* internals #f
  (provide check-optional-context-options context-options-diagnostics add-context-options-diagnostics)

  ; check-optional-context-options : symbol? any/c -> (or/c #f gpu-context-options?)
  ;   Checks optional factory settings, retaining #f to request native defaults.
  (define (check-optional-context-options who value)
    (unless (or (not value) (gpu-context-options? value))
      (raise-argument-error who "#f or gpu-context-options?" value))
    value)

  ; context-options-diagnostics : (or/c #f gpu-context-options?) symbol? -> hash?
  ;   Describes requested options and factory selection without claiming native readback.
  (define (context-options-diagnostics options backend)
    (check-optional-context-options 'context-options-diagnostics options)
    (define factory
      (case backend
        [(opengl) "gr_direct_context_make_gl"]
        [(metal) "gr_direct_context_make_metal"]
        [(direct3d) "gr_direct_context_make_direct3d"]
        [else
         (raise-argument-error 'context-options-diagnostics "'opengl, 'metal or 'direct3d" backend)]))
    (hasheq 'context_factory
            (string->immutable-string (if options (string-append factory "_with_options") factory))
            'context_options_source (if options "explicit" "native-defaults")
            'context_options (and options (gpu-context-options->jsexpr options))))

  ; add-context-options-diagnostics : hash? (or/c #f gpu-context-options?) symbol? -> hash?
  ;   Adds factory and requested-option metadata to immutable context diagnostics.
  (define (add-context-options-diagnostics details options backend)
    (for/fold ([result details])
              ([(key value) (in-hash (context-options-diagnostics options backend))])
      (hash-set result key value))))
