#lang racket/base
(require ffi/unsafe
         "color.rkt" "private/core.rkt" "private/native.rkt"
         "private/lifetime.rkt" "private/color-filter-util.rkt"
         "private/color-filter-types.rkt"
         (prefix-in raw: (submod "private/core.rkt" runtime-internals)))
(provide make-hsla-matrix-filter
         make-linear-to-srgb-gamma-color-filter make-srgb-to-linear-gamma-color-filter
         make-lerp-color-filter make-luma-color-filter make-high-contrast-color-filter
         make-table-color-filter make-table-argb-color-filter make-lighting-color-filter)

(define (make-hsla-matrix-filter matrix)
  (define who 'make-hsla-matrix-filter)
  (define values (checked-filter-matrix who matrix))
  (define data (malloc 80 'atomic))
  (for ([v (in-vector values)] [i (in-naturals)]) (ptr-set! data _float i v))
  (begin0 (raw:new-color-filter who (lambda () (sk_colorfilter_new_hsla_matrix data)))
    (void/reference-sink data values)))

(define (make-linear-to-srgb-gamma-color-filter)
  (raw:new-color-filter 'make-linear-to-srgb-gamma-color-filter
                        sk_colorfilter_new_linear_to_srgb_gamma))
(define (make-srgb-to-linear-gamma-color-filter)
  (raw:new-color-filter 'make-srgb-to-linear-gamma-color-filter
                        sk_colorfilter_new_srgb_to_linear_gamma))
(define (make-luma-color-filter)
  (raw:new-color-filter 'make-luma-color-filter sk_colorfilter_new_luma_color))

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

(define (make-high-contrast-color-filter #:grayscale? [grayscale? #f]
                                         #:invert-style [invert-style 'none]
                                         #:contrast [contrast 0])
  (define who 'make-high-contrast-color-filter)
  (define-values (gray invert amount)
    (checked-high-contrast who grayscale? invert-style contrast))
  (define config (make-sk-high-contrast-config gray invert amount))
  (begin0 (raw:new-color-filter who (lambda () (sk_colorfilter_new_high_contrast config)))
    (void/reference-sink config)))

(define (table-buffer table)
  (and table
       (let ([p (malloc 256 'atomic)])
         (for ([v (in-bytes table)] [i (in-naturals)]) (ptr-set! p _uint8 i v))
         p)))
(define (make-table-color-filter table)
  (define who 'make-table-color-filter)
  (define copy (checked-filter-table who table))
  (define data (table-buffer copy))
  (begin0 (raw:new-color-filter who (lambda () (sk_colorfilter_new_table data)))
    (void/reference-sink data copy)))
(define identity-color-matrix
  '#(1.0 0.0 0.0 0.0 0.0
     0.0 1.0 0.0 0.0 0.0
     0.0 0.0 1.0 0.0 0.0
     0.0 0.0 0.0 1.0 0.0))
(define (make-explicit-identity-filter who)
  ;; SkColorTable::Make returns null when all four channel tables are null: at
  ;; that point the table is exactly identity. Public factories always return
  ;; an owned color-filter?, so represent that optimized-away case explicitly.
  (define data (malloc 80 'atomic))
  (for ([v (in-vector identity-color-matrix)] [i (in-naturals)])
    (ptr-set! data _float i v))
  (begin0 (raw:new-color-filter who (lambda () (sk_colorfilter_new_color_matrix data)))
    (void/reference-sink data identity-color-matrix)))
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
(define (make-lighting-color-filter multiply add)
  (define mul (color->argb multiply))
  (define plus (color->argb add))
  (raw:new-color-filter 'make-lighting-color-filter
                        (lambda () (sk_colorfilter_new_lighting mul plus))))
