#lang racket/base
(require ffi/unsafe
         racket/promise
         "native-loader.rkt"
         (only-in "native-abi.rkt" native-abi-check-layouts!)
         "native-layouts.rkt"
         "types.rkt" "audit-trace.rkt"
         (only-in "lifetime.rkt" lifetime-native-call))
(provide native-package-version native-platform native-filename
         skia-check! skia-available? skia-native-version skia-native-library-path
         skia-native-library-handle skia-native-capabilities skia-native-symbol-inventory)

(define native-bindings '())
(define-syntax-rule (define-native name signature)
  (begin
    (provide name)
    (define delayed-procedure
      (delay/sync
        (get-ffi-obj 'name (car (force native-library)) signature)))
    (set! native-bindings
          (cons (cons 'name delayed-procedure) native-bindings))
    (define (name . args)
      (audit-native-call 'name args
        (lambda ()
          (lifetime-native-call 'name args
            (lambda () (apply (force delayed-procedure) args))))))))

(define-native sk_version_get_milestone (_fun -> _int))
(define-native sk_version_get_increment (_fun -> _int))

;; 0.66 m119 factories. Inputs are copied or synchronously ref-counted.
(define-native sk_path_effect_create_1d_path (_fun _pointer _float _float _int -> _pointer))
(define-native sk_path_effect_create_2d_line (_fun _float _pointer -> _pointer))
(define-native sk_path_effect_create_2d_path (_fun _pointer _pointer -> _pointer))
(define-native sk_maskfilter_new_table (_fun _bytes -> _pointer))
(define-native sk_maskfilter_new_gamma (_fun _float -> _pointer))
(define-native sk_maskfilter_new_clip (_fun _uint8 _uint8 -> _pointer))
(define-native sk_maskfilter_new_shader (_fun _pointer -> _pointer))
(define-native sk_shader_new_perlin_noise_fractal_noise (_fun _float _float _int _float _pointer -> _pointer))
(define-native sk_shader_new_perlin_noise_turbulence (_fun _float _float _int _float _pointer -> _pointer))
(define-native sk_shader_new_empty (_fun  -> _pointer))
(define-native sk_shader_with_color_filter (_fun _pointer _pointer -> _pointer))
(define-native sk_shader_new_blender (_fun _pointer _pointer _pointer -> _pointer))
(define-native sk_blender_new_arithmetic (_fun _float _float _float _float _stdbool -> _pointer))
(define-native sk_imagefilter_new_blender (_fun _pointer _pointer _pointer _pointer -> _pointer))
(define-native sk_imagefilter_new_picture_with_rect (_fun _pointer _pointer -> _pointer))

;; 0.67 geometry completion. Pointer outputs remain synchronous private buffers.
(define-native sk_path_arc_to (_fun _pointer _float _float _float _int _int _float _float -> _void))
(define-native sk_path_rarc_to (_fun _pointer _float _float _float _int _int _float _float -> _void))
(define-native sk_path_arc_to_with_oval (_fun _pointer _pointer _float _float _stdbool -> _void))
(define-native sk_path_arc_to_with_points (_fun _pointer _float _float _float _float _float -> _void))
(define-native sk_path_add_arc (_fun _pointer _pointer _float _float -> _void))
(define-native sk_path_add_rect_start (_fun _pointer _pointer _int _uint32 -> _void))
(define-native sk_path_add_rrect_start (_fun _pointer _pointer _int _uint32 -> _void))
(define-native sk_path_add_path_matrix (_fun _pointer _pointer _pointer _int -> _void))
(define-native sk_path_add_poly (_fun _pointer _pointer _int _stdbool -> _void))
(define-native sk_path_get_segment_masks (_fun _pointer -> _uint32))
(define-native sk_path_rewind (_fun _pointer -> _void))
(define-native sk_path_is_line (_fun _pointer _pointer -> _stdbool))
(define-native sk_path_is_oval (_fun _pointer _pointer -> _stdbool))
(define-native sk_path_is_rect (_fun _pointer _pointer _pointer _pointer -> _stdbool))
(define-native sk_path_is_rrect (_fun _pointer _pointer -> _stdbool))
(define-native sk_pathop_tight_bounds (_fun _pointer _pointer -> _stdbool))
(define-native sk_path_convert_conic_to_quads (_fun _pointer _pointer _pointer _float _pointer _int -> _int))
(define-native sk_opbuilder_new (_fun -> _pointer))
(define-native sk_opbuilder_add (_fun _pointer _pointer _int -> _void))
(define-native sk_opbuilder_destroy (_fun _pointer -> _void))
(define-native sk_opbuilder_resolve (_fun _pointer _pointer -> _stdbool))
(define-native sk_paint_get_blendmode (_fun _pointer -> _int))
(define-native sk_paint_get_stroke_cap (_fun _pointer -> _int))
(define-native sk_paint_get_stroke_join (_fun _pointer -> _int))
(define-native sk_paint_get_stroke_miter (_fun _pointer -> _float))
(define-native sk_paint_get_stroke_width (_fun _pointer -> _float))
(define-native sk_paint_is_antialias (_fun _pointer -> _stdbool))
(define-native sk_paint_is_dither (_fun _pointer -> _stdbool))
(define-native sk_paint_reset (_fun _pointer -> _void))
(define-native sk_paint_set_dither (_fun _pointer _stdbool -> _void))
(define-native sk_region_cliperator_new (_fun _pointer _pointer -> _pointer))
(define-native sk_region_cliperator_delete (_fun _pointer -> _void))
(define-native sk_region_cliperator_done (_fun _pointer -> _stdbool))
(define-native sk_region_cliperator_next (_fun _pointer -> _void))
(define-native sk_region_cliperator_rect (_fun _pointer _pointer -> _void))
(define-native sk_region_spanerator_new (_fun _pointer _int _int _int -> _pointer))
(define-native sk_region_spanerator_delete (_fun _pointer -> _void))
(define-native sk_region_spanerator_next (_fun _pointer _pointer _pointer -> _stdbool))
(define-native sk_region_intersects_rect (_fun _pointer _pointer -> _stdbool))
(define-native sk_region_quick_contains (_fun _pointer _pointer -> _stdbool))
(define-native sk_region_quick_reject (_fun _pointer _pointer -> _stdbool))
(define-native sk_region_quick_reject_rect (_fun _pointer _pointer -> _stdbool))
(define-native sk_region_op_rect (_fun _pointer _pointer _int -> _stdbool))
(define-native sk_region_set_empty (_fun _pointer -> _stdbool))
(define-native sk_region_set_rect (_fun _pointer _pointer -> _stdbool))
(define-native sk_rrect_get_type (_fun _pointer -> _int))
(define-native sk_rrect_inset (_fun _pointer _float _float -> _void))
(define-native sk_rrect_outset (_fun _pointer _float _float -> _void))
(define-native sk_rrect_offset (_fun _pointer _float _float -> _void))
(define-native sk_rrect_set_nine_patch (_fun _pointer _pointer _float _float _float _float -> _void))
(define-native sk_rrect_transform (_fun _pointer _pointer _pointer -> _stdbool))
(define-native sk_path_count_verbs (_fun _pointer -> _int))
(define-native sk_rrect_get_rect (_fun _pointer _pointer -> _void))
(define-native sk_rrect_get_radii (_fun _pointer _int _pointer -> _void))
(define-native sk_rrect_is_valid (_fun _pointer -> _stdbool))

;; Structured geometry. Vertex arrays are copied by Skia. Lattice/atlas/patch
;; arrays remain alive for the complete synchronous canvas call.
(define-native sk_region_new (_fun -> _pointer))
(define-native sk_region_delete (_fun _pointer -> _void))
(define-native sk_region_set_rects (_fun _pointer _pointer _int -> _stdbool))
(define-native sk_region_set_region (_fun _pointer _pointer -> _stdbool))
(define-native sk_region_set_path (_fun _pointer _pointer _pointer -> _stdbool))
(define-native sk_region_is_empty (_fun _pointer -> _stdbool))
(define-native sk_region_is_rect (_fun _pointer -> _stdbool))
(define-native sk_region_is_complex (_fun _pointer -> _stdbool))
(define-native sk_region_get_bounds (_fun _pointer _sk-irect-pointer -> _void))
(define-native sk_region_get_boundary_path (_fun _pointer _pointer -> _stdbool))
(define-native sk_region_contains_point (_fun _pointer _int _int -> _stdbool))
(define-native sk_region_contains_rect (_fun _pointer _sk-irect-pointer -> _stdbool))
(define-native sk_region_contains (_fun _pointer _pointer -> _stdbool))
(define-native sk_region_intersects (_fun _pointer _pointer -> _stdbool))
(define-native sk_region_op (_fun _pointer _pointer _int -> _stdbool))
(define-native sk_region_translate (_fun _pointer _int _int -> _void))
(define-native sk_region_iterator_new (_fun _pointer -> _pointer))
(define-native sk_region_iterator_delete (_fun _pointer -> _void))
(define-native sk_region_iterator_done (_fun _pointer -> _stdbool))
(define-native sk_region_iterator_next (_fun _pointer -> _void))
(define-native sk_region_iterator_rect (_fun _pointer _sk-irect-pointer -> _void))
(define-native sk_paint_get_style (_fun _pointer -> _int))
;; m119: paint, source, destination, nullable cull rect, explicit query matrix.
(define-native sk_paint_get_fill_path
  (_fun _pointer _pointer _pointer _pointer _pointer -> _stdbool))
(define-native sk_vertices_make_copy
  (_fun _int _int _pointer _pointer _pointer _int _pointer -> _pointer))
(define-native sk_vertices_unref (_fun _pointer -> _void))
(define-native sk_canvas_draw_region (_fun _pointer _pointer _pointer -> _void))
(define-native sk_canvas_clip_region (_fun _pointer _pointer _int -> _void))
(define-native sk_canvas_draw_vertices (_fun _pointer _pointer _int _pointer -> _void))
(define-native sk_canvas_draw_image_nine
  (_fun _pointer _pointer _sk-irect-pointer _sk-rect-pointer _int _pointer -> _void))
(define-native sk_canvas_draw_image_lattice
  (_fun _pointer _pointer _sk-lattice-pointer _sk-rect-pointer _int _pointer -> _void))
(define-native sk_canvas_draw_atlas
  (_fun _pointer _pointer _pointer _pointer _pointer _int _int _sk-sampling-pointer
        _pointer _pointer -> _void))
(define-native sk_canvas_draw_patch
  (_fun _pointer _pointer _pointer _pointer _int _pointer -> _void))

;; Canvas primitives. Arrays and temporary rounded rectangles are borrowed only
;; during synchronous calls. Layer paint state is copied by Skia at save time.
(define-native sk_canvas_draw_point (_fun _pointer _float _float _pointer -> _void))
(define-native sk_canvas_draw_points (_fun _pointer _int _size _pointer _pointer -> _void))
(define-native sk_canvas_draw_arc
  (_fun _pointer _sk-rect-pointer _float _float _stdbool _pointer -> _void))
(define-native sk_canvas_draw_rrect (_fun _pointer _pointer _pointer -> _void))
(define-native sk_canvas_draw_drrect (_fun _pointer _pointer _pointer _pointer -> _void))
(define-native sk_canvas_draw_color (_fun _pointer _uint32 _int -> _void))
(define-native sk_path_add_rrect (_fun _pointer _pointer _int -> _void))
(define-native sk_canvas_get_local_clip_bounds (_fun _pointer _sk-rect-pointer -> _stdbool))
(define-native sk_canvas_get_device_clip_bounds (_fun _pointer _sk-irect-pointer -> _stdbool))
(define-native sk_canvas_is_clip_empty (_fun _pointer -> _stdbool))
(define-native sk_canvas_is_clip_rect (_fun _pointer -> _stdbool))
(define-native sk_canvas_quick_reject (_fun _pointer _sk-rect-pointer -> _stdbool))
(define-native sk_canvas_save_layer (_fun _pointer _pointer _pointer -> _int))
(define-native sk_rrect_new (_fun -> _pointer))
(define-native sk_rrect_delete (_fun _pointer -> _void))
(define-native sk_rrect_set_rect_radii (_fun _pointer _sk-rect-pointer _pointer -> _void))
(define-native sk_rrect_contains (_fun _pointer _sk-rect-pointer -> _stdbool))

;; SkSL compiler/reflection. Use index queries only after validating the count:
;; the C shim's from-name queries dereference a null pointer on a missing name.
(define-native sk_runtimeeffect_make_for_shader (_fun _pointer _pointer -> _pointer))
(define-native sk_runtimeeffect_make_for_color_filter (_fun _pointer _pointer -> _pointer))
(define-native sk_runtimeeffect_make_for_blender (_fun _pointer _pointer -> _pointer))
(define-native sk_runtimeeffect_unref (_fun _pointer -> _void))
(define-native sk_runtimeeffect_get_uniform_byte_size (_fun _pointer -> _size))
(define-native sk_runtimeeffect_get_uniforms_size (_fun _pointer -> _size))
(define-native sk_runtimeeffect_get_uniform_name (_fun _pointer _int _pointer -> _void))
(define-native sk_runtimeeffect_get_uniform_from_index
  (_fun _pointer _int _sk-runtime-uniform-pointer -> _void))
(define-native sk_runtimeeffect_get_children_size (_fun _pointer -> _size))
(define-native sk_runtimeeffect_get_child_name (_fun _pointer _int _pointer -> _void))
(define-native sk_runtimeeffect_get_child_from_index
  (_fun _pointer _int _sk-runtime-child-pointer -> _void))
(define-native sk_runtimeeffect_make_shader
  (_fun _pointer _pointer _pointer _size _pointer -> _pointer))
(define-native sk_runtimeeffect_make_color_filter
  (_fun _pointer _pointer _pointer _size -> _pointer))
(define-native sk_runtimeeffect_make_blender
  (_fun _pointer _pointer _pointer _size -> _pointer))
(define-native sk_blender_new_mode (_fun _int -> _pointer))
(define-native sk_blender_unref (_fun _pointer -> _void))
(define-native sk_paint_set_blender (_fun _pointer _pointer -> _void))
(define-native sk_paint_get_blender (_fun _pointer -> _pointer))

;; Document annotations. SkData contains copied, NUL-terminated ASCII URI/ID
;; bytes. PDF and SVG consume the data synchronously; picture recordings ref it.
(define-native sk_canvas_draw_url_annotation
  (_fun _pointer _sk-rect-pointer _pointer -> _void))
(define-native sk_canvas_draw_named_destination_annotation
  (_fun _pointer _sk-point-pointer _pointer -> _void))
(define-native sk_canvas_draw_link_destination_annotation
  (_fun _pointer _sk-rect-pointer _pointer -> _void))

;; SDR RGB color-space construction and detached numerical inspection.
(define-native sk_colorspace_new_rgb (_fun _sk-transfer-pointer _sk-xyz-pointer -> _pointer))
(define-native sk_colorspace_transfer_fn_named_srgb (_fun _sk-transfer-pointer -> _void))
(define-native sk_colorspace_transfer_fn_named_linear (_fun _sk-transfer-pointer -> _void))
(define-native sk_colorspace_transfer_fn_named_2dot2 (_fun _sk-transfer-pointer -> _void))
(define-native sk_colorspace_transfer_fn_named_rec2020 (_fun _sk-transfer-pointer -> _void))
(define-native sk_colorspace_transfer_fn_invert
  (_fun _sk-transfer-pointer _sk-transfer-pointer -> _stdbool))
(define-native sk_colorspace_primaries_to_xyzd50
  (_fun _sk-primaries-pointer _sk-xyz-pointer -> _stdbool))
(define-native sk_colorspace_xyz_named_srgb (_fun _sk-xyz-pointer -> _void))
(define-native sk_colorspace_xyz_named_adobe_rgb (_fun _sk-xyz-pointer -> _void))
(define-native sk_colorspace_xyz_named_display_p3 (_fun _sk-xyz-pointer -> _void))
(define-native sk_colorspace_xyz_named_rec2020 (_fun _sk-xyz-pointer -> _void))
(define-native sk_colorspace_xyz_named_xyz (_fun _sk-xyz-pointer -> _void))

;; Advanced image filters. Every array/rect is consumed synchronously and every
;; retained input is ref-counted by the pinned C shim. Crop pointers are nullable.
(define-native sk_imagefilter_new_offset (_fun _float _float _pointer _pointer -> _pointer))
(define-native sk_imagefilter_new_merge (_fun _pointer _int _pointer -> _pointer))
(define-native sk_imagefilter_new_blend (_fun _int _pointer _pointer _pointer -> _pointer))
(define-native sk_imagefilter_new_arithmetic
  (_fun _float _float _float _float _stdbool _pointer _pointer _pointer -> _pointer))
(define-native sk_imagefilter_new_dilate (_fun _float _float _pointer _pointer -> _pointer))
(define-native sk_imagefilter_new_erode (_fun _float _float _pointer _pointer -> _pointer))
(define-native sk_imagefilter_new_displacement_map_effect
  (_fun _int _int _float _pointer _pointer _pointer -> _pointer))
(define-native sk_imagefilter_new_matrix_convolution
  (_fun _sk-isize-pointer _pointer _float _float _sk-ipoint-pointer _int _stdbool
        _pointer _pointer -> _pointer))
(define-native sk_imagefilter_new_matrix_transform
  (_fun _sk-matrix-pointer _sk-sampling-pointer _pointer -> _pointer))
(define-native sk_imagefilter_new_image
  (_fun _pointer _sk-rect-pointer _sk-rect-pointer _sk-sampling-pointer -> _pointer))
(define-native sk_imagefilter_new_shader (_fun _pointer _stdbool _pointer -> _pointer))
(define-native sk_imagefilter_new_picture (_fun _pointer -> _pointer))
(define-native sk_imagefilter_new_tile
  (_fun _sk-rect-pointer _sk-rect-pointer _pointer -> _pointer))
(define-native sk_imagefilter_new_magnifier
  (_fun _sk-rect-pointer _float _float _sk-sampling-pointer _pointer _pointer -> _pointer))
(define-native sk_imagefilter_new_distant_lit_diffuse
  (_fun _sk-point3-pointer _uint32 _float _float _pointer _pointer -> _pointer))
(define-native sk_imagefilter_new_point_lit_diffuse
  (_fun _sk-point3-pointer _uint32 _float _float _pointer _pointer -> _pointer))
(define-native sk_imagefilter_new_spot_lit_diffuse
  (_fun _sk-point3-pointer _sk-point3-pointer _float _float _uint32 _float _float
        _pointer _pointer -> _pointer))
(define-native sk_imagefilter_new_distant_lit_specular
  (_fun _sk-point3-pointer _uint32 _float _float _float _pointer _pointer -> _pointer))
(define-native sk_imagefilter_new_point_lit_specular
  (_fun _sk-point3-pointer _uint32 _float _float _float _pointer _pointer -> _pointer))
(define-native sk_imagefilter_new_spot_lit_specular
  (_fun _sk-point3-pointer _sk-point3-pointer _float _float _uint32 _float _float _float
        _pointer _pointer -> _pointer))

;; Affine matrix adapters. Canvas uses the 64-byte SkM44 storage; path,
;; shader and measurement functions use the 36-byte sk_matrix_t conversion.
(define-native sk_canvas_get_matrix (_fun _pointer _sk-m44-pointer -> _void))
(define-native sk_canvas_set_matrix (_fun _pointer _sk-m44-pointer -> _void))
(define-native sk_canvas_concat (_fun _pointer _sk-m44-pointer -> _void))
(define-native sk_path_transform (_fun _pointer _sk-matrix-pointer -> _void))
(define-native sk_path_transform_to_dest
  (_fun _pointer _sk-matrix-pointer _pointer -> _void))
(define-native sk_shader_with_local_matrix
  (_fun _pointer _sk-matrix-pointer -> _pointer))
(define-native sk_pathmeasure_get_matrix
  (_fun _pointer _float _sk-matrix-pointer _int -> _stdbool))

;; Iterators are scoped inside an eager snapshot; no native iterator escapes.
;; The C shim uses int (not bool) for forceClose and isCloseLine.
(define-native sk_path_create_iter (_fun _pointer _int -> _pointer))
(define-native sk_path_iter_next (_fun _pointer _pointer -> _int))
(define-native sk_path_iter_conic_weight (_fun _pointer -> _float))
(define-native sk_path_iter_is_close_line (_fun _pointer -> _int))
(define-native sk_path_iter_destroy (_fun _pointer -> _void))
(define-native sk_path_create_rawiter (_fun _pointer -> _pointer))
(define-native sk_path_rawiter_next (_fun _pointer _pointer -> _int))
(define-native sk_path_rawiter_conic_weight (_fun _pointer -> _float))
(define-native sk_path_rawiter_destroy (_fun _pointer -> _void))

;; SVG owns its canvas; surface/PDF canvases remain borrowed and must never
;; be passed to this destructor. The pinned SVG C shim has no flags argument.
(define-native sk_svgcanvas_create_with_stream
  (_fun _sk-rect-pointer _pointer -> _pointer))
(define-native sk_canvas_destroy (_fun _pointer -> _void))

;; Native PDF output. SkDocument borrows the stream and owns each page canvas.
(define-native sk_document_create_pdf_from_stream_with_metadata
  (_fun _pointer _sk-pdf-metadata-pointer -> _pointer))
(define-native sk_document_begin_page
  (_fun _pointer _float _float _pointer -> _pointer))
(define-native sk_document_end_page (_fun _pointer -> _void))
(define-native sk_document_close (_fun _pointer -> _void))
(define-native sk_document_abort (_fun _pointer -> _void))
(define-native sk_document_unref (_fun _pointer -> _void))
(define-native sk_string_new_with_copy (_fun _bytes _size -> _pointer))

;; Immutable native data and codec inspection.
(define-native sk_data_new_with_copy (_fun _bytes _size -> _pointer))
(define-native sk_data_new_from_file (_fun _bytes -> _pointer))
(define-native sk_data_unref (_fun _pointer -> _void))
(define-native sk_data_get_size (_fun _pointer -> _size))
(define-native sk_data_get_data (_fun _pointer -> _pointer))
(define-native sk_codec_new_from_data (_fun _pointer -> _pointer))
(define-native sk_codec_destroy (_fun _pointer -> _void))
(define-native sk_codec_get_info (_fun _pointer _sk-image-info-pointer -> _void))
(define-native sk_codec_get_encoded_format (_fun _pointer -> _int))
(define-native sk_codec_get_origin (_fun _pointer -> _int))
(define-native sk_codec_get_frame_count (_fun _pointer -> _int))
;; Synchronous decode only: native code never retains the Racket pixel buffer.
(define-native sk_codec_get_pixels
  (_fun _pointer _sk-image-info-pointer _bytes _size _sk-codec-options-pointer -> _int))
(define-native sk_codec_get_frame_info_for_index
  (_fun _pointer _int _sk-codec-frame-info-pointer -> _stdbool))
(define-native sk_codec_get_repetition_count (_fun _pointer -> _int))

;; Ref-counted color spaces plus ICC profile helpers. The two built-in sRGB
;; constructors return immortal singleton pointers; public wrappers take an
;; explicit reference before treating them as owned resources.
(define-native sk_colorspace_ref (_fun _pointer -> _void))
(define-native sk_colorspace_unref (_fun _pointer -> _void))
(define-native sk_colorspace_new_srgb (_fun -> _pointer))
(define-native sk_colorspace_new_srgb_linear (_fun -> _pointer))
(define-native sk_colorspace_is_srgb (_fun _pointer -> _stdbool))
(define-native sk_colorspace_gamma_close_to_srgb (_fun _pointer -> _stdbool))
(define-native sk_colorspace_gamma_is_linear (_fun _pointer -> _stdbool))
(define-native sk_colorspace_equals (_fun _pointer _pointer -> _stdbool))
(define-native sk_colorspace_make_linear_gamma (_fun _pointer -> _pointer))
(define-native sk_colorspace_make_srgb_gamma (_fun _pointer -> _pointer))
(define-native sk_colorspace_icc_profile_new (_fun -> _pointer))
(define-native sk_colorspace_icc_profile_delete (_fun _pointer -> _void))
(define-native sk_colorspace_icc_profile_parse
  (_fun _pointer _size _pointer -> _stdbool))
(define-native sk_colorspace_new_icc (_fun _pointer -> _pointer))
;; SkColorSpace::toProfile populates an in-memory skcms profile but does not
;; serialize ICC bytes. Query the numerical transfer function and D50 matrix
;; instead; the Racket layer writes a compact matrix/TRC ICC profile.
(define-native sk_colorspace_is_numerical_transfer_fn
  (_fun _pointer _pointer -> _stdbool))
(define-native sk_colorspace_to_xyzd50
  (_fun _pointer _pointer -> _stdbool))

;; Stream access used by the HarfBuzz shaping bridge.
(define-native sk_stream_asset_destroy (_fun _pointer -> _void))
(define-native sk_stream_get_length (_fun _pointer -> _size))
(define-native sk_stream_read (_fun _pointer _bytes _size -> _size))

;; Native-owned CPU surfaces. No Racket byte buffer is retained by Skia.
(define-native sk_surface_new_raster
  (_fun _sk-image-info-pointer _size _pointer -> _pointer))

;; Direct storage is native-owned by the Racket wrapper. A null releaseProc
;; means Skia borrows it only until the scoped surface is unreferenced.
(define-native sk_surface_new_raster_direct
  (_fun _sk-image-info-pointer _pointer _size _pointer _pointer _pointer -> _pointer))
(define-native sk_pixmap_new_with_params
  (_fun _sk-image-info-pointer _pointer _size -> _pointer))
(define-native sk_pixmap_get_pixel_color (_fun _pointer _int _int -> _uint32))
(define-native sk_pixmap_read_pixels
  (_fun _pointer _sk-image-info-pointer _bytes _size _int _int -> _stdbool))
(define-native sk_pixmap_erase_color (_fun _pointer _uint32 _pointer -> _stdbool))
(define-native sk_pixmap_scale_pixels
  (_fun _pointer _pointer _sk-sampling-pointer -> _stdbool))
(define-native sk_surface_unref (_fun _pointer -> _void))
(define-native sk_surface_get_canvas (_fun _pointer -> _pointer))
(define-native sk_surface_new_image_snapshot (_fun _pointer -> _pointer))
(define-native sk_surface_read_pixels
  (_fun _pointer _sk-image-info-pointer _bytes _size _int _int -> _stdbool))
(define-native sk_surface_peek_pixels (_fun _pointer _pointer -> _stdbool))

(define-native sk_canvas_clear (_fun _pointer _uint32 -> _void))
(define-native sk_canvas_save (_fun _pointer -> _int))
(define-native sk_canvas_get_save_count (_fun _pointer -> _int))
(define-native sk_canvas_restore (_fun _pointer -> _void))
(define-native sk_canvas_restore_to_count (_fun _pointer _int -> _void))
(define-native sk_canvas_translate (_fun _pointer _float _float -> _void))
(define-native sk_canvas_scale (_fun _pointer _float _float -> _void))
(define-native sk_canvas_rotate_degrees (_fun _pointer _float -> _void))
(define-native sk_canvas_rotate_radians (_fun _pointer _float -> _void))
(define-native sk_canvas_skew (_fun _pointer _float _float -> _void))
(define-native sk_canvas_reset_matrix (_fun _pointer -> _void))
(define-native sk_canvas_clip_rect_with_operation
  (_fun _pointer _sk-rect-pointer _int _stdbool -> _void))
(define-native sk_canvas_clip_path_with_operation
  (_fun _pointer _pointer _int _stdbool -> _void))
(define-native sk_canvas_draw_paint (_fun _pointer _pointer -> _void))
(define-native sk_canvas_draw_line
  (_fun _pointer _float _float _float _float _pointer -> _void))
(define-native sk_canvas_draw_rect
  (_fun _pointer _sk-rect-pointer _pointer -> _void))
(define-native sk_canvas_draw_round_rect
  (_fun _pointer _sk-rect-pointer _float _float _pointer -> _void))
(define-native sk_canvas_draw_circle
  (_fun _pointer _float _float _float _pointer -> _void))
(define-native sk_canvas_draw_oval
  (_fun _pointer _sk-rect-pointer _pointer -> _void))
(define-native sk_canvas_draw_path (_fun _pointer _pointer _pointer -> _void))
(define-native sk_canvas_draw_image
  (_fun _pointer _pointer _float _float _sk-sampling-pointer _pointer -> _void))
(define-native sk_canvas_draw_image_rect
  (_fun _pointer _pointer _sk-rect-pointer _sk-rect-pointer
        _sk-sampling-pointer _pointer -> _void))
(define-native sk_canvas_draw_picture
  (_fun _pointer _pointer _pointer _pointer -> _void))

;; Simple text drawing.  The public API intentionally names this "simple"
;; because this Skia entry point does not perform script shaping.
(define-native sk_canvas_draw_simple_text
  (_fun _pointer _bytes _size _int _float _float _pointer _pointer -> _void))
(define-native sk_canvas_draw_text_blob
  (_fun _pointer _pointer _float _float _pointer -> _void))

(define-native sk_paint_new (_fun -> _pointer))
(define-native sk_paint_clone (_fun _pointer -> _pointer))
(define-native sk_paint_delete (_fun _pointer -> _void))
(define-native sk_paint_set_antialias (_fun _pointer _stdbool -> _void))
(define-native sk_paint_set_color (_fun _pointer _uint32 -> _void))
(define-native sk_paint_get_color (_fun _pointer -> _uint32))
(define-native sk_paint_set_style (_fun _pointer _int -> _void))
(define-native sk_paint_set_stroke_width (_fun _pointer _float -> _void))
(define-native sk_paint_set_stroke_miter (_fun _pointer _float -> _void))
(define-native sk_paint_set_stroke_cap (_fun _pointer _int -> _void))
(define-native sk_paint_set_stroke_join (_fun _pointer _int -> _void))
(define-native sk_paint_set_blendmode (_fun _pointer _int -> _void))
(define-native sk_paint_get_shader (_fun _pointer -> _pointer))
(define-native sk_paint_set_shader (_fun _pointer _pointer -> _void))
(define-native sk_paint_get_path_effect (_fun _pointer -> _pointer))
(define-native sk_paint_set_path_effect (_fun _pointer _pointer -> _void))
(define-native sk_paint_get_colorfilter (_fun _pointer -> _pointer))
(define-native sk_paint_set_colorfilter (_fun _pointer _pointer -> _void))
(define-native sk_paint_get_maskfilter (_fun _pointer -> _pointer))
(define-native sk_paint_set_maskfilter (_fun _pointer _pointer -> _void))
(define-native sk_paint_get_imagefilter (_fun _pointer -> _pointer))
(define-native sk_paint_set_imagefilter (_fun _pointer _pointer -> _void))

;; Color, mask, and image filter primitives. The factory functions return one
;; owned reference. Paint setters and image-filter graph constructors retain
;; their own references to supplied child filters.
(define-native sk_colorfilter_unref (_fun _pointer -> _void))
(define-native sk_colorfilter_new_mode (_fun _uint32 _int -> _pointer))
(define-native sk_colorfilter_new_compose (_fun _pointer _pointer -> _pointer))
(define-native sk_colorfilter_new_color_matrix (_fun _pointer -> _pointer))
;; Remaining m119 CPU color filters. Tables/matrices/configs are copied during
;; the call; lerp retains its children. High-contrast layout is tested separately.
(define-native sk_colorfilter_new_hsla_matrix (_fun _pointer -> _pointer))
(define-native sk_colorfilter_new_linear_to_srgb_gamma (_fun -> _pointer))
(define-native sk_colorfilter_new_srgb_to_linear_gamma (_fun -> _pointer))
(define-native sk_colorfilter_new_lerp (_fun _float _pointer _pointer -> _pointer))
(define-native sk_colorfilter_new_luma_color (_fun -> _pointer))
(define-native sk_colorfilter_new_high_contrast (_fun _pointer -> _pointer))
(define-native sk_colorfilter_new_table (_fun _pointer -> _pointer))
(define-native sk_colorfilter_new_table_argb
  (_fun _pointer _pointer _pointer _pointer -> _pointer))
(define-native sk_colorfilter_new_lighting (_fun _uint32 _uint32 -> _pointer))

(define-native sk_maskfilter_unref (_fun _pointer -> _void))
(define-native sk_maskfilter_new_blur_with_flags
  (_fun _int _float _stdbool -> _pointer))

(define-native sk_imagefilter_unref (_fun _pointer -> _void))
(define-native sk_imagefilter_new_blur
  (_fun _float _float _int _pointer _pointer -> _pointer))
(define-native sk_imagefilter_new_color_filter
  (_fun _pointer _pointer _pointer -> _pointer))
(define-native sk_imagefilter_new_compose
  (_fun _pointer _pointer -> _pointer))
(define-native sk_imagefilter_new_drop_shadow
  (_fun _float _float _float _float _uint32 _pointer _pointer -> _pointer))
(define-native sk_imagefilter_new_drop_shadow_only
  (_fun _float _float _float _float _uint32 _pointer _pointer -> _pointer))

;; Shader/gradient primitives. Gradient arrays are consumed synchronously;
;; Skia constructs its own immutable shader state before these calls return.
(define-native sk_shader_unref (_fun _pointer -> _void))
(define-native sk_shader_new_color (_fun _uint32 -> _pointer))
(define-native sk_shader_new_linear_gradient
  (_fun _pointer _pointer _pointer _int _int _pointer -> _pointer))
(define-native sk_shader_new_radial_gradient
  (_fun _sk-point-pointer _float _pointer _pointer _int _int _pointer -> _pointer))
(define-native sk_shader_new_sweep_gradient
  (_fun _sk-point-pointer _pointer _pointer _int _int _float _float _pointer
        -> _pointer))
(define-native sk_shader_new_two_point_conical_gradient
  (_fun _sk-point-pointer _float _sk-point-pointer _float
        _pointer _pointer _int _int _pointer -> _pointer))
(define-native sk_shader_new_blend
  (_fun _int _pointer _pointer -> _pointer))

(define-native sk_path_new (_fun -> _pointer))
(define-native sk_path_delete (_fun _pointer -> _void))
(define-native sk_path_clone (_fun _pointer -> _pointer))
(define-native sk_path_move_to (_fun _pointer _float _float -> _void))
(define-native sk_path_rmove_to (_fun _pointer _float _float -> _void))
(define-native sk_path_line_to (_fun _pointer _float _float -> _void))
(define-native sk_path_rline_to (_fun _pointer _float _float -> _void))
(define-native sk_path_quad_to
  (_fun _pointer _float _float _float _float -> _void))
(define-native sk_path_rquad_to
  (_fun _pointer _float _float _float _float -> _void))
(define-native sk_path_conic_to
  (_fun _pointer _float _float _float _float _float -> _void))
(define-native sk_path_rconic_to
  (_fun _pointer _float _float _float _float _float -> _void))
(define-native sk_path_cubic_to
  (_fun _pointer _float _float _float _float _float _float -> _void))
(define-native sk_path_rcubic_to
  (_fun _pointer _float _float _float _float _float _float -> _void))
(define-native sk_path_close (_fun _pointer -> _void))
(define-native sk_path_reset (_fun _pointer -> _void))
(define-native sk_path_add_rect (_fun _pointer _sk-rect-pointer _int -> _void))
(define-native sk_path_add_rounded_rect
  (_fun _pointer _sk-rect-pointer _float _float _int -> _void))
(define-native sk_path_add_oval (_fun _pointer _sk-rect-pointer _int -> _void))
(define-native sk_path_add_circle
  (_fun _pointer _float _float _float _int -> _void))
(define-native sk_path_add_path
  (_fun _pointer _pointer _int -> _void))
(define-native sk_path_add_path_offset
  (_fun _pointer _pointer _float _float _int -> _void))
(define-native sk_path_add_path_reverse (_fun _pointer _pointer -> _void))
(define-native sk_path_count_points (_fun _pointer -> _int))
(define-native sk_path_get_point (_fun _pointer _int _sk-point-pointer -> _void))
(define-native sk_path_get_last_point (_fun _pointer _sk-point-pointer -> _stdbool))
(define-native sk_path_is_convex (_fun _pointer -> _stdbool))
(define-native sk_path_parse_svg_string (_fun _pointer _bytes -> _stdbool))
(define-native sk_path_to_svg_string (_fun _pointer _pointer -> _void))
(define-native sk_path_get_bounds (_fun _pointer _sk-rect-pointer -> _void))
(define-native sk_path_compute_tight_bounds
  (_fun _pointer _sk-rect-pointer -> _void))
(define-native sk_path_contains (_fun _pointer _float _float -> _stdbool))
(define-native sk_path_get_filltype (_fun _pointer -> _int))
(define-native sk_path_set_filltype (_fun _pointer _int -> _void))

;; Path effects. These are SkRefCnt-derived and the constructors return one
;; owned reference. Paint setters retain their own reference.
(define-native sk_path_effect_unref (_fun _pointer -> _void))
(define-native sk_path_effect_create_dash
  (_fun _pointer _int _float -> _pointer))
(define-native sk_path_effect_create_corner (_fun _float -> _pointer))
(define-native sk_path_effect_create_discrete
  (_fun _float _float _uint32 -> _pointer))
(define-native sk_path_effect_create_compose
  (_fun _pointer _pointer -> _pointer))
(define-native sk_path_effect_create_sum
  (_fun _pointer _pointer -> _pointer))
(define-native sk_path_effect_create_trim
  (_fun _float _float _int -> _pointer))

;; Path measurement. The public wrapper snapshots the source path because the
;; native SkPathMeasure stores a pointer to path data rather than retaining a
;; ref-counted object.
(define-native sk_pathmeasure_new_with_path
  (_fun _pointer _stdbool _float -> _pointer))
(define-native sk_pathmeasure_destroy (_fun _pointer -> _void))
(define-native sk_pathmeasure_set_path
  (_fun _pointer _pointer _stdbool -> _void))
(define-native sk_pathmeasure_get_length (_fun _pointer -> _float))
(define-native sk_pathmeasure_get_pos_tan
  (_fun _pointer _float _sk-point-pointer _sk-point-pointer -> _stdbool))
(define-native sk_pathmeasure_get_segment
  (_fun _pointer _float _float _pointer _stdbool -> _stdbool))
(define-native sk_pathmeasure_is_closed (_fun _pointer -> _stdbool))
(define-native sk_pathmeasure_next_contour (_fun _pointer -> _stdbool))

;; Boolean path operations.
(define-native sk_pathop_op
  (_fun _pointer _pointer _int _pointer -> _stdbool))
(define-native sk_pathop_simplify
  (_fun _pointer _pointer -> _stdbool))
(define-native sk_pathop_as_winding
  (_fun _pointer _pointer -> _stdbool))

;; Picture recording / replay.
(define-native sk_picture_unref (_fun _pointer -> _void))
;; m119 picture streams, metadata, picture shaders, and optional spatial index.
(define-native sk_picture_get_unique_id (_fun _pointer -> _uint32))
(define-native sk_picture_get_cull_rect (_fun _pointer _sk-rect-pointer -> _void))
(define-native sk_picture_approximate_op_count (_fun _pointer _stdbool -> _int))
(define-native sk_picture_approximate_bytes_used (_fun _pointer -> _size))
(define-native sk_picture_serialize_to_data (_fun _pointer -> _pointer))
(define-native sk_picture_deserialize_from_data (_fun _pointer -> _pointer))
(define-native sk_picture_make_shader
  (_fun _pointer _int _int _int _pointer _pointer -> _pointer))
(define-native sk_rtree_factory_new (_fun -> _pointer))
(define-native sk_rtree_factory_delete (_fun _pointer -> _void))
(define-native sk_picture_recorder_begin_recording_with_bbh_factory
  (_fun _pointer _sk-rect-pointer _pointer -> _pointer))
(define-native sk_picture_recorder_new (_fun -> _pointer))
(define-native sk_picture_recorder_delete (_fun _pointer -> _void))
(define-native sk_picture_recorder_begin_recording
  (_fun _pointer _sk-rect-pointer -> _pointer))
(define-native sk_picture_recorder_end_recording
  (_fun _pointer -> _pointer))


;; Font manager, typeface, font, and text-blob primitives -------------------

;; 0.68a typeface resources. Factories return one owned reference; SkData
;; inputs are retained by native typefaces. Style/string/data outputs are owned.
;; Kerning writes count-1 int32 values only when its boolean result is true.
(define-native sk_typeface_create_from_data (_fun _pointer _int -> _pointer))
(define-native sk_fontmgr_create_from_data (_fun _pointer _pointer _int -> _pointer))
(define-native sk_fontmgr_create_styleset (_fun _pointer _int -> _pointer))
(define-native sk_fontmgr_match_family (_fun _pointer _bytes -> _pointer))
(define-native sk_fontstyleset_create_empty (_fun -> _pointer))
(define-native sk_fontstyleset_unref (_fun _pointer -> _void))
(define-native sk_fontstyleset_get_count (_fun _pointer -> _int))
(define-native sk_fontstyleset_get_style (_fun _pointer _int _pointer _pointer -> _void))
(define-native sk_fontstyleset_create_typeface (_fun _pointer _int -> _pointer))
(define-native sk_fontstyleset_match_style (_fun _pointer _pointer -> _pointer))
(define-native sk_fontstyle_get_weight (_fun _pointer -> _int))
(define-native sk_fontstyle_get_width (_fun _pointer -> _int))
(define-native sk_fontstyle_get_slant (_fun _pointer -> _int))
(define-native sk_typeface_is_fixed_pitch (_fun _pointer -> _stdbool))
(define-native sk_typeface_count_glyphs (_fun _pointer -> _int))
(define-native sk_typeface_count_tables (_fun _pointer -> _int))
(define-native sk_typeface_get_table_tags (_fun _pointer _pointer -> _int))
(define-native sk_typeface_get_table_size (_fun _pointer _uint32 -> _size))
(define-native sk_typeface_get_table_data (_fun _pointer _uint32 _size _size _bytes -> _size))
(define-native sk_typeface_copy_table_data (_fun _pointer _uint32 -> _pointer))
(define-native sk_typeface_get_post_script_name (_fun _pointer -> _pointer))
(define-native sk_typeface_get_kerning_pair_adjustments (_fun _pointer _pointer _int _pointer -> _stdbool))

(define-native sk_fontmgr_create_default (_fun -> _pointer))
(define-native sk_fontmgr_ref_default (_fun -> _pointer))
(define-native sk_fontmgr_unref (_fun _pointer -> _void))
(define-native sk_fontmgr_count_families (_fun _pointer -> _int))
(define-native sk_fontmgr_get_family_name (_fun _pointer _int _pointer -> _void))
(define-native sk_fontmgr_match_family_style
  (_fun _pointer _pointer _pointer -> _pointer))
(define-native sk_fontmgr_match_family_style_character
  (_fun _pointer _pointer _pointer _pointer _int _int32 -> _pointer))

(define-native sk_typeface_create_default (_fun -> _pointer))
(define-native sk_typeface_create_from_file (_fun _bytes _int -> _pointer))
(define-native sk_typeface_create_from_name (_fun _bytes _pointer -> _pointer))
(define-native sk_typeface_get_family_name (_fun _pointer -> _pointer))
(define-native sk_typeface_get_font_slant (_fun _pointer -> _int))
(define-native sk_typeface_get_font_weight (_fun _pointer -> _int))
(define-native sk_typeface_get_font_width (_fun _pointer -> _int))
(define-native sk_typeface_unref (_fun _pointer -> _void))
(define-native sk_typeface_get_units_per_em (_fun _pointer -> _int))
(define-native sk_typeface_open_stream (_fun _pointer _pointer -> _pointer))

(define-native sk_fontstyle_new (_fun _int _int _int -> _pointer))
(define-native sk_fontstyle_delete (_fun _pointer -> _void))

(define-native sk_font_new_with_values
  (_fun _pointer _float _float _float -> _pointer))
(define-native sk_font_delete (_fun _pointer -> _void))
(define-native sk_font_get_typeface (_fun _pointer -> _pointer))
(define-native sk_font_get_size (_fun _pointer -> _float))
(define-native sk_font_set_size (_fun _pointer _float -> _void))
(define-native sk_font_get_scale_x (_fun _pointer -> _float))
(define-native sk_font_set_scale_x (_fun _pointer _float -> _void))
(define-native sk_font_get_skew_x (_fun _pointer -> _float))
(define-native sk_font_set_skew_x (_fun _pointer _float -> _void))
(define-native sk_font_get_edging (_fun _pointer -> _int))
(define-native sk_font_set_edging (_fun _pointer _int -> _void))
(define-native sk_font_get_hinting (_fun _pointer -> _int))
(define-native sk_font_set_hinting (_fun _pointer _int -> _void))
(define-native sk_font_is_subpixel (_fun _pointer -> _stdbool))
(define-native sk_font_set_subpixel (_fun _pointer _stdbool -> _void))
(define-native sk_font_is_linear_metrics (_fun _pointer -> _stdbool))
(define-native sk_font_set_linear_metrics (_fun _pointer _stdbool -> _void))
(define-native sk_font_is_embolden (_fun _pointer -> _stdbool))
(define-native sk_font_set_embolden (_fun _pointer _stdbool -> _void))
(define-native sk_font_get_metrics
  (_fun _pointer _sk-font-metrics-pointer -> _float))
(define-native sk_font_measure_text
  (_fun _pointer _bytes _size _int _sk-rect-pointer _pointer -> _float))
(define-native sk_font_text_to_glyphs
  (_fun _pointer _bytes _size _int _pointer _int -> _int))
(define-native sk_font_unichar_to_glyph
  (_fun _pointer _int32 -> _uint16))
(define-native sk_font_get_path
  (_fun _pointer _uint16 _pointer -> _stdbool))
(define-native sk_text_utils_get_path
  (_fun _bytes _size _int _float _float _pointer _pointer -> _void))

(define-native sk_textblob_unref (_fun _pointer -> _void))
(define-native sk_textblob_get_bounds (_fun _pointer _sk-rect-pointer -> _void))
(define-native sk_textblob_get_unique_id (_fun _pointer -> _uint32))
(define-native sk_textblob_builder_new (_fun -> _pointer))
(define-native sk_textblob_builder_delete (_fun _pointer -> _void))
(define-native sk_textblob_builder_make (_fun _pointer -> _pointer))
(define-native sk_textblob_builder_alloc_run_pos
  (_fun _pointer _pointer _int _pointer _sk-textblob-runbuffer-pointer -> _void))

(define-native sk_string_new_empty (_fun -> _pointer))
(define-native sk_string_destructor (_fun _pointer -> _void))
(define-native sk_string_get_c_str (_fun _pointer -> _pointer))
(define-native sk_string_get_size (_fun _pointer -> _size))

(define-native sk_image_unref (_fun _pointer -> _void))
(define-native sk_image_new_raster_copy
  (_fun _sk-image-info-pointer _bytes _size -> _pointer))
(define-native sk_image_new_from_encoded (_fun _pointer -> _pointer))
(define-native sk_image_get_width (_fun _pointer -> _int))
(define-native sk_image_get_height (_fun _pointer -> _int))
(define-native sk_image_get_color_type (_fun _pointer -> _int))
(define-native sk_image_get_alpha_type (_fun _pointer -> _int))
(define-native sk_image_get_colorspace (_fun _pointer -> _pointer))
(define-native sk_image_make_subset_raster
  (_fun _pointer _sk-irect-pointer -> _pointer))
(define-native sk_image_make_raster_image (_fun _pointer -> _pointer))
(define-native sk_image_peek_pixels (_fun _pointer _pointer -> _stdbool))
(define-native sk_image_ref_encoded (_fun _pointer -> _pointer))
(define-native sk_image_make_shader
  (_fun _pointer _int _int _sk-sampling-pointer _pointer -> _pointer))
(define-native sk_image_read_pixels
  (_fun _pointer _sk-image-info-pointer _bytes _size _int _int _int -> _stdbool))

;; Native PNG encoder; no dependency on racket/draw's encoder.
(define-native sk_pixmap_new (_fun -> _pointer))
(define-native sk_pixmap_destructor (_fun _pointer -> _void))
(define-native sk_pixmap_set_colorspace (_fun _pointer _pointer -> _void))
(define-native sk_dynamicmemorywstream_new (_fun -> _pointer))
(define-native sk_dynamicmemorywstream_destroy (_fun _pointer -> _void))
(define-native sk_dynamicmemorywstream_detach_as_data (_fun _pointer -> _pointer))
(define-native sk_pngencoder_encode
  (_fun _pointer _pointer _sk-png-options-pointer -> _stdbool))
(define-native sk_jpegencoder_encode
  (_fun _pointer _pointer _sk-jpeg-options-pointer -> _stdbool))
(define-native sk_webpencoder_encode
  (_fun _pointer _pointer _sk-webp-options-pointer -> _stdbool))

;; Pre-resolve *all* callouts before allocating objects. Destructors then
;; never need a first-time library lookup while a finalizer is running.
(define native-ready
  (delay/sync
    (force native-library)
    (native-abi-check-layouts! (native-library-profile) (native-layout-sizes))
    (for ([entry (in-list (reverse native-bindings))])
      (force (cdr entry)))
    #t))

(define (skia-check!) (force native-ready) (void))

;; Optional registries share the exact checked handle, not a reopened filename.
;; These functions are private plumbing except for the explicit diagnostic API.
(define (skia-native-library-handle)
  (skia-check!)
  (car (force native-library)))
(define (skia-native-capabilities)
  (skia-check!)
  (hash-set (hash-set (hash-set (native-library-report)
                               'required_cpu_symbols_resolved #t)
                     'racket_layouts_checked #t)
            'required_cpu_symbol_count (length native-bindings)))
(define (skia-native-symbol-inventory names)
  (skia-check!)
  (native-symbol-inventory names))
(define (skia-available?)
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (skia-check!) #t))
(define (skia-native-version)
  (skia-check!)
  (format "~a.~a" (sk_version_get_milestone) (sk_version_get_increment)))
(define (skia-native-library-path)
  (skia-check!)
  (cdr (force native-library)))

;; 0.68b SkFont controls/queries; synchronous checked private buffers.
(define-native sk_font_is_force_auto_hinting (_fun _pointer -> _stdbool))
(define-native sk_font_set_force_auto_hinting (_fun _pointer _stdbool -> _void))
(define-native sk_font_is_embedded_bitmaps (_fun _pointer -> _stdbool))
(define-native sk_font_set_embedded_bitmaps (_fun _pointer _stdbool -> _void))
(define-native sk_font_is_baseline_snap (_fun _pointer -> _stdbool))
(define-native sk_font_set_baseline_snap (_fun _pointer _stdbool -> _void))
(define-native sk_font_set_typeface (_fun _pointer _pointer -> _void))
(define-native sk_font_get_widths_bounds (_fun _pointer _pointer _int _pointer _pointer _pointer -> _void))
(define-native sk_font_get_pos (_fun _pointer _pointer _int _pointer _pointer -> _void))
(define-native sk_font_get_xpos (_fun _pointer _pointer _int _pointer _float -> _void))
(define-native sk_font_get_paths (_fun _pointer _pointer _int _fpointer _pointer -> _void))
(define-native sk_font_break_text (_fun _pointer _bytes _size _int _float _pointer _pointer -> _size))

;; 0.69 multi-run text; all native buffers remain private and synchronous.
(define-native sk_textblob_builder_alloc_run (_fun _pointer _pointer _int _float _float _pointer _pointer -> _void))
(define-native sk_textblob_builder_alloc_run_pos_h (_fun _pointer _pointer _int _float _pointer _pointer -> _void))
(define-native sk_textblob_builder_alloc_run_rsxform (_fun _pointer _pointer _int _pointer _pointer -> _void))
(define-native sk_textblob_builder_alloc_run_text (_fun _pointer _pointer _int _float _float _int _pointer _pointer -> _void))
(define-native sk_textblob_builder_alloc_run_text_pos_h (_fun _pointer _pointer _int _float _int _pointer _pointer -> _void))
(define-native sk_textblob_builder_alloc_run_text_pos (_fun _pointer _pointer _int _int _pointer _pointer -> _void))
(define-native sk_textblob_builder_alloc_run_text_rsxform (_fun _pointer _pointer _int _int _pointer _pointer -> _void))
(define-native sk_textblob_get_intercepts (_fun _pointer _pointer _pointer _pointer -> _int))
(define-native sk_text_utils_get_pos_path (_fun _pointer _size _int _pointer _pointer _pointer -> _void))

;; 0.70: checked opaque-pixel inspection; no native pointer escapes.
(define-native sk_pixmap_compute_is_opaque (_fun _pointer -> _stdbool))

;; 0.71 pinned m119 Color4f ABI. Canvas takes a struct BY VALUE; other
;; Color4f arguments below are pointers to synchronous sixteen-byte records.
(define-native sk_canvas_clear_color4f (_fun _pointer _sk-color4f -> _void))
(define-native sk_canvas_draw_color4f (_fun _pointer _sk-color4f _int -> _void))
(define-native sk_paint_get_color4f (_fun _pointer _sk-color4f-pointer -> _void))
(define-native sk_paint_set_color4f (_fun _pointer _sk-color4f-pointer _pointer -> _void))
(define-native sk_shader_new_color4f (_fun _sk-color4f-pointer _pointer -> _pointer))
(define-native sk_shader_new_linear_gradient_color4f (_fun _pointer _pointer _pointer _pointer _int _int _pointer -> _pointer))
(define-native sk_shader_new_radial_gradient_color4f (_fun _pointer _float _pointer _pointer _pointer _int _int _pointer -> _pointer))
(define-native sk_shader_new_sweep_gradient_color4f (_fun _pointer _pointer _pointer _pointer _int _int _float _float _pointer -> _pointer))
(define-native sk_shader_new_two_point_conical_gradient_color4f (_fun _pointer _float _pointer _float _pointer _pointer _pointer _int _int _pointer -> _pointer))
(define-native sk_pixmap_get_pixel_color4f (_fun _pointer _int _int _sk-color4f-pointer -> _void))
(define-native sk_pixmap_get_pixel_alphaf (_fun _pointer _int _int -> _float))
(define-native sk_pixmap_erase_color4f (_fun _pointer _sk-color4f-pointer _pointer -> _stdbool))

;; 0.72 image queries and CPU operations: pinned m119 signatures.
;; Three metadata symbols also have existing GPU registry entries. The combined
;; inventory counts them once; their CPU declarations are intentional.
(define-native sk_image_get_unique_id (_fun _pointer -> _uint32))
(define-native sk_image_is_alpha_only (_fun _pointer -> _stdbool))
(define-native sk_image_is_lazy_generated (_fun _pointer -> _stdbool))
(define-native sk_image_is_texture_backed (_fun _pointer -> _stdbool))
(define-native sk_image_is_valid (_fun _pointer _pointer -> _stdbool))
(define-native sk_image_make_non_texture_image (_fun _pointer -> _pointer))
(define-native sk_image_make_raw_shader
  (_fun _pointer _int _int _sk-sampling-pointer _pointer -> _pointer))
(define-native sk_image_read_pixels_into_pixmap
  (_fun _pointer _pointer _int _int _int -> _stdbool))
(define-native sk_image_scale_pixels
  (_fun _pointer _pointer _sk-sampling-pointer _int -> _stdbool))
(define-native sk_image_make_with_filter_raster
  (_fun _pointer _pointer _sk-irect-pointer _sk-irect-pointer _sk-irect-pointer _sk-ipoint-pointer -> _pointer))

;; 0.73: SkSurfaceProps is opaque; getters are scalar, get_props is borrowed.
(define-native sk_surfaceprops_new (_fun _uint32 _int -> _pointer))
(define-native sk_surfaceprops_delete (_fun _pointer -> _void))
(define-native sk_surfaceprops_get_flags (_fun _pointer -> _uint32))
(define-native sk_surfaceprops_get_pixel_geometry (_fun _pointer -> _int))
(define-native sk_surface_get_props (_fun _pointer -> _pointer))

;; 0.74: SaveLayerRec, recorded drawables, and scoped diagnostic canvases.
;; Pointer-only arguments keep the public boundary independent of C++ layout.
(define-native sk_canvas_save_layer_rec (_fun _pointer _pointer -> _int))
(define-native sk_canvas_discard (_fun _pointer -> _void))
(define-native sk_canvas_draw_drawable (_fun _pointer _pointer _pointer -> _void))
(define-native sk_picture_recorder_end_recording_as_drawable (_fun _pointer -> _pointer))
(define-native sk_drawable_unref (_fun _pointer -> _void))
(define-native sk_drawable_get_generation_id (_fun _pointer -> _uint32))
(define-native sk_drawable_get_bounds (_fun _pointer _pointer -> _void))
(define-native sk_drawable_draw (_fun _pointer _pointer _pointer -> _void))
(define-native sk_drawable_new_picture_snapshot (_fun _pointer -> _pointer))
(define-native sk_drawable_notify_drawing_changed (_fun _pointer -> _void))
(define-native sk_drawable_approximate_bytes_used (_fun _pointer -> _size))
(define-native sk_nodraw_canvas_new (_fun _int _int -> _pointer))
(define-native sk_nodraw_canvas_destroy (_fun _pointer -> _void))
(define-native sk_nway_canvas_new (_fun _int _int -> _pointer))
(define-native sk_nway_canvas_destroy (_fun _pointer -> _void))
(define-native sk_nway_canvas_add_canvas (_fun _pointer _pointer -> _void))
(define-native sk_nway_canvas_remove_canvas (_fun _pointer _pointer -> _void))
(define-native sk_nway_canvas_remove_all (_fun _pointer -> _void))
(define-native sk_overdraw_canvas_new (_fun _pointer -> _pointer))
(define-native sk_overdraw_canvas_destroy (_fun _pointer -> _void))

;; 0.75a native stream foundations. All buffers are synchronously copied; no
;; Racket callbacks are installed in Skia's process-global managed-stream table.
(define-native sk_filestream_new (_fun _bytes -> _pointer))
(define-native sk_filestream_is_valid (_fun _pointer -> _stdbool))
(define-native sk_memorystream_new_with_data (_fun _bytes _size _stdbool -> _pointer))
(define-native sk_stream_destroy (_fun _pointer -> _void))
(define-native sk_stream_peek (_fun _pointer _bytes _size -> _size))
(define-native sk_stream_skip (_fun _pointer _size -> _size))
(define-native sk_stream_is_at_end (_fun _pointer -> _stdbool))
(define-native sk_stream_rewind (_fun _pointer -> _stdbool))
(define-native sk_stream_has_position (_fun _pointer -> _stdbool))
(define-native sk_stream_get_position (_fun _pointer -> _size))
(define-native sk_stream_seek (_fun _pointer _size -> _stdbool))
(define-native sk_stream_move (_fun _pointer _long -> _stdbool))
(define-native sk_stream_has_length (_fun _pointer -> _stdbool))
(define-native sk_stream_fork (_fun _pointer -> _pointer))
(define-native sk_stream_duplicate (_fun _pointer -> _pointer))
(define-native sk_wstream_write (_fun _pointer _bytes _size -> _stdbool))
(define-native sk_wstream_bytes_written (_fun _pointer -> _size))
(define-native sk_dynamicmemorywstream_copy_to (_fun _pointer _bytes -> _void))
(define-native sk_dynamicmemorywstream_detach_as_stream (_fun _pointer -> _pointer))
(define-native sk_data_new_from_stream (_fun _pointer _size -> _pointer))
(define-native sk_codec_new_from_stream (_fun _pointer _pointer -> _pointer))
(define-native sk_typeface_create_from_stream (_fun _pointer _int -> _pointer))
(define-native sk_picture_deserialize_from_stream (_fun _pointer -> _pointer))

;; 0.75b native file output. Live callbacks have a separately checked private registry.
(define-native sk_filewstream_new (_fun _bytes -> _pointer))
(define-native sk_filewstream_destroy (_fun _pointer -> _void))
(define-native sk_filewstream_is_valid (_fun _pointer -> _stdbool))
(define-native sk_wstream_flush (_fun _pointer -> _void))

;; 0.76a: synchronous encoded-coordinate codec negotiation. Both outputs use
;; existing checked layouts; no address is retained by the native query.
(define-native sk_codec_get_scaled_dimensions (_fun _pointer _float _pointer -> _void))
(define-native sk_codec_get_valid_subset (_fun _pointer _pointer -> _stdbool))

;; 0.76b: native scanline sessions. getScanlines borrows dst synchronously;
;; unlike incremental decode, it does not retain the caller's pixel address.
(define-native sk_codec_start_scanline_decode (_fun _pointer _sk-image-info-pointer _pointer -> _int))
(define-native sk_codec_get_scanlines (_fun _pointer _pointer _int _size -> _int))
(define-native sk_codec_skip_scanlines (_fun _pointer _int -> _stdbool))
(define-native sk_codec_get_scanline_order (_fun _pointer -> _int))
(define-native sk_codec_next_scanline (_fun _pointer -> _int))
(define-native sk_codec_output_scanline (_fun _pointer _int -> _int))

;; 0.76c retained pixel destination. Input callbacks only access bounded memory;
;; they do not run user procedures or port I/O. All C-facing descriptors and
;; result cells in codec-incremental.rkt use immobile storage.
(define-native sk_codec_start_incremental_decode
  (_fun _pointer _pointer _pointer _size _pointer -> _int))
(define-native sk_codec_incremental_decode
  (_fun _pointer _pointer -> _int))

;; 0.77a: explicit process-global cache controls; no import-time mutations.
(define-native sk_graphics_init (_fun -> _void))
(define-native sk_graphics_purge_font_cache (_fun -> _void))
(define-native sk_graphics_purge_resource_cache (_fun -> _void))
(define-native sk_graphics_purge_all_caches (_fun -> _void))
(define-native sk_graphics_get_font_cache_used (_fun -> _size))
(define-native sk_graphics_get_font_cache_limit (_fun -> _size))
(define-native sk_graphics_set_font_cache_limit (_fun _size -> _size))
(define-native sk_graphics_get_font_cache_count_used (_fun -> _int))
(define-native sk_graphics_get_font_cache_count_limit (_fun -> _int))
(define-native sk_graphics_set_font_cache_count_limit (_fun _int -> _int))
(define-native sk_graphics_get_resource_cache_total_bytes_used (_fun -> _size))
(define-native sk_graphics_get_resource_cache_total_byte_limit (_fun -> _size))
(define-native sk_graphics_set_resource_cache_total_byte_limit (_fun _size -> _size))
(define-native sk_graphics_get_resource_cache_single_allocation_byte_limit (_fun -> _size))
(define-native sk_graphics_set_resource_cache_single_allocation_byte_limit (_fun _size -> _size))
(define-native sk_graphics_dump_memory_statistics (_fun _pointer -> _void))
