#lang racket/base
(require "native.rkt" "lifetime.rkt" "color-output-util.rkt")
(provide call-with-encoder-profile)

(define (temporary who kind create release proc)
  (define h (new-owned who kind create release))
  (call-with-scoped-resource
   h (lambda (v) (owned-close! who v))
   (lambda (v) (call-with-owned who (list v) proc))))

;; skcms's parsed curves can point into the input buffer. Use *native* SkData,
;; and retain that data, the profile, and the description until encoding ends.
;; The native encoder regenerates a profile; this is not byte-for-byte copying
;; of arbitrary ICC metadata and it performs no color conversion by itself.
(define (call-with-encoder-profile who input description proc)
  (define bs (checked-encoding-profile who input))
  (define desc (icc-description-bytes who bs description))
  (cond
    [(not bs) (proc #f #f)]
    [else
     (skia-check!)
     (define text (or desc #"skia-for-racket RGB\0"))
     (temporary
      who 'encoder-icc-data
      (lambda () (sk_data_new_with_copy bs (bytes-length bs))) sk_data_unref
      (lambda (dp)
        (temporary
         who 'encoder-icc-profile sk_colorspace_icc_profile_new sk_colorspace_icc_profile_delete
         (lambda (pp)
           (unless (sk_colorspace_icc_profile_parse (sk_data_get_data dp) (bytes-length bs) pp)
             (error who "native ICC parser rejected the encoding profile"))
           ;; A well-formed tag directory alone does not validate curve bodies.
           (temporary
            who 'encoder-icc-space (lambda () (sk_colorspace_new_icc pp)) sk_colorspace_unref
            (lambda (_cs)
              (temporary
               who 'encoder-icc-description
               (lambda () (sk_data_new_with_copy text (bytes-length text))) sk_data_unref
               (lambda (td) (proc pp (sk_data_get_data td))))))))))]))
