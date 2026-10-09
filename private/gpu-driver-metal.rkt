#lang racket/base
(require ffi/unsafe "gpu-native.rkt" "gpu-provider.rkt" "gpu-metal-system.rkt"
         "gpu-metal-util.rkt" "gpu-types.rkt"
         (only-in "types.rkt" rgba-8888)
         (only-in "native.rkt" native-package-version skia-native-version skia-native-library-path))
(provide make-owned-metal-components)
(define (make-owned-metal-components #:options [options #f])
  (check-optional-context-options 'make-owned-metal-components options)
  ;; Platform rejection precedes symbol lookup, and neither happens on import.
  (define platform (load-metal-platform))
  (gpu-native-check! 'metal)
  (make-metal-components
   platform
   (metal-context-ops
    (if options
        (lambda (device queue)
          (call-with-native-context-options 'make-gpu-context options
            (lambda (record) (gr_direct_context_make_metal_with_options device queue record))))
        gr_direct_context_make_metal)
    gr_recording_context_unref gr_direct_context_abandon_context
    (lambda (p)
      (when (gr_direct_context_is_abandoned p)
        (error 'call-with-gpu-context "native Metal context is abandoned; close or abandon this domain"))
      ;; A private Metal queue has no external GL state to reset.
      (void))
    (lambda (p device-details)
      (unless (= (gr_recording_context_get_backend p) gr-metal)
        (error 'make-gpu-context "native context did not select the Metal backend"))
      (define count (malloc _int 'atomic))
      (define size (malloc _size 'atomic))
      (gr_direct_context_get_resource_cache_usage p count size)
      (hash-set* (add-context-options-diagnostics device-details options 'metal)
                 'binding_package native-package-version
                 'native_version (skia-native-version)
                 'native_library_candidate (format "~a" (skia-native-library-path))
                 'native_backend gr-metal
                 'max_texture_size (gr_recording_context_max_texture_size p)
                 'max_render_target_size (gr_recording_context_max_render_target_size p)
                 'max_rgba_sample_count (gr_recording_context_get_max_surface_sample_count_for_color_type p rgba-8888)
                 'cache_limit_bytes (gr_direct_context_get_resource_cache_limit p)
                 'initial_cache_resources (ptr-ref count _int)
                 'initial_cache_bytes (ptr-ref size _size))))))
(require "gpu-context-options-native.rkt"
         (submod "../gpu-context-options.rkt" internals))
