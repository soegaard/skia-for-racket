#lang racket/base

;;;
;;; Native Image Information
;;;

;; Converts between detached image descriptions and native image-info records.
;; Shares color-space-aware image metadata preparation across pixel operations.

(require "../image-info.rkt" (submod "../image-info.rkt" internals)
         "core.rkt" "native.rkt" "types.rkt" "lifetime.rkt"
         (submod "core.rkt" color-internals)
         (only-in (submod "core.rkt" codec-query-internals) call-with-codec-image-info))
(provide color-space->descriptor descriptor->color-space
         color-space-input->descriptor call-with-color-space-input
         call-with-image-info-native borrowed-color-space->descriptor
         codec-output-info call-with-codec-output-info-native)

; descriptor->color-space : (or/c #f 'srgb 'linear-srgb bytes?) -> (or/c #f color-space?)
;   Returns #f for an absent description, or a newly owned native color space for a named
;   description or copied ICC bytes.
(define (descriptor->color-space descriptor)
  (make-descriptor-color-space 'descriptor->color-space descriptor))

; checked-color-space-input : symbol? any/c -> (or/c color-space? color-space-descriptor?)
;   Checks an open caller-owned color space or copies and validates a color-space descriptor.
(define (checked-color-space-input who value)
  (cond
    [(color-space? value)
     (call-with-owned who (list (color-space-h who value)) void)
     value]
    [else (copy-descriptor who value)]))

; color-space-input->descriptor : symbol? any/c -> color-space-descriptor?
;   Copies a color-space input into immutable configuration data without closing the caller's
;   resource.
(define (color-space-input->descriptor who value)
  (define checked (checked-color-space-input who value))
  (if (color-space? checked) (color-space->descriptor checked) checked))

; call-with-color-space-input : symbol? any/c procedure? -> any
;   Borrows a supplied color space, or scopes a new resource made from a copied descriptor.
(define (call-with-color-space-input who value proc)
  (define checked (checked-color-space-input who value))
  (cond
    [(color-space? checked) (proc checked)]
    [(not checked) (proc #f)]
    [else (with-skia ([space (descriptor->color-space checked)]) (proc space))]))

; codec-output-info : symbol? cpointer? image-info? boolean? -> image-info?
;   Resolves a source-preserving decode request to a concrete output description.
(define (codec-output-info who cp template source?)
  (if (and source? (not (eq? (image-info-color-type template) 'alpha-8)))
      (call-with-codec-image-info who cp
        (lambda (native)
          (make-image-info (image-info-width template) (image-info-height template)
            #:color-type (image-info-color-type template)
            #:alpha-type (image-info-alpha-type template)
            #:color-space
            (borrowed-color-space->descriptor who (sk-image-info-colorspace native)))))
      template))

; call-with-codec-output-info-native : symbol? cpointer? image-info? boolean? procedure? -> any/c
;   Preserves the codec's original native profile when requested, without serializing it again.
(define (call-with-codec-output-info-native who cp info source? proc)
  (if (and source? (not (eq? (image-info-color-type info) 'alpha-8)))
      (call-with-codec-image-info who cp
        (lambda (source)
          (define space (sk-image-info-colorspace source))
          (proc (make-sk-image-info
                 space (image-info-width info) (image-info-height info)
                 (vector-ref (format-data who (image-info-color-type info)) 0)
                 (case (image-info-alpha-type info) [(opaque) 1] [(premul) 2] [(unpremul) 3]))
                space)))
      (call-with-image-info-native who info proc)))

; color-space->descriptor : color-space? -> (or/c 'srgb 'linear-srgb (and/c bytes? immutable?))
;   Returns a detached color-space description.
(define (color-space->descriptor space)
  (unless (color-space? space) (raise-argument-error 'color-space->descriptor "color-space?" space))
  (cond
    [(color-space-srgb? space) 'srgb]
    [else
     (with-skia ([linear (make-linear-srgb-color-space)])
       (if (color-space=? space linear) 'linear-srgb
           (copy-descriptor 'color-space->descriptor (color-space->icc-bytes space))))]))

; borrowed-color-space->descriptor : symbol? (or/c #f cpointer?) -> (or/c #f symbol? bytes?)
;   Temporarily retains a borrowed native color space while copying its detached named or ICC
;   description.
(define (borrowed-color-space->descriptor who pointer)
  (and pointer
       (with-skia ([space (wrap-owned-color-space who
                            (lambda () (sk_colorspace_ref pointer) pointer))])
         (color-space->descriptor space))))

; call-with-image-info-native : symbol? image-info? procedure? -> any
;   Builds a native image-info record and keeps its optional color-space pointer alive throughout
;   the callback.
(define (call-with-image-info-native who info proc)
  (check-info who info)
  (define space (descriptor->color-space (image-info-color-space info)))
  (dynamic-wind void
    (lambda ()
      (call-with-owned who (if space (list (color-space-h who space)) '())
        (lambda pointers
          (define cp (and space (car pointers)))
          (define native
            (make-sk-image-info cp (image-info-width info) (image-info-height info)
                                (vector-ref (format-data who (image-info-color-type info)) 0)
                                (case (image-info-alpha-type info) [(opaque) 1] [(premul) 2]
                                  [(unpremul) 3])))
          (proc native cp))))
    (lambda () (when space (skia-close! space)))))
