#lang racket/base

;;;
;;; ICC Encoding Metadata
;;;

;; Prepares ICC profile and description values for native image encoders.
;; Shares color-profile lifetime handling across PNG, JPEG, and WebP output.

(require ffi/unsafe/atomic "native.rkt" "lifetime.rkt" "color-output-util.rkt"
         "live-native-lease.rkt")
(provide call-with-encoder-profile make-encoder-profile-reference)

; make-encoder-profile-reference : symbol? any/c any/c -> (values any/c any/c any/c)
;   Creates a worker-owned profile lease, description pointer, and PNG metadata sentinel.
;   The lease keeps parsed curves and all backing native storage alive until worker completion.
(define (make-encoder-profile-reference who input description)
  (define bs (checked-encoding-profile who input))
  (define desc (icc-description-bytes who bs description))
  (if (not bs)
      (values #f #f #f)
      (call-as-atomic
       (lambda ()
         (define releases '())
         (define (release-all)
           (for ([release (in-list releases)]) (release))
           (set! releases '()))
         (define (acquire create destroy)
           (define p (or (create) (error who "native encoding metadata allocation failed")))
           (set! releases (cons (lambda () (destroy p)) releases))
           p)
         (with-handlers ([(lambda (_) #t) (lambda (e) (release-all) (raise e))])
           (skia-check!)
           (define data
             (acquire (lambda () (sk_data_new_with_copy bs (bytes-length bs))) sk_data_unref))
           (define profile
             (acquire sk_colorspace_icc_profile_new sk_colorspace_icc_profile_delete))
           (unless (sk_colorspace_icc_profile_parse (sk_data_get_data data) (bytes-length bs) profile)
             (error who "native ICC parser rejected the encoding profile"))
           (acquire (lambda () (sk_colorspace_new_icc profile)) sk_colorspace_unref)
           (define text (or desc #"skia-for-racket RGB\0"))
           (define text-data
             (acquire (lambda () (sk_data_new_with_copy text (bytes-length text))) sk_data_unref))
           (define sentinel (acquire sk_colorspace_new_srgb_linear sk_colorspace_unref))
           (values (make-native-reference profile (lambda (_) (release-all)))
                   (sk_data_get_data text-data) sentinel))))))

; temporary : symbol? any/c any/c any/c any/c -> any
;   Owns a temporary native encoder resource through one callback and closes it on every exit.
(define (temporary who kind create release proc)
  (define h (new-owned who kind create release))
  (call-with-scoped-resource
   h (lambda (v) (owned-close! who v))
   (lambda (v) (call-with-owned who (list v) proc))))

;; skcms's parsed curves can point into the input buffer. Use *native* SkData,
;; and retain that data, the profile, and the description until encoding ends.
;; The native encoder regenerates a profile; this is not byte-for-byte copying
;; of arbitrary ICC metadata and it performs no color conversion by itself.

; call-with-encoder-profile : symbol? any/c any/c procedure? -> any
;   Retains profile bytes, parsed curves, and description storage until the encoder callback
;   finishes.
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
