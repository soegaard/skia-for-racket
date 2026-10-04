#lang racket/base
;; Private, parsing-only Pango bridge. No font map, layout, Cairo context,
;; drawing, system font lookup, or Skia library is initialized here.
;; Reuse the public Pango library handle when draw-lib provides it. Racket
;; 8.18/9.3 (draw-lib 1.22-1.24) keep that handle private inside unsafe/pango,
;; so reproduce only their platform library-loading rule in that case.
(require ffi/unsafe
         (only-in racket/draw/unsafe/cairo cairo-lock-name))
(provide parse-font-description)

(define legacy-pango-dependencies '())
(define (retain-legacy-lib! lib)
  ;; Match racket/draw's old preload ordering and keep the dependency handle
  ;; reachable for this module's lifetime.
  (set! legacy-pango-dependencies (cons lib legacy-pango-dependencies))
  lib)
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

(define pango-lib
  (with-handlers ([exn:fail:filesystem:missing-module?
                   (lambda (_e) (legacy-pango-lib))])
    ;; Added by draw-lib 1.25. Keep this dynamic so compiling against the
    ;; supported 1.22-1.24 releases does not require a nonexistent module.
    (dynamic-require 'racket/draw/unsafe/pango-lib 'pango-lib)))

(define-syntax-rule (_pfun spec ...)
  (_fun #:lock-name (or cairo-lock-name "pango-lock") spec ...))
(define from-string
  (get-ffi-obj "pango_font_description_from_string" pango-lib
               (_pfun _string/utf-8 -> _pointer)))
(define free-description
  (get-ffi-obj "pango_font_description_free" pango-lib (_pfun _pointer -> _void)))
(define get-family
  (get-ffi-obj "pango_font_description_get_family" pango-lib
               (_pfun _pointer -> _string/utf-8)))
(define get-weight
  (get-ffi-obj "pango_font_description_get_weight" pango-lib (_pfun _pointer -> _int)))
(define get-style
  (get-ffi-obj "pango_font_description_get_style" pango-lib (_pfun _pointer -> _int)))
(define get-stretch
  (get-ffi-obj "pango_font_description_get_stretch" pango-lib (_pfun _pointer -> _int)))
(define get-variant
  (get-ffi-obj "pango_font_description_get_variant" pango-lib (_pfun _pointer -> _int)))
(define get-fields
  (get-ffi-obj "pango_font_description_get_set_fields" pango-lib (_pfun _pointer -> _uint)))
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
