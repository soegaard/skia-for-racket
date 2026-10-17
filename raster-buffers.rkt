#lang racket/base

;;;
;;; Raster Storage and Scoped Pixmaps
;;;

;; Owns formatted pixel storage and lends checked pixmap or canvas access to callbacks.
;; This public pixel layer connects detached image descriptions, exclusive native-memory leases, and
;; copied image results.

;;;
;;; Imports and Exports
;;;

(require ffi/unsafe
         "color.rkt"
         "image-info.rkt"
         "private/core.rkt"
         "private/native.rkt"
         "private/check.rkt"
         "private/types.rkt"
         "private/lifetime.rkt"
         "private/raster-buffer-util.rkt"
         "private/pixel-sample-util.rkt"
         "private/float-pixel-util.rkt"
         "color4f.rkt"
         "private/float-color-native.rkt"
         (only-in "private/audit-trace.rkt" audit-mark-float-pixels!)
         "private/image-info-native.rkt"
         (submod "image-info.rkt" internals)
         (submod "private/core.rkt" raster-buffer-internals))
(provide raster-buffer? make-raster-buffer raster-buffer-width raster-buffer-height
         raster-buffer-row-bytes raster-buffer-byte-size raster-buffer-copy
         raster-buffer->storage-bytes raster-buffer->rgba-bytes
         raster-buffer-write-rgba! raster-buffer->image
         call-with-raster-buffer-canvas call-with-raster-buffer-pixmap
         pixmap? pixmap-width pixmap-height pixmap-row-bytes pixmap-writable?
         pixmap-subset pixmap-pixel pixmap-set-pixel! pixmap-fill!
         pixmap->rgba-bytes pixmap-write-rgba! pixmap-scale!
         make-raster-buffer-from-info raster-buffer-image-info pixmap-image-info
         raster-buffer-write-storage! pixmap->storage-bytes pixmap-write-storage!
         pixmap-sample pixmap-set-sample! pixmap-opaque? raster-buffer-opaque?
         pixmap-convert! raster-buffer-convert raster-buffer-extract-alpha
         make-surface-from-info image->image-info
         color-space->descriptor descriptor->color-space
         pixmap-color4f pixmap-alphaf pixmap-fill-color4f! pixmap-set-color4f!)

; raster-buffer? : any/c -> boolean?
;;   Returns #t for a raster buffer, including a closed one, and #f otherwise.
(define raster-buffer? raster-buffer-resource?)

;;;
;;; Buffer Ownership and Format Metadata
;;;

; buffer-h : symbol? raster-buffer? -> (or/c owned? domain-resource?)
;;   Checks a raster-buffer wrapper and retrieves its managed storage handle.
(define (buffer-h who b)
  (unless (raster-buffer? b) (raise-argument-error who "raster-buffer?" b))
  (raster-buffer-resource-handle b))
