#lang racket/base
(require "check.rkt")
(provide gpu-surface-options gpu-transfer-shape! gpu-presentation-format)
(define (gpu-surface-options who w h samples opaque? budgeted? background-alpha)
  (check-dimensions who w h)
  (unless (and (exact-nonnegative-integer? samples) (<= samples 64))
    (raise-argument-error who "exact sample count from 0 through 64" samples))
  (boolean who opaque?)
  (boolean who budgeted?)
  (when (and opaque? (not (= background-alpha 255)))
    (error who "an opaque GPU surface requires an opaque background"))
  (hasheq 'width w 'height h 'color_type "RGBA8888"
          'alpha_type (if opaque? "opaque" "premultiplied")
          'origin "top-left" 'requested_sample_count samples
          'actual_sample_count #f
          'sample_count_note "The pinned C API does not expose the sample count of this Skia-owned target."
          'budgeted budgeted? 'storage "gpu" 'target_kind "offscreen"))
(define (gpu-transfer-shape! who source-width source-height destination-width destination-height)
  (unless (and (= source-width destination-width) (= source-height destination-height))
    (raise-arguments-error who "source and destination dimensions must match exactly"
                           "source" (list source-width source-height)
                           "destination" (list destination-width destination-height))))
;; Checked public-sized format description for the diagnostic framebuffer.
;; GL component encoding is queried, never inferred from the OS or FBO number.
(define (gpu-presentation-format red green blue alpha encoding component-type)
  (unless (and (= red 8) (= green 8) (= blue 8) (memv alpha '(0 8))
               (= component-type #x8C17)) ; GL_UNSIGNED_NORMALIZED
    (error 'gpu-window "diagnostic requires an actual RGB8/RGBA8 normalized color buffer; got ~a"
           (list red green blue alpha component-type)))
  (cond [(= encoding #x2601) (if (zero? alpha) #x8051 #x8058)] ; GL_LINEAR -> GL_RGBA8
        [(= encoding #x8C40) (if (zero? alpha) #x8C41 #x8C43)] ; GL_SRGB -> GL_SRGB8_ALPHA8
        [else (error 'gpu-window "unsupported color encoding ~a" encoding)]))
