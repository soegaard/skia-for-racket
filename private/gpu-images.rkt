#lang racket/base

;;;
;;; GPU Image Resources
;;;

;; Uploads images, snapshots surfaces, and explicitly detaches GPU pixels.
;; Implements public GPU image transfers under domain lifetime and affinity checks.

(require (only-in "native.rkt" sk_image_get_color_type)
         "image-operation-util.rkt"
         (only-in (submod "../raster-buffers.rkt" image-operation-internals) view-owner)
         (prefix-in r: "../raster-buffers.rkt"))
(require ffi/unsafe ffi/unsafe/atomic
         "core.rkt" "types.rkt" "check.rkt" "lifetime.rkt"
         "gpu-domain.rkt" "gpu-context.rkt" "gpu-surfaces.rkt"
         "gpu-image-native.rkt" "gpu-io-trace.rkt"
         (submod "core.rkt" gpu-image-internals)
         (submod "core.rkt" gpu-surface-internals)
         (only-in "gpu-native.rkt" gr_direct_context_is_abandoned)
         (only-in "../raster-buffers.rkt" raster-buffer?))
(provide gpu-image->raster-buffer gpu-image? image-residency skia-resource-gpu-context
         gpu-upload-image gpu-surface-snapshot gpu-image-subset gpu-image-info
         gpu-image->rgba-bytes gpu-image->raster-image gpu-image-read-raster-buffer!
         gpu-image-read-pixmap!)

;;;
;;; Image Residency and Domain Ownership
;;;

