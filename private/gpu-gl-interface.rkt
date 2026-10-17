#lang racket/base

;;;
;;; OpenGL Native Interfaces
;;;

;; Constructs Skia GL interfaces from provider-resolved entry points.
;; Keeps GL procedure discovery tied to the selected context provider.

;; One owned interface reference per GL driver. The context's native reference
;; is independent. All access occurs on the owning domain thread while current.
(require ffi/unsafe "gpu-native.rkt" "gpu-provider.rkt" "gpu-diagnostic-util.rkt")
(provide create-gl-interface/native register-gl-interface! release-gl-interface!
         gl-context-interface-info/native gl-context-has-extension?/native)
(struct interface-record (pointer requested factory))
;; Fields:
;;   pointer: owned native GL interface. requested: requested interface flavor. factory: selected
;;   native factory identifier. Diagnostics retain selection metadata without changing pointer
;;   ownership.

; interfaces : hash?
;   Retains one owned GL interface record for each native context identity.
(define interfaces (make-hasheqv))

; current-interface-dispatch : parameter?
;   Lets native-free tests replace GL interface factories and queries.
(define current-interface-dispatch (make-parameter #f))
(module* testing #f (provide current-interface-dispatch))

; native-call : any/c any/c ... -> any
;   Dispatches interface operations through the injected test backend or the selected native
;   factory.
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

; resolver-version : any/c -> string?
;   Copies a bounded GL_VERSION string using the current provider's own glGetString resolver.
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

; context-key : any/c -> any
;   Converts a nonnull context pointer to its numeric identity for the private interface registry.
(define (context-key pointer)
  (unless (and pointer (cpointer? pointer))
    (error 'gl-interface "missing native context pointer"))
  (cast pointer _pointer _uintptr))

; factory-label : any/c -> string?
;   Distinguishes native interface construction from the selected assembled GL dialect in
;   diagnostics.
(define (factory-label mode)
  (case mode
    [(auto) "assembled-auto"] [(desktop) "assembled-desktop-gl"]
    [(gles) "assembled-gles"] [(webgl) "assembled-webgl"]
    [else "native"]))

; assemble : any/c any/c -> any
;   Checks the current host dialect and captures resolver failures before they can cross native
;   assembler frames.
(define (assemble mode resolver)
  (unless resolver
    (gpu-unavailable 'gl-interface-resolver "~a interface assembly requires a provider resolver"
      mode))
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

; create-gl-interface/native : any/c any/c -> (values #f any/c)
;   Chooses a native or provider-assembled interface appropriate to the requested mode and host
;   context.
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
    (gpu-unavailable 'gl-interface
      "~a GL interface unavailable for this host; no different-standard fallback is performed" mode))
  (values interface factory))

; register-gl-interface! : any/c any/c any/c any/c -> void?
;   Associates an owned interface reference and selection metadata with one native context.
(define (register-gl-interface! context interface requested factory)
  (define key (context-key context))
  (when (hash-has-key? interfaces key)
    (error 'gl-interface "native context already has an owned interface"))
  (hash-set! interfaces key (interface-record interface requested (string->immutable-string factory)))
  (void))

; release-gl-interface! : any/c -> void?
;   Removes the context's interface record before releasing its owned native reference.
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

; lookup : any/c -> any
;   Finds the retained interface record for the checked native context identity.
(define (lookup context)
  (hash-ref interfaces (context-key context)
            (lambda () (error 'gl-interface "context has no retained GL interface"))))

; gl-context-interface-info/native : any/c -> hash?
;   Returns detached requested/factory interface metadata for the current context.
(define (gl-context-interface-info/native context)
  (define record (lookup context))
  (hasheq 'requested (string->immutable-string (symbol->string (interface-record-requested record)))
          'factory (interface-record-factory record) 'validated #t
          'extension_source "context-owned-skia-interface"))

; gl-context-has-extension?/native : any/c any/c -> any
;   Queries the retained Skia interface's extension table for a validated extension name.
(define (gl-context-has-extension?/native context extension)
  (define name (checked-gl-extension 'gpu-gl-has-extension? extension))
  (and (native-call 'extension (interface-record-pointer (lookup context)) name) #t))
