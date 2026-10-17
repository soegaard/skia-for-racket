#lang racket/base

;;;
;;; Pict Conversion
;;;

;; Converts Skia images, surfaces, and recorded pictures into Racket pict values.
;; This opt-in rendering bridge preserves requested logical geometry while copying pixel results for
;; ordinary pict composition.

;;;
;;; Imports and Exports
;;;


;; Explicit, eager Skia-to-pict snapshots. This module deliberately does not
;; alter main.rkt or add conversion properties to Skia resources.
(require racket/class
         (prefix-in pict: pict)
         "private/bitmap-transfer.rkt"
         "private/core.rkt"
         (submod "private/core.rkt" pict-internals)
         "private/pict-util.rkt")

(provide image->pict surface->pict picture->pict)

;;;
;;; Bitmap and Image Conversion
;;;

; bitmap->pict : (is-a?/c bitmap%) real? real? -> pict?
;   Scales a physical bitmap to logical pict dimensions while preserving the bitmap baseline
;   convention.
(define (bitmap->pict bitmap logical-width logical-height)
  (define physical-width (send bitmap get-width))
  (define physical-height (send bitmap get-height))
  ;; A bitmap pict has ascent equal to its height and descent zero. Scaling it
  ;; preserves that baseline convention while retaining the requested logical
  ;; dimensions, including fractional ones.
  (parameterize ([pict:bitmap-draft-mode #f])
    (pict:scale (pict:bitmap bitmap)
                (/ logical-width physical-width)
                (/ logical-height physical-height))))

; read-image-pixels : image? -> bytes?
;   Reads premultiplied pixels, converting tagged input to sRGB and preserving untagged numeric
;   samples.
(define (read-image-pixels im)
  ;; Tagged input is rendered into owned sRGB. Untagged samples have no profile
  ;; interpretation to preserve, so their numerical RGBA values are copied.
  (define source-space (image-color-space im))
  (cond
    [source-space
     (with-skia ([source source-space]
                 [destination (make-srgb-color-space)])
       (image->rgba-bytes im #:premultiplied? #t #:color-space destination))]
    [else (image->rgba-bytes im #:premultiplied? #t)]))

; image->pict/geometry : symbol? image? integer? integer? real? real? -> pict?
;   Creates an independent bitmap pict after enforcing explicit CPU image residency.
(define (image->pict/geometry who im width height logical-width logical-height)
  ;; Metadata inspection happens only after the explicit CPU-residency gate.
  ;; The RGBA byte vector and its ARGB copy coexist only while this call builds
  ;; the independent Racket bitmap.
  (require-cpu-image who im)
  (bitmap->pict (rgba-premul->bitmap width height (read-image-pixels im))
                logical-width logical-height))

; image->pict : image? [#:backing-scale (and/c real? (>/c 0))] -> pict:pict?
;   Returns an ordinary Racket pict containing an eager copy of the CPU image.
(define (image->pict im #:backing-scale [backing-scale 1])
  (define who 'image->pict)
  (unless (image? im) (raise-argument-error who "image?" im))
  ;; Reject an invalid option before inspecting a caller-owned resource.
  (checked-backing-scale who backing-scale)
  ;; Do not even inspect a GPU image's dimensions or metadata: the caller must
  ;; make the explicit transfer first.
  (require-cpu-image who im)
  (define width (image-width im))
  (define height (image-height im))
  (define-values (logical-width logical-height)
    (checked-image-pict-geometry who width height backing-scale))
  ;; Do this before querying the image color space: a GPU image must follow its
  ;; existing explicit transfer route and never trigger bridge-side readback.
  (image->pict/geometry who im width height logical-width logical-height))

;;;
;;; Surface Snapshots and Picture Rendering
;;;

; surface->pict : surface? [#:backing-scale (and/c real? (>/c 0))] -> pict:pict?
;   Returns a pict from an eager snapshot of the CPU surface's current pixels.
(define (surface->pict surface #:backing-scale [backing-scale 1])
  (define who 'surface->pict)
  (unless (surface? surface) (raise-argument-error who "surface?" surface))
  (checked-backing-scale who backing-scale)
  ;; Preflight before asking Skia for a temporary snapshot.
  (checked-image-pict-geometry who (surface-width surface) (surface-height surface) backing-scale)
  (with-skia ([snapshot (surface-snapshot surface)])
    (image->pict snapshot #:backing-scale backing-scale)))

; picture->pict : picture? [#:bounds (or/c #f (vector/c real? real? (and/c real? (>/c 0)) (and/c
;   real? (>/c 0))))] [#:raster-scale (and/c real? (>/c 0))] -> pict:pict?
;   Returns an ordinary pict by replaying picture once into a transparent CPU sRGB surface.
(define (picture->pict picture #:bounds [requested-bounds #f] #:raster-scale [raster-scale 1])
  (define who 'picture->pict)
  (unless (picture? picture) (raise-argument-error who "picture?" picture))
  (checked-backing-scale who raster-scale)
  (define default-width (picture-width picture))
  (define default-height (picture-height picture))
  (when (and (not requested-bounds)
             (or (zero? default-width) (zero? default-height)))
    (raise-arguments-error who
                           "picture has a zero nominal extent; supply positive #:bounds"
                           "picture width" default-width
                           "picture height" default-height))
  (define bounds
    (checked-picture-bounds who requested-bounds default-width default-height))
  (define-values (pixel-width pixel-height logical-width logical-height)
    (checked-picture-pict-geometry who bounds raster-scale))
  (define x (vector-ref bounds 0))
  (define y (vector-ref bounds 1))
  ;; The raster surface and its snapshot are temporary. The returned pict owns
  ;; only an independent Racket bitmap, so later source mutation/closure is safe.
  (with-skia ([color-space (make-srgb-color-space)]
              [surface (make-surface pixel-width pixel-height
                                     #:background 'transparent
                                     #:color-space color-space)])
    (define canvas (surface-canvas surface))
    (with-canvas-state canvas
      ;; Native canvas operations preconcat, so this realizes
      ;; pixel-x = (picture-x - x) * pixel-width / logical-width.
      (canvas-scale! canvas (/ pixel-width logical-width) (/ pixel-height logical-height))
      (canvas-translate! canvas (- x) (- y))
      (canvas-clip-rect! canvas x y logical-width logical-height)
      (draw-picture canvas picture))
    (with-skia ([snapshot (surface-snapshot surface)])
      (image->pict/geometry who snapshot pixel-width pixel-height
                            logical-width logical-height))))
