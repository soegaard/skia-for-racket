#lang racket/base
(require ffi/unsafe ffi/unsafe/atomic
         "core.rkt" "types.rkt" "lifetime.rkt" "check.rkt"
         "gpu-domain.rkt" "gpu-context.rkt" "gpu-types.rkt"
         "gpu-surface-util.rkt" "gpu-surface-native.rkt" "gpu-raw.rkt" "gpu-io-trace.rkt"
         (prefix-in n: "gpu-native.rkt")
         (only-in "native.rkt" skia-check! sk_colorspace_ref sk_colorspace_unref)
         (submod "core.rkt" gpu-surface-internals)
         (submod "../raster-buffers.rkt" gpu-transfer-internals)
         "../color.rkt")
(provide make-gpu-surface gpu-surface? gpu-surface-info
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
(define (make-gpu-surface context width height
                          #:background [background 'transparent]
                          #:color-space [colorspace #f]
                          #:sample-count [samples 0]
                          #:opaque? [opaque? #f]
                          #:budgeted? [budgeted? #t])
  (define who 'make-gpu-surface)
  (define color (color->rgba background))
  (define description
    (gpu-surface-options who width height samples opaque? budgeted? (rgba-alpha color)))
  (define d (context-domain who context))
  (define context-p (native-context who context))
  (define ch (and colorspace (color-space-h who colorspace)))
  (define maximum (n:gr_recording_context_max_render_target_size context-p))
  (when (or (> width maximum) (> height maximum))
    (error who "GPU target ~ax~a exceeds this context's reported limit ~a" width height maximum))
  (define max-samples
    (n:gr_recording_context_get_max_surface_sample_count_for_color_type context-p rgba-8888))
  (when (or (zero? max-samples) (> samples max-samples))
    (error who "requested RGBA8 sample count ~a exceeds reported support ~a" samples max-samples))
  (skia-check!)
  (gpu-surface-native-check!)
  (define result #f)
  (define handle #f)
  (define completed? #f)
  (dynamic-wind
    void
    (lambda ()
      ;; The CPU space is borrowed only during construction. An extra native
      ;; reference backs our metadata query; SkSurface retains its own too.
      (call-with-owned
       who (if ch (list ch) '())
       (lambda color-pointers
         (define cp (and ch (car color-pointers)))
         (set! handle
           (domain-new-resource
            d 'surface
            (lambda ()
              (define sp
                (n:sk_surface_new_render_target
                 context-p budgeted?
                 (make-sk-image-info cp width height rgba-8888 (if opaque? 1 alpha-premul))
                 samples gr-top-left #f #f))
              (when (and sp cp) (sk_colorspace_ref cp))
              sp)
            (lambda (sp)
              (n:sk_surface_unref sp)
              (when cp (sk_colorspace_unref cp)))))
         (set! result
           (make-gpu-surface-record handle width height '() context d cp
             (hash-set* description 'backend (symbol->string (domain-backend d))
                        'context_generation (domain-generation d)
                        'max_rgba_sample_count max-samples
                        'render_path "sk_surface_new_render_target")))))
      (define rp (n:sk_surface_get_recording_context (resource-pointer handle)))
      (unless (and rp (pointer=? context-p (n:gr_recording_context_get_direct_context rp)))
        (error who "native target is not backed by the requested Ganesh context"))
      (canvas-clear! (surface-canvas result) color)
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
  (unless (and (= native-backend gr-opengl)
               (pointer=? (domain-pointer d) (n:gr_recording_context_get_direct_context rp)))
    (error who "surface context/backend mismatch"))
  (hash-set* (gpu-surface-description s)
             'context_matches #t 'native_backend native-backend
             'width (surface-width s) 'height (surface-height s)))
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
  (gpu-surface-domain/checked 'gpu-surface->raster-image s)
  (define space (surface-color-space s))
  (dynamic-wind
    void
    (lambda ()
      (rgba-bytes->image (surface-width s) (surface-height s)
        (gpu-surface->rgba-bytes s #:premultiplied? #t)
        #:premultiplied? #t #:color-space space))
    (lambda () (when space (skia-close! space)))))
(define (gpu-surface-read-raster-buffer! s buffer)
  (define who 'gpu-surface-read-raster-buffer!)
  (gpu-surface-domain/checked who s)
  (call-with-raster-buffer-gpu-transfer
   buffer
   (lambda (pixels width height row-bytes colorspace)
     (gpu-transfer-shape! who (surface-width s) (surface-height s) width height)
     (read-into! who s pixels row-bytes colorspace alpha-premul)))
  (void))
