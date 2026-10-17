#lang racket/base

;;;
;;; Image Queries and Pixel Operations
;;;

;; Queries image properties and performs materialization, pixel transfers, scaling, and filtering.
;; This public layer joins native images to scoped pixmaps and raster buffers while enforcing
;; CPU/GPU and color-conversion boundaries.

;;;
;;; Imports and Exports
;;;

(require ffi/unsafe racket/list
         "matrix.rkt" "image-info.rkt" "raster-buffers.rkt"
         "private/core.rkt" "private/native.rkt" "private/types.rkt"
         "private/check.rkt" "private/lifetime.rkt" "private/gpu-domain.rkt"
         "private/image-operation-util.rkt"
         (only-in "private/audit-trace.rkt" audit-mark-float-pixels! audit-inherit-image-precision!)
         (submod "private/core.rkt" image-operation-internals)
         (submod "raster-buffers.rkt" image-operation-internals))
(provide image-unique-id image-alpha-only? image-lazy-generated? image-texture-backed?
         image-valid? image-pixels-available?
         image->non-texture-image image->raster-image
         image-read-pixmap! image-scale-pixmap! image->raster-buffer
         image-apply-filter make-raw-image-shader)


;;;
;;; Image Inspection
;;;

; image-query : symbol? image? procedure? -> any/c
;   Runs a native image query while holding the managed image handle.
(define (image-query who im native)
  (call-with-owned who (list (image-h who im)) native))

