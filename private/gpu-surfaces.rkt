#lang racket/base
(require "gpu-format-util.rkt" "surface-property-native.rkt" "../surface-properties.rkt"
         (only-in "audit-trace.rkt" audit-mark-float-pixels!)
         "../image-info.rkt" "image-info-native.rkt"
         (prefix-in r: "../raster-buffers.rkt")
         (submod "core.rkt" image-operation-internals)
         (submod "../raster-buffers.rkt" image-operation-internals)
         (only-in "native.rkt" sk_surface_new_image_snapshot sk_image_unref
                  sk_image_get_width sk_image_get_height sk_image_get_color_type
                  sk_image_get_alpha_type sk_image_is_texture_backed))
(require "gpu-surface-identity.rkt")
(require ffi/unsafe ffi/unsafe/atomic
         "core.rkt" "types.rkt" "lifetime.rkt" "check.rkt"
         "gpu-domain.rkt" "gpu-context.rkt" "gpu-types.rkt"
         "gpu-surface-util.rkt" "gpu-surface-native.rkt" "gpu-raw.rkt" "gpu-io-trace.rkt"
         (prefix-in n: "gpu-native.rkt")
         (only-in "native.rkt" skia-check! sk_colorspace_ref sk_colorspace_unref)
         (submod "core.rkt" gpu-surface-internals)
         (submod "../raster-buffers.rkt" gpu-transfer-internals)
         "../color.rkt")
(provide gpu-surface-format-info gpu-surface->image-info gpu-surface-read-pixmap!
         gpu-surface->raster-buffer make-gpu-surface gpu-surface? gpu-surface-info
         gpu-flush! gpu-submit! gpu-flush-and-submit! gpu-wait!
         gpu-surface->rgba-bytes gpu-surface->raster-image
         gpu-surface-read-raster-buffer!)
(define (gpu-surface-domain/checked who s)
  (unless (gpu-surface? s) (raise-argument-error who "gpu-surface?" s))
  (resource-pointer (surface-h who s))
  (gpu-surface-domain s))
