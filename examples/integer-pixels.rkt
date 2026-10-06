#lang racket/base
(require "../main.rkt")
;; Raw 10-bit channels remain exact. Conversion to 8-bit happens explicitly.
(with-skia ([source (make-raster-buffer-from-info
                     (make-image-info 2 1 #:color-type 'rgba-1010102))])
  (call-with-raster-buffer-pixmap source
    (lambda (v)
      (pixmap-set-sample! v 0 0 '#(1 2 3 3))
      (pixmap-set-sample! v 1 0 '#(1023 0 0 3))
      (displayln (pixmap-sample v 0 0))) #:writable? #t)
  (with-skia ([rgba-buffer (raster-buffer-convert source (make-image-info 2 1))]
              [image (raster-buffer->image rgba-buffer)])
    (displayln (bytes->list (image->rgba-bytes image)))
    (displayln (raster-buffer-image-info source))))