; image-unique-id : image? -> exact-nonnegative-integer?
;   Returns the native image's process-local identifier.
(define (image-unique-id im) (image-query 'image-unique-id im sk_image_get_unique_id))

; image-alpha-only? : image? -> boolean?
;   Reports whether the image has an alpha-only native format.
(define (image-alpha-only? im) (image-query 'image-alpha-only? im sk_image_is_alpha_only))

; image-lazy-generated? : image? -> boolean?
;   Reports whether the image uses deferred generation.
(define (image-lazy-generated? im) (image-query 'image-lazy-generated? im sk_image_is_lazy_generated))

; image-texture-backed? : image? -> boolean?
;   Reports whether the native image is texture-backed.
(define (image-texture-backed? im) (image-query 'image-texture-backed? im sk_image_is_texture_backed))

; image-valid? : image? -> boolean?
;   Queries native validity, using the image's GPU context when applicable.
(define (image-valid? im)
  (define who 'image-valid?)
  (define ih (image-h who im))
  (call-with-owned who (list ih)
    (lambda (ip)
      (define d (owned-gpu-domain ih))
      (sk_image_is_valid ip (and d (domain-pointer d))))))

; image-pixels-available? : image? -> boolean?
;   Reports whether native pixel storage can be inspected immediately.
(define (image-pixels-available? im)
  (define who 'image-pixels-available?)
  (call-with-owned who (list (image-h who im))
    (lambda (ip)
      ;; A synchronous peek only: no read/decode or borrowed address is exposed.
      (call-with-native-temporary who 'pixmap sk_pixmap_new sk_pixmap_destructor
        (lambda (pm) (sk_image_peek_pixels ip pm))))))


;;;
;;; CPU Residency and Result Ownership
;;;

; cpu-image-h : symbol? image? -> (or/c owned? domain-resource?)
;   Rejects GPU-affine images before returning a handle for CPU operations.
(define (cpu-image-h who im)
  (define ih (image-h who im))
  (when (owned-gpu-domain ih)
    (error who "GPU images require an explicit gpu-image->raster-image transfer first"))
  ih)

; require-native-cpu-image : symbol? cpointer? -> void?
;   Rejects native texture-backed images to prevent implicit GPU readback.
(define (require-native-cpu-image who ip)
  (when (sk_image_is_texture_backed ip)
    (error who "a CPU image operation cannot perform an implicit texture readback")))

;; An owned handle must already be installed before inspecting a native result.
;; Caller catches errors and releases that handle on every failed validation.

; operation-image-record : symbol? (or/c owned? domain-resource?) cpointer? integer? -> image?
;   Checks result size and storage precision before adopting an image and its audit provenance.
(define (operation-image-record who handle ip source-color)
  (define width (sk_image_get_width ip)) (define height (sk_image_get_height ip))
  (operation-budget who width height)
  (define color (sk_image_get_color_type ip))
  (unless (operation-precision-compatible? source-color color)
    (error who "native image operation reduced float storage precision; convert explicitly first"))
  (when (memv color '(14 15 16)) (audit-mark-float-pixels! handle))
  (make-image-record handle width height))

; cpu-image-result : symbol? integer? procedure? -> image?
;   Adopts a newly owned CPU image, closing its handle if validity or precision checks fail.
(define (cpu-image-result who source-color create)
  (define h (new-owned who 'image create sk_image_unref))
  (with-handlers ([(lambda (_) #t) (lambda (e) (owned-close! who h) (raise e))])
    (call-with-owned who (list h)
      (lambda (ip)
        (require-native-cpu-image who ip)
        (unless (sk_image_is_valid ip #f)
          (error who "native image result is invalid"))
        (operation-image-record who h ip source-color)))))

; materialize-image : symbol? image? procedure? boolean? -> image?
;   Creates a checked CPU image and optionally requires directly available raster pixels.
(define (materialize-image who im native raster?)
  (define ih (cpu-image-h who im))
  (call-with-owned who (list ih)
    (lambda (ip)
      (require-native-cpu-image who ip)
      (operation-budget who (image-width im) (image-height im))
      (define result (cpu-image-result who (sk_image_get_color_type ip) (lambda () (native ip))))
      (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! result) (raise e))])
        (when (and raster? (or (image-lazy-generated? result) (not (image-pixels-available? result))))
          (error who "native materialization did not return directly available raster pixels"))
        (audit-inherit-image-precision! (image-h who result) (list ih))
        result))))

; image->non-texture-image : image? -> image?
;   Returns an independently owned non-texture image.
(define (image->non-texture-image im)
  (materialize-image 'image->non-texture-image im sk_image_make_non_texture_image #f))

; image->raster-image : image? -> image?
;   Returns an independently owned, non-lazy CPU image with immediately available pixels.
(define (image->raster-image im)
  (materialize-image 'image->raster-image im sk_image_make_raster_image #t))

; check-conversion-spaces : symbol? cpointer? sk-image-info? -> void?
;   Rejects implicit tagged/untagged color-space conversion and releases the temporary source
;   reference.
(define (check-conversion-spaces who ip info)
  ;; get_colorspace returns one owned reference, not a borrowed pointer.
  (define source-space (sk_image_get_colorspace ip))
  (dynamic-wind void
    (lambda ()
      (unless (eq? (and source-space #t) (and (sk-image-info-colorspace info) #t))
        (error who
               "tagged/untagged conversion requires an explicit source interpretation; no implicit sRGB relabeling")))
    (lambda () (when source-space (sk_colorspace_unref source-space)))))

; caching-hint : symbol? boolean? -> (or/c 0 1)
;   Maps the checked cache preference to the native allow/disallow caching enumeration.
(define (caching-hint who cache?) (if (boolean who cache?) 0 1))

; image-read-pixmap! : image? pixmap? [#:source-x exact-nonnegative-integer?] [#:source-y
;   exact-nonnegative-integer?] [#:cache? boolean?] -> void?
;   Copies an image rectangle to the entire destination view without resizing.
(define (image-read-pixmap! im destination #:source-x [x 0] #:source-y [y 0] #:cache? [cache? #f])
  (define who 'image-read-pixmap!)
  (define ih (cpu-image-h who im))
  (define hint (caching-hint who cache?))
  (view-owner who destination #t)
  ;; Require a full in-bounds read. Native partial clipping must not leave an
  ;; unspecified part of a writable destination looking successfully initialized.
  (operation-subset who (vector x y (pixmap-width destination) (pixmap-height destination))
                    (image-width im) (image-height im))
  (operation-budget who (image-width im) (image-height im))
  (call-with-owned who (list ih)
    (lambda (ip)
      (require-native-cpu-image who ip)
      (call-with-pixmap-write-staging who destination
        (lambda (pm info)
          (check-conversion-spaces who ip info)
          (unless (sk_image_read_pixels_into_pixmap ip pm x y hint)
            (error who "native image read/conversion failed; destination unchanged"))))))
  (void))

; image-scale-pixmap! : image? pixmap? [#:sampling (or/c 'nearest 'linear)] [#:cache? boolean?] ->
;   void?
;   Resizes the entire image to the destination view's dimensions, with the specified sampling.
(define (image-scale-pixmap! im destination #:sampling [mode 'linear] #:cache? [cache? #f])
  (define who 'image-scale-pixmap!)
  (define ih (cpu-image-h who im))
  (define hint (caching-hint who cache?)) (define sm (sampling who mode))
  (view-owner who destination #t)
  (operation-budget who (image-width im) (image-height im))
  (call-with-owned who (list ih)
    (lambda (ip)
      (require-native-cpu-image who ip)
      (call-with-pixmap-write-staging who destination
        (lambda (pm info)
          (check-conversion-spaces who ip info)
          (unless (sk_image_scale_pixels ip pm sm hint)
            (error who "native image scaling/conversion failed; destination unchanged"))))
      (void/reference-sink sm)))
  (void))

; image->raster-buffer : image? [#:info (or/c #f image-info?)] [#:row-bytes (or/c #f
;   exact-positive-integer?)] [#:sampling (or/c 'nearest 'linear)] [#:cache? boolean?] ->
;   raster-buffer?
;   Returns a new owned mutable buffer.
(define (image->raster-buffer im #:info [requested #f] #:row-bytes [row-bytes #f]
                              #:sampling [mode 'linear] #:cache? [cache? #f])
  (define who 'image->raster-buffer)
  (define ih (cpu-image-h who im))
  (call-with-owned who (list ih) (lambda (ip) (require-native-cpu-image who ip)))
  (sampling who mode) (caching-hint who cache?)
  (define info (or requested (image->image-info im)))
  (define result (make-raster-buffer-from-info info #:row-bytes row-bytes))
  (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! result) (raise e))])
    (call-with-raster-buffer-pixmap result
      (lambda (dst)
        (if (and (= (image-width im) (pixmap-width dst)) (= (image-height im) (pixmap-height dst)))
            (image-read-pixmap! im dst #:cache? cache?)
            (image-scale-pixmap! im dst #:sampling mode #:cache? cache?))) #:writable? #t)
    result))


;;;
;;; Image Filtering
;;;

; native-operation-rect : vector? -> sk-irect?
;   Converts checked integer x/y/width/height bounds to native edge coordinates.
(define (native-operation-rect r)
  (make-sk-irect (vector-ref r 0) (vector-ref r 1)
                 (+ (vector-ref r 0) (vector-ref r 2)) (+ (vector-ref r 1) (vector-ref r 3))))

; prepare-image-filter : symbol? image? any/c any/c -> (values sk-irect? sk-irect? vector?)
;   Checks subset, clip, allocation budgets, and intermediate coordinate ranges before filtering.
(define (prepare-image-filter who im subset clip)
  (image-h who im)
  (define s (operation-subset who subset (image-width im) (image-height im)))
  (define c (operation-rectangle who clip))
  (operation-budget who (image-width im) (image-height im))
  (operation-budget who (vector-ref c 2) (vector-ref c 3))
  ;; m119 subtracts subset.topLeft() from the clip using signed SkIPoint math.
  ;; Check these intermediate edges as well, not just the user-facing rectangle.
  (operation-rectangle who (vector (- (vector-ref c 0) (vector-ref s 0))
                                   (- (vector-ref c 1) (vector-ref s 1))
                                   (vector-ref c 2) (vector-ref c 3)))
  (values (native-operation-rect s) (native-operation-rect c) c))

; finish-image-filter : symbol? image? sk-irect? sk-ipoint? vector? list? -> (values image? vector?
;   vector?)
;   Validates result geometry and preserves precision provenance, closing the image on failure.
(define (finish-image-filter who result out-subset out-offset clip sources)
  (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! result) (raise e))])
    (define-values (subset offset)
      (operation-result-geometry who (image-width result) (image-height result)
        (vector (sk-irect-left out-subset) (sk-irect-top out-subset)
                (- (sk-irect-right out-subset) (sk-irect-left out-subset))
                (- (sk-irect-bottom out-subset) (sk-irect-top out-subset)))
        (vector (sk-ipoint-x out-offset) (sk-ipoint-y out-offset)) clip))
    (audit-inherit-image-precision! (image-h who result) sources)
    (values result subset offset)))

; image-apply-filter : image? image-filter? [#:subset (or/c #f list? vector?)] #:clip (or/c list?
;   vector?) -> (values image? (and/c (vector/c exact-integer? exact-integer?
;   exact-positive-integer? exact-positive-integer?) immutable?) (and/c (vector/c exact-integer?
;   exact-integer?) immutable?))
;   Applies a CPU filter and returns an owned result image, an immutable source rectangle within
;   that image, and an immutable placement offset.
(define (image-apply-filter im filter #:subset [subset #f] #:clip clip)
  (define who 'image-apply-filter)
  (define ih (cpu-image-h who im)) (define fh (image-filter-h who filter))
  (when (owned-gpu-domain fh)
    (error who "GPU-dependent filters require gpu-image-apply-filter; no implicit transfer"))
  (define-values (sr cr checked-clip) (prepare-image-filter who im subset clip))
  (define out-subset (make-sk-irect 0 0 0 0)) (define out-offset (make-sk-ipoint 0 0))
  (call-with-owned who (list ih fh)
    (lambda (ip fp)
      (require-native-cpu-image who ip)
      (define result
        (cpu-image-result who (sk_image_get_color_type ip)
          (lambda () (sk_image_make_with_filter_raster ip fp sr cr out-subset out-offset))))
      ;; A null native return raises; its unspecified out parameters are never
      ;; read and it is not fabricated into a successful empty result.
      (begin0 (finish-image-filter who result out-subset out-offset checked-clip (list ih fh))
        (void/reference-sink sr cr out-subset out-offset)))))


;;;
;;; Raw Image Shaders
;;;

; raw-local-matrix : symbol? (or/c #f matrix?) -> (or/c #f sk-matrix?)
;   Converts an optional invertible affine local matrix to native layout.
(define (raw-local-matrix who value)
  (cond [(not value) #f]
        [else
         (unless (matrix? value) (raise-argument-error who "#f or matrix?" value))
         (unless (matrix-invert value) (error who "local matrix must be invertible"))
         (make-sk-matrix (matrix-xx value) (matrix-xy value) (matrix-x0 value)
                         (matrix-yx value) (matrix-yy value) (matrix-y0 value) 0.0 0.0 1.0)]))

; make-raw-image-shader : image? [#:tile-x (or/c 'clamp 'repeat 'mirror 'decal)] [#:tile-y (or/c
;   'clamp 'repeat 'mirror 'decal)] [#:sampling (or/c 'nearest 'linear)] [#:matrix (or/c #f
;   matrix?)] -> shader?
;   Creates an owned shader that treats image channels as raw numeric samples.
(define (make-raw-image-shader im #:tile-x [tile-x 'clamp] #:tile-y [tile-y 'clamp]
                                #:sampling [mode 'nearest] #:matrix [matrix #f])
  (define who 'make-raw-image-shader)
  (define ih (image-h who im))
  (define tx (choice who tile-x tile-mode-values)) (define ty (choice who tile-y tile-mode-values))
  (define sm (sampling who mode)) (define lm (raw-local-matrix who matrix))
  (when (sk-sampling-use-cubic sm) (error who "raw image shaders do not support cubic sampling"))
  (call-with-owned who (list ih)
    (lambda (ip)
      (begin0 (new-shader who (lambda () (sk_image_make_raw_shader ip tx ty sm lm)))
        (void/reference-sink sm lm)))))

(module* internals #f
  (provide prepare-image-filter finish-image-filter operation-image-record))
