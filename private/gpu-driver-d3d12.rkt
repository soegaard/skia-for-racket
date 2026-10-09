#lang racket/base
(require ffi/unsafe "gpu-d3d12-handles.rkt"
         "gpu-d3d12-system.rkt" "gpu-d3d12-util.rkt" "gpu-d3d12-types.rkt"
         "gpu-native.rkt" "gpu-types.rkt"
         (only-in "gpu-surface-native.rkt" flush/native submit/native)
         (only-in "types.rkt" rgba-8888)
         (only-in "native.rkt" native-package-version skia-native-version skia-native-library-path))
(provide make-owned-d3d12-components)
(define (make-owned-d3d12-components selection index #:receive-handles [receive void]
                                      #:options [options #f])
  (check-optional-context-options 'make-owned-d3d12-components options)
  (unless (and (procedure? receive) (procedure-arity-includes? receive 3))
    (raise-argument-error 'make-owned-d3d12-components "three-argument private handle receiver" receive))
  (d3d12-selection! selection index)
  (define platform (load-d3d12-platform))
  (gpu-native-check! 'direct3d)
  (make-d3d12-components
   platform
   (d3d12-context-ops
    (lambda (adapter device queue)
      (define descriptor (make-gr-d3d-backend-context adapter device queue #f #f))
      (define context
        (if options
            (call-with-native-context-options 'make-gpu-context options
              (lambda (record) (gr_direct_context_make_direct3d_with_options descriptor record)))
            (gr_direct_context_make_direct3d descriptor)))
      (when context
        (with-handlers ([(lambda (_) #t)
                         (lambda (e) (forget-d3d12-handles! context) (gr_recording_context_unref context) (raise e))])
          (register-d3d12-handles! context adapter device queue)
          (receive adapter device queue)))
      context)
    (lambda (p) (forget-d3d12-handles! p) (gr_recording_context_unref p))
    gr_direct_context_abandon_context gr_direct_context_is_abandoned
    (lambda (p)
      (flush/native p)
      (unless (submit/native p #t) (error 'gpu-context-close! "D3D12 final completion failed")))
    (lambda (p details)
      (unless (= (gr_recording_context_get_backend p) gr-direct3d)
        (error 'make-gpu-context "native context did not select Direct3D"))
      (hash-set* (add-context-options-diagnostics details options 'direct3d)
                 'binding_package native-package-version
                 'native_version (skia-native-version)
                 'native_library_candidate (format "~a" (skia-native-library-path))
                 'native_backend gr-direct3d
                 'max_texture_size (gr_recording_context_max_texture_size p)
                 'max_render_target_size (gr_recording_context_max_render_target_size p)
                 'max_rgba_sample_count (gr_recording_context_get_max_surface_sample_count_for_color_type p rgba-8888)
                 'cache_limit_bytes (gr_direct_context_get_resource_cache_limit p))))
   selection index))
(require "gpu-context-options-native.rkt"
         (submod "../gpu-context-options.rkt" internals))
