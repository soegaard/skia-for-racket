#lang racket/base

;;;
;;; Scoped GPU Drawing Contexts
;;;

;; Supplies drawing-context adapters during a GPU frame or surface callback.
;; This public bridge preserves the active GPU lease while adapting it to the supported Racket
;; drawing-context interface.

;;;
;;; Imports and Exports
;;;

;; Explicit, headless-safe entry point. Native GPU code is loaded on first use,
;; never by importing this module or querying its declaration/predicate.
(require racket/runtime-path "surface-properties.rkt" "private/gpu-format-util.rkt"
         "private/gpu-dc-scope.rkt"
         (only-in "private/gpu-presenter.rkt" gpu-frame? gpu-frame-canvas))
(provide call-with-gpu-frame-dc call-with-gpu-surface-dc
         skia-gpu-dc? skia-gpu-dc-capabilities)

;;;
;;; Lazy Drawing-Context Bridge
;;;

; native-module : path?
;   Locates private/gpu-dc-native.rkt for lazy loading of the selected implementation.
(define-runtime-path native-module "private/gpu-dc-native.rkt")

; check-callback : symbol? procedure? -> void?
;   Requires a one-argument DC callback and rejects nested GPU drawing-context scopes.
(define (check-callback who proc)
  (unless (and (procedure? proc) (procedure-arity-includes? proc 1))
    (raise-argument-error who "procedure accepting one DC argument" proc))
  (when (gpu-dc-scope-active?) (error who "nested GPU DC scopes are not supported")))

;;;
;;; Frame and Surface Drawing Scopes
;;;

; call-with-gpu-frame-dc : gpu-frame? (-> (is-a?/c draw:dc<%>) any) [#:background (or/c string?
;   (is-a?/c draw:color%))] [#:smoothing (or/c 'unsmoothed 'smoothed 'aligned)] [#:color-type (or/c
;   'rgba-8888 'bgra-8888 'rgba-f16 'rgba-f32)]
;   [#:color-space (or/c color-space? #f 'srgb 'linear-srgb bytes?)]
;   [#:sample-count (integer-in 0 64)] [#:surface-properties surface-properties?] -> any
;   Calls proc with a fresh GPU drawing context for a live presenter frame and returns the
;   callback's values.
(define (call-with-gpu-frame-dc frame proc
                               #:background [background "white"]
                               #:smoothing [smoothing 'smoothed]
                               #:color-type [color-type 'rgba-8888]
                               #:color-space [color-space #f]
                               #:sample-count [samples 0]
                               #:surface-properties [properties (make-surface-properties)])
  (check-callback 'call-with-gpu-frame-dc proc)
  (unless (gpu-frame? frame) (raise-argument-error 'call-with-gpu-frame-dc "gpu-frame?" frame))
  (gpu-frame-canvas frame) ; owner/expiry rejection before loading native code
  ((dynamic-require native-module 'call-with-gpu-frame-dc/native)
   frame proc background smoothing color-type color-space samples properties))

; call-with-gpu-surface-dc : gpu-surface? (-> (is-a?/c draw:dc<%>) any) [#:logical-width (or/c #f
;   (and/c real? (>/c 0)))] [#:logical-height (or/c #f (and/c real? (>/c 0)))] [#:background (or/c
;   string? (is-a?/c draw:color%))] [#:smoothing (or/c 'unsmoothed 'smoothed 'aligned)] [#:clear?
;   boolean?] -> any
;   Calls proc with a fresh DC borrowing surface and returns the callback's values.
(define (call-with-gpu-surface-dc surface proc
                                 #:logical-width [logical-width #f]
                                 #:logical-height [logical-height #f]
                                 #:background [background "white"]
                                 #:smoothing [smoothing 'smoothed]
                                 #:clear? [clear? #f])
  (check-callback 'call-with-gpu-surface-dc proc)
  ((dynamic-require native-module 'call-with-gpu-surface-dc/native)
   surface proc logical-width logical-height background smoothing clear?))
