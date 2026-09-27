#lang racket/base
(require ffi/unsafe "gpu-provider.rkt" "gpu-diagnostics.rkt")
(provide make-system-gl-tools)
(define (make-system-gl-tools)
  (define os (system-type 'os))
  ;; Windows x86 uses different GL calling conventions. Do not accidentally
  ;; invoke those functions through this x64 ABI, even with a library override.
  (when (and (eq? os 'windows) (not (eq? (system-type 'arch) 'x86_64)))
    (gpu-unavailable 'opengl-platform "the built-in Windows GL adapter requires x64 Racket"))
  (define lib
    (with-handlers ([exn:fail? (lambda (e) (gpu-unavailable 'opengl-library "~a" (exn-message e)))])
      (ffi-lib
       (case os
         [(macosx) "/System/Library/Frameworks/OpenGL.framework/OpenGL"]
         [(windows) "opengl32.dll"]
         [(unix) "libGL.so.1"]
         [else (gpu-unavailable 'opengl-library "unsupported native GL platform: ~a" os)]))))
  (define current
    (get-ffi-obj (case os [(macosx) "CGLGetCurrentContext"]
                          [(windows) "wglGetCurrentContext"] [else "glXGetCurrentContext"])
                 lib (_fun -> _pointer)))
  (define get-string (get-ffi-obj "glGetString" lib (_fun _uint32 -> _pointer)))
  (define get-int (get-ffi-obj "glGetIntegerv" lib (_fun _uint32 _pointer -> _void)))
  (define extension-address
    (case os
      [(windows) (get-ffi-obj "wglGetProcAddress" lib (_fun _string/utf-8 -> _pointer))]
      [(unix) (get-ffi-obj "glXGetProcAddressARB" lib (_fun _string/utf-8 -> _pointer)
                         (lambda () #f))]
      [else #f]))
  (define (key)
    (define p (current))
    (and p (cast p _pointer _uintptr)))
  (define (string-value token)
    (define p (get-string token))
    (and p (string->immutable-string (cast p _pointer _string/utf-8))))
  (define (integer-value token)
    (define p (malloc _int 'atomic))
    (ptr-set! p _int 0)
    (get-int token p)
    (ptr-ref p _int))
  (define (describe)
    (unless (key) (error 'opengl-diagnostics "there is no current native GL context"))
    (define vendor (string-value #x1F00))
    (define renderer (string-value #x1F01))
    (define version (string-value #x1F02))
    (unless (and vendor renderer version)
      (gpu-unavailable 'opengl-identity "glGetString returned null"))
    (define match (regexp-match #px"^([0-9]+)\\.([0-9]+)" version))
    (define major (and match (string->number (cadr match))))
    (define minor (and match (string->number (caddr match))))
    (hasheq 'vendor vendor 'renderer renderer 'api_version version
            'renderer_class (renderer-class vendor renderer)
            'renderer_class_evidence "driver strings; not an independent hardware attestation"
            'shading_language_version (if (and major (>= major 2)) (string-value #x8B8C) #f)
            'profile_mask (if (and major (or (> major 3) (and (= major 3) (>= minor 2))))
                              (integer-value #x9126) #f)
            'host_samples (if (and major (>= major 2)) (integer-value #x80A9) #f)))
  (define (resolve name)
    ;; wglGetProcAddress has documented non-null failure sentinels. Always try
    ;; opengl32's exports for GL 1.1 entry points as well.
    (define p (and extension-address (extension-address name)))
    (define address (and p (cast p _pointer _intptr)))
    (if (and address (not (memv address '(-1 0 1 2 3)))) p
        (get-ffi-obj name lib _fpointer (lambda () #f))))
  (values key describe resolve))
