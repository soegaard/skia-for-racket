#lang racket/base

;;;
;;; Color Filter Factories
;;;

;; Constructs channel-table, gamma, lighting, luma, and contrast filters.
;; This public factory layer validates color-filter specifications and transfers them to owned
;; native filter objects.

;;;
;;; Imports and Exports
;;;

(require ffi/unsafe
         "color.rkt" "private/core.rkt" "private/native.rkt"
         "private/lifetime.rkt" "private/color-filter-util.rkt"
         "private/color-filter-types.rkt"
         (prefix-in raw: (submod "private/core.rkt" runtime-internals)))
(provide make-hsla-matrix-filter
         make-linear-to-srgb-gamma-color-filter make-srgb-to-linear-gamma-color-filter
         make-lerp-color-filter make-luma-color-filter make-high-contrast-color-filter
         make-table-color-filter make-table-argb-color-filter make-lighting-color-filter)

; make-hsla-matrix-filter : (or/c list? vector?) -> color-filter?
;   Returns a filter that converts unpremultiplied RGB to hue, saturation, and lightness, applies a
;   four-row, five-column matrix to HSLA, then converts back to RGB.
(define (make-hsla-matrix-filter matrix)
  (define who 'make-hsla-matrix-filter)
  (define values (checked-filter-matrix who matrix))
  (define data (malloc 80 'atomic))
  (for ([v (in-vector values)] [i (in-naturals)]) (ptr-set! data _float i v))
  (begin0 (raw:new-color-filter who (lambda () (sk_colorfilter_new_hsla_matrix data)))
    (void/reference-sink data values)))

; make-linear-to-srgb-gamma-color-filter : -> color-filter?
;   Returns a filter applying the sRGB encoding transfer function to RGB channels.
(define (make-linear-to-srgb-gamma-color-filter)
  (raw:new-color-filter 'make-linear-to-srgb-gamma-color-filter
                        sk_colorfilter_new_linear_to_srgb_gamma))

; make-srgb-to-linear-gamma-color-filter : -> color-filter?
;   Returns a filter applying the inverse sRGB transfer function to RGB channels.
(define (make-srgb-to-linear-gamma-color-filter)
  (raw:new-color-filter 'make-srgb-to-linear-gamma-color-filter
                        sk_colorfilter_new_srgb_to_linear_gamma))

; make-luma-color-filter : -> color-filter?
;   Returns a filter with black RGB and alpha derived from the incoming color's luminance and
;   alpha.
(define (make-luma-color-filter)
  (raw:new-color-filter 'make-luma-color-filter sk_colorfilter_new_luma_color))

; make-lerp-color-filter : (real-in 0 1) color-filter? color-filter? -> color-filter?
;   Returns a filter interpolating between the two filters' results for the same input color.
(define (make-lerp-color-filter weight filter0 filter1)
  (define who 'make-lerp-color-filter)
  (define t (checked-filter-weight who weight))
  (define h0 (raw:color-filter-h who filter0))
  (define h1 (raw:color-filter-h who filter1))
  ;; Keep dependencies inside the allocation's ownership scope: provenance must
  ;; retain both child summaries, even when Skia optimizes an endpoint.
  (raw:new-color-filter
   who
   (lambda ()
     (call-with-owned who (list h0 h1)
       (lambda (p0 p1) (sk_colorfilter_new_lerp t p0 p1))))))

; make-high-contrast-color-filter : [#:grayscale? boolean?] [#:invert-style (or/c 'none 'brightness
;   'lightness)] [#:contrast (real-in -1 1)] -> color-filter?
;   Returns a high-contrast color filter.
(define (make-high-contrast-color-filter #:grayscale? [grayscale? #f]
                                         #:invert-style [invert-style 'none]
                                         #:contrast [contrast 0])
  (define who 'make-high-contrast-color-filter)
  (define-values (gray invert amount)
    (checked-high-contrast who grayscale? invert-style contrast))
  (define config (make-sk-high-contrast-config gray invert amount))
  (begin0 (raw:new-color-filter who (lambda () (sk_colorfilter_new_high_contrast config)))
    (void/reference-sink config)))

; table-buffer : (or/c #f bytes?) -> (or/c #f cpointer?)
;   Copies an already validated 256-entry channel table into native storage; #f means identity.
(define (table-buffer table)
  (and table
       (let ([p (malloc 256 'atomic)])
         (for ([v (in-bytes table)] [i (in-naturals)]) (ptr-set! p _uint8 i v))
         p)))

; make-table-color-filter : (or/c bytes? (listof byte?) (vectorof byte?)) -> color-filter?
;   Returns a filter applying the same 256-entry table to alpha, red, green, and blue.
(define (make-table-color-filter table)
  (define who 'make-table-color-filter)
  (define copy (checked-filter-table who table))
  (define data (table-buffer copy))
  (begin0 (raw:new-color-filter who (lambda () (sk_colorfilter_new_table data)))
    (void/reference-sink data copy)))

; identity-color-matrix : (vectorof flonum?)
;   Stores the RGBA identity transform as four row-major rows of five coefficients.
(define identity-color-matrix
  '#(1.0 0.0 0.0 0.0 0.0
     0.0 1.0 0.0 0.0 0.0
     0.0 0.0 1.0 0.0 0.0
     0.0 0.0 0.0 1.0 0.0))

; make-explicit-identity-filter : symbol? -> color-filter?
;   Allocates an owned identity filter when Skia optimizes a table filter to a null pointer.
(define (make-explicit-identity-filter who)
  ;; SkColorTable::Make returns null when all four channel tables are null: at
  ;; that point the table is exactly identity. Public factories always return
  ;; an owned color-filter?, so represent that optimized-away case explicitly.
  (define data (malloc 80 'atomic))
  (for ([v (in-vector identity-color-matrix)] [i (in-naturals)])
    (ptr-set! data _float i v))
  (begin0 (raw:new-color-filter who (lambda () (sk_colorfilter_new_color_matrix data)))
    (void/reference-sink data identity-color-matrix)))

; make-table-argb-color-filter : [#:alpha (or/c #f bytes? (listof byte?) (vectorof byte?))] [#:red
;   (or/c #f bytes? (listof byte?) (vectorof byte?))] [#:green (or/c #f bytes? (listof byte?)
;   (vectorof byte?))] [#:blue (or/c #f bytes? (listof byte?) (vectorof byte?))] -> color-filter?
;   Returns a filter with a separate table for each channel.
(define (make-table-argb-color-filter #:alpha [alpha #f] #:red [red #f]
                                      #:green [green #f] #:blue [blue #f])
  (define who 'make-table-argb-color-filter)
  (define copies (checked-filter-tables who alpha red green blue))
  (if (andmap not copies)
      (make-explicit-identity-filter who)
      (let ([buffers (map table-buffer copies)])
        ;; NULL is the documented per-channel identity. Skia copies non-null
        ;; tables synchronously. No Racket buffers are retained.
        (begin0
          (raw:new-color-filter who (lambda () (apply sk_colorfilter_new_table_argb buffers)))
          (void/reference-sink copies buffers)))))

; make-lighting-color-filter : color? color? -> color-filter?
;   Returns a filter that multiplies RGB by the normalized RGB channels of multiply, adds those of
;   add, and clamps the result.
(define (make-lighting-color-filter multiply add)
  (define mul (color->argb multiply))
  (define plus (color->argb add))
  (raw:new-color-filter 'make-lighting-color-filter
                        (lambda () (sk_colorfilter_new_lighting mul plus))))
