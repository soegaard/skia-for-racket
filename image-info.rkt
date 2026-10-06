#lang racket/base
;; Pure, detached descriptions. Requiring this module does not load Skia.
(require racket/list racket/vector "private/check.rkt")
(provide image-info? make-image-info image-info-width image-info-height
         image-info-color-type image-info-alpha-type image-info-color-space
         image-info-bytes-per-pixel image-info-channel-bits image-info-byte-order
         image-info-min-row-bytes image-info-storage-layout image-info-with-dimensions
         integer-pixel-formats float-pixel-formats pixel-formats image-info-sample-type image-info-supports? color-space-descriptor?)

(struct image-info (width height color-type alpha-type color-space)
  #:transparent #:constructor-name make-image-info-record)
(define integer-pixel-formats
  '#(rgba-8888 bgra-8888 rgb-888x alpha-8 gray-8 rgb-565 rgba-1010102))
(define float-pixel-formats '#(rgba-f16 rgba-f32))
(define pixel-formats (vector->immutable-vector (vector-append integer-pixel-formats float-pixel-formats)))
;; Native enum, bytes/pixel, logical sample channel bits, alpha-bearing?
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
(define (check-info who info)
  (unless (image-info? info) (raise-argument-error who "image-info?" info))
  info)
(define (format-data who color)
  (hash-ref formats color
            (lambda () (raise-argument-error who "supported integer or floating-point pixel format" color))))
(define (color-space-descriptor? v)
  (or (not v) (eq? v 'srgb) (eq? v 'linear-srgb)
      (and (bytes? v) (immutable? v) (>= (bytes-length v) 128)
           (bytes=? (subbytes v 36 40) #"acsp")
           (= (integer-bytes->integer v #f #t 0 4) (bytes-length v)))))
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
    [else (raise-argument-error who "#f, 'srgb, 'linear-srgb or ICC bytes (not a live color-space resource)" value)]))
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
(define (image-info-with-dimensions info width height)
  (check-info 'image-info-with-dimensions info)
  (make-image-info width height #:color-type (image-info-color-type info)
                   #:alpha-type (image-info-alpha-type info) #:color-space (image-info-color-space info)))
(define (image-info-bytes-per-pixel info)
  (vector-ref (format-data 'image-info-bytes-per-pixel
                          (image-info-color-type (check-info 'image-info-bytes-per-pixel info))) 1))
(define (image-info-channel-bits info)
  (vector-ref (format-data 'image-info-channel-bits
                          (image-info-color-type (check-info 'image-info-channel-bits info))) 2))
(define (image-info-sample-type info)
  (check-info 'image-info-sample-type info)
  (if (memq (image-info-color-type info) '(rgba-f16 rgba-f32)) 'float 'unsigned-integer))
(define (image-info-byte-order info)
  (check-info 'image-info-byte-order info)
  (if (memq (image-info-color-type info) '(rgb-565 rgba-1010102 rgba-f16 rgba-f32))
      (if (system-big-endian?) 'big-endian 'little-endian) 'byte-channels))
(define (image-info-min-row-bytes info)
  (* (image-info-width (check-info 'image-info-min-row-bytes info)) (image-info-bytes-per-pixel info)))
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
(define operations '(storage sample rgba-read rgba-write convert image-copy raster-canvas gpu-readback))
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
