#lang racket/base

;;;
;;; Native Font Description Parsing
;;;

;; Loads platform font-description support lazily and copies parsed font attributes.
;; Supports racket/draw font-name compatibility without eagerly loading a GUI backend.

;; Private, parsing-only Pango bridge. No font map, layout, Cairo context,
;; drawing, system font lookup, or Skia library is initialized here.
;; Reuse the public Pango library handle when draw-lib provides it. Racket
;; 8.18/9.3 (draw-lib 1.22-1.24) keep that handle private inside unsafe/pango,
;; so reproduce only their platform library-loading rule in that case.

;;;
;;; Imports and Exports
;;;

(require ffi/unsafe
         (only-in racket/draw/unsafe/cairo cairo-lock-name))
(provide parse-font-description)

;;;
;;; Library Selection and Retention
;;;

; legacy-pango-dependencies : (listof ffi-lib?)
;   Keeps preloaded platform dependency handles reachable for the lifetime of the legacy Pango
;   bridge.
(define legacy-pango-dependencies '())

; retain-legacy-lib! : ffi-lib? -> ffi-lib?
;   Retains and returns a dependency handle loaded before the legacy Pango library.
(define (retain-legacy-lib! lib)
  ;; Match racket/draw's old preload ordering and keep the dependency handle
  ;; reachable for this module's lifetime.
  (set! legacy-pango-dependencies (cons lib legacy-pango-dependencies))
  lib)

; legacy-pango-lib : -> ffi-lib?
;   Loads Pango using the platform filenames and dependency order of older draw-lib releases.
(define (legacy-pango-lib)
  (case (system-type)
    [(unix)
     (ffi-lib "libpango-1.0" '("0" ""))]
    [(macosx)
     (retain-legacy-lib! (ffi-lib "libfribidi.0.dylib"))
     (ffi-lib "libpango-1.0.0.dylib")]
    [(windows)
     (retain-legacy-lib! (ffi-lib "libfribidi-0.dll"))
     (ffi-lib "libpango-1.0-0.dll")]
    [else
     (error 'dc-font-description "unsupported platform for Racket Pango library")]))

; pango-lib : ffi-lib?
;   Uses draw-lib's shared Pango handle when available, with the legacy loading rule as a
;   compatibility fallback.
(define pango-lib
  (with-handlers ([exn:fail:filesystem:missing-module?
                   (lambda (_e) (legacy-pango-lib))])
    ;; Added by draw-lib 1.25. Keep this dynamic so compiling against the
    ;; supported 1.22-1.24 releases does not require a nonexistent module.
    (dynamic-require 'racket/draw/unsafe/pango-lib 'pango-lib)))

;;;
;;; Serialized Pango Parsing Calls
;;;

; _pfun : syntax
;   Constructs a Pango foreign-function type using the same serialization lock as racket/draw.
(define-syntax-rule (_pfun spec ...)
  (_fun #:lock-name (or cairo-lock-name "pango-lock") spec ...))

; from-string : string? -> (or/c #f cpointer?)
;   Allocates a Pango font description; the caller must free a successful result.
(define from-string
  (get-ffi-obj "pango_font_description_from_string" pango-lib
               (_pfun _string/utf-8 -> _pointer)))

; free-description : cpointer? -> void?
;   Releases a Pango font description allocated by from-string.
(define free-description
  (get-ffi-obj "pango_font_description_free" pango-lib (_pfun _pointer -> _void)))

; get-family : cpointer? -> (or/c #f string?)
;   Copies the parsed family name from a live Pango description.
(define get-family
  (get-ffi-obj "pango_font_description_get_family" pango-lib
               (_pfun _pointer -> _string/utf-8)))

; get-weight : cpointer? -> exact-integer?
;   Reads the Pango numeric font weight from a live description.
(define get-weight
  (get-ffi-obj "pango_font_description_get_weight" pango-lib (_pfun _pointer -> _int)))

; get-style : cpointer? -> exact-integer?
;   Reads the Pango style enum: normal, oblique, or italic.
(define get-style
  (get-ffi-obj "pango_font_description_get_style" pango-lib (_pfun _pointer -> _int)))

; get-stretch : cpointer? -> exact-integer?
;   Reads the Pango stretch enum, from ultra-condensed through ultra-expanded.
(define get-stretch
  (get-ffi-obj "pango_font_description_get_stretch" pango-lib (_pfun _pointer -> _int)))

; get-variant : cpointer? -> exact-integer?
;   Reads the Pango variant enum so the adapter can reject unsupported variants.
(define get-variant
  (get-ffi-obj "pango_font_description_get_variant" pango-lib (_pfun _pointer -> _int)))

; get-fields : cpointer? -> exact-nonnegative-integer?
;   Reads the explicitly set field bitmask for compatibility validation.
(define get-fields
  (get-ffi-obj "pango_font_description_get_set_fields" pango-lib (_pfun _pointer -> _uint)))

; parse-font-description : string? -> vector?
;   Returns copied family, weight, style, stretch, variant, and field-mask values, freeing the native
;   description on every exit.
(define (parse-font-description text)
  ;; The caller validates and copies the name before reaching this boundary.
  ;; Raw ownership is local: no finalizer, native pointer, or description can
  ;; escape. Mask breaks across allocation/free, including exceptional exits.
  (call-with-continuation-barrier
   (lambda ()
     (parameterize-break #f
       (define description (from-string text))
       (unless description (error 'dc-font-description "Pango description allocation failed"))
       (dynamic-wind
        void
        (lambda ()
          (vector-immutable (string->immutable-string (or (get-family description) ""))
                            (get-weight description) (get-style description)
                            (get-stretch description) (get-variant description)
                            (get-fields description)))
        (lambda () (free-description description)))))))
