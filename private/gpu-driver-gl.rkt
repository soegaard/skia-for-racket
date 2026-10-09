#lang racket/base
(require ffi/unsafe "gpu-native.rkt" "gpu-domain.rkt" "gpu-provider.rkt"
         "gpu-types.rkt" (only-in "types.rkt" rgba-8888)
         (only-in "native.rkt" native-package-version skia-native-version skia-native-library-path))
(provide make-gl-driver)
(define (make-gl-driver provider #:options [options #f] #:interface [interface-mode 'default])
  (check-gl-interface-mode 'make-gl-driver interface-mode)
  (check-optional-context-options 'make-gl-driver options)
  (gpu-native-check! 'opengl)
  (define interface-kind (box #f))
  (gpu-driver
   (lambda ()
     (define-values (interface factory) (create-gl-interface/native provider interface-mode))
     (define retained? #f)
     (set-box! interface-kind factory)
     (dynamic-wind
       void
       (lambda ()
         (unless (gr_glinterface_validate interface)
           (gpu-unavailable 'gl-interface-validation "Skia rejected the current GL interface"))
         (define p
           (if options
               (call-with-native-context-options 'make-gpu-context options
                 (lambda (record) (gr_direct_context_make_gl_with_options interface record)))
               (gr_direct_context_make_gl interface)))
         (unless p (gpu-unavailable 'ganesh-context "Ganesh GL context creation returned null"))
         (with-handlers ([(lambda (_) #t)
                          (lambda (e) (gr_recording_context_unref p) (raise e))])
           (register-gl-interface! p interface interface-mode factory)
           (set! retained? #t))
         p)
       (lambda () (unless retained? (gr_glinterface_unref interface)))))
   (lambda (p)
     (gr_recording_context_unref p)
     (release-gl-interface! p))
   gr_direct_context_abandon_context
   (lambda (p)
     (when (gr_direct_context_is_abandoned p)
       (error 'call-with-gpu-context "native Ganesh context is abandoned; close or abandon this domain"))
     ;; Invalidate Skia's assumptions after external host use. This does NOT
     ;; restore the host's GL state when the scope returns.
     (gr_direct_context_reset_context p #xffffffff))
   (lambda (p)
     (unless (= (gr_recording_context_get_backend p) gr-opengl)
       (error 'make-gpu-context "native context did not select the OpenGL backend"))
     (define details (freeze-gpu-details ((gpu-provider-describe provider))))
     (define count (malloc _int 'atomic))
     (define size (malloc _size 'atomic))
     (gr_direct_context_get_resource_cache_usage p count size)
     (hash-set* (add-context-options-diagnostics details options 'opengl)
                'binding_package native-package-version
                'native_version (skia-native-version)
                'native_library_candidate (format "~a" (skia-native-library-path))
                'gl_interface_requested (symbol->string interface-mode)
                'interface_factory (unbox interface-kind)
                'interface_validated #t
                'native_backend gr-opengl
                'max_texture_size (gr_recording_context_max_texture_size p)
                'max_render_target_size (gr_recording_context_max_render_target_size p)
                'max_rgba_sample_count (gr_recording_context_get_max_surface_sample_count_for_color_type p rgba-8888)
                'cache_limit_bytes (gr_direct_context_get_resource_cache_limit p)
                'initial_cache_resources (ptr-ref count _int)
                'initial_cache_bytes (ptr-ref size _size)))))
(require "gpu-context-options-native.rkt"
         (submod "../gpu-context-options.rkt" internals))
(require "gpu-gl-interface.rkt" "gpu-diagnostic-util.rkt")