; gpu-image? : any/c -> boolean?
;   Returns whether v is an image whose wrapper has GPU ownership.
(define (gpu-image? v)
  ;; Classification is by ownership, not an incidental cached GPU copy of an
  ;; ordinary lazy/encoded image. It remains a predicate after explicit close.
  (and (image? v) (domain-resource? (image-h 'gpu-image? v))))

; image-residency : image? -> (or/c 'cpu 'gpu)
;   Returns the live wrapper's ownership classification.
(define (image-residency im)
  (define h (image-h 'image-residency im))
  (when (owned-closed? h) (error 'image-residency "image is closed"))
  (if (gpu-image? im) 'gpu 'cpu))

; skia-resource-gpu-context : skia-resource? -> (or/c gpu-context? #f)
;   Returns the existing context wrapper associated with a live resource, or false when the
;   resource has no GPU dependency.
(define (skia-resource-gpu-context resource)
  (define h (resource-handle 'skia-resource-gpu-context resource))
  (when (owned-closed? h) (error 'skia-resource-gpu-context "resource is closed"))
  (owned-gpu-context h))

; context-pointer : symbol? any/c -> any
;   Resolves a live context pointer through the shared domain checks.
(define (context-pointer who context)
  (define d (context-domain who context))
  (define p (domain-pointer d))
  (when (gr_direct_context_is_abandoned p)
    (domain-request-shutdown! d 'native-context-lost)
    (error who "native GPU context is lost or abandoned"))
  p)

; gpu-h : symbol? any/c -> any
;   Requires an image with GPU affinity and returns its lifetime cell for scoped native use.
(define (gpu-h who im)
  (unless (gpu-image? im) (raise-argument-error who "gpu-image?" im))
  (define h (image-h who im))
  (resource-pointer h)
  h)

; adopt-image : symbol? any/c any/c any/c any/c -> image?
;   Wraps a newly created GPU image with its context keepalive and checked pixel dimensions.
(define (adopt-image who context w h create)
  (define d (context-domain who context))
  (define cp (context-pointer who context))
  (gpu-image-native-check!)
  (define handle (new-gpu-owned who 'image d context create image-unref/native))
  (with-handlers ([(lambda (_) #t)
                   (lambda (e) (domain-resource-close! handle) (raise e))])
    (define ip (resource-pointer handle))
    (unless (and (texture-backed?/native ip) (valid-image?/native ip cp))
      (error who
        "native result is not a valid texture-backed image for this context; no CPU fallback"))
    (make-image-record handle w h)))

;;;
;;; Upload, Snapshot, and Subset Construction
;;;

; gpu-upload-image : gpu-context? image? [#:mipmapped? boolean?] [#:budgeted? boolean?] ->
;   gpu-image?
;   Returns an independently owned, valid texture-backed image for the active context.
(define (gpu-upload-image context im #:mipmapped? [mipmapped? #f] #:budgeted? [budgeted? #t])
  (define who 'gpu-upload-image)
  (boolean who mipmapped?) (boolean who budgeted?)
  (define ih (image-h who im))
  (define d (context-domain who context))
  (define cp (context-pointer who context))
  (when (and (owned-gpu-domain ih) (not (eq? d (owned-gpu-domain ih))))
    (error who
      "image belongs to another GPU context; detach before uploading to a different context"))
  (define w (image-width im)) (define h (image-height im))
  (check-dimensions who w h)
  (define maximum (hash-ref (domain-info d) 'max_texture_size #f))
  (unless (and (exact-positive-integer? maximum) (<= w maximum) (<= h maximum))
    (error who "image exceeds the context's reported texture size limit: ~a" maximum))
  (gpu-image-native-check!)
  (call-with-owned who (list ih)
    (lambda (ip)
      (define out
        (adopt-image who context w h
          (lambda () (texture-image/native ip cp mipmapped? budgeted?))))
      (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! out) (raise e))])
        (call-with-owned who (list (image-h who out))
          (lambda (op)
            (unless (operation-precision-compatible? (sk_image_get_color_type ip)
                                                       (sk_image_get_color_type op))
              (error who "GPU upload reduced float storage precision; convert explicitly first")))))
      (record-gpu-io!
       (hasheq 'kind (if (gpu-image? im) "gpu-image-reuse" "upload")
               'width w 'height h 'mipmapped_requested mipmapped? 'budgeted_requested budgeted?))
      out)))

; gpu-surface-snapshot : gpu-surface? -> gpu-image?
;   Returns an independently owned GPU image of the surface's current contents.
(define (gpu-surface-snapshot s)
  (define who 'gpu-surface-snapshot)
  (unless (gpu-surface? s) (raise-argument-error who "gpu-surface?" s))
  (define context (gpu-surface-context s))
  (context-pointer who context)
  (unless (= 1 (canvas-save-count (surface-canvas s)))
    (error who "snapshot requires a balanced canvas save/layer stack"))
  (gpu-image-native-check!)
  (call-with-owned who (list (surface-h who s))
    (lambda (sp)
      (define im (adopt-image who context (surface-width s) (surface-height s)
                   (lambda () (snapshot/native sp))))
      (record-gpu-io! (hasheq 'kind "gpu-snapshot" 'width (image-width im) 'height (image-height im)))
      im)))

; gpu-image-subset : gpu-image? exact-nonnegative-integer? exact-nonnegative-integer?
;   exact-positive-integer? exact-positive-integer? -> gpu-image?
;   Returns an independently owned GPU image of a nonempty integer rectangle fully inside image.
(define (gpu-image-subset im x y width height)
  (define who 'gpu-image-subset)
  (define ih (gpu-h who im))
  (unless (and (exact-nonnegative-integer? x) (exact-nonnegative-integer? y)
               (exact-positive-integer? width) (exact-positive-integer? height)
               (<= (+ x width) (image-width im)) (<= (+ y height) (image-height im)))
    (raise-arguments-error who "subset must be a nonempty integer rectangle inside the image"
                           "x" x "y" y "width" width "height" height))
  (check-dimensions who width height)
  (define context (owned-gpu-context ih))
  (define cp (context-pointer who context))
  (gpu-image-native-check!)
  (define rect (make-sk-irect x y (+ x width) (+ y height)))
  (call-with-owned who (list ih)
    (lambda (ip)
      (begin0
        (adopt-image who context width height (lambda () (subset/native ip cp rect)))
        (record-gpu-io! (hasheq 'kind "gpu-subset" 'x x 'y y 'width width 'height height))
        (void/reference-sink rect)))))

;;;
;;; Detached Image Metadata
;;;

; gpu-image-info : gpu-image? -> (and/c hash? immutable?)
;   Returns detached metadata after verifying native texture backing and validity for the owning
;   active context.
(define (gpu-image-info im)
  (define who 'gpu-image-info)
  (define ih (gpu-h who im))
  (define d (owned-gpu-domain ih))
  (define cp (context-pointer who (owned-gpu-context ih)))
  (gpu-image-native-check!)
  (call-with-owned who (list ih)
    (lambda (ip)
      (define valid? (valid-image?/native ip cp))
      (define texture? (texture-backed?/native ip))
      (unless (and valid? texture?) (error who "native texture is invalid or no longer GPU-backed"))
      (hasheq 'storage "gpu" 'backend (symbol->string (domain-backend d))
              'width (image-width im) 'height (image-height im)
              'context_generation (domain-generation d)
              'context_matches valid? 'texture_backed texture?
              'unique_id (image-id/native ip)
              'readback_path "GPU staging surface; explicit synchronous transfer"))))

;;;
;;; Explicit CPU Readback
;;;

;; m119's C sk_image_read_pixels and make_raster_image omit GrDirectContext.
;; Never pretend they provide a context-aware texture download. Instead draw
;; the image 1:1 with Src into a same-context/same-space staging GPU surface,
;; then use 0.39's explicit surface readback. No texture pointer is exposed.

; call-with-image-staging : symbol? any/c any/c -> any
;   Renders an image into temporary GPU staging storage for explicit transfer operations.
(define (call-with-image-staging who im proc)
  (define ih (gpu-h who im))
  (define context (owned-gpu-context ih))
  (context-pointer who context)
  (define space (image-color-space im))
  (dynamic-wind
    void
    (lambda ()
      (with-skia ([s (make-gpu-surface context (image-width im) (image-height im)
                                      #:color-space space
                                      #:color-type (image-color-type im)
                                      #:alpha-type (if (eq? (image-alpha-type im) 'opaque) 'opaque
                                        'premul)
                                      #:background (if (eq? (image-alpha-type im) 'opaque) 'black
                                        'transparent))]
                  [paint (make-paint #:blend-mode 'src #:antialias? #f)])
        (draw-image (surface-canvas s) im 0 0 #:sampling 'nearest #:paint paint)
        (proc s)))
    (lambda () (when space (skia-close! space)))))

; gpu-image->rgba-bytes : gpu-image? [#:premultiplied? boolean?] [#:color-space (or/c color-space?
;   #f)] -> bytes?
;   Like gpu-surface->rgba-bytes, using the image staging route: the image is first drawn
;   one-to-one into a same-context staging surface.
(define (gpu-image->rgba-bytes im #:premultiplied? [premultiplied? #f] #:color-space [space #f])
  (define who 'gpu-image->rgba-bytes)
  (boolean who premultiplied?)
  (when space (call-with-owned who (list (color-space-h who space)) void))
  (call-with-image-staging who im
    (lambda (s) (gpu-surface->rgba-bytes s #:premultiplied? premultiplied? #:color-space space))))

; gpu-image->raster-buffer : gpu-image? [#:info (or/c image-info? #f)] [#:row-bytes (or/c
;   exact-nonnegative-integer? #f)] -> raster-buffer?
;   Like gpu-surface->raster-buffer, after same-context image staging.
(define (gpu-image->raster-buffer im #:info [info #f] #:row-bytes [row-bytes #f])
  (gpu-h 'gpu-image->raster-buffer im)
  (define requested (or info (r:image->image-info im)))
  (call-with-image-staging 'gpu-image->raster-buffer im
    (lambda (s) (gpu-surface->raster-buffer s #:info requested #:row-bytes row-bytes))))

; gpu-image->raster-image : gpu-image? -> image?
;   Like gpu-surface->raster-image, using the GPU image's staging and typed readback route.
(define (gpu-image->raster-image im)
  (with-skia ([buffer (gpu-image->raster-buffer im)]) (r:raster-buffer->image buffer)))

; gpu-image-read-raster-buffer! : gpu-image? raster-buffer? -> void?
;   Like gpu-surface-read-raster-buffer!, after drawing the image into its same-context staging
;   surface.
(define (gpu-image-read-raster-buffer! im buffer)
  (define who 'gpu-image-read-raster-buffer!)
  (gpu-h who im)
  (unless (raster-buffer? buffer) (raise-argument-error who "raster-buffer?" buffer))
  (r:call-with-raster-buffer-pixmap buffer
    (lambda (destination) (gpu-image-read-pixmap! im destination)) #:writable? #t))

; gpu-image-read-pixmap! : gpu-image? pixmap? -> void?
;   Reads into a matching writable pixmap through checked staging, leaving it unchanged on failure.
(define (gpu-image-read-pixmap! im destination)
  (define who 'gpu-image-read-pixmap!)
  (gpu-h who im)
  (view-owner who destination #t)
  (unless (and (= (image-width im) (r:pixmap-width destination))
               (= (image-height im) (r:pixmap-height destination)))
    (error who "source image and destination pixmap dimensions must match"))
  (call-with-image-staging who im
    (lambda (surface) (gpu-surface-read-pixmap! surface destination))))

(module* image-operation-internals #f
  (provide gpu-h context-pointer))