(define (native-context who context)
  (define d (context-domain who context))
  (define p (domain-pointer d))
  (when (n:gr_direct_context_is_abandoned p)
    (domain-request-shutdown! d 'native-context-lost)
    (error who "native context is lost or abandoned; abandon/close this execution domain"))
  p)
(define (gpu-flush! context)
  (define p (native-context 'gpu-flush! context))
  (gpu-surface-native-check!)
  (record-gpu-io! (hasheq 'kind "flush"))
  (flush/native p)
  (void))
(define (gpu-submit! context #:wait? [wait? #f])
  (boolean 'gpu-submit! wait?)
  (define p (native-context 'gpu-submit! context))
  (gpu-surface-native-check!)
  (record-gpu-io! (hasheq 'kind "submit" 'wait_requested wait?))
  (unless (submit/native p wait?)
    (error 'gpu-submit! "native submission failed (no CPU rendering fallback)"))
  (void))
(define (gpu-flush-and-submit! context #:wait? [wait? #f])
  (boolean 'gpu-flush-and-submit! wait?)
  (gpu-flush! context)
  (gpu-submit! context #:wait? wait?))
(define (gpu-wait! context)
  ;; Wait includes pending Skia commands as well as submitted backend work.
  ;; Presentation is a separate operation, not implied by this boundary.
  (gpu-flush-and-submit! context #:wait? #t))
(define (pointer=? a b)
  (and a b (= (cast a _pointer _uintptr) (cast b _pointer _uintptr))))
(define (gpu-surface-format-info context color-type)
  (define who 'gpu-surface-format-info)
  ;; Validation is native-free until a reviewed color symbol is established.
  (define label (gpu-format-label color-type))
  (define ct (choice who color-type color-type-values))
  (define d (context-domain who context))
  (define cp (native-context who context))
  (define maximum (n:gr_recording_context_get_max_surface_sample_count_for_color_type cp ct))
  (unless (and (exact-nonnegative-integer? maximum) (<= maximum #x7fffffff))
    (error who "invalid native sample-count capability"))
  (hasheq 'backend (symbol->string (domain-backend d))
          'context_generation (domain-generation d) 'color_type label
          'color_type_name (symbol->string color-type)
          'renderable (positive? maximum) 'max_sample_count maximum
          'max_render_target_size (n:gr_recording_context_max_render_target_size cp)
          'allocation_verified #f 'actual_sample_count #f))
(define (make-gpu-surface context width height
                          #:background [background 'transparent]
                          #:color-space [colorspace #f]
                          #:sample-count [samples 0]
                          #:opaque? [opaque? #f]
                          #:budgeted? [budgeted? #t]
                          #:color-type [color-type 'rgba-8888]
                          #:alpha-type [alpha-type #f]
                          #:surface-properties [properties (make-surface-properties)])
  (define who 'make-gpu-surface)
  (boolean who opaque?) (boolean who budgeted?)
  (define color (color->rgba background))
  (define alpha (or alpha-type (if opaque? 'opaque 'premul)))
  (when (and opaque? (not (eq? alpha 'opaque)))
    (error who "#:opaque? #t conflicts with the requested alpha type"))
  (when (and (eq? alpha 'opaque) (not (= (rgba-alpha color) 255)))
    (error who "an opaque GPU surface requires an opaque background"))
  (gpu-format-request who width height color-type alpha samples properties)
  (when (and (eq? color-type 'alpha-8) colorspace)
    (error who "alpha-only GPU targets have no color-space interpretation"))
  (define ct (choice who color-type color-type-values))
  (define at (choice who alpha alpha-type-values))
  (define d (context-domain who context))
  (define context-p (native-context who context))
  (define support (gpu-surface-format-info context color-type))
  (define maximum (hash-ref support 'max_render_target_size))
  (define max-samples (hash-ref support 'max_sample_count))
  (unless (and (positive? maximum) (<= width maximum) (<= height maximum))
    (error who "GPU target ~ax~a exceeds this context's reported limit ~a" width height maximum))
  (when (or (zero? max-samples) (> samples max-samples))
    (error who "unsupported GPU format/sample request: ~a, requested ~a, maximum ~a"
           color-type samples max-samples))
  (define ch (and colorspace (color-space-h who colorspace)))
  (skia-check!) (gpu-surface-native-check!)
  (define description
    (hasheq 'width width 'height height 'color_type (gpu-format-label color-type)
            'color_type_name (symbol->string color-type)
            'alpha_type (if (eq? alpha 'opaque) "opaque" "premultiplied")
            'alpha_type_name (symbol->string alpha) 'origin "top-left"
            'requested_sample_count samples 'actual_sample_count #f
            'sample_count_note "Skia may round a request up. The pinned C API exposes only the maximum, not this owned target's actual count."
            'surface_properties (surface-properties->jsexpr properties)
            'max_sample_count max-samples
            'budgeted budgeted? 'storage "gpu" 'target_kind "offscreen"))
  (define result #f) (define handle #f) (define completed? #f)
  (dynamic-wind
    void
    (lambda ()
      (call-with-owned who (if ch (list ch) '())
        (lambda color-pointers
          (define cp (and ch (car color-pointers)))
          (call-with-native-surface-properties who properties
            (lambda (props)
              (set! handle
                (domain-new-resource d 'surface
                  (lambda ()
                    (define sp
                      (n:sk_surface_new_render_target context-p budgeted?
                        (make-sk-image-info cp width height ct at)
                        samples gr-top-left props #f))
                    (when (and sp cp) (sk_colorspace_ref cp))
                    sp)
                  (lambda (sp) (n:sk_surface_unref sp) (when cp (sk_colorspace_unref cp)))
                  #:keepalive context))))
          (set! result
            (make-gpu-surface-record handle width height '() context d cp
              (hash-set* description 'backend (symbol->string (domain-backend d))
                         'context_generation (domain-generation d)
                         'max_rgba_sample_count
                         (n:gr_recording_context_get_max_surface_sample_count_for_color_type context-p rgba-8888)
                         'render_path "sk_surface_new_render_target")))))
      (when (memq color-type '(rgba-f16 rgba-f32)) (audit-mark-float-pixels! handle))
      (define rp (n:sk_surface_get_recording_context (resource-pointer handle)))
      (unless (and rp (pointer=? context-p (n:gr_recording_context_get_direct_context rp)))
        (error who "native target is not backed by the requested Ganesh context"))
      (unless (equal? properties (surface-properties-of result))
        (error who "native target changed requested surface properties"))
      ;; Initialize before querying a snapshot. No uninitialized native pixels
      ;; or implicitly quantized fallback target may escape this constructor.
      (canvas-clear! (surface-canvas result) color)
      (define actual (gpu-surface->image-info result))
      (unless (and (= width (image-info-width actual)) (= height (image-info-height actual))
                   (eq? color-type (image-info-color-type actual))
                   (eq? alpha (image-info-alpha-type actual)))
        (error who "native target changed requested dimensions or color/alpha format"))
      (set! completed? #t)
      result)
    (lambda ()
      (unless completed?
        (when handle (domain-resource-close! handle))
        (domain-drain! d)))))
(define (gpu-surface-info s)
  (define who 'gpu-surface-info)
  (define d (gpu-surface-domain/checked who s))
  (define sp (resource-pointer (surface-h who s)))
  (define rp (n:sk_surface_get_recording_context sp))
  (unless rp (error who "native target has no GPU recording context"))
  (define native-backend (n:gr_recording_context_get_backend rp))
  (unless (and (= native-backend (gpu-backend-native-id (domain-backend d)))
               (pointer=? (domain-pointer d) (n:gr_recording_context_get_direct_context rp)))
    (error who "surface context/backend mismatch"))
  (gpu-surface-identity/validated (gpu-surface-description s)
                                (domain-backend d) (domain-generation d) native-backend
                                (surface-width s) (surface-height s)))
(define (ready-for-read! who s)
  (gpu-surface-domain/checked who s)
  (gpu-surface-native-check!)
  (define sp (resource-pointer (surface-h who s)))
  (unless (= 1 (canvas-save-count/native (n:sk_surface_get_canvas sp)))
    (error who "readback requires a balanced canvas save/layer stack"))
  sp)
(define (read-into! who s pixels row-bytes colorspace alpha-type)
  (define sp (ready-for-read! who s))
  (record-gpu-io! (hasheq 'kind "readback" 'width (surface-width s)
                        'height (surface-height s) 'row_bytes row-bytes))
  (gpu-wait! (gpu-surface-context s))
  (call-with-gpu-image-info
   colorspace (surface-width s) (surface-height s) rgba-8888 alpha-type
   (lambda (info)
     (unless (read-pixels/native sp info pixels row-bytes 0 0)
       (error who "GPU readback failed; destination writes are not transactional"))))
  (void/reference-sink s)
  (void))
(define (gpu-surface->rgba-bytes s #:premultiplied? [premultiplied? #f]
                                   #:color-space [colorspace #f])
  (define who 'gpu-surface->rgba-bytes)
  (boolean who premultiplied?)
  (gpu-surface-domain/checked who s)
  (define size (check-dimensions who (surface-width s) (surface-height s)))
  (define ch (and colorspace (color-space-h who colorspace)))
  ;; A live local wrapper holds an optional destination reference across the
  ;; blocking call, without holding a blanket Racket atomic section around it.
  (define cp (if ch (call-with-owned who (list ch) values) (gpu-surface-colorspace s)))
  (define out (make-bytes size))
  (call-with-gpu-raw
   size
   (lambda (p)
     (read-into! who s p (* 4 (surface-width s)) cp
                 (if premultiplied? alpha-premul alpha-unpremul))
     (memcpy out p size)))
  (void/reference-sink colorspace)
  out)
(define (gpu-surface->raster-image s)
  ;; Preserve target format and color interpretation. RGBA-byte helpers remain
  ;; the explicit eight-bit conversion route, not hidden staging for F16/F32.
  (with-skia ([buffer (gpu-surface->raster-buffer s)])
    (r:raster-buffer->image buffer)))
(define (gpu-surface-read-raster-buffer! s buffer)
  (define who 'gpu-surface-read-raster-buffer!)
  (gpu-surface-domain/checked who s)
  (call-with-raster-buffer-gpu-transfer
   buffer
   (lambda (pixels width height row-bytes colorspace)
     (gpu-transfer-shape! who (surface-width s) (surface-height s) width height)
     (read-into! who s pixels row-bytes colorspace alpha-premul)))
  (void))

;; Detached metadata is verified against a temporary native snapshot, not just
;; echoed constructor arguments. No pixel readback is involved.
(define (gpu-surface->image-info s)
  (define who 'gpu-surface->image-info)
  (gpu-surface-domain/checked who s)
  (define space (surface-color-space s))
  (dynamic-wind void
    (lambda ()
      (define descriptor (and space (color-space->descriptor space)))
      (call-with-owned who (list (surface-h who s))
        (lambda (sp)
          (call-with-native-temporary who 'image
            (lambda () (sk_surface_new_image_snapshot sp)) sk_image_unref
            (lambda (ip)
              (unless (sk_image_is_texture_backed ip)
                (error who "GPU surface snapshot is not texture-backed"))
              (define color-code (sk_image_get_color_type ip))
              (define alpha-code (sk_image_get_alpha_type ip))
              (define color (for/first ([(k v) (in-hash color-type-values)] #:when (= color-code v)) k))
              (define alpha (for/first ([(k v) (in-hash alpha-type-values)] #:when (= alpha-code v)) k))
              (make-image-info (sk_image_get_width ip) (sk_image_get_height ip)
                               #:color-type color #:alpha-type alpha #:color-space descriptor))))))
    (lambda () (when space (skia-close! space)))))
(define (gpu-surface-read-pixmap! s destination)
  (define who 'gpu-surface-read-pixmap!)
  (gpu-surface-domain/checked who s)
  (view-owner who destination #t)
  (gpu-transfer-shape! who (surface-width s) (surface-height s)
                      (r:pixmap-width destination) (r:pixmap-height destination))
  (define sp (ready-for-read! who s))
  ;; Flush/wait occurs before borrowing any temporary Racket cstruct. During
  ;; the blocking read both descriptor and pixel memory are immobile raw memory.
  (gpu-wait! (gpu-surface-context s))
  (call-with-pixmap-write-staging who destination
    (lambda (_pm info memory row-bytes)
      (unless (eq? (and (gpu-surface-colorspace s) #t)
                   (and (sk-image-info-colorspace info) #t))
        (error who "tagged/untagged readback needs explicit source interpretation"))
      (call-with-gpu-image-info (sk-image-info-colorspace info)
        (sk-image-info-width info) (sk-image-info-height info)
        (sk-image-info-color-type info) (sk-image-info-alpha-type info)
        (lambda (raw-info)
          (record-gpu-io! (hasheq 'kind "readback" 'width (surface-width s)
                          'height (surface-height s) 'row_bytes row-bytes
                          'format_aware #t))
          (unless (read-pixels/native sp raw-info memory row-bytes 0 0)
            (error who "GPU readback/conversion failed; destination unchanged"))))))
  (void/reference-sink s)
  (void))
(define (gpu-surface->raster-buffer s #:info [requested #f] #:row-bytes [row-bytes #f])
  (define who 'gpu-surface->raster-buffer)
  (gpu-surface-domain/checked who s)
  (define info (or requested (gpu-surface->image-info s)))
  (unless (image-info? info) (raise-argument-error who "image-info?" info))
  (gpu-transfer-shape! who (surface-width s) (surface-height s)
                      (image-info-width info) (image-info-height info))
  (define buffer (r:make-raster-buffer-from-info info #:row-bytes row-bytes))
  (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! buffer) (raise e))])
    (r:call-with-raster-buffer-pixmap buffer
      (lambda (v) (gpu-surface-read-pixmap! s v)) #:writable? #t)
    buffer))
