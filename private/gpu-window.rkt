#lang racket/base
;; Diagnostic-only borrowed framebuffer integration. No native handles are
;; exported by skia/gpu. The host owns its framebuffer for the entire scope.
(require ffi/unsafe ffi/unsafe/atomic
         "gpu-gl-system.rkt" "gpu-surface-util.rkt" "gpu-surface-native.rkt"
         "gpu-domain.rkt" "gpu-context.rkt" "gpu-types.rkt" "types.rkt"
         "lifetime.rkt"
         "core.rkt" (submod "core.rkt" gpu-surface-internals)
         (prefix-in n: "gpu-native.rkt"))
(provide make-window-gl-access call-with-window-target draw-gpu-target-to-window!)
(define (make-window-gl-access)
  (define-values (key describe resolve) (make-system-gl-tools))
  (define (bind name type)
    (define p (resolve name))
    (unless p (error 'gpu-window "missing desktop GL entry point ~a" name))
    (cast p _pointer type))
  (define get-int (bind "glGetIntegerv" (_fun _uint32 _pointer -> _void)))
  (define get-error (bind "glGetError" (_fun -> _uint32)))
  (define bind-framebuffer (bind "glBindFramebuffer" (_fun _uint32 _uint32 -> _void)))
  (define framebuffer-status (bind "glCheckFramebufferStatus" (_fun _uint32 -> _uint32)))
  (define get-attachment
    (bind "glGetFramebufferAttachmentParameteriv" (_fun _uint32 _uint32 _uint32 _pointer -> _void)))
  (define (checked who thunk)
    (define value (thunk))
    (define err (get-error))
    (unless (zero? err) (error 'gpu-window "~a produced GL error 0x~x" who err))
    value)
  (define (integer token)
    (define p (malloc _int 'atomic))
    (ptr-set! p _int 0)
    (checked 'integer-query (lambda () (get-int token p) (ptr-ref p _int))))
  (define (attachment point token)
    (define p (malloc _int 'atomic))
    (ptr-set! p _int 0)
    (checked 'attachment-query
             (lambda () (get-attachment #x8D40 point token p) (ptr-ref p _int))))
  ;; Capture this BEFORE creating a Ganesh context or offscreen target. Do not
  ;; assume zero, and do not mistake a leftover Skia FBO for the host's buffer.
  (define host-key (key))
  (unless host-key (error 'gpu-window "host GL context must be current"))
  (define host-fbo (integer #x8CA6)) ; GL_DRAW_FRAMEBUFFER_BINDING
  (define (query-target width height)
    (unless (equal? (key) host-key) (error 'gpu-window "native host context changed"))
    (unless (and (exact-positive-integer? width) (exact-positive-integer? height))
      (error 'gpu-window "host has no drawable pixel extent"))
    (unless (= (framebuffer-status #x8D40) #x8CD5)
      (error 'gpu-window "host framebuffer is incomplete"))
    (define draw-buffer (integer #x0C01)) ; actual GL_DRAW_BUFFER
    (define double-buffered? (not (zero? (integer #x0C32))))
    (unless double-buffered? (error 'gpu-window "diagnostic requires a double-buffered window"))
    (define color-attachment
      (cond [(and (zero? host-fbo) (memv draw-buffer '(#x0405 #x0402))) #x0402]
            [(and (positive? host-fbo) (<= #x8CE0 draw-buffer #x8CFF)) draw-buffer]
            [else (error 'gpu-window "unsupported actual host draw buffer 0x~x" draw-buffer)]))
    (define stencil-attachment (if (zero? host-fbo) #x1802 #x8D20))
    (define red (attachment color-attachment #x8212))
    (define green (attachment color-attachment #x8213))
    (define blue (attachment color-attachment #x8214))
    (define alpha (attachment color-attachment #x8215))
    (define encoding (attachment color-attachment #x8210))
    (define component-type (attachment color-attachment #x8211))
    (define queried-format
      (gpu-presentation-format red green blue alpha encoding component-type))
    (define default-window? (zero? host-fbo))
    (define format (gpu-window-wrap-format host-fbo queried-format))
    (define stencil
      (if (zero? (attachment stencil-attachment #x8CD0)) 0
          (attachment stencil-attachment #x8217)))
    (hasheq 'width width 'height height 'framebuffer_id host-fbo
            'draw_buffer draw-buffer 'double_buffered double-buffered?
            'color_bits (list red green blue alpha) 'color_encoding encoding
            'component_type component-type 'format format
            'color_type (if default-window? rgba-8888 (if (zero? alpha) 5 rgba-8888))
            'srgb (gpu-presentation-srgb? encoding)
            'actual_sample_count (integer #x80A9) 'stencil_bits stencil
            'origin "bottom-left"))
  (define (with-target width height proc)
    (unless (equal? (key) host-key) (error 'gpu-window "wrong native context"))
    (define previous-draw (integer #x8CA6))
    (define previous-read (integer #x8CAA))
    (dynamic-wind
      (lambda () (bind-framebuffer #x8D40 host-fbo))
      (lambda () (proc (query-target width height)))
      (lambda ()
        ;; Framebuffer bindings only. This exclusive diagnostic window does
        ;; not promise to restore arbitrary host programs, VAOs, or textures.
        (bind-framebuffer #x8CA9 previous-draw)
        (bind-framebuffer #x8CA8 previous-read))))
  with-target)
(define (call-with-window-target context description proc)
  (define d (context-domain 'gpu-window context))
  (define p (domain-pointer d))
  (gpu-surface-native-check! #t)
  (define descriptor #f)
  (define handle #f)
  (define space #f)
  (define colorspace #f)
  (dynamic-wind
    void
    (lambda ()
      (when (hash-ref description 'srgb)
        (set! space (make-srgb-color-space))
        (set! colorspace
          (call-with-owned 'gpu-window (list (color-space-h 'gpu-window space)) values)))
      (call-as-atomic
       (lambda ()
         (define info
           (make-gr-gl-framebuffer-info (hash-ref description 'framebuffer_id)
                                       (hash-ref description 'format) #f))
         (set! descriptor
           (make-backend-target/native (hash-ref description 'width) (hash-ref description 'height)
             (hash-ref description 'actual_sample_count) (hash-ref description 'stencil_bits) info))
         (unless (and descriptor (backend-target-valid?/native descriptor))
           (error 'gpu-window "native framebuffer descriptor rejected"))
         (set! handle
           (domain-new-resource d 'window-surface
             (lambda ()
               (wrap-backend-target/native p descriptor gr-bottom-left
                                           (hash-ref description 'color_type) colorspace #f))
             n:sk_surface_unref))))
      ;; A host bind invalidates Skia's cached framebuffer state, not its
      ;; intended drawing transform or the host's external GL state.
      (n:gr_direct_context_reset_context p #xffffffff)
      (define surface
        (make-gpu-surface-record handle (hash-ref description 'width) (hash-ref description 'height)
          '() context d colorspace
          (hash-set* description 'target_kind "host-framebuffer" 'storage "gpu"
                     'backend "opengl" 'context_generation (domain-generation d)
                     'render_path "sk_surface_new_backend_render_target")))
      (proc surface))
    (lambda ()
      ;; Unref the borrowed SkSurface BEFORE its descriptor. Neither deletes
      ;; the actual host FBO. All native cleanup is in this current GL scope.
      (parameterize-break #f
        (when handle (domain-resource-close! handle) (domain-drain! d))
        (when descriptor (delete-backend-target/native descriptor))
        (when space (skia-close! space))))))
(define (draw-gpu-target-to-window! source destination)
  (unless (and (gpu-surface? source) (gpu-surface? destination))
    (error 'gpu-window "expected two GPU surfaces"))
  (unless (eq? (gpu-surface-domain source) (gpu-surface-domain destination))
    (error 'gpu-window "foreign execution domains cannot share a frame"))
  (define sp (resource-pointer (surface-h 'gpu-window source)))
  (define dp (resource-pointer (surface-h 'gpu-window destination)))
  (draw-surface/native sp (n:sk_surface_get_canvas dp) 0.0 0.0 #f)
  (void/reference-sink source destination))
