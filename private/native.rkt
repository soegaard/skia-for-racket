#lang racket/base
(require ffi/unsafe
         racket/promise
         racket/runtime-path
         racket/path
         "types.rkt")
(provide native-package-version native-platform native-filename
         skia-check! skia-available? skia-native-version skia-native-library-path)

(define native-package-version "3.119.1")
(define-runtime-path native-root "../native")

(define (native-platform)
  (case (system-type 'os)
    [(macosx) "osx"]
    [(unix)
     (case (system-type 'arch)
       [(x86_64) "linux-x64"]
       [(aarch64) "linux-arm64"]
       [else #f])]
    [else #f]))

(define (native-filename)
  (if (eq? (system-type 'os) 'macosx)
      "libSkiaSharp.dylib"
      "libSkiaSharp.so"))

;; Requiring or compiling the package does not load a native library.
;; No network access occurs here. The explicit installer is separate.
(define native-library
  (delay/sync
    (define override (getenv "RACKET_SKIA_LIBRARY"))
    (define platform (native-platform))
    (define candidates
      (cond
        [override (list (path->complete-path override))]
        [platform
         (list (build-path native-root platform (native-filename))
               "libSkiaSharp")]
        [else
         (error 'skia
                "unsupported automatic library selection for ~a/~a; set RACKET_SKIA_LIBRARY to a compatible library"
                (system-type 'os) (system-type 'arch))]))
    (define failures '())
    (define found
      (for/or ([candidate (in-list candidates)])
        (with-handlers ([exn:fail?
                         (lambda (e)
                           (set! failures (cons (exn-message e) failures))
                           #f)])
          (define lib (ffi-lib candidate))
          ;; Probe the version before calling functions with versioned structs.
          (define milestone
            ((get-ffi-obj "sk_version_get_milestone" lib (_fun -> _int))))
          (unless (= milestone 119)
            (error 'skia
                   "incompatible native milestone ~a; this binding requires 119 (SkiaSharp ~a)"
                   milestone native-package-version))
          (cons lib candidate))))
    (unless found
      (error 'skia
             (string-append
              "could not load a compatible libSkiaSharp\n"
              "  run: bash tools/install-native.sh\n"
              "  or set RACKET_SKIA_LIBRARY to the full library filename\n"
              "  native package: ~a\n  loader errors: ~a")
             native-package-version (reverse failures)))
    found))

(define native-bindings '())
(define-syntax-rule (define-native name signature)
  (begin
    (provide name)
    (define delayed-procedure
      (delay/sync
        (get-ffi-obj 'name (car (force native-library)) signature)))
    (set! native-bindings
          (cons (cons 'name delayed-procedure) native-bindings))
    (define (name . args) (apply (force delayed-procedure) args))))

(define-native sk_version_get_milestone (_fun -> _int))
(define-native sk_version_get_increment (_fun -> _int))

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
(define-native sk_picture_recorder_new (_fun -> _pointer))
(define-native sk_picture_recorder_delete (_fun _pointer -> _void))
(define-native sk_picture_recorder_begin_recording
  (_fun _pointer _sk-rect-pointer -> _pointer))
(define-native sk_picture_recorder_end_recording
  (_fun _pointer -> _pointer))


;; Font manager, typeface, font, and text-blob primitives -------------------

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
    (for ([entry (in-list (reverse native-bindings))])
      (force (cdr entry)))
    #t))

(define (skia-check!) (force native-ready) (void))
(define (skia-available?)
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (skia-check!) #t))
(define (skia-native-version)
  (skia-check!)
  (format "~a.~a" (sk_version_get_milestone) (sk_version_get_increment)))
(define (skia-native-library-path)
  (skia-check!)
  (cdr (force native-library)))
