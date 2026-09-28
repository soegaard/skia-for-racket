#lang racket/base
(require ffi/unsafe ffi/unsafe/global racket/promise racket/string
         "gpu-provider.rkt" "gpu-egl-util.rkt" "gpu-diagnostics.rkt")
(provide make-egl-platform-ops capture-current-egl-provider)
;; EGLBoolean and EGLenum are 32-bit, NOT C bool. EGLint is signed 32-bit.
;; GetPlatformDisplay is called with a NULL attribute list, avoiding the
;; EGLAttrib/intptr_t (core) versus EGLint (EXT) array ABI distinction.
(define EGL-OPENGL-API #x30A2)
(define EGL-NONE #x3038)
(define lib
  (delay/sync
    (unless (eq? (system-type 'os) 'unix)
      (gpu-unavailable 'egl-platform "the built-in EGL adapter supports Linux; use Metal or a native GL provider on this platform"))
    (with-handlers ([exn:fail? (lambda (e) (gpu-unavailable 'egl-library "~a" (exn-message e)))])
      (ffi-lib "libEGL.so.1"))))
;; A single native initialization registry cannot be split across places (or
;; independent namespace instances). A process-global, one-byte raw token
;; enforces that policy. This token intentionally lives for the process lifetime;
;; it is not an EGL context/display allocation and never points into the GC heap.
(define process-token
  (delay/sync
    (define token (malloc 1 'raw))
    (unless token (error 'egl-place "cannot allocate process ownership token"))
    (define previous (register-process-global #"skia-for-racket/EGL-instance/v1" token))
    (when previous
      (free token)
      (gpu-unavailable 'egl-place "another EGL adapter instance/place owns process initialization; use a separate process"))
    token))
(define gl-lib
  (delay/sync
    (or (ffi-lib "libOpenGL.so.0" #:fail (lambda () #f))
        (ffi-lib "libGL.so.1" #:fail (lambda () #f)))))
(define (bind name type) (get-ffi-obj name (force lib) type))
(define-syntax-rule (egl name type)
  (begin (define pending (delay/sync (bind 'name type)))
         (define (name . args) (apply (force pending) args))))
(egl eglGetError (_fun -> _uint32))
(egl eglQueryString (_fun _pointer _int -> _pointer))
(egl eglGetProcAddress (_fun _string/utf-8 -> _pointer))
(egl eglInitialize (_fun _pointer _pointer _pointer -> _uint32))
(egl eglTerminate (_fun _pointer -> _uint32))
(egl eglBindAPI (_fun _uint32 -> _uint32))
(egl eglQueryAPI (_fun -> _uint32))
(egl eglChooseConfig (_fun _pointer _pointer _pointer _int _pointer -> _uint32))
(egl eglCreateContext (_fun _pointer _pointer _pointer _pointer -> _pointer))
(egl eglDestroyContext (_fun _pointer _pointer -> _uint32))
(egl eglCreatePbufferSurface (_fun _pointer _pointer _pointer -> _pointer))
(egl eglDestroySurface (_fun _pointer _pointer -> _uint32))
(egl eglMakeCurrent (_fun _pointer _pointer _pointer _pointer -> _uint32))
(egl eglGetCurrentContext (_fun -> _pointer))
(egl eglGetCurrentDisplay (_fun -> _pointer))
(egl eglGetCurrentSurface (_fun _int -> _pointer))
(define (address p) (and p (cast p _pointer _uintptr)))
(define (pointer=? a b) (equal? (address a) (address b)))
(define (ok who value)
  (when (or (not value) (and (number? value) (zero? value)))
    (gpu-unavailable who "~a failed with EGL error 0x~x" who (eglGetError)))
  value)
(define (string-at p) (and p (string->immutable-string (cast p _pointer _string/utf-8))))
(define (query d token) (or (string-at (eglQueryString d token)) ""))
(define (int-cell [value 0]) (define p (malloc _int 'atomic)) (ptr-set! p _int value) p)
(define (ints . values)
  (define p (malloc _int (length values) 'atomic))
  (for ([v (in-list values)] [i (in-naturals)]) (ptr-set! p _int i v)) p)
(define (resolve name)
  (or (eglGetProcAddress name)
      (get-ffi-obj name (force lib) _fpointer (lambda () #f))
      (and (force gl-lib) (get-ffi-obj name (force gl-lib) _fpointer (lambda () #f)))))
(define (extension-function name type)
  (define p (resolve name))
  (unless p (gpu-unavailable 'egl-entrypoint "EGL function ~a is unavailable" name))
  (cast p _pointer type))
(define (require-extension text name)
  (unless (egl-extension? text name)
    (gpu-unavailable 'egl-extension "required extension ~a is not advertised" name)))

;; EGL displays are NOT reference-counted by eglInitialize. Share one package
;; initialization across our contexts; terminate only after the last closes.
;; All operations are serialized by the package EGL provider lock. Borrowed
;; current-context providers never initialize/terminate the host display.
(struct display-entry (pointer [references #:mutable] major minor extensions))
(define displays (make-hasheqv))
(define quarantine (make-hasheq))
(define owned-contexts (make-hasheqv))
(define (retain-display! p)
  (define key (address p))
  (define previous (hash-ref displays key #f))
  (cond [previous (set-display-entry-references! previous (add1 (display-entry-references previous))) previous]
        [else
         ;; EGL initialization is not reference-counted. Refuse an already
         ;; initialized display owned outside this module, even when it has no
         ;; current context. A caller must not race external initialization
         ;; against this exclusive-owner constructor.
         (define version-before (eglQueryString p #x3054))
         (when version-before
           (gpu-unavailable 'egl-display-ownership
             "EGL display was initialized outside this adapter; borrow its current provider instead"))
         (define state-error (eglGetError))
         (unless (= state-error #x3001) ; EGL_NOT_INITIALIZED
           (gpu-unavailable 'egl-display-ownership "cannot establish exclusive display ownership (EGL error 0x~x)" state-error))
         (define major (int-cell)) (define minor (int-cell))
         (ok 'eglInitialize (eglInitialize p major minor))
         (define entry (display-entry p 1 (ptr-ref major _int) (ptr-ref minor _int) (query p #x3055)))
         (hash-set! displays key entry) entry]))
(define (release-display! entry)
  (cond [(> (display-entry-references entry) 1)
         (set-display-entry-references! entry (sub1 (display-entry-references entry)))]
        [else
         (ok 'eglTerminate (eglTerminate (display-entry-pointer entry)))
         (hash-remove! displays (address (display-entry-pointer entry)))
         (set-display-entry-references! entry 0)]))
(struct egl-host (entry context draw read details owned? [closed? #:mutable]))
;; Save/restore the desktop GL current binding AND the caller's bound client
;; API. Query GL bindings after selecting GL, not a potentially different ES
;; API. We never use eglReleaseThread: it would discard foreign API state.
(define (call-with-desktop-binding thunk)
  (define api (eglQueryAPI))
  (define d #f) (define context #f) (define draw #f) (define read #f)
  (define selected? #f)
  (dynamic-wind
    void
    (lambda ()
      (ok 'eglBindAPI (eglBindAPI EGL-OPENGL-API))
      (set! selected? #t)
      (set! d (eglGetCurrentDisplay)) (set! context (eglGetCurrentContext))
      (set! draw (eglGetCurrentSurface #x3059)) (set! read (eglGetCurrentSurface #x305A))
      (thunk))
    (lambda ()
      (parameterize-break #f
        (when selected?
          (dynamic-wind
            void
            (lambda ()
              (ok 'eglBindAPI (eglBindAPI EGL-OPENGL-API))
              (cond [context (ok 'eglRestoreCurrent (eglMakeCurrent d draw read context))]
                    [(eglGetCurrentContext)
                     (ok 'eglUnbind (eglMakeCurrent (eglGetCurrentDisplay) #f #f #f))]))
            (lambda () (ok 'eglRestoreAPI (eglBindAPI api)))))))))
(define (enter host)
  (when (egl-host-closed? host) (error 'egl-provider "EGL host is closed"))
  (define api (eglQueryAPI))
  (ok 'eglBindAPI (eglBindAPI EGL-OPENGL-API))
  (define previous-display (eglGetCurrentDisplay))
  (define previous-context (eglGetCurrentContext))
  (define previous-draw (eglGetCurrentSurface #x3059))
  (define previous-read (eglGetCurrentSurface #x305A))
  (define (restore)
    (parameterize-break #f
      (dynamic-wind
        void
        (lambda ()
          (ok 'eglBindAPI (eglBindAPI EGL-OPENGL-API))
          (cond [previous-context
                 (ok 'eglRestoreCurrent (eglMakeCurrent previous-display previous-draw previous-read previous-context))]
                [(eglGetCurrentContext)
                 (ok 'eglUnbind (eglMakeCurrent (eglGetCurrentDisplay) #f #f #f))]))
        (lambda () (ok 'eglRestoreAPI (eglBindAPI api))))))
  (with-handlers ([(lambda (_) #t) (lambda (e) (restore) (raise e))])
    (ok 'eglMakeCurrent (eglMakeCurrent (display-entry-pointer (egl-host-entry host))
                                       (egl-host-draw host) (egl-host-read host) (egl-host-context host))))
  restore)
(define (current? host)
  (and (= (eglQueryAPI) EGL-OPENGL-API)
       (not (egl-host-closed? host))
       (pointer=? (eglGetCurrentContext) (egl-host-context host))
       (pointer=? (eglGetCurrentDisplay) (display-entry-pointer (egl-host-entry host)))
       (pointer=? (eglGetCurrentSurface #x3059) (egl-host-draw host))
       (pointer=? (eglGetCurrentSurface #x305A) (egl-host-read host))))
(define (close host)
  (unless (egl-host-closed? host)
    (unless (egl-host-owned? host) (error 'egl-close "cannot destroy a borrowed EGL host"))
    (set-egl-host-closed?! host #t)
    (hash-set! quarantine host #t)
    (define d (display-entry-pointer (egl-host-entry host)))
    (call-with-desktop-binding
     (lambda ()
       ;; If this context is current, the saved binding in call-with-desktop-
       ;; binding would be destroyed. Unbind it before saving below instead.
       (when (pointer=? (eglGetCurrentContext) (egl-host-context host))
         (error 'egl-close "internal unbind ordering violation"))
       (ok 'eglDestroyContext (eglDestroyContext d (egl-host-context host)))
       (when (egl-host-draw host)
         (ok 'eglDestroySurface (eglDestroySurface d (egl-host-draw host))))))
    (release-display! (egl-host-entry host))
    (hash-remove! owned-contexts (address (egl-host-context host)))
    (hash-remove! quarantine host)))
(define (close-owned host)
  ;; The enclosing provider retains the *previous* binding separately. Normal
  ;; Ganesh release calls this with our EGL context current; lost-domain close
  ;; may call it with no context current. Never unbind a foreign context.
  (define api (eglQueryAPI))
  (dynamic-wind
    (lambda () (ok 'eglBindAPI (eglBindAPI EGL-OPENGL-API)))
    (lambda ()
      (when (pointer=? (eglGetCurrentContext) (egl-host-context host))
        (ok 'eglUnbind (eglMakeCurrent (display-entry-pointer (egl-host-entry host)) #f #f #f)))
      (close host))
    (lambda () (ok 'eglRestoreAPI (eglBindAPI api)))))
(define (describe host)
  (unless (current? host) (error 'egl-diagnostics "EGL context is not current"))
  (define get-string (extension-function "glGetString" (_fun _uint32 -> _pointer)))
  (define get-int (extension-function "glGetIntegerv" (_fun _uint32 _pointer -> _void)))
  (define (gl-string token) (string-at (get-string token)))
  (define (gl-int token) (define p (int-cell)) (get-int token p) (ptr-ref p _int))
  (define renderer (gl-string #x1F01)) (define vendor (gl-string #x1F00))
  (define version (gl-string #x1F02))
  (unless (and renderer vendor version (not (string-prefix? version "OpenGL ES")))
    (gpu-unavailable 'egl-desktop-gl "current EGL context is not desktop OpenGL"))
  (unless (or (> (gl-int #x821B) 3)
              (and (= (gl-int #x821B) 3) (>= (gl-int #x821C) 3)))
    (gpu-unavailable 'egl-desktop-gl "EGL adapter requires desktop OpenGL 3.3 or newer"))
  (hash-set* (egl-host-details host)
             'vendor vendor 'renderer renderer 'api_version version
             'renderer_class (renderer-class vendor renderer)
             'renderer_class_evidence "driver strings; not an independent hardware attestation"
             'profile_mask (gl-int #x9126)
             'host_samples (gl-int #x80A9) 'shading_language_version (gl-string #x8B8C)))
(define (create platform index surface)
  (force lib) (force process-token)
  (define client (query #f #x3055))
  (define get-display
    ;; A loader can export a 1.5 stub while the driver only advertises the
    ;; 1.4 EXT entry point. Prefer the explicitly advertised platform contract.
    (cond [(egl-extension? client "EGL_EXT_platform_base")
           (extension-function "eglGetPlatformDisplayEXT" (_fun _uint32 _pointer _pointer -> _pointer))]
          [else
           (define p (get-ffi-obj 'eglGetPlatformDisplay (force lib) _fpointer (lambda () #f)))
           (unless p (gpu-unavailable 'egl-entrypoint "neither EGL 1.5 platform display nor EGL_EXT_platform_base is available"))
           (cast p _pointer (_fun _uint32 _pointer _pointer -> _pointer))]))
  (define device
    (case platform
      [(surfaceless) (require-extension client "EGL_MESA_platform_surfaceless") #f]
      [(device)
       (require-extension client "EGL_EXT_platform_device")
       (unless (or (egl-extension? client "EGL_EXT_device_enumeration")
                   (egl-extension? client "EGL_EXT_device_base"))
         (gpu-unavailable 'egl-device "EGL device enumeration is not advertised"))
       (define enumerate (extension-function "eglQueryDevicesEXT" (_fun _int _pointer _pointer -> _uint32)))
       (define count (int-cell))
       (ok 'eglQueryDevicesEXT (enumerate 0 #f count))
       (define n (ptr-ref count _int))
       (unless (<= 1 n 1024) (gpu-unavailable 'egl-device "invalid EGL device count: ~a" n))
       (define devices (malloc _pointer n 'atomic))
       (ok 'eglQueryDevicesEXT (enumerate n devices count))
       (unless (< index (min n (ptr-ref count _int)))
         (gpu-unavailable 'egl-device "device-index ~a exceeds the enumerated device list" index))
       (ptr-ref devices _pointer index)]))
  (define d (ok 'eglGetPlatformDisplay (get-display (if (eq? platform 'device) #x313F #x31DD) device #f)))
  (define entry #f) (define ctx #f) (define buffer #f) (define success? #f)
  (call-with-desktop-binding
   (lambda ()
     ;; A current foreign owner on the same display cannot be safely adopted.
     (when (and (pointer=? d (eglGetCurrentDisplay))
                (not (hash-has-key? displays (address d))))
       (gpu-unavailable 'egl-display-ownership "this EGL display is already current outside the package; use make-current-egl-gpu-provider"))
     (dynamic-wind
       void
       (lambda ()
         (set! entry (retain-display! d))
         (define version15? (or (> (display-entry-major entry) 1)
                               (and (= (display-entry-major entry) 1) (>= (display-entry-minor entry) 5))))
         (unless version15? (require-extension (display-entry-extensions entry) "EGL_KHR_create_context"))
         (when (and (eq? surface 'surfaceless) (not version15?))
           (require-extension (display-entry-extensions entry) "EGL_KHR_surfaceless_context"))
         (define config-p (malloc _pointer 'atomic)) (ptr-set! config-p _pointer #f)
         (define count (int-cell))
         (define attrs (ints #x3040 #x0008 #x3033 (if (eq? surface 'pbuffer) #x0001 0)
                             #x3024 8 #x3023 8 #x3022 8 #x3021 8 EGL-NONE))
         (ok 'eglChooseConfig (eglChooseConfig d attrs config-p 1 count))
         (unless (positive? (ptr-ref count _int)) (gpu-unavailable 'egl-config "no desktop GL EGL config matches"))
         (define config (ptr-ref config-p _pointer))
         (when (eq? surface 'pbuffer)
           (set! buffer (ok 'eglCreatePbufferSurface (eglCreatePbufferSurface d config (ints #x3057 1 #x3056 1 EGL-NONE)))))
         (set! ctx (ok 'eglCreateContext
                       (eglCreateContext d config #f (ints #x3098 3 #x30FB 3 #x30FD #x0001 EGL-NONE))))
         (set! success? #t)
         (define result (egl-host entry ctx buffer buffer
           (hasheq 'egl_platform (symbol->string platform) 'egl_surface (symbol->string surface)
                   'egl_device_index (and (eq? platform 'device) index)
                   'egl_version (format "~a.~a" (display-entry-major entry) (display-entry-minor entry))
                   'egl_vendor (query d #x3053) 'headless #t 'display_server_free #t
                   'window_created #f 'requires_window #f 'requires_glx #f
                   'owns_egl_context #t 'owns_egl_display_initialization #t
                   'display_lifetime "package reference-counted; no external eglTerminate"
                   'context_sharing #f 'egl_place_policy "one-instance/place-per-process"
                   'presentation_tested #f)
           #t #f))
         (hash-set! owned-contexts (address ctx) #t)
         result)
       (lambda ()
         (unless success?
           ;; A native cleanup failure is not retried. Keep the dependent
           ;; display initialization alive rather than terminating underneath it.
           (when ctx (ok 'eglDestroyContext (eglDestroyContext d ctx)))
           (when buffer (ok 'eglDestroySurface (eglDestroySurface d buffer)))
           (when entry (release-display! entry))))))))
(define (make-egl-platform-ops platform index surface)
  (check-egl-options 'make-egl-platform-ops platform index surface)
  (force lib)
  (egl-platform-ops (lambda () (create platform index surface)) close-owned enter current? describe resolve))
(define (capture-current-egl-provider)
  (force lib) (force process-token)
  (unless (= (eglQueryAPI) EGL-OPENGL-API)
    (gpu-unavailable 'egl-current "bind the desktop OpenGL API before capturing an EGL provider"))
  (define ctx (eglGetCurrentContext)) (define d (eglGetCurrentDisplay))
  (unless (and ctx d) (gpu-unavailable 'egl-current "no current desktop EGL context"))
  (when (hash-has-key? owned-contexts (address ctx))
    (gpu-unavailable 'egl-current-ownership "use the existing owned GPU context, not a second Ganesh wrapper"))
  (define host
    (egl-host (display-entry d 0 0 0 (query d #x3055)) ctx
      (eglGetCurrentSurface #x3059) (eglGetCurrentSurface #x305A)
      (hasheq 'egl_platform "host-owned" 'headless #f 'display_server_free #f
              'window_created #f 'owns_egl_context #f 'owns_egl_display_initialization #f
              'requires_glx #f 'presentation_tested #f) #f #f))
  (describe host) ; validates desktop GL version while the host is current
  (make-gpu-provider
   #:name 'egl-current #:backend 'opengl #:key (address ctx)
   #:get-proc-address resolve #:current? (lambda () (current? host))
   #:describe (lambda () (describe host))
   #:call-as-current
   (lambda (thunk)
     (call-with-egl-lock
      (lambda ()
        (define restore #f)
        (dynamic-wind
          (lambda () (parameterize-break #f (set! restore (enter host))))
          thunk
          (lambda () (when restore (restore)))))))))
