#lang racket/base

;;;
;;; Native GPU Context Bindings
;;;

;; Loads Ganesh context and interface entry points lazily.
;; Supplies common native services to the backend drivers.

;; FFI contracts below describe ABI values only. The group tag controls readiness checks; it does
;; not select a device or prove driver support. Domain/driver code supplies current-context checks
;; and owns create/unref pairing. Resolvers and native thread-local scopes must remain live for
;; the complete synchronous call; optional groups are resolved only when their backend is selected.

(require ffi/unsafe racket/promise racket/list "gpu-d3d12-types.rkt" "gpu-dxgi-types.rkt"
         (only-in "native.rkt" skia-native-library-handle) "types.rkt" "gpu-provider.rkt"
           "gpu-native-scope.rkt")
(provide gpu-native-check! gpu-native-inventory gpu-symbol-names)

;;;
;;; Lazy Backend Binding Registry
;;;

;; Separate lazy group: the CPU native-bindings registry remains unchanged.
;; Loading this module does not dlopen GL, Metal, a GUI, or even libSkiaSharp.

; library : promise?
;   Defers access to the checked Skia shared-library handle until a native binding is first used.
(define library (delay/sync (skia-native-library-handle)))

; bindings : list?
;   Accumulates native symbol promises for availability checks and detached binding inventories.
(define bindings '())

; define-gpu-native : syntax transformer
;   Declares a lazily resolved native procedure and registers its symbol for readiness and
;   inventory checks.
(define-syntax-rule (define-gpu-native group name type)
  (begin
    (provide name)
    (define promise (delay/sync (get-ffi-obj 'name (force library) type)))
    (set! bindings (cons (list 'group 'name promise) bindings))
    (define (name . arguments)
      (define call (force promise))
      (call-with-gpu-native-scope (lambda () (apply call arguments))))))

;;;
;;; Context State and Backend Construction
;;;

; _get-gl-proc : ctype?
;   Declares the GL resolver callback ABI: a user-data pointer and UTF-8 symbol name yield an
;   entry-point address.
(define _get-gl-proc (_fun _pointer _string/utf-8 -> _pointer))

; gr_recording_context_unref : (_fun _pointer -> _void) (FFI)
;   Calls the native gr_recording_context_unref entry point using the declared FFI layout.
(define-gpu-native common gr_recording_context_unref (_fun _pointer -> _void))

; gr_recording_context_get_direct_context : (_fun _pointer -> _pointer) (FFI)
;   Calls the native gr_recording_context_get_direct_context entry point using the declared FFI
;   layout.
(define-gpu-native common gr_recording_context_get_direct_context (_fun _pointer -> _pointer))

; gr_recording_context_get_backend : (_fun _pointer -> _int) (FFI)
;   Calls the native gr_recording_context_get_backend entry point using the declared FFI layout.
(define-gpu-native common gr_recording_context_get_backend (_fun _pointer -> _int))

; gr_recording_context_max_texture_size : (_fun _pointer -> _int) (FFI)
;   Calls the native gr_recording_context_max_texture_size entry point using the declared FFI
;   layout.
(define-gpu-native common gr_recording_context_max_texture_size (_fun _pointer -> _int))

; gr_recording_context_max_render_target_size : (_fun _pointer -> _int) (FFI)
;   Calls the native gr_recording_context_max_render_target_size entry point using the declared FFI
;   layout.
(define-gpu-native common gr_recording_context_max_render_target_size (_fun _pointer -> _int))

; gr_recording_context_get_max_surface_sample_count_for_color_type : (_fun _pointer _int -> _int)
;   (FFI)
;   Calls the native gr_recording_context_get_max_surface_sample_count_for_color_type entry point
;   using the declared FFI layout.
(define-gpu-native common gr_recording_context_get_max_surface_sample_count_for_color_type
  (_fun _pointer _int -> _int))

; gr_direct_context_is_abandoned : (_fun _pointer -> _stdbool) (FFI)
;   Calls the native gr_direct_context_is_abandoned entry point using the declared FFI layout.
(define-gpu-native common gr_direct_context_is_abandoned (_fun _pointer -> _stdbool))

; gr_direct_context_abandon_context : (_fun _pointer -> _void) (FFI)
;   Calls the native gr_direct_context_abandon_context entry point using the declared FFI layout.
(define-gpu-native common gr_direct_context_abandon_context (_fun _pointer -> _void))

; gr_direct_context_reset_context : (_fun _pointer _uint32 -> _void) (FFI)
;   Calls the native gr_direct_context_reset_context entry point using the declared FFI layout.
(define-gpu-native common gr_direct_context_reset_context (_fun _pointer _uint32 -> _void))

; gr_direct_context_flush : (_fun _pointer -> _void) (FFI)
;   Calls the native gr_direct_context_flush entry point using the declared FFI layout.
(define-gpu-native common gr_direct_context_flush (_fun _pointer -> _void))

; gr_direct_context_submit : (_fun _pointer _stdbool -> _stdbool) (FFI)
;   Calls the native gr_direct_context_submit entry point using the declared FFI layout.
(define-gpu-native common gr_direct_context_submit (_fun _pointer _stdbool -> _stdbool))

; gr_direct_context_get_resource_cache_limit : (_fun _pointer -> _size) (FFI)
;   Calls the native gr_direct_context_get_resource_cache_limit entry point using the declared FFI
;   layout.
(define-gpu-native common gr_direct_context_get_resource_cache_limit (_fun _pointer -> _size))

; gr_direct_context_get_resource_cache_usage : (_fun _pointer _pointer _pointer -> _void) (FFI)
;   Calls the native gr_direct_context_get_resource_cache_usage entry point using the declared FFI
;   layout.
(define-gpu-native common gr_direct_context_get_resource_cache_usage
  (_fun _pointer _pointer _pointer -> _void))

; gr_glinterface_create_native_interface : (_fun -> _pointer) (FFI)
;   Calls the native gr_glinterface_create_native_interface entry point using the declared FFI
;   layout.
(define-gpu-native opengl gr_glinterface_create_native_interface (_fun -> _pointer))

; gr_glinterface_assemble_gl_interface : (_fun _pointer _get-gl-proc -> _pointer) (FFI)
;   Calls the native gr_glinterface_assemble_gl_interface entry point using the declared FFI
;   layout.
(define-gpu-native opengl gr_glinterface_assemble_gl_interface
  (_fun _pointer _get-gl-proc -> _pointer))

; gr_glinterface_validate : (_fun _pointer -> _stdbool) (FFI)
;   Calls the native gr_glinterface_validate entry point using the declared FFI layout.
(define-gpu-native opengl gr_glinterface_validate (_fun _pointer -> _stdbool))

; gr_glinterface_unref : (_fun _pointer -> _void) (FFI)
;   Calls the native gr_glinterface_unref entry point using the declared FFI layout.
(define-gpu-native opengl gr_glinterface_unref (_fun _pointer -> _void))

; gr_direct_context_make_gl : (_fun _pointer -> _pointer) (FFI)
;   Calls the native gr_direct_context_make_gl entry point using the declared FFI layout.
(define-gpu-native opengl gr_direct_context_make_gl (_fun _pointer -> _pointer))

; gr_direct_context_make_metal : (_fun _pointer _pointer -> _pointer) (FFI)
;   Calls the native gr_direct_context_make_metal entry point using the declared FFI layout.
(define-gpu-native metal gr_direct_context_make_metal (_fun _pointer _pointer -> _pointer))
;; The C ABI takes the complete descriptor BY VALUE, not a pointer.

; gr_direct_context_make_direct3d : (_fun _gr-d3d-backend-context -> _pointer) (FFI)
;   Calls the native gr_direct_context_make_direct3d entry point using the declared FFI layout.
(define-gpu-native direct3d gr_direct_context_make_direct3d
  (_fun _gr-d3d-backend-context -> _pointer))

;;;
;;; Render Targets and Smoke Drawing
;;;

; sk_surface_new_render_target : (_fun _pointer _stdbool _sk-image-info-pointer _int _int _pointer
;   _stdbool -> _pointer) (FFI)
;   Calls the native sk_surface_new_render_target entry point using the declared FFI layout.
(define-gpu-native probe sk_surface_new_render_target
  (_fun _pointer _stdbool _sk-image-info-pointer _int _int _pointer _stdbool -> _pointer))

; sk_surface_get_recording_context : (_fun _pointer -> _pointer) (FFI)
;   Calls the native sk_surface_get_recording_context entry point using the declared FFI layout.
(define-gpu-native probe sk_surface_get_recording_context (_fun _pointer -> _pointer))
;; The following are existing CPU ABI entries, resolved here without adding
;; them to the CPU audit registry or manufacturing a public GPU surface.

; sk_surface_unref : (_fun _pointer -> _void) (FFI)
;   Calls the native sk_surface_unref entry point using the declared FFI layout.
(define-gpu-native probe sk_surface_unref (_fun _pointer -> _void))

; sk_surface_get_canvas : (_fun _pointer -> _pointer) (FFI)
;   Calls the native sk_surface_get_canvas entry point using the declared FFI layout.
(define-gpu-native probe sk_surface_get_canvas (_fun _pointer -> _pointer))

; sk_surface_read_pixels : (_fun _pointer _sk-image-info-pointer _bytes _size _int _int -> _stdbool)
;   (FFI)
;   Calls the native sk_surface_read_pixels entry point using the declared FFI layout.
(define-gpu-native probe sk_surface_read_pixels
  (_fun _pointer _sk-image-info-pointer _bytes _size _int _int -> _stdbool))

; sk_canvas_clear : (_fun _pointer _uint32 -> _void) (FFI)
;   Calls the native sk_canvas_clear entry point using the declared FFI layout.
(define-gpu-native probe sk_canvas_clear (_fun _pointer _uint32 -> _void))

; sk_canvas_draw_rect : (_fun _pointer _sk-rect-pointer _pointer -> _void) (FFI)
;   Calls the native sk_canvas_draw_rect entry point using the declared FFI layout.
(define-gpu-native probe sk_canvas_draw_rect (_fun _pointer _sk-rect-pointer _pointer -> _void))

; sk_paint_new : (_fun -> _pointer) (FFI)
;   Calls the native sk_paint_new entry point using the declared FFI layout.
(define-gpu-native probe sk_paint_new (_fun -> _pointer))

; sk_paint_delete : (_fun _pointer -> _void) (FFI)
;   Calls the native sk_paint_delete entry point using the declared FFI layout.
(define-gpu-native probe sk_paint_delete (_fun _pointer -> _void))

; sk_paint_set_color : (_fun _pointer _uint32 -> _void) (FFI)
;   Calls the native sk_paint_set_color entry point using the declared FFI layout.
(define-gpu-native probe sk_paint_set_color (_fun _pointer _uint32 -> _void))

; sk_paint_set_antialias : (_fun _pointer _stdbool -> _void) (FFI)
;   Calls the native sk_paint_set_antialias entry point using the declared FFI layout.
(define-gpu-native probe sk_paint_set_antialias (_fun _pointer _stdbool -> _void))

;;;
;;; Direct3D Target Descriptors
;;;

;; 0.49 optional DXGI group: offscreen Direct3D does not require these.

; gr_backendrendertarget_new_direct3d : (_fun _int _int _gr-d3d-texture-info-pointer -> _pointer)
;   (FFI)
;   Calls the native gr_backendrendertarget_new_direct3d entry point using the declared FFI layout.
(define-gpu-native dxgi gr_backendrendertarget_new_direct3d
  (_fun _int _int _gr-d3d-texture-info-pointer -> _pointer))

; gr_backendrendertarget_delete : (_fun _pointer -> _void) (FFI)
;   Calls the native gr_backendrendertarget_delete entry point using the declared FFI layout.
(define-gpu-native dxgi gr_backendrendertarget_delete (_fun _pointer -> _void))

; gr_backendrendertarget_is_valid : (_fun _pointer -> _stdbool) (FFI)
;   Calls the native gr_backendrendertarget_is_valid entry point using the declared FFI layout.
(define-gpu-native dxgi gr_backendrendertarget_is_valid (_fun _pointer -> _stdbool))

; gr_backendrendertarget_get_backend : (_fun _pointer -> _int) (FFI)
;   Calls the native gr_backendrendertarget_get_backend entry point using the declared FFI layout.
(define-gpu-native dxgi gr_backendrendertarget_get_backend (_fun _pointer -> _int))

; gr_backendrendertarget_get_samples : (_fun _pointer -> _int) (FFI)
;   Calls the native gr_backendrendertarget_get_samples entry point using the declared FFI layout.
(define-gpu-native dxgi gr_backendrendertarget_get_samples (_fun _pointer -> _int))

; gr_backendrendertarget_get_width : (_fun _pointer -> _int) (FFI)
;   Calls the native gr_backendrendertarget_get_width entry point using the declared FFI layout.
(define-gpu-native dxgi gr_backendrendertarget_get_width (_fun _pointer -> _int))

; gr_backendrendertarget_get_height : (_fun _pointer -> _int) (FFI)
;   Calls the native gr_backendrendertarget_get_height entry point using the declared FFI layout.
(define-gpu-native dxgi gr_backendrendertarget_get_height (_fun _pointer -> _int))

; sk_surface_new_backend_render_target : (_fun _pointer _pointer _int _int _pointer _pointer ->
;   _pointer) (FFI)
;   Calls the native sk_surface_new_backend_render_target entry point using the declared FFI
;   layout.
(define-gpu-native dxgi sk_surface_new_backend_render_target
  (_fun _pointer _pointer _int _int _pointer _pointer -> _pointer))

; gr_direct_context_free_gpu_resources : (_fun _pointer -> _void) (FFI)
;   Calls the native gr_direct_context_free_gpu_resources entry point using the declared FFI
;   layout.
(define-gpu-native dxgi gr_direct_context_free_gpu_resources (_fun _pointer -> _void))

;;;
;;; Symbol Selection and Readiness
;;;

; selected : symbol? -> list?
;   Selects common, probe, and requested-backend bindings in their original declaration order.
(define (selected backend)
  (unless (memq backend '(opengl metal direct3d dxgi))
    (raise-argument-error 'gpu-native-inventory "'opengl, 'metal, 'direct3d, or private 'dxgi group"
      backend))
  (filter (lambda (entry) (memq (car entry) (list 'common 'probe backend)))
          (reverse bindings)))

; gpu-symbol-names : symbol? -> (listof symbol?)
;   Returns the reviewed native symbol names required by the selected GPU binding group.
(define (gpu-symbol-names backend) (map cadr (selected backend)))

; gpu-native-inventory : any/c -> list?
;   Resolves selected symbols and reports availability without claiming context creation or
;   hardware acceleration.
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

; gpu-native-check! : any/c -> void?
;   Rejects missing symbols in the selected optional GPU group before backend construction.
(define (gpu-native-check! backend)
  (define inventory (gpu-native-inventory backend))
  (define missing (filter (lambda (row) (not (hash-ref row 'available))) inventory))
  (unless (null? missing)
    (gpu-unavailable 'native-symbols "missing optional GPU bindings: ~a"
                     (map (lambda (row) (hash-ref row 'name)) missing)))
  (void))

;;;
;;; Context Options, Targeted Flushes, and Teardown
;;;

;; 0.77b: the complete six-field m119 context-options descriptor is borrowed
;; synchronously. D3D's existing backend descriptor remains passed BY VALUE.

; gr_direct_context_make_gl_with_options : (_fun _pointer _pointer -> _pointer) (FFI)
;   Calls the native gr_direct_context_make_gl_with_options entry point using the declared FFI
;   layout.
(define-gpu-native opengl gr_direct_context_make_gl_with_options
  (_fun _pointer _pointer -> _pointer))

; gr_direct_context_make_metal_with_options : (_fun _pointer _pointer _pointer -> _pointer) (FFI)
;   Calls the native gr_direct_context_make_metal_with_options entry point using the declared FFI
;   layout.
(define-gpu-native metal gr_direct_context_make_metal_with_options
  (_fun _pointer _pointer _pointer -> _pointer))

; gr_direct_context_make_direct3d_with_options : (_fun _gr-d3d-backend-context _pointer -> _pointer)
;   (FFI)
;   Calls the native gr_direct_context_make_direct3d_with_options entry point using the declared
;   FFI layout.
(define-gpu-native direct3d gr_direct_context_make_direct3d_with_options
  (_fun _gr-d3d-backend-context _pointer -> _pointer))

; gr_direct_context_flush_surface : (_fun #:blocking? #t _pointer _pointer -> _void) (FFI)
;   Calls the native gr_direct_context_flush_surface entry point using the declared FFI layout.
(define-gpu-native common gr_direct_context_flush_surface
  (_fun #:blocking? #t _pointer _pointer -> _void))

; gr_direct_context_flush_image : (_fun #:blocking? #t _pointer _pointer -> _void) (FFI)
;   Calls the native gr_direct_context_flush_image entry point using the declared FFI layout.
(define-gpu-native common gr_direct_context_flush_image
  (_fun #:blocking? #t _pointer _pointer -> _void))

; gr_direct_context_release_resources_and_abandon_context : (_fun #:blocking? #t _pointer -> _void)
;   (FFI)
;   Calls the native gr_direct_context_release_resources_and_abandon_context entry point using the
;   declared FFI layout.
(define-gpu-native common gr_direct_context_release_resources_and_abandon_context
  (_fun #:blocking? #t _pointer -> _void))

;;;
;;; Memory Diagnostics and GL Interface Variants
;;;

;; 0.77c: synchronous memory-only trace callbacks and GL interface helpers.
;; Deliberately not #:blocking?: these callbacks run synchronously on the owner.

; gr_direct_context_dump_memory_statistics : (_fun _pointer _pointer -> _void) (FFI)
;   Calls the native gr_direct_context_dump_memory_statistics entry point using the declared FFI
;   layout.
(define-gpu-native common gr_direct_context_dump_memory_statistics
  (_fun _pointer _pointer -> _void))

; gr_glinterface_assemble_interface : (_fun _pointer _get-gl-proc -> _pointer) (FFI)
;   Calls the native gr_glinterface_assemble_interface entry point using the declared FFI layout.
(define-gpu-native opengl gr_glinterface_assemble_interface
  (_fun _pointer _get-gl-proc -> _pointer))

; gr_glinterface_assemble_gles_interface : (_fun _pointer _get-gl-proc -> _pointer) (FFI)
;   Calls the native gr_glinterface_assemble_gles_interface entry point using the declared FFI
;   layout.
(define-gpu-native opengl gr_glinterface_assemble_gles_interface
  (_fun _pointer _get-gl-proc -> _pointer))

; gr_glinterface_assemble_webgl_interface : (_fun _pointer _get-gl-proc -> _pointer) (FFI)
;   Calls the native gr_glinterface_assemble_webgl_interface entry point using the declared FFI
;   layout.
(define-gpu-native opengl gr_glinterface_assemble_webgl_interface
  (_fun _pointer _get-gl-proc -> _pointer))

; gr_glinterface_has_extension : (_fun _pointer _string/utf-8 -> _stdbool) (FFI)
;   Calls the native gr_glinterface_has_extension entry point using the declared FFI layout.
(define-gpu-native opengl gr_glinterface_has_extension
  (_fun _pointer _string/utf-8 -> _stdbool))
