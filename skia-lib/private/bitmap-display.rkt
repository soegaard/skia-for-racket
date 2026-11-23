#lang racket/base

;;;
;;; Display Pixel Conversion
;;;

;; Reads CPU image pixels for the Racket bitmap and pict bridges.
;; Keeps their display colors consistent without changing the raw pixel-reading APIs.

(require "core.rkt" (submod "core.rkt" pict-internals))
(provide image->display-rgba-bytes)

; image->display-rgba-bytes : image? -> bytes?
;   Converts tagged CPU pixels to premultiplied sRGB bytes and copies untagged samples unchanged.
(define (image->display-rgba-bytes image)
  (require-cpu-image 'image->display-rgba-bytes image)
  (define source-space (image-color-space image))
  (cond
    [source-space
     (with-skia ([source source-space]
                 [destination (make-srgb-color-space)])
       (image->rgba-bytes image #:premultiplied? #t #:color-space destination))]
    [else (image->rgba-bytes image #:premultiplied? #t)]))
