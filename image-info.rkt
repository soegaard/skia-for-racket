#lang racket/base

;;;
;;; Detached Image Descriptions
;;;

;; Describes image dimensions, pixel formats, alpha interpretation, and color-space metadata.
;; This native-free public layer supplies checked storage-layout descriptions shared by raster
;; buffers, codecs, and image operations.

;;;
;;; Imports and Exports
;;;

;; Pure, detached descriptions. Requiring this module does not load Skia.
(require racket/list racket/vector "private/check.rkt")
(provide image-info?
         make-image-info
         image-info-width
         image-info-height
         image-info-color-type
         image-info-alpha-type
         image-info-color-space
         image-info-bytes-per-pixel
         image-info-channel-bits
         image-info-byte-order
         image-info-min-row-bytes
         image-info-storage-layout
         image-info-with-dimensions
         integer-pixel-formats
         float-pixel-formats
         pixel-formats
         image-info-sample-type
         image-info-supports?
         color-space-descriptor?)

(struct image-info (width height color-type alpha-type color-space)
  #:transparent #:constructor-name make-image-info-record)
;; An image-info value describes pixels without owning their storage.
;;  - width        exact integer  Pixel columns, from 0 through 32768.
;;  - height       exact integer  Pixel rows, from 0 through 32768.
;;  - color-type   symbol?        One of the published integer or float formats.
;;  - alpha-type   symbol?        'opaque, 'premul, or 'unpremul, subject to format.
;;  - color-space  descriptor     #f, 'srgb, 'linear-srgb, or copied immutable ICC
;;                                bytes; never a live native color-space object.
;; Non-alpha formats require opaque alpha. Alpha-only storage excludes unpremul
;; and has no color space. Zero extents describe emptiness, not an allocatable
;; raster surface; storage stride and byte limits are checked separately.

; integer-pixel-formats : (vectorof symbol?)
;;   Lists the supported integer formats in their public catalog order.
(define integer-pixel-formats
  '#(rgba-8888 bgra-8888 rgb-888x alpha-8 gray-8 rgb-565 rgba-1010102))
; float-pixel-formats : (vectorof symbol?)
;;   Lists the supported half- and single-precision channel formats.
(define float-pixel-formats '#(rgba-f16 rgba-f32))
; pixel-formats : (vectorof symbol?)
;;   Combines integer formats followed by floating-point formats in one snapshot.
(define pixel-formats
  (vector->immutable-vector (vector-append integer-pixel-formats float-pixel-formats)))
;; Native enum, bytes/pixel, logical sample channel bits, alpha-bearing?
; formats : (hash/c symbol? vector?)
;;   Maps each format to native enum, bytes per pixel, channel bits, and alpha support.
(define formats
  (hasheq 'rgba-8888 '#(4 4 #(8 8 8 8) #t)
          'bgra-8888 '#(6 4 #(8 8 8 8) #t)
          'rgb-888x '#(5 4 #(8 8 8) #f)
          'alpha-8 '#(1 1 #(8) #t)
          'gray-8 '#(13 1 #(8) #f)
          'rgb-565 '#(2 2 #(5 6 5) #f)
          'rgba-1010102 '#(7 4 #(10 10 10 2) #t)
          'rgba-f16 '#(15 8 #(16 16 16 16) #t)
          'rgba-f32 '#(16 16 #(32 32 32 32) #t)))
; check-info : symbol? image-info? -> image-info?
;;   Checks an image description without inspecting or allocating pixel storage.
(define (check-info who info)
  (unless (image-info? info) (raise-argument-error who "image-info?" info))
  info)
; format-data : symbol? symbol? -> vector?
;;   Looks up the storage specification for a supported pixel-format symbol.
(define (format-data who color)
  (hash-ref formats color
            (lambda ()
              (raise-argument-error who "supported integer or floating-point pixel format" color))))
; color-space-descriptor? : any/c -> boolean?
;;   Returns #t for #f, the two named descriptors, or an immutable byte string of at least 128 bytes
;;   with acsp at byte offsets 36 through 39 and a big-endian declared size equal to the complete
;;   byte length.
(define (color-space-descriptor? v)
  (or (not v) (eq? v 'srgb) (eq? v 'linear-srgb)
      (and (bytes? v) (immutable? v) (>= (bytes-length v) 128)
           (bytes=? (subbytes v 36 40) #"acsp")
           (= (integer-bytes->integer v #f #t 0 4) (bytes-length v)))))
; copy-descriptor : symbol? (or/c #f symbol? bytes?) -> (or/c #f symbol? bytes?)
;;   Copies and validates a detached color-space descriptor within the byte budget.
(define (copy-descriptor who value)
  (cond
    [(or (not value) (eq? value 'srgb) (eq? value 'linear-srgb)) value]
    [(bytes? value)
     (unless (<= (bytes-length value) (current-skia-byte-limit))
       (error who "ICC descriptor exceeds current-skia-byte-limit"))
     (define copied (bytes->immutable-bytes (bytes-copy value)))
     (unless (color-space-descriptor? copied)
       (raise-argument-error who "complete ICC bytes with an acsp header" value))
     copied]
    [else
     (raise-argument-error
      who "#f, 'srgb, 'linear-srgb or ICC bytes (not a live color-space resource)" value)]))
; make-image-info : (integer-in 0 32768) (integer-in 0 32768) [#:color-type (or/c 'rgba-8888
;   'bgra-8888 'rgb-888x 'alpha-8 'gray-8 'rgb-565 'rgba-1010102 'rgba-f16 'rgba-f32)] [#:alpha-type
;   (or/c 'opaque 'premul 'unpremul)] [#:color-space (or/c #f 'srgb 'linear-srgb bytes?)] ->
;   image-info?
;;   Returns a pixel description.
(define (make-image-info width height #:color-type [color 'rgba-8888]
                         #:alpha-type [alpha 'premul] #:color-space [space #f])
  (define who 'make-image-info)
  (for ([n (in-list (list width height))])
    (unless (and (exact-integer? n) (<= 0 n 32768))
      (raise-argument-error who "exact pixel extent from 0 through 32768" n)))
  (define spec (format-data who color))
  (unless (memq alpha '(opaque premul unpremul))
    (raise-argument-error who "'opaque, 'premul or 'unpremul" alpha))
  (when (and (not (vector-ref spec 3)) (not (eq? alpha 'opaque)))
    (error who "~a requires #:alpha-type 'opaque" color))
  ;; Skia canonicalizes unpremultiplied alpha-only storage to premultiplied.
  ;; Reject that mismatch instead of returning a lying description.
  (when (and (eq? color 'alpha-8) (eq? alpha 'unpremul))
    (error who "alpha-8 supports only 'premul or 'opaque"))
  (when (and (eq? color 'alpha-8) space)
    (error who "alpha-only pixels have no color-space interpretation"))
  (make-image-info-record width height color alpha (copy-descriptor who space)))
; image-info-with-dimensions : image-info? (integer-in 0 32768) (integer-in 0 32768) -> image-info?
;;   Returns a description with new dimensions and the same format, alpha type, and color
;;   interpretation.
(define (image-info-with-dimensions info width height)
  (check-info 'image-info-with-dimensions info)
  (make-image-info width height #:color-type (image-info-color-type info)
                   #:alpha-type (image-info-alpha-type info)
                   #:color-space (image-info-color-space info)))
; image-info-bytes-per-pixel : image-info? -> exact-positive-integer?
;;   Returns the storage bytes per pixel: 4 for RGBA8888, BGRA8888, RGBX8888, and RGBA1010102; 1 for
;;   alpha or grayscale; 2 for RGB565; 8 for RGBA F16; and 16 for RGBA F32.
(define (image-info-bytes-per-pixel info)
  (vector-ref (format-data 'image-info-bytes-per-pixel
                          (image-info-color-type (check-info 'image-info-bytes-per-pixel info))) 1))
; image-info-channel-bits : image-info? -> (and/c vector? immutable?)
;;   Returns immutable logical-channel widths.
(define (image-info-channel-bits info)
  (vector-ref (format-data 'image-info-channel-bits
                          (image-info-color-type (check-info 'image-info-channel-bits info))) 2))
; image-info-sample-type : image-info? -> (or/c 'float 'unsigned-integer)
;;   Returns 'float for F16/F32 storage and 'unsigned-integer otherwise.
(define (image-info-sample-type info)
  (check-info 'image-info-sample-type info)
  (if (memq (image-info-color-type info) '(rgba-f16 rgba-f32)) 'float 'unsigned-integer))
; image-info-byte-order : image-info? -> (or/c 'byte-channels 'big-endian 'little-endian)
;;   Returns 'byte-channels for byte-wise channel formats.
(define (image-info-byte-order info)
  (check-info 'image-info-byte-order info)
  (if (memq (image-info-color-type info) '(rgb-565 rgba-1010102 rgba-f16 rgba-f32))
      (if (system-big-endian?) 'big-endian 'little-endian) 'byte-channels))
; image-info-min-row-bytes : image-info? -> exact-nonnegative-integer?
;;   Returns width times bytes per pixel.
(define (image-info-min-row-bytes info)
  (* (image-info-width (check-info 'image-info-min-row-bytes info))
     (image-info-bytes-per-pixel info)))
; image-info-storage-layout : image-info? [#:row-bytes (or/c exact-nonnegative-integer? #f)] ->
;   (values exact-nonnegative-integer? exact-nonnegative-integer? exact-nonnegative-integer?)
;;   Returns the row stride, minimum addressable byte length, and full allocation size.
(define (image-info-storage-layout info #:row-bytes [requested #f])
  (define who 'image-info-storage-layout)
  (check-info who info)
  (define tight (image-info-min-row-bytes info))
  (define bpp (image-info-bytes-per-pixel info))
  (define rb (if requested requested tight))
  (unless (and (exact-nonnegative-integer? rb) (>= rb tight) (zero? (modulo rb bpp)))
    (raise-argument-error who "row bytes at least the tight stride and aligned to bytes/pixel" rb))
  (define empty? (or (zero? (image-info-width info)) (zero? (image-info-height info))))
  (define allocation (if empty? 0 (* rb (image-info-height info))))
  (define minimum (if empty? 0 (+ (* rb (sub1 (image-info-height info))) tight)))
  ;; m119 SkBitmap row bytes and raster surface allocation use signed 31 bits.
  (unless (and (<= rb #x7fffffff) (<= allocation #x7fffffff)
               (<= allocation (current-skia-byte-limit)))
    (error who "layout exceeds native 31-bit storage range or current-skia-byte-limit"))
  (values rb minimum allocation))
; operations : (listof symbol?)
;;   Names the format-level capability queries accepted by image-info-supports?.
(define operations
  '(storage sample rgba-read rgba-write convert image-copy raster-canvas gpu-readback))
; image-info-supports? : image-info? (or/c 'storage 'sample 'rgba-read 'rgba-write 'convert
;   'image-copy 'raster-canvas 'gpu-readback) -> boolean?
;;   Returns whether the description satisfies this wrapper's format-level rule for operation.
(define (image-info-supports? info operation)
  (check-info 'image-info-supports? info)
  (unless (memq operation operations)
    (raise-argument-error 'image-info-supports? "known image-info operation" operation))
  ;; This table is a wrapper contract, not evidence of runtime/device support.
  (case operation
    [(raster-canvas) (not (eq? (image-info-alpha-type info) 'unpremul))]
    [(gpu-readback) (and (eq? (image-info-color-type info) 'rgba-8888)
                         (eq? (image-info-alpha-type info) 'premul))]
    [else #t]))
(module* internals #f
  (provide check-info copy-descriptor format-data))
