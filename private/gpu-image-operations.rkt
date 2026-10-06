#lang racket/base
;; Explicit GPU filtering. Requiring gpu.rkt still does not construct a context.
(require ffi/unsafe
         "core.rkt" "types.rkt" "lifetime.rkt" "gpu-domain.rkt" "gpu-context.rkt"
         "gpu-image-native.rkt" "gpu-io-trace.rkt"
         (only-in "native.rkt" sk_image_get_color_type)
         (submod "core.rkt" image-operation-internals)
         (submod "gpu-images.rkt" image-operation-internals)
         (submod "../image-operations.rkt" internals))
(provide gpu-image-apply-filter)
(define (gpu-image-apply-filter im filter #:subset [subset #f] #:clip clip)
  (define who 'gpu-image-apply-filter)
  (define ih (gpu-h who im)) (define fh (image-filter-h who filter))
  (define context (owned-gpu-context ih))
  (define d (owned-gpu-domain ih)) (define cp (context-pointer who context))
  (define-values (sr cr checked-clip) (prepare-image-filter who im subset clip))
  (define maximum (hash-ref (domain-info d) 'max_texture_size #f))
  (unless (and (exact-positive-integer? maximum)
               (<= (vector-ref checked-clip 2) maximum) (<= (vector-ref checked-clip 3) maximum))
    (error who "filter clip exceeds the context's texture-size limit"))
  (define out-subset (make-sk-irect 0 0 0 0)) (define out-offset (make-sk-ipoint 0 0))
  (gpu-image-native-check!)
  ;; The combined owned scope rejects cross-context filter graphs before FFI.
  (call-with-owned who (list ih fh)
    (lambda (ip fp)
      (define source-color (sk_image_get_color_type ip))
      (define handle
        (new-gpu-owned who 'image d context
          (lambda () (filter-image/native ip cp fp sr cr out-subset out-offset)) image-unref/native))
      (define result
        (with-handlers ([(lambda (_) #t) (lambda (e) (owned-close! who handle) (raise e))])
          (call-with-owned who (list handle)
            (lambda (p)
              (unless (and (texture-backed?/native p) (valid-image?/native p cp))
                (error who "native filter result is not a valid same-context texture; no CPU fallback"))
              (define image (operation-image-record who handle p source-color))
              (unless (and (<= (image-width image) maximum) (<= (image-height image) maximum))
                (error who "native filtered image exceeds the texture-size limit"))
              image))))
      (define-values (image valid offset)
        (finish-image-filter who result out-subset out-offset checked-clip (list ih fh)))
      (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! image) (raise e))])
        (record-gpu-io! (hasheq 'kind "gpu-image-filter" 'width (image-width image) 'height (image-height image)
                                'subset (vector->list valid) 'offset (vector->list offset)))
        (void/reference-sink sr cr out-subset out-offset)
        (values image valid offset)))))
