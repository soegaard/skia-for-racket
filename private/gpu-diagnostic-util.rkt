#lang racket/base

;;;
;;; GPU Diagnostic Conversion
;;;

;; Checks diagnostic values and converts native reports to detached Racket data.
;; Keeps public GPU diagnostics independent of native buffer lifetimes.

;; Validation only. Importing this module performs no native/GUI initialization.
(provide gl-interface-modes check-gl-interface-mode checked-gl-extension
         check-gl-interface-backend check-owned-egl-interface-mode gl-version-standard)
; gl-interface-modes : vector?
;;   Lists supported native and assembled GL interface requests in stable display order.
(define gl-interface-modes (vector-immutable 'default 'auto 'desktop 'gles 'webgl))
; check-gl-interface-mode : symbol? any/c -> any
;;   Checks that an interface request names one of the supported GL assembly modes.
(define (check-gl-interface-mode who mode)
  (unless (memq mode '(default auto desktop gles webgl))
    (raise-argument-error who "'default, 'auto, 'desktop, 'gles or 'webgl" mode))
  mode)
; check-gl-interface-backend : symbol? any/c any/c -> void?
;;   Restricts nondefault GL interface selection to OpenGL providers.
(define (check-gl-interface-backend who backend mode)
  (check-gl-interface-mode who mode)
  (when (and (not (eq? mode 'default)) (not (eq? backend 'opengl)))
    (raise-arguments-error who "#:gl-interface is only supported for OpenGL providers"
                           "backend" backend "interface mode" mode))
  (void))
; check-owned-egl-interface-mode : symbol? any/c -> any
;;   Prevents an owned desktop-EGL context from being mislabeled as GLES or WebGL.
(define (check-owned-egl-interface-mode who mode)
  (check-gl-interface-mode who mode)
  ;; The existing owned EGL provider creates desktop OpenGL. Selecting a
  ;; different assembler must not pretend to create an ES or browser context.
  (unless (memq mode '(default auto desktop))
    (raise-arguments-error who
      "owned EGL creates desktop OpenGL; GLES/WebGL require an explicitly supplied matching provider"
      "interface mode" mode))
  mode)
; checked-gl-extension : symbol? string? -> string?
;;   Copies a bounded ASCII extension identifier after rejecting whitespace and embedded NUL.
(define (checked-gl-extension who value)
  (unless (and (string? value) (<= 1 (string-length value) 255)
               (regexp-match? #px"^[A-Za-z][A-Za-z0-9_]*$" value))
    (raise-argument-error who
      "ASCII extension identifier, 1 through 255 characters, without whitespace/NUL" value))
  (string->immutable-string value))

;; Match the pinned GrGLUtil.cpp categories, checking WebGL before generic ES.
; gl-version-standard : any/c -> (or/c #f symbol?)
;;   Classifies native GL version text, checking the WebGL form before generic GLES.
(define (gl-version-standard value)
  (cond [(not (string? value)) #f]
        [(regexp-match? #px"^[0-9]+\\.[0-9]+" value) 'desktop]
        [(regexp-match? #px"^OpenGL ES [0-9]+\\.[0-9]+ \\(WebGL [0-9]+\\.[0-9]+" value) 'webgl]
        [(regexp-match? #px"^OpenGL ES [0-9]+\\.[0-9]+" value) 'gles]
        [else #f]))
