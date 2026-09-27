#lang racket/base
(require ffi/unsafe ffi/unsafe/atomic
         "gpu-native.rkt" "gpu-domain.rkt" "gpu-types.rkt"
         "gpu-diagnostics.rkt" "types.rkt")
(provide run-gpu-smoke)
(define (pointer=? a b)
  (and a b (= (cast a _pointer _uintptr) (cast b _pointer _uintptr))))
(define (run-gpu-smoke domain)
  (domain-call
   domain
   (lambda ()
     (define context (domain-pointer domain))
     (define surface #f)
     (define paint #f)
     (dynamic-wind
       void
       (lambda ()
         ;; Register each cleanup slot in the same atomic interval as creation.
         (call-as-atomic
          (lambda ()
            (define info (make-sk-image-info #f 8 8 rgba-8888 alpha-premul))
            (set! surface
              (domain-new-resource domain 'probe-surface
                (lambda () (sk_surface_new_render_target context #t info 0 gr-top-left #f #f))
                sk_surface_unref))
            (set! paint (domain-new-resource domain 'probe-paint sk_paint_new sk_paint_delete))))
         (define sp (resource-pointer surface))
         (define recording (sk_surface_get_recording_context sp))
         (unless (and recording
                      (pointer=? (gr_recording_context_get_direct_context recording) context)
                      (= (gr_recording_context_get_backend recording) gr-opengl))
           (error 'gpu-smoke-test "target is not backed by this Ganesh OpenGL context"))
         (define canvas (sk_surface_get_canvas sp))
         (unless canvas (error 'gpu-smoke-test "GPU surface returned a null canvas"))
         (define pp (resource-pointer paint))
         (sk_paint_set_antialias pp #f)
         (sk_canvas_clear canvas 0)
         (for ([color '(#xffff0000 #xff00ff00 #xff0000ff #xffffff00)]
               [rect '((0 0 3 4) (4 0 8 4) (0 4 3 8) (4 4 8 8))])
           (sk_paint_set_color pp color)
           (sk_canvas_draw_rect canvas (apply make-sk-rect (map exact->inexact rect)) pp))
         ;; Flush != submit != completion. This diagnostic deliberately asks
         ;; for CPU completion before its explicit synchronous readback.
         (gr_direct_context_flush context)
         (unless (gr_direct_context_submit context #t)
           (error 'gpu-smoke-test "Ganesh submit(syncCpu=true) failed"))
         (define bytes (make-bytes (* 8 8 4)))
         (define info (make-sk-image-info #f 8 8 rgba-8888 alpha-unpremul))
         (unless (sk_surface_read_pixels sp info bytes 32 0 0)
           (error 'gpu-smoke-test "GPU RGBA readback failed"))
         (verify-smoke-pixels bytes)
         (hasheq 'width 8 'height 8 'row_bytes 32 'rgba (bytes->immutable-bytes bytes)
                 'requested_sample_count 0 'actual_sample_count #f
                 'sample_count_note "The pinned C API does not expose this Skia-owned target's actual sample count."
                 'origin "top-left" 'transfer_format "RGBA8888-unpremultiplied"
                 'render_path "sk_surface_new_render_target"
                 'native_backend gr-opengl 'context_matches #t 'exact_pixels #t))
       (lambda ()
         (when paint (domain-resource-close! paint))
         (when surface (domain-resource-close! surface)))))))
