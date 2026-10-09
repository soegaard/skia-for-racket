#lang racket/base
(require ffi/unsafe racket/promise racket/list "gpu-d3d12-types.rkt" "gpu-dxgi-types.rkt"
         (only-in "native.rkt" skia-native-library-handle) "types.rkt" "gpu-provider.rkt" "gpu-native-scope.rkt")
(provide gpu-native-check! gpu-native-inventory gpu-symbol-names)
;; Separate lazy group: the CPU native-bindings registry remains unchanged.
;; Loading this module does not dlopen GL, Metal, a GUI, or even libSkiaSharp.
(define library (delay/sync (skia-native-library-handle)))
(define bindings '())
(define-syntax-rule (define-gpu-native group name type)
  (begin
    (provide name)
    (define promise (delay/sync (get-ffi-obj 'name (force library) type)))
    (set! bindings (cons (list 'group 'name promise) bindings))
    (define (name . arguments)
      (define call (force promise))
      (call-with-gpu-native-scope (lambda () (apply call arguments))))))
(define _get-gl-proc (_fun _pointer _string/utf-8 -> _pointer))

(define-gpu-native common gr_recording_context_unref (_fun _pointer -> _void))
(define-gpu-native common gr_recording_context_get_direct_context (_fun _pointer -> _pointer))
(define-gpu-native common gr_recording_context_get_backend (_fun _pointer -> _int))
(define-gpu-native common gr_recording_context_max_texture_size (_fun _pointer -> _int))
(define-gpu-native common gr_recording_context_max_render_target_size (_fun _pointer -> _int))
(define-gpu-native common gr_recording_context_get_max_surface_sample_count_for_color_type
  (_fun _pointer _int -> _int))
(define-gpu-native common gr_direct_context_is_abandoned (_fun _pointer -> _stdbool))
(define-gpu-native common gr_direct_context_abandon_context (_fun _pointer -> _void))
(define-gpu-native common gr_direct_context_reset_context (_fun _pointer _uint32 -> _void))
(define-gpu-native common gr_direct_context_flush (_fun _pointer -> _void))
(define-gpu-native common gr_direct_context_submit (_fun _pointer _stdbool -> _stdbool))
(define-gpu-native common gr_direct_context_get_resource_cache_limit (_fun _pointer -> _size))
(define-gpu-native common gr_direct_context_get_resource_cache_usage
  (_fun _pointer _pointer _pointer -> _void))
(define-gpu-native opengl gr_glinterface_create_native_interface (_fun -> _pointer))
(define-gpu-native opengl gr_glinterface_assemble_gl_interface (_fun _pointer _get-gl-proc -> _pointer))
(define-gpu-native opengl gr_glinterface_validate (_fun _pointer -> _stdbool))
(define-gpu-native opengl gr_glinterface_unref (_fun _pointer -> _void))
(define-gpu-native opengl gr_direct_context_make_gl (_fun _pointer -> _pointer))
(define-gpu-native metal gr_direct_context_make_metal (_fun _pointer _pointer -> _pointer))
;; The C ABI takes the complete descriptor BY VALUE, not a pointer.
(define-gpu-native direct3d gr_direct_context_make_direct3d
  (_fun _gr-d3d-backend-context -> _pointer))
(define-gpu-native probe sk_surface_new_render_target
  (_fun _pointer _stdbool _sk-image-info-pointer _int _int _pointer _stdbool -> _pointer))
(define-gpu-native probe sk_surface_get_recording_context (_fun _pointer -> _pointer))
;; The following are existing CPU ABI entries, resolved here without adding
;; them to the CPU audit registry or manufacturing a public GPU surface.
(define-gpu-native probe sk_surface_unref (_fun _pointer -> _void))
(define-gpu-native probe sk_surface_get_canvas (_fun _pointer -> _pointer))
(define-gpu-native probe sk_surface_read_pixels
  (_fun _pointer _sk-image-info-pointer _bytes _size _int _int -> _stdbool))
(define-gpu-native probe sk_canvas_clear (_fun _pointer _uint32 -> _void))
(define-gpu-native probe sk_canvas_draw_rect (_fun _pointer _sk-rect-pointer _pointer -> _void))
(define-gpu-native probe sk_paint_new (_fun -> _pointer))
(define-gpu-native probe sk_paint_delete (_fun _pointer -> _void))
(define-gpu-native probe sk_paint_set_color (_fun _pointer _uint32 -> _void))
(define-gpu-native probe sk_paint_set_antialias (_fun _pointer _stdbool -> _void))

;; 0.49 optional DXGI group: offscreen Direct3D does not require these.
(define-gpu-native dxgi gr_backendrendertarget_new_direct3d
  (_fun _int _int _gr-d3d-texture-info-pointer -> _pointer))
(define-gpu-native dxgi gr_backendrendertarget_delete (_fun _pointer -> _void))
(define-gpu-native dxgi gr_backendrendertarget_is_valid (_fun _pointer -> _stdbool))
(define-gpu-native dxgi gr_backendrendertarget_get_backend (_fun _pointer -> _int))
(define-gpu-native dxgi gr_backendrendertarget_get_samples (_fun _pointer -> _int))
(define-gpu-native dxgi gr_backendrendertarget_get_width (_fun _pointer -> _int))
(define-gpu-native dxgi gr_backendrendertarget_get_height (_fun _pointer -> _int))
(define-gpu-native dxgi sk_surface_new_backend_render_target
  (_fun _pointer _pointer _int _int _pointer _pointer -> _pointer))
(define-gpu-native dxgi gr_direct_context_free_gpu_resources (_fun _pointer -> _void))

(define (selected backend)
  (unless (memq backend '(opengl metal direct3d dxgi))
    (raise-argument-error 'gpu-native-inventory "'opengl, 'metal, 'direct3d, or private 'dxgi group" backend))
  (filter (lambda (entry) (memq (car entry) (list 'common 'probe backend)))
          (reverse bindings)))
(define (gpu-symbol-names backend) (map cadr (selected backend)))
(define (gpu-native-inventory backend)
  ;; An inventory proves symbol resolution, not backend implementation,
  ;; context creation, driver support, rendering, or hardware acceleration.
  (force library)
  (for/list ([entry (in-list (selected backend))])
    (with-handlers ([exn:fail?
                     (lambda (e) (hasheq 'name (symbol->string (cadr entry))
                                         'available #f 'error (exn-message e)))])
      (force (caddr entry))
      (hasheq 'name (symbol->string (cadr entry)) 'available #t))))
(define (gpu-native-check! backend)
  (define inventory (gpu-native-inventory backend))
  (define missing (filter (lambda (row) (not (hash-ref row 'available))) inventory))
  (unless (null? missing)
    (gpu-unavailable 'native-symbols "missing optional GPU bindings: ~a"
                     (map (lambda (row) (hash-ref row 'name)) missing)))
  (void))

;; 0.77b: the complete six-field m119 context-options descriptor is borrowed
;; synchronously. D3D's existing backend descriptor remains passed BY VALUE.
(define-gpu-native opengl gr_direct_context_make_gl_with_options
  (_fun _pointer _pointer -> _pointer))
(define-gpu-native metal gr_direct_context_make_metal_with_options
  (_fun _pointer _pointer _pointer -> _pointer))
(define-gpu-native direct3d gr_direct_context_make_direct3d_with_options
  (_fun _gr-d3d-backend-context _pointer -> _pointer))
(define-gpu-native common gr_direct_context_flush_surface
  (_fun #:blocking? #t _pointer _pointer -> _void))
(define-gpu-native common gr_direct_context_flush_image
  (_fun #:blocking? #t _pointer _pointer -> _void))
(define-gpu-native common gr_direct_context_release_resources_and_abandon_context
  (_fun #:blocking? #t _pointer -> _void))

;; 0.77c: synchronous memory-only trace callbacks and GL interface helpers.
;; Deliberately not #:blocking?: these callbacks run synchronously on the owner.
(define-gpu-native common gr_direct_context_dump_memory_statistics
  (_fun _pointer _pointer -> _void))
(define-gpu-native opengl gr_glinterface_assemble_interface
  (_fun _pointer _get-gl-proc -> _pointer))
(define-gpu-native opengl gr_glinterface_assemble_gles_interface
  (_fun _pointer _get-gl-proc -> _pointer))
(define-gpu-native opengl gr_glinterface_assemble_webgl_interface
  (_fun _pointer _get-gl-proc -> _pointer))
(define-gpu-native opengl gr_glinterface_has_extension
  (_fun _pointer _string/utf-8 -> _stdbool))
