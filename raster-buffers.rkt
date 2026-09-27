#lang racket/base
(require ffi/unsafe
         "color.rkt" "private/core.rkt" "private/native.rkt"
         "private/check.rkt" "private/types.rkt" "private/lifetime.rkt"
         "private/raster-buffer-util.rkt"
         (submod "private/core.rkt" raster-buffer-internals))
(provide raster-buffer? make-raster-buffer raster-buffer-width raster-buffer-height
         raster-buffer-row-bytes raster-buffer-byte-size raster-buffer-copy
         raster-buffer->storage-bytes raster-buffer->rgba-bytes
         raster-buffer-write-rgba! raster-buffer->image
         call-with-raster-buffer-canvas call-with-raster-buffer-pixmap
         pixmap? pixmap-width pixmap-height pixmap-row-bytes pixmap-writable?
         pixmap-subset pixmap-pixel pixmap-set-pixel! pixmap-fill!
         pixmap->rgba-bytes pixmap-write-rgba! pixmap-scale!)

(define raster-buffer? raster-buffer-resource?)
(define (buffer-h who b)
  (unless (raster-buffer? b) (raise-argument-error who "raster-buffer?" b))
  (raster-buffer-resource-handle b))
(define (call-buffer who b proc #:idle? [idle? #t])
  (call-with-owned who (list (buffer-h who b))
    (lambda (p)
      (when (and idle? (unbox (raster-buffer-resource-state b)))
        (error who "raster buffer has an active canvas or pixmap scope"))
      (proc p))))
(define (metadata who b get)
  (call-buffer who b (lambda (_) (get b)) #:idle? #f))
(define (raster-buffer-width b) (metadata 'raster-buffer-width b raster-buffer-resource-width))
(define (raster-buffer-height b) (metadata 'raster-buffer-height b raster-buffer-resource-height))
(define (raster-buffer-row-bytes b) (metadata 'raster-buffer-row-bytes b raster-buffer-resource-row-bytes))
(define (raster-buffer-byte-size b)
  (metadata 'raster-buffer-byte-size b
            (lambda (v) (* (raster-buffer-resource-row-bytes v) (raster-buffer-resource-height v)))))

;; cp is borrowed for this synchronous constructor. The returned allocation
;; retains its own color-space reference; its release closure owns no wrapper.
(define (allocate-buffer who w h rb cp)
  (define size (* rb h))
  (define handle
    (new-owned who 'raster-buffer
      (lambda ()
        (define p (malloc size 'raw))
        (unless p (error who "pixel allocation failed"))
        (memset p 0 size)
        (when cp (sk_colorspace_ref cp))
        p)
      (lambda (p)
        (free p)
        (when cp (sk_colorspace_unref cp)))))
  (make-raster-buffer-record handle w h rb cp (box #f)))

(define (make-raster-buffer w h #:row-bytes [row-bytes #f] #:color-space [cs #f])
  (define who 'make-raster-buffer)
  (define-values (rb minimum allocation) (raster-layout who w h row-bytes))
  (define ch (and cs (color-space-h who cs)))
  (skia-check!)
  (call-with-owned who (if ch (list ch) '())
    (lambda ps (allocate-buffer who w h rb (and ch (car ps))))))

;; Each borrow is exclusive. Leave the atomic section before calling user
;; code; each actual memory/native operation rechecks ownership atomically.
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

;; An escaped view keeps a retired lease, not a retained buffer or raw pointer.
(struct pixel-lease ([owner #:mutable] creator writable?))
(struct pixmap (lease x y width-value height-value))
(define (view-owner who v [write? #f])
  (unless (pixmap? v) (raise-argument-error who "pixmap?" v))
  (define lease (pixmap-lease v))
  (unless (eq? (current-thread) (pixel-lease-creator lease))
    (error who "pixmap belongs to another Racket thread"))
  (define b (pixel-lease-owner lease))
  (unless (and b (eq? lease (unbox (raster-buffer-resource-state b))))
    (error who "pixmap scope has expired"))
  (when (and write? (not (pixel-lease-writable? lease)))
    (error who "pixmap is read-only"))
  b)
(define (pixmap-width v) (view-owner 'pixmap-width v) (pixmap-width-value v))
(define (pixmap-height v) (view-owner 'pixmap-height v) (pixmap-height-value v))
(define (pixmap-row-bytes v)
  (raster-buffer-resource-row-bytes (view-owner 'pixmap-row-bytes v)))
(define (pixmap-writable? v)
  (view-owner 'pixmap-writable? v)
  (pixel-lease-writable? (pixmap-lease v)))

(define (call-with-raster-buffer-pixmap b proc #:writable? [writable? #f])
  (define who 'call-with-raster-buffer-pixmap)
  (raster-procedure who proc)
  (boolean who writable?)
  (buffer-h who b)
  (define lease (pixel-lease b (current-thread) writable?))
  (call-exclusive who b lease
    (lambda ()
      (dynamic-wind void
        (lambda () (proc (pixmap lease 0 0 (raster-buffer-resource-width b)
                                (raster-buffer-resource-height b))))
        (lambda () (set-pixel-lease-owner! lease #f))))))

(define (pixmap-subset v x y w h)
  (view-owner 'pixmap-subset v)
  (raster-subset 'pixmap-subset x y w h (pixmap-width-value v) (pixmap-height-value v))
  (pixmap (pixmap-lease v) (+ (pixmap-x v) x) (+ (pixmap-y v) y) w h))

;; A native SkPixmap is a temporary descriptor, never a pixel-memory owner.
;; It is rebuilt from checked integers and a live buffer at each operation.
(define (call-view who v proc #:write? [write? #f])
  (define b (view-owner who v write?))
  (call-buffer who b
    (lambda (base)
      (define rb (raster-buffer-resource-row-bytes b))
      (define address (ptr-add base (+ (* rb (pixmap-y v)) (* 4 (pixmap-x v)))))
      (define info (make-sk-image-info (raster-buffer-resource-colorspace b)
                                      (pixmap-width-value v) (pixmap-height-value v)
                                      rgba-8888 alpha-premul))
      (call-with-native-temporary who 'pixmap
        (lambda () (sk_pixmap_new_with_params info address rb)) sk_pixmap_destructor
        (lambda (pm) (proc pm address rb b))))
    #:idle? #f))

(define (pixmap-pixel v x y)
  (view-owner 'pixmap-pixel v)
  (raster-point 'pixmap-pixel x y (pixmap-width-value v) (pixmap-height-value v))
  (call-view 'pixmap-pixel v
    (lambda (pm address rb b) (color->rgba (sk_pixmap_get_pixel_color pm x y)))))

(define (pixmap-fill! v color)
  (define who 'pixmap-fill!)
  (define argb (color->argb color))
  (call-view who v
    (lambda (pm address rb b)
      (unless (sk_pixmap_erase_color pm argb #f) (error who "native pixel fill failed")))
    #:write? #t)
  (void))
(define (pixmap-set-pixel! v x y color)
  (define who 'pixmap-set-pixel!)
  (view-owner who v #t)
  (raster-point who x y (pixmap-width-value v) (pixmap-height-value v))
  (pixmap-fill! (pixmap-subset v x y 1 1) color))

(define (pixmap->rgba-bytes v #:premultiplied? [premultiplied? #f])
  (define who 'pixmap->rgba-bytes)
  (boolean who premultiplied?)
  (view-owner who v)
  (define w (pixmap-width-value v))
  (define h (pixmap-height-value v))
  (define out (make-bytes (check-dimensions who w h)))
  (call-view who v
    (lambda (pm address rb b)
      (define info (make-sk-image-info (raster-buffer-resource-colorspace b) w h
                                      rgba-8888 (if premultiplied? alpha-premul alpha-unpremul)))
      (unless (sk_pixmap_read_pixels pm info out (* 4 w) 0 0)
        (error who "native RGBA read failed"))))
  out)

(define (pixmap-write-rgba! v data #:row-bytes [row-bytes #f]
                              #:premultiplied? [premultiplied? #f])
  (define who 'pixmap-write-rgba!)
  (view-owner who v #t)
  (define w (pixmap-width-value v))
  (define h (pixmap-height-value v))
  (define tight (prepare-raster-input who w h data row-bytes premultiplied?))
  (call-view who v
    (lambda (pm address rb b)
      (for ([y (in-range h)])
        (memcpy (ptr-add address (* y rb)) (subbytes tight (* y w 4) (* (add1 y) w 4)) (* 4 w))))
    #:write? #t)
  (void))

(define (pixmap-scale! destination source #:sampling [mode 'linear])
  (define who 'pixmap-scale!)
  (define sm (sampling who mode))
  (define dst (view-owner who destination #t))
  (define src (view-owner who source))
  ;; Native scalePixels does not promise memmove semantics. Reject even
  ;; disjoint aliases of the same allocation rather than guessing overlap.
  (when (eq? dst src) (error who "source and destination must have distinct raster buffers"))
  (call-view who source
    (lambda (sp sa sr sb)
      (call-view who destination
        (lambda (dp da dr db)
          (unless (sk_pixmap_scale_pixels sp dp sm) (error who "native pixmap scaling failed")))
        #:write? #t)))
  (void))

(define (raster-buffer->storage-bytes b)
  (define who 'raster-buffer->storage-bytes)
  (call-buffer who b
    (lambda (p)
      (define n (raster-buffer-byte-size b))
      (unless (<= n (current-skia-byte-limit)) (error who "storage copy exceeds byte limit"))
      (define out (make-bytes n))
      (memcpy out p n)
      out)))
(define (raster-buffer->rgba-bytes b #:premultiplied? [premultiplied? #f])
  (boolean 'raster-buffer->rgba-bytes premultiplied?)
  (call-with-raster-buffer-pixmap b
    (lambda (v) (pixmap->rgba-bytes v #:premultiplied? premultiplied?))))
(define (raster-buffer-write-rgba! b data #:row-bytes [row-bytes #f]
                                       #:premultiplied? [premultiplied? #f])
  (call-with-raster-buffer-pixmap b
    (lambda (v) (pixmap-write-rgba! v data #:row-bytes row-bytes #:premultiplied? premultiplied?))
    #:writable? #t))

(define (raster-buffer-copy b #:row-bytes [row-bytes #f])
  (define who 'raster-buffer-copy)
  (call-buffer who b
    (lambda (p)
      (define w (raster-buffer-resource-width b))
      (define h (raster-buffer-resource-height b))
      (define-values (rb minimum allocation) (raster-layout who w h row-bytes))
      (define result (allocate-buffer who w h rb (raster-buffer-resource-colorspace b)))
      (with-handlers ([(lambda (_) #t) (lambda (e) (skia-close! result) (raise e))])
        (call-buffer who result
          (lambda (q)
            (for ([y (in-range h)])
              (memcpy (ptr-add q (* y rb))
                      (ptr-add p (* y (raster-buffer-resource-row-bytes b))) (* 4 w)))))
      result))))

(define (raster-buffer->image b)
  (define who 'raster-buffer->image)
  ;; Two copies by design: tight Racket staging then Skia's immutable raster
  ;; copy. No image/picture/shader can retain a reference to mutable storage.
  (define pixels (raster-buffer->rgba-bytes b #:premultiplied? #t))
  (call-buffer who b
    (lambda (p)
      (define w (raster-buffer-resource-width b))
      (define h (raster-buffer-resource-height b))
      (define info (make-sk-image-info (raster-buffer-resource-colorspace b) w h rgba-8888 alpha-premul))
      (make-image-record
        (new-owned who 'image (lambda () (sk_image_new_raster_copy info pixels (* 4 w))) sk_image_unref)
        w h))))

(define (call-with-raster-buffer-canvas b proc)
  (define who 'call-with-raster-buffer-canvas)
  (raster-procedure who proc)
  (call-exclusive who b 'canvas
    (lambda ()
      (define surface #f)
      (dynamic-wind
        void
        (lambda ()
          ;; Install the cleanup slot in the same atomic section as creation,
          ;; before an asynchronous break could unwind the buffer borrow.
          (call-buffer who b
            (lambda (pixels)
              (define w (raster-buffer-resource-width b))
              (define h (raster-buffer-resource-height b))
              (define info (make-sk-image-info (raster-buffer-resource-colorspace b) w h rgba-8888 alpha-premul))
              (set! surface
                (make-surface-record
                  (new-owned who 'surface
                    (lambda () (sk_surface_new_raster_direct info pixels
                                   (raster-buffer-resource-row-bytes b) #f #f #f))
                    sk_surface_unref)
                  w h '())))
            #:idle? #f)
          (define c (surface-canvas surface))
          ;; Restores saved states/layers before destroying the borrowed
          ;; surface. An exception can leave pixels changed: no rollback.
          (with-canvas-state c (proc c)))
        (lambda () (when surface (skia-close! surface)))))))
