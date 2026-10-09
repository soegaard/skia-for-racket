#lang racket/base
;; Validation only. Importing this module performs no native/GUI initialization.
(provide gl-interface-modes check-gl-interface-mode checked-gl-extension
         check-gl-interface-backend check-owned-egl-interface-mode gl-version-standard)
(define gl-interface-modes (vector-immutable 'default 'auto 'desktop 'gles 'webgl))
(define (check-gl-interface-mode who mode)
  (unless (memq mode '(default auto desktop gles webgl))
    (raise-argument-error who "'default, 'auto, 'desktop, 'gles or 'webgl" mode))
  mode)
(define (check-gl-interface-backend who backend mode)
  (check-gl-interface-mode who mode)
  (when (and (not (eq? mode 'default)) (not (eq? backend 'opengl)))
    (raise-arguments-error who "#:gl-interface is only supported for OpenGL providers"
                           "backend" backend "interface mode" mode))
  (void))
(define (check-owned-egl-interface-mode who mode)
  (check-gl-interface-mode who mode)
  ;; The existing owned EGL provider creates desktop OpenGL. Selecting a
  ;; different assembler must not pretend to create an ES or browser context.
  (unless (memq mode '(default auto desktop))
    (raise-arguments-error who
      "owned EGL creates desktop OpenGL; GLES/WebGL require an explicitly supplied matching provider"
      "interface mode" mode))
  mode)
(define (checked-gl-extension who value)
  (unless (and (string? value) (<= 1 (string-length value) 255)
               (regexp-match? #px"^[A-Za-z][A-Za-z0-9_]*$" value))
    (raise-argument-error who "ASCII extension identifier, 1 through 255 characters, without whitespace/NUL" value))
  (string->immutable-string value))

;; Match the pinned GrGLUtil.cpp categories, checking WebGL before generic ES.
(define (gl-version-standard value)
  (cond [(not (string? value)) #f]
        [(regexp-match? #px"^[0-9]+\\.[0-9]+" value) 'desktop]
        [(regexp-match? #px"^OpenGL ES [0-9]+\\.[0-9]+ \\(WebGL [0-9]+\\.[0-9]+" value) 'webgl]
        [(regexp-match? #px"^OpenGL ES [0-9]+\\.[0-9]+" value) 'gles]
        [else #f]))