; call-buffer : symbol? raster-buffer? procedure? [#:idle? boolean?] -> any/c
;;   Locks buffer storage and, by default, rejects access during an exclusive canvas or pixmap
;;   scope.
(define (call-buffer who b proc #:idle? [idle? #t])
  (call-with-owned who (list (buffer-h who b))
    (lambda (p)
      (when (and idle? (unbox (raster-buffer-resource-state b)))
        (error who "raster buffer has an active canvas or pixmap scope"))
      (proc p))))
; metadata : symbol? raster-buffer? procedure? -> any/c
;;   Reads retained metadata after checking liveness, including during an active exclusive scope.
(define (metadata who b get)
  (call-buffer who b (lambda (_) (get b)) #:idle? #f))
; raster-buffer-width : raster-buffer? -> exact-positive-integer?
;;   Returns the buffer's width in pixels.
(define (raster-buffer-width b) (metadata 'raster-buffer-width b raster-buffer-resource-width))
; raster-buffer-height : raster-buffer? -> exact-positive-integer?
;;   Returns the buffer's height in pixels.
(define (raster-buffer-height b) (metadata 'raster-buffer-height b raster-buffer-resource-height))
; raster-buffer-row-bytes : raster-buffer? -> exact-positive-integer?
;;   Returns the buffer's byte stride between row starts.
(define (raster-buffer-row-bytes b)
  (metadata 'raster-buffer-row-bytes b raster-buffer-resource-row-bytes))
; raster-buffer-byte-size : raster-buffer? -> exact-positive-integer?
;;   Returns the buffer's full allocation size, including padding after every row.
(define (raster-buffer-byte-size b)
  (metadata 'raster-buffer-byte-size b
            (lambda (v) (* (raster-buffer-resource-row-bytes v) (raster-buffer-resource-height v)))))
;; Legacy buffers keep their native color space and original constructor ABI.
;; Only generalized constructors install a detached immutable description.
; buffer-format-info : raster-buffer? -> image-info?
;;   Returns the retained pixel description or the legacy default-format description.
(define (buffer-format-info b)
  (or (raster-buffer-resource-description b)
      (make-image-info (raster-buffer-resource-width b) (raster-buffer-resource-height b))))
; buffer-bpp : raster-buffer? -> exact-positive-integer?
;;   Returns bytes per pixel for the buffer's retained format.
(define (buffer-bpp b) (image-info-bytes-per-pixel (buffer-format-info b)))
; buffer-native-info : raster-buffer? exact-nonnegative-integer? exact-nonnegative-integer? ->
;   sk-image-info?
;;   Builds native image information for specified dimensions using the buffer's format and color
;;   space.
(define (buffer-native-info b w h)
  (define info (buffer-format-info b))
  (make-sk-image-info (raster-buffer-resource-colorspace b) w h
                      (vector-ref (format-data 'raster-buffer (image-info-color-type info)) 0)
                      (case (image-info-alpha-type info) [(opaque) 1] [(premul) 2] [(unpremul) 3])))
; raster-buffer-image-info : raster-buffer? -> image-info?
;;   Returns a detached description of an open buffer's dimensions, storage format, alpha type, and
;;   color interpretation.
(define (raster-buffer-image-info b)
  (metadata 'raster-buffer-image-info b
    (lambda (v)
      (or (raster-buffer-resource-description v)
          (make-image-info (raster-buffer-resource-width v) (raster-buffer-resource-height v)
                           #:color-space (borrowed-color-space->descriptor
                                          'raster-buffer-image-info
                                          (raster-buffer-resource-colorspace v)))))))

;;;
;;; Storage Allocation
;;;

; nonempty-info : symbol? image-info? -> void?
;;   Requires positive dimensions before allocating pixel storage or a surface.
(define (nonempty-info who info)
  (check-info who info)
  (unless (and (positive? (image-info-width info)) (positive? (image-info-height info)))
    (error who "zero-sized image information cannot allocate storage or a surface")))

;; cp is borrowed synchronously. The allocation retains its own native reference.
; allocate-buffer : symbol? integer? integer? integer? any/c [any/c] -> raster-buffer?
;;   Allocates owned strided storage, retains its color space, and initializes format-valid black
;;   pixels.
(define (allocate-buffer who w h rb cp [description #f])
  (define size (* rb h))
  (define handle
    (new-owned who 'raster-buffer
      (lambda ()
        (define p (malloc size 'raw))
        (unless p (error who "pixel allocation failed"))
        (memset p 0 size)
        (when cp (sk_colorspace_ref cp))
        p)
      (lambda (p) (free p) (when cp (sk_colorspace_unref cp)))))
  (define result (make-raster-buffer-record handle w h rb cp (box #f)))
  (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! result) (raise e))])
    (set-raster-buffer-resource-description! result description)
    ;; Opaque formats need initialized maximum alpha, not a zero-alpha lie.
    ;; The unused RGBX byte is initialized to 255; row padding stays zero.
    (when (and description
               (or (eq? (image-info-alpha-type description) 'opaque)
                   (eq? (image-info-color-type description) 'rgb-888x)))
      (define sample (pixel-sample->bytes who description (pixel-black-sample description)))
      (define bpp (bytes-length sample))
      (define row (make-bytes (* w bpp)))
      (for ([x (in-range w)]) (bytes-copy! row (* x bpp) sample))
      (call-with-owned who (list handle)
        (lambda (p)
          (for ([y (in-range h)]) (memcpy (ptr-add p (* y rb)) row (bytes-length row)))
          (void/reference-sink row sample))))
    result))
; make-raster-buffer : (integer-in 1 32768) (integer-in 1 32768) [#:row-bytes (or/c #f
;   exact-positive-integer?)] [#:color-space (or/c #f color-space?)] -> raster-buffer?
;;   Creates an owned RGBA8888 premultiplied buffer initialized to transparent black.
(define (make-raster-buffer w h #:row-bytes [row-bytes #f] #:color-space [cs #f])
  (define who 'make-raster-buffer)
  (define-values (rb minimum allocation) (raster-layout who w h row-bytes))
  (define ch (and cs (color-space-h who cs)))
  (skia-check!)
  (call-with-owned who (if ch (list ch) '())
    (lambda ps (allocate-buffer who w h rb (and ch (car ps))))))
; make-raster-buffer-from-info : image-info? [#:row-bytes (or/c #f exact-positive-integer?)] ->
;   raster-buffer?
;;   Creates an owned buffer in the specified integer or floating-point format.
(define (make-raster-buffer-from-info info #:row-bytes [row-bytes #f])
  (define who 'make-raster-buffer-from-info)
  (nonempty-info who info)
  (define-values (rb minimum allocation) (image-info-storage-layout info #:row-bytes row-bytes))
  (skia-check!)
  (call-with-image-info-native who info
    (lambda (_ cp)
      (allocate-buffer who (image-info-width info) (image-info-height info) rb cp info))))

;; The exclusive lease and continuation barrier are the existing 0.37 protocol.
; call-exclusive : symbol? raster-buffer? any/c procedure? -> any/c
;;   Claims a buffer scope token and clears it on every exit, preventing continuation reentry.
(define (call-exclusive who b token thunk)
  (buffer-h who b)
  (call-with-continuation-barrier
   (lambda ()
     (dynamic-wind
       (lambda ()
         (call-buffer who b
           (lambda (_) (set-box! (raster-buffer-resource-state b) token))))
       thunk
       (lambda () (set-box! (raster-buffer-resource-state b) #f))))))
(struct pixel-lease ([owner #:mutable] creator writable?))
;; A pixel-lease authorizes one thread to use an exclusively borrowed buffer.
;;  - owner      raster-buffer? or #f  Backing buffer while live; cleared on exit.
;;  - creator    thread?              Thread permitted to use the lease.
;;  - writable?  boolean?             Whether pixel writes are allowed.
;; Every pixmap subset shares this lease. Its owner must still point back to the
;; same active lease; keeping the Racket value reachable does not extend the scope.

(struct pixmap (lease x y width-value height-value))
;; A pixmap is a non-owning rectangular view into one leased raster buffer.
;;  - lease         pixel-lease?  Shared lifetime, owner thread, and write authority.
;;  - x             exact nonnegative integer  Column offset in the backing buffer.
;;  - y             exact nonnegative integer  Row offset in the backing buffer.
;;  - width-value   exact positive integer     View width in pixels.
;;  - height-value  exact positive integer     View height in pixels.
;; Bounds stay within the owner. Subsets preserve its row stride rather than
;; repacking rows, and every access validates the shared lease before using memory.

;;;
;;; Scoped Pixmap Access
;;;

; view-owner : symbol? pixmap? [boolean?] -> raster-buffer?
;;   Checks thread, lease lifetime, and optional write permission before returning the backing
;;   buffer.
(define (view-owner who v [write? #f])
  (unless (pixmap? v) (raise-argument-error who "pixmap?" v))
  (define lease (pixmap-lease v))
  (unless (eq? (current-thread) (pixel-lease-creator lease))
    (error who "pixmap belongs to another Racket thread"))
  (define b (pixel-lease-owner lease))
  (unless (and b (eq? lease (unbox (raster-buffer-resource-state b))))
    (error who "pixmap scope has expired"))
  (when (and write? (not (pixel-lease-writable? lease))) (error who "pixmap is read-only"))
  b)
; pixmap-width : pixmap? -> exact-positive-integer?
;;   Returns the view's width in pixels.
(define (pixmap-width v) (view-owner 'pixmap-width v) (pixmap-width-value v))
; pixmap-height : pixmap? -> exact-positive-integer?
;;   Returns the view's height in pixels.
(define (pixmap-height v) (view-owner 'pixmap-height v) (pixmap-height-value v))
; pixmap-row-bytes : pixmap? -> exact-positive-integer?
;;   Returns the view's byte stride of its underlying buffer.
(define (pixmap-row-bytes v) (raster-buffer-resource-row-bytes (view-owner 'pixmap-row-bytes v)))
; pixmap-writable? : pixmap? -> boolean?
;;   Returns the view's write permission.
(define (pixmap-writable? v)
  (view-owner 'pixmap-writable? v)
  (pixel-lease-writable? (pixmap-lease v)))
; pixmap-image-info : pixmap? -> image-info?
;;   Returns the view's detached image description, with the view's dimensions.
(define (pixmap-image-info v)
  (define b (view-owner 'pixmap-image-info v))
  (image-info-with-dimensions
   (raster-buffer-image-info b) (pixmap-width-value v) (pixmap-height-value v)))
; view-format-info : pixmap? -> image-info?
;;   Combines the live backing format with the view's dimensions.
(define (view-format-info v)
  (image-info-with-dimensions (buffer-format-info (view-owner 'pixmap v))
                              (pixmap-width-value v) (pixmap-height-value v)))
; call-with-raster-buffer-pixmap : raster-buffer? (-> pixmap? any) [#:writable? boolean?] -> any
;;   Calls proc with a view of the entire buffer and returns its values.
(define (call-with-raster-buffer-pixmap b proc #:writable? [writable? #f])
  (define who 'call-with-raster-buffer-pixmap)
  (raster-procedure who proc) (boolean who writable?) (buffer-h who b)
  (define lease (pixel-lease b (current-thread) writable?))
  (call-exclusive who b lease
    (lambda ()
      (dynamic-wind void
        (lambda ()
          (proc (pixmap lease 0 0
                        (raster-buffer-resource-width b) (raster-buffer-resource-height b))))
        (lambda () (set-pixel-lease-owner! lease #f))))))
; pixmap-subset : pixmap? exact-nonnegative-integer? exact-nonnegative-integer?
;   exact-positive-integer? exact-positive-integer? -> pixmap?
;;   Returns a subview wholly inside view.
(define (pixmap-subset v x y w h)
  (view-owner 'pixmap-subset v)
  (raster-subset 'pixmap-subset x y w h (pixmap-width-value v) (pixmap-height-value v))
  (pixmap (pixmap-lease v) (+ (pixmap-x v) x) (+ (pixmap-y v) y) w h))
; call-view : symbol? pixmap? procedure? [#:write? boolean?] -> any/c
;;   Lends a temporary native pixmap over the leased subrectangle while preserving backing row
;;   stride.
(define (call-view who v proc #:write? [write? #f])
  (define b (view-owner who v write?))
  (call-buffer who b
    (lambda (base)
      (define rb (raster-buffer-resource-row-bytes b))
      (define address (ptr-add base (+ (* rb (pixmap-y v)) (* (buffer-bpp b) (pixmap-x v)))))
      (define info (buffer-native-info b (pixmap-width-value v) (pixmap-height-value v)))
      (call-with-native-temporary who 'pixmap
        (lambda () (sk_pixmap_new_with_params info address rb)) sk_pixmap_destructor
        (lambda (pm) (proc pm address rb b))))
    #:idle? #f))
; pixmap-pixel : pixmap? exact-nonnegative-integer? exact-nonnegative-integer? -> rgba?
;;   Returns an unpremultiplied eight-bit color.
(define (pixmap-pixel v x y)
  (view-owner 'pixmap-pixel v)
  (raster-point 'pixmap-pixel x y (pixmap-width-value v) (pixmap-height-value v))
  (if (float-info? (view-format-info v))
      (color4f->rgba (pixmap-color4f v x y) #:out-of-range 'clip)
      (call-view 'pixmap-pixel v
        (lambda (pm address rb b) (color->rgba (sk_pixmap_get_pixel_color pm x y))))))
; pixmap-fill! : pixmap? color? -> void?
;;   Fills the view through the native color eraser.
(define (pixmap-fill! v color)
  (define who 'pixmap-fill!)
  (define argb (color->argb color))
  (call-view who v
    (lambda (pm address rb b)
      (define packed (if (eq? (image-info-alpha-type (buffer-format-info b)) 'opaque)
                         (bitwise-ior argb #xff000000) argb))
      (unless (sk_pixmap_erase_color pm packed #f)
        (error who "native pixel fill failed")))
    #:write? #t)
  (void))
; pixmap-set-pixel! : pixmap? exact-nonnegative-integer? exact-nonnegative-integer? color? -> void?
;;   Like pixmap-fill!, but writes one pixel.
(define (pixmap-set-pixel! v x y color)
  (define who 'pixmap-set-pixel!)
  (view-owner who v #t)
  (raster-point who x y (pixmap-width-value v) (pixmap-height-value v))
  (pixmap-fill! (pixmap-subset v x y 1 1) color))
; pixmap-opaque? : pixmap? -> boolean?
;;   Reports whether all pixels in the view have fully opaque alpha.
(define (pixmap-opaque? v)
  (call-view 'pixmap-opaque? v (lambda (pm _a _rb _b) (sk_pixmap_compute_is_opaque pm))))
; raster-buffer-opaque? : raster-buffer? -> boolean?
;;   Scans the pixels and reports whether their alpha is fully opaque.
(define (raster-buffer-opaque? b) (call-with-raster-buffer-pixmap b pixmap-opaque?))


;;;
;;; Stored Pixel Samples
;;;

; pixmap-sample : pixmap? exact-nonnegative-integer? exact-nonnegative-integer? -> (and/c vector?
;   immutable?)
;;   Returns the stored logical channels as a detached immutable vector.
(define (pixmap-sample v x y)
  (define who 'pixmap-sample)
  (define b (view-owner who v))
  (raster-point who x y (pixmap-width-value v) (pixmap-height-value v))
  (define info (buffer-format-info b))
  (define bpp (buffer-bpp b))
  (call-view who v
    (lambda (_pm address rb _b)
      (define bytes (make-bytes bpp))
      (memcpy bytes (ptr-add address (+ (* y rb) (* x bpp))) bpp)
      (pixel-bytes->sample who info bytes))))
; pixmap-set-sample! : pixmap? exact-nonnegative-integer? exact-nonnegative-integer? (or/c list?
;   vector?) -> void?
;;   Validates and stores one sample in the view's format.
(define (pixmap-set-sample! v x y sample)
  (define who 'pixmap-set-sample!)
  (define b (view-owner who v #t))
  (raster-point who x y (pixmap-width-value v) (pixmap-height-value v))
  (define data (pixel-sample->bytes who (buffer-format-info b) sample))
  (call-view who v
    (lambda (_pm address rb _b)
      (memcpy (ptr-add address (+ (* y rb) (* x (bytes-length data)))) data (bytes-length data))
      (void/reference-sink data)) #:write? #t)
  (void))
; pixmap->storage-bytes : pixmap? -> bytes?
;;   Returns a detached mutable copy of the view's pixels in their stored format.
(define (pixmap->storage-bytes v)
  (define who 'pixmap->storage-bytes)
  (define info (view-format-info v))
  (define-values (tight _minimum count) (image-info-storage-layout info))
  (define out (make-bytes count))
  (call-view who v
    (lambda (_pm address rb _b)
      (define row (make-bytes tight))
      (for ([y (in-range (image-info-height info))])
        (memcpy row (ptr-add address (* y rb)) tight)
        (bytes-copy! out (* y tight) row))
      (void/reference-sink out row)))
  out)
; pixmap-write-storage! : pixmap? bytes? [#:row-bytes (or/c #f exact-positive-integer?)] -> void?
;;   Copies validated stored samples into the view.
(define (pixmap-write-storage! v data #:row-bytes [row-bytes #f])
  (define who 'pixmap-write-storage!)
  (view-owner who v #t)
  (define info (view-format-info v))
  (define-values (rb _min _alloc) (image-info-storage-layout info #:row-bytes row-bytes))
  (define input (pixel-tight-input who info data rb))
  (copy-tight-to-view! who v input))
; copy-tight-to-view! : symbol? pixmap? bytes? -> void?
;;   Copies packed rows into a writable view without changing destination row padding.
(define (copy-tight-to-view! who v input)
  (define w (pixmap-width-value v)) (define h (pixmap-height-value v))
  (call-view who v
    (lambda (_pm address rb b)
      (define tight (* w (buffer-bpp b)))
      (for ([y (in-range h)])
        (memcpy (ptr-add address (* y rb)) (subbytes input (* y tight) (* (add1 y) tight)) tight))
      (void/reference-sink input)) #:write? #t)
  (void))
; raster-buffer-write-storage! : raster-buffer? bytes? -> void?
;;   Replaces the full allocation, including padding.
(define (raster-buffer-write-storage! b data)
  (define who 'raster-buffer-write-storage!)
  (call-buffer who b
    (lambda (p)
      (define input (pixel-storage-input who (buffer-format-info b) data
                                            (raster-buffer-resource-row-bytes b) #:full? #t))
      (memcpy p input (bytes-length input))
      (void/reference-sink input)))
  (void))

;;;
;;; RGBA Conversion and Transfer
;;;

; pixmap->rgba-bytes : pixmap? [#:premultiplied? boolean?] -> bytes?
;;   Returns tightly packed, mutable RGBA8888 bytes for the view.
(define (pixmap->rgba-bytes v #:premultiplied? [premultiplied? #f])
  (define who 'pixmap->rgba-bytes)
  (boolean who premultiplied?) (view-owner who v)
  (define w (pixmap-width-value v)) (define h (pixmap-height-value v))
  (define out (make-bytes (check-dimensions who w h)))
  (call-view who v
    (lambda (pm address rb b)
      (define info (make-sk-image-info (raster-buffer-resource-colorspace b) w h
                                      rgba-8888 (if premultiplied? alpha-premul alpha-unpremul)))
      (unless (sk_pixmap_read_pixels pm info out (* 4 w) 0 0) (error who "native RGBA read failed"))))
  out)
; pixmap-write-rgba! : pixmap? bytes? [#:row-bytes (or/c #f exact-positive-integer?)]
;   [#:premultiplied? boolean?] -> void?
;;   Converts RGBA8888 input into the view's storage format.
(define (pixmap-write-rgba! v data #:row-bytes [row-bytes #f] #:premultiplied? [premultiplied? #f])
  (define who 'pixmap-write-rgba!)
  (define owner (view-owner who v #t))
  (define w (pixmap-width-value v)) (define h (pixmap-height-value v))
  (cond
    [(not (raster-buffer-resource-description owner))
     ;; Preserve the existing byte-exact Racket premultiplication contract.
     (copy-tight-to-view! who v (prepare-raster-input who w h data row-bytes premultiplied?))]
    [else
     (boolean who premultiplied?)
     (define src-info (make-image-info w h #:alpha-type (if premultiplied? 'premul 'unpremul)))
     (define-values (rb _m _n) (image-info-storage-layout src-info #:row-bytes row-bytes))
     (define input (pixel-tight-input who src-info data rb))
     (define tight (* w (buffer-bpp owner)))
     (define out (make-bytes (* tight h)))
     (call-view who v
       (lambda (_pm _address _rb b)
         ;; These RGBA input samples use the destination's color interpretation,
         ;; as in the legacy write operation; this is NOT an implicit sRGB tag.
         (define native (make-sk-image-info (raster-buffer-resource-colorspace b) w h rgba-8888
                                            (if premultiplied? alpha-premul alpha-unpremul)))
         ;; SkPixmap retains its input address between FFI calls. Use raw,
         ;; immobile storage, not a borrowed address into a movable byte string.
         ;; This allocation/cleanup pair is inside call-view's atomic scope.
         (define memory (malloc (bytes-length input) 'raw))
         (unless memory (error who "temporary pixel allocation failed"))
         (dynamic-wind void
           (lambda ()
             (memcpy memory input (bytes-length input))
             (call-with-native-temporary who 'pixmap
               (lambda () (sk_pixmap_new_with_params native memory (* w 4))) sk_pixmap_destructor
               (lambda (src)
                 (unless (sk_pixmap_read_pixels src (buffer-native-info b w h) out tight 0 0)
                   (error who "native RGBA-to-storage conversion failed")))))
           (lambda () (free memory)))
         (void/reference-sink input out)))
     (copy-tight-to-view! who v out)])
  (void))

;;;
;;; Checked Buffer Conversion
;;;

; conversion-spaces : symbol? raster-buffer? raster-buffer? -> void?
;;   Rejects tagged/untagged conversions that would require an unstated source interpretation.
(define (conversion-spaces who src dst)
  (define sc (raster-buffer-resource-colorspace src))
  (define dc (raster-buffer-resource-colorspace dst))
  (unless (eq? (and sc #t) (and dc #t))
    (error who
           "tagged/untagged conversion requires an explicit source interpretation; metadata is not conversion")))
; pixmap-convert! : pixmap? pixmap? -> void?
;;   Converts source pixels into the destination format and color space.
(define (pixmap-convert! destination source)
  (define who 'pixmap-convert!)
  (define dst (view-owner who destination #t)) (define src (view-owner who source))
  (when (eq? dst src) (error who "source and destination must have distinct raster buffers"))
  (unless (and (= (pixmap-width-value destination) (pixmap-width-value source))
               (= (pixmap-height-value destination) (pixmap-height-value source)))
    (error who "conversion requires matching dimensions; use pixmap-scale! for scaling"))
  (conversion-spaces who src dst)
  (define info (view-format-info destination))
  (define-values (tight _m size) (image-info-storage-layout info))
  (define staging (make-bytes size))
  (call-view who source
    (lambda (sp _a _rb _b)
      (call-view who destination
        (lambda (_dp _da _dr db)
          (unless (sk_pixmap_read_pixels
                   sp (buffer-native-info db (image-info-width info) (image-info-height info))
                                         staging tight 0 0)
            (error who "native pixel conversion failed"))) #:write? #t)))
  ;; A conversion that overflows its destination float format must not publish
  ;; nonfinite pixels or modify the destination before validation completes.
  (when (float-info? info) (pixel-storage-input who info staging tight))
  (copy-tight-to-view! who destination staging))
; pixmap-scale! : pixmap? pixmap? [#:sampling (or/c 'nearest 'linear)] -> void?
;;   Scales and converts the source into the destination.
(define (pixmap-scale! destination source #:sampling [mode 'linear])
  (define who 'pixmap-scale!) (define sm (sampling who mode))
  (define dst (view-owner who destination #t)) (define src (view-owner who source))
  (when (eq? dst src) (error who "source and destination must have distinct raster buffers"))
  ;; Preserve legacy color semantics; new explicit format routes reject an
  ;; otherwise silent tagged/untagged color interpretation change.
  (when (or (raster-buffer-resource-description src) (raster-buffer-resource-description dst))
    (conversion-spaces who src dst))
  (call-view who source
    (lambda (sp sa sr sb)
      (call-view who destination
        (lambda (dp da dr db)
          (unless (sk_pixmap_scale_pixels sp dp sm)
            (error who "native pixmap scaling failed")))
        #:write? #t)))
  (void))
; raster-buffer->storage-bytes : raster-buffer? -> bytes?
;;   Returns a detached mutable copy of the full allocation, including all row padding.
(define (raster-buffer->storage-bytes b)
  (define who 'raster-buffer->storage-bytes)
  (call-buffer who b
    (lambda (p)
      (define n (raster-buffer-byte-size b))
      (unless (<= n (current-skia-byte-limit)) (error who "storage copy exceeds byte limit"))
      (define out (make-bytes n)) (memcpy out p n) out)))
; raster-buffer->rgba-bytes : raster-buffer? [#:premultiplied? boolean?] -> bytes?
;;   Returns a detached mutable, tightly packed RGBA8888 copy.
(define (raster-buffer->rgba-bytes b #:premultiplied? [premultiplied? #f])
  (boolean 'raster-buffer->rgba-bytes premultiplied?)
  (call-with-raster-buffer-pixmap b
    (lambda (v) (pixmap->rgba-bytes v #:premultiplied? premultiplied?))))
; raster-buffer-write-rgba! : raster-buffer? bytes? [#:row-bytes (or/c #f exact-positive-integer?)]
;   [#:premultiplied? boolean?] -> void?
;;   Writes RGBA8888 input using pixmap-write-rgba!
(define (raster-buffer-write-rgba! b data
                                   #:row-bytes [row-bytes #f]
                                   #:premultiplied? [premultiplied? #f])
  (call-with-raster-buffer-pixmap b
    (lambda (v)
      (pixmap-write-rgba! v data #:row-bytes row-bytes #:premultiplied? premultiplied?))
    #:writable? #t))
; raster-buffer-copy : raster-buffer? [#:row-bytes (or/c #f exact-positive-integer?)] ->
;   raster-buffer?
;;   Returns an independently owned copy with the same dimensions, format, and color interpretation.
(define (raster-buffer-copy b #:row-bytes [row-bytes #f])
  (define who 'raster-buffer-copy)
  (call-buffer who b
    (lambda (p)
      (define w (raster-buffer-resource-width b)) (define h (raster-buffer-resource-height b))
      (define d (raster-buffer-resource-description b))
      (define-values (rb minimum allocation)
        (if d (image-info-storage-layout d #:row-bytes row-bytes) (raster-layout who w h row-bytes)))
      (define result (allocate-buffer who w h rb (raster-buffer-resource-colorspace b) d))
      (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! result) (raise e))])
        (call-buffer who result
          (lambda (q)
            (for ([y (in-range h)])
              (memcpy (ptr-add q (* y rb)) (ptr-add p (* y (raster-buffer-resource-row-bytes b)))
                      (* (buffer-bpp b) w)))))
        result))))
; raster-buffer-convert : raster-buffer? image-info? [#:row-bytes (or/c #f exact-positive-integer?)]
;   -> raster-buffer?
;;   Returns a new owned buffer converted to info.
(define (raster-buffer-convert b info #:row-bytes [row-bytes #f])
  (define who 'raster-buffer-convert)
  (nonempty-info who info)
  (call-buffer who b (lambda (_) (void)))
  (unless (and (= (image-info-width info) (raster-buffer-width b))
               (= (image-info-height info) (raster-buffer-height b)))
    (error who "conversion requires matching dimensions"))
  (define result (make-raster-buffer-from-info info #:row-bytes row-bytes))
  (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! result) (raise e))])
    (call-with-raster-buffer-pixmap b
      (lambda (src)
        (call-with-raster-buffer-pixmap result
          (lambda (dst) (pixmap-convert! dst src))
          #:writable? #t)))
    result))
; raster-buffer-extract-alpha : raster-buffer? -> raster-buffer?
;;   Returns an independent Alpha8 buffer containing normalized alpha quantized to eight bits.
(define (raster-buffer-extract-alpha b)
  (define who 'raster-buffer-extract-alpha)
  (call-buffer who b (lambda (_) (void)))
  (define info (buffer-format-info b))
  (define width (image-info-width info)) (define height (image-info-height info))
  (define result (make-raster-buffer-from-info (make-image-info width height #:color-type 'alpha-8)))
  (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! result) (raise e))])
    (define pixels (raster-buffer->storage-bytes b))
    (define rb (raster-buffer-row-bytes b)) (define bpp (buffer-bpp b))
    (define alpha (make-bytes (* width height)))
    (for* ([y (in-range height)] [x (in-range width)])
      (bytes-set! alpha (+ x (* y width))
                  (pixel-sample-alpha/8
                   info (pixel-bytes->sample who info pixels (+ (* y rb) (* x bpp))))))
    (raster-buffer-write-storage! result alpha)
    result))

;;;
;;; Image and Surface Bridges
;;;

; raster-buffer->image : raster-buffer? -> image?
;;   Returns an independently owned image containing copied pixels in the buffer's color and alpha
;;   format.
(define (raster-buffer->image b)
  (define who 'raster-buffer->image)
  ;; Two copies: detached Racket storage, then an immutable native raster copy.
  ;; Preserve the selected color/alpha format; never alias mutable storage.
  (define pixels (raster-buffer->storage-bytes b))
  (call-buffer who b
    (lambda (p)
      (define w (raster-buffer-resource-width b)) (define h (raster-buffer-resource-height b))
      (define info (buffer-native-info b w h))
      (define handle
        (new-owned who 'image
                   (lambda ()
                     (sk_image_new_raster_copy info pixels (raster-buffer-resource-row-bytes b)))
                   sk_image_unref))
      (when (float-info? (buffer-format-info b)) (audit-mark-float-pixels! handle))
      (begin0 (make-image-record handle w h) (void/reference-sink pixels)))))
; image->image-info : image? -> image-info?
;;   Returns a detached description of the image's dimensions, native color/alpha types, and copied
;;   color interpretation.
(define (image->image-info image)
  (unless (image? image) (raise-argument-error 'image->image-info "image?" image))
  (define space (image-color-space image))
  (dynamic-wind void
    (lambda ()
      (make-image-info (image-width image) (image-height image)
                       #:color-type (image-color-type image) #:alpha-type (image-alpha-type image)
                       #:color-space (and space (color-space->descriptor space))))
    (lambda () (when space (skia-close! space)))))
; make-surface-from-info : image-info? [#:row-bytes (or/c #f exact-positive-integer?)] [#:background
;   (or/c #f color?)] -> surface?
;;   Creates an owned CPU surface in a supported drawing format.
(define (make-surface-from-info info #:row-bytes [row-bytes #f] #:background [background #f])
  (define who 'make-surface-from-info)
  (nonempty-info who info)
  (unless (image-info-supports? info 'raster-canvas)
    (error who "unpremultiplied raster targets are not supported"))
  (define-values (rb minimum allocation) (image-info-storage-layout info #:row-bytes row-bytes))
  (define clear (if background (color->argb background)
                    (if (eq? (image-info-alpha-type info) 'opaque) #xff000000 0)))
  (skia-check!)
  (call-with-image-info-native who info
    (lambda (native _cp)
      (define handle
        (new-owned who 'surface (lambda () (sk_surface_new_raster native rb #f)) sk_surface_unref))
      (when (float-info? info) (audit-mark-float-pixels! handle))
      (define result
        (make-surface-record handle (image-info-width info) (image-info-height info) '()))
      (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! result) (raise e))])
        (canvas-clear! (surface-canvas result) clear)
        result))))
; call-with-raster-buffer-canvas : raster-buffer? (-> canvas? any) -> any
;;   Calls proc once with a canvas drawing directly into the buffer and returns its values.
(define (call-with-raster-buffer-canvas b proc)
  (define who 'call-with-raster-buffer-canvas)
  (raster-procedure who proc) (buffer-h who b)
  (unless (image-info-supports? (buffer-format-info b) 'raster-canvas)
    (error who "unpremultiplied raster targets are not supported"))
  (call-exclusive who b 'canvas
    (lambda ()
      (define surface #f)
      (dynamic-wind void
        (lambda ()
          (call-buffer who b
            (lambda (pixels)
              (define w (raster-buffer-resource-width b)) (define h (raster-buffer-resource-height b))
              (define info (buffer-native-info b w h))
              (define handle
                (new-owned who 'surface
                  (lambda ()
                    (sk_surface_new_raster_direct
                     info pixels (raster-buffer-resource-row-bytes b) #f #f #f))
                  sk_surface_unref))
              (when (float-info? (buffer-format-info b)) (audit-mark-float-pixels! handle))
              (set! surface (make-surface-record handle w h '()))) #:idle? #f)
          (define c (surface-canvas surface))
          (with-canvas-state c (proc c)))
        (lambda () (when surface (skia-close! surface)))))))

;; The existing GPU readback ABI supplies only width/height/stride/color-space:
;; it writes RGBA8888 premultiplied. Reject other formats BEFORE exposing memory.
(module* gpu-transfer-internals #f
  (provide call-with-raster-buffer-gpu-transfer)
  ; call-with-raster-buffer-gpu-transfer : raster-buffer? procedure? -> any/c
  ;;   Exclusively lends compatible raster storage for an explicit GPU readback operation.
  (define (call-with-raster-buffer-gpu-transfer b proc)
    (define who 'gpu-surface-read-raster-buffer!)
    (buffer-h who b)
    (unless (image-info-supports? (buffer-format-info b) 'gpu-readback)
      (error who
             "GPU readback requires RGBA8888 premultiplied storage; convert explicitly after readback"))
    (call-exclusive who b 'gpu-transfer
      (lambda ()
        (define p (call-buffer who b values #:idle? #f))
        (begin0
          (proc p (raster-buffer-resource-width b) (raster-buffer-resource-height b)
                (raster-buffer-resource-row-bytes b) (raster-buffer-resource-colorspace b))
          (void/reference-sink b))))))


;; Float color reads return unpremultiplied values in the PIXMAP's color space,
;; without converting them to sRGB. Raw pixmap-sample instead returns stored
;; (possibly premultiplied) channels and preserves binary16 subnormals exactly.

;;;
;;; Floating-Point Pixel Access
;;;

; pixmap-color4f : pixmap? exact-nonnegative-integer? exact-nonnegative-integer? -> color4f?
;;   Returns the unpremultiplied floating-point color in the pixmap's color space.
(define (pixmap-color4f v x y)
  (define who 'pixmap-color4f)
  (view-owner who v)
  (raster-point who x y (pixmap-width-value v) (pixmap-height-value v))
  (define out (make-sk-color4f 0.0 0.0 0.0 0.0))
  (call-view who v (lambda (pm _a _rb _b) (sk_pixmap_get_pixel_color4f pm x y out)))
  (native->color4f out))
; pixmap-alphaf : pixmap? exact-nonnegative-integer? exact-nonnegative-integer? -> (real-in 0 1)
;;   Returns normalized alpha without returning or converting the RGB channels.
(define (pixmap-alphaf v x y)
  (define who 'pixmap-alphaf)
  (view-owner who v)
  (raster-point who x y (pixmap-width-value v) (pixmap-height-value v))
  (define a (call-view who v (lambda (pm _a _rb _b) (sk_pixmap_get_pixel_alphaf pm x y))))
  (unless (and (real? a) (<= 0 a 1)) (error who "native alpha is not finite/in [0,1]"))
  a)
; pixmap-fill-color4f! : pixmap? color4f? -> void?
;;   Fills the view with an unpremultiplied sRGB color converted to the destination color space and
;;   storage format.
(define (pixmap-fill-color4f! v color)
  (define who 'pixmap-fill-color4f!)
  (define native (color4f-native who color))
  (define b (view-owner who v #t))
  (define info (buffer-format-info b))
  (when (and (eq? (image-info-alpha-type info) 'opaque) (not (= (color4f-alpha color) 1)))
    (error who "opaque storage requires an opaque fill color"))
  (call-view who v
    (lambda (_pm address rb owner)
      (define bpp (buffer-bpp owner))
      (define scratch (malloc bpp 'raw))
      (unless scratch (error who "temporary sample allocation failed"))
      (dynamic-wind void
        (lambda ()
          (memset scratch 0 bpp)
          ;; Pinned SkPixmap::erase converts UNPREMULTIPLIED sRGB into the
          ;; destination space. It is not a raw local-space sample write.
          ;; Stage one native pixel first so overflow/invalid converted samples
          ;; reject before any destination mutation (including late failures).
          (call-with-native-temporary who 'pixmap
            (lambda () (sk_pixmap_new_with_params (buffer-native-info owner 1 1) scratch bpp))
            sk_pixmap_destructor
            (lambda (sp)
              (unless (sk_pixmap_erase_color4f sp native #f) (error who "native float fill failed"))))
          (define data (make-bytes bpp))
          (memcpy data scratch bpp)
          (define sample (pixel-bytes->sample who info data))
          (pixel-sample->bytes who info sample) ; validate integer alpha semantics too
          (define row (make-bytes (* bpp (pixmap-width-value v))))
          (for ([x (in-range (pixmap-width-value v))]) (bytes-copy! row (* x bpp) data))
          (for ([y (in-range (pixmap-height-value v))])
            (memcpy (ptr-add address (* y rb)) row (bytes-length row)))
          (void/reference-sink row data native))
        (lambda () (free scratch)))) #:write? #t)
  (void))
; pixmap-set-color4f! : pixmap? exact-nonnegative-integer? exact-nonnegative-integer? color4f? ->
;   void?
;;   Like pixmap-fill-color4f!, but writes one pixel.
(define (pixmap-set-color4f! v x y color)
  (view-owner 'pixmap-set-color4f! v #t)
  (raster-point 'pixmap-set-color4f! x y (pixmap-width-value v) (pixmap-height-value v))
  (pixmap-fill-color4f! (pixmap-subset v x y 1 1) color))


;; Internal image read/scale transaction. The callback is library-authored,
;; synchronous, and never exposed as an application callback. The destination
;; lease is checked before allocation and remains checked throughout the copy.
(module* image-operation-internals #f
  (provide view-owner call-with-pixmap-write-staging)
  ; call-with-pixmap-write-staging : symbol? pixmap? procedure? -> void?
  ;;   Stages a native write in fixed storage and commits validated pixels only after successful
  ;;   completion.
  (define (call-with-pixmap-write-staging who destination proc)
    (view-owner who destination #t)
    (define info (view-format-info destination))
    (define-values (tight _minimum size) (image-info-storage-layout info))
    (call-view who destination
      (lambda (_dp address rb owner)
        ;; Native SkPixmap retains an address between calls. Use immobile raw
        ;; storage, not a pointer into a movable Racket byte string.
        (define memory (malloc size 'raw))
        (unless memory (error who "image staging allocation failed"))
        (dynamic-wind void
          (lambda ()
            (memset memory 0 size)
            (define native
              (buffer-native-info owner (image-info-width info) (image-info-height info)))
            (call-with-native-temporary who 'pixmap
              (lambda () (sk_pixmap_new_with_params native memory tight)) sk_pixmap_destructor
              (lambda (pm)
                (cond
                  [(procedure-arity-includes? proc 4) (proc pm native memory tight)]
                  [(procedure-arity-includes? proc 2) (proc pm native)]
                  [else
                   (raise-arguments-error who
                     "staging callback must accept two or four arguments"
                     "callback" proc)])))
            ;; No destination byte changes on a failed native call or invalid
            ;; float/premultiplied/opaque result. Padding is never committed.
            (define observed (make-bytes size))
            (memcpy observed memory size)
            (pixel-storage-input who info observed tight)
            (for ([y (in-range (image-info-height info))])
              (memcpy (ptr-add address (* y rb)) (ptr-add memory (* y tight)) tight))
            (void/reference-sink observed native))
          (lambda () (free memory)))) #:write? #t)
    (void)))
