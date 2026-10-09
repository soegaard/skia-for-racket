#lang racket/base
;; One owned interface reference per GL driver. The context's native reference
;; is independent. All access occurs on the owning domain thread while current.
(require ffi/unsafe "gpu-native.rkt" "gpu-provider.rkt" "gpu-diagnostic-util.rkt")
(provide create-gl-interface/native register-gl-interface! release-gl-interface!
         gl-context-interface-info/native gl-context-has-extension?/native)
(struct interface-record (pointer requested factory))
(define interfaces (make-hasheqv))
(define current-interface-dispatch (make-parameter #f))
(module* testing #f (provide current-interface-dispatch))
(define (native-call operation . arguments)
  (define test-dispatch (current-interface-dispatch))
  (if test-dispatch (apply test-dispatch operation arguments)
      (apply (case operation
               [(native) gr_glinterface_create_native_interface]
               [(desktop) gr_glinterface_assemble_gl_interface]
               [(auto) gr_glinterface_assemble_interface]
               [(gles) gr_glinterface_assemble_gles_interface]
               [(webgl) gr_glinterface_assemble_webgl_interface]
               [(unref) gr_glinterface_unref]
               [(extension) gr_glinterface_has_extension]
               [(version) resolver-version]
               [else (error 'gl-interface "unknown private operation")])
             arguments)))
(define (resolver-version resolver)
  ;; Called under provider activation, before entering the C++ assembler.
  ;; 64-bit native GL function pointers use the platform ABI; no extra loader.
  (define pointer (resolver "glGetString"))
  (unless (and pointer (cpointer? pointer))
    (gpu-unavailable 'gl-interface-version "provider has no glGetString function"))
  (define get-string (cast pointer _pointer (_fun _uint -> _pointer)))
  (define text (get-string #x1f02)) ; GL_VERSION
  (unless text (gpu-unavailable 'gl-interface-version "no GL version in the current host"))
  (define n
    (let loop ([at 0])
      (cond [(zero? (ptr-ref text _ubyte at)) at]
            [(= at 1024) (gpu-unavailable 'gl-interface-version "unbounded GL version string")]
            [else (loop (add1 at))])))
  (define copied (make-bytes n))
  (unless (zero? n) (memcpy copied text n))
  (void/reference-sink resolver get-string)
  (bytes->string/utf-8 copied #f))
(define (context-key pointer)
  (unless (and pointer (cpointer? pointer))
    (error 'gl-interface "missing native context pointer"))
  (cast pointer _pointer _uintptr))
(define (factory-label mode)
  (case mode
    [(auto) "assembled-auto"] [(desktop) "assembled-desktop-gl"]
    [(gles) "assembled-gles"] [(webgl) "assembled-webgl"]
    [else "native"]))
(define (assemble mode resolver)
  (unless resolver
    (gpu-unavailable 'gl-interface-resolver "~a interface assembly requires a provider resolver" mode))
  ;; Explicit GLES/WebGL builders do not themselves check the host standard.
  ;; Reject mismatches before one can build a mislabelled function table.
  (define host-standard (gl-version-standard (native-call 'version resolver)))
  (unless (and host-standard (or (eq? mode 'auto) (eq? host-standard mode)))
    (gpu-unavailable 'gl-interface-standard
      "requested ~a interface does not match current host standard ~a" mode host-standard))
  (define no-error (gensym 'no-resolver-error))
  (define failure no-error)
  (define callback
    (lambda (_ name)
      ;; The assembler calls synchronously. No exception can cross its C++
      ;; frames, including a raised #f. Root resolver/callback until it returns.
      (if (eq? failure no-error)
          (with-handlers ([(lambda (_) #t)
                           (lambda (e) (set! failure e) #f)])
            (define pointer (resolver name))
            (cond [(not pointer) #f]
                  [(cpointer? pointer) pointer]
                  [else (error 'gl-interface "provider resolver returned neither a pointer nor #f")]))
          #f)))
  (define interface (native-call mode #f callback))
  (void/reference-sink callback resolver)
  (unless (eq? failure no-error)
    (when interface (native-call 'unref interface))
    (raise failure))
  interface)
(define (create-gl-interface/native provider mode)
  (check-gl-interface-mode 'make-gpu-context mode)
  (define resolver (gpu-provider-resolve provider))
  (define egl? (memq (gpu-provider-name provider) '(egl-owned egl-current)))
  (define interface #f)
  (define factory (factory-label mode))
  (cond
    [(eq? mode 'default)
     ;; Preserve the accepted native-first path, but never select GLX for EGL.
     (unless egl? (set! interface (native-call 'native)))
     (when (and (not interface) resolver)
       (set! interface (assemble 'desktop resolver))
       (set! factory (factory-label 'desktop)))]
    [else (set! interface (assemble mode resolver))])
  (unless interface
    (gpu-unavailable 'gl-interface "~a GL interface unavailable for this host; no different-standard fallback is performed" mode))
  (values interface factory))
(define (register-gl-interface! context interface requested factory)
  (define key (context-key context))
  (when (hash-has-key? interfaces key)
    (error 'gl-interface "native context already has an owned interface"))
  (hash-set! interfaces key (interface-record interface requested (string->immutable-string factory)))
  (void))
(define (release-gl-interface! context)
  ;; Invoked after the driver's context unref, including constructor failure
  ;; and already-abandoned domains. Interface unref frees CPU tables only.
  ;; Remove before calling C so an indeterminate unref is never retried here.
  (define key (context-key context))
  (define record (hash-ref interfaces key #f))
  (when record
    (hash-remove! interfaces key)
    (native-call 'unref (interface-record-pointer record)))
  (void))
(define (lookup context)
  (hash-ref interfaces (context-key context)
            (lambda () (error 'gl-interface "context has no retained GL interface"))))
(define (gl-context-interface-info/native context)
  (define record (lookup context))
  (hasheq 'requested (string->immutable-string (symbol->string (interface-record-requested record)))
          'factory (interface-record-factory record) 'validated #t
          'extension_source "context-owned-skia-interface"))
(define (gl-context-has-extension?/native context extension)
  (define name (checked-gl-extension 'gpu-gl-has-extension? extension))
  (and (native-call 'extension (interface-record-pointer (lookup context)) name) #t))
