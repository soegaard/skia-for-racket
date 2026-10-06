#lang racket/base
(require racket/file "../main.rkt")
;; A real float drawing target. Quantization is explicit, only for the PNG.
(with-skia ([buffer (make-raster-buffer-from-info
                    (make-image-info 256 64 #:color-type 'rgba-f16 #:color-space 'srgb))]
            [shader (make-linear-gradient-color4f-shader '(0 0) '(256 0)
                      (list (make-color4f 0.5 0.2 0.1) (make-color4f 0.501953125 0.8 0.9))
                      #:color-space 'srgb)]
            [paint (make-paint #:shader shader)])
  (call-with-raster-buffer-canvas buffer (lambda (c) (draw-rect c 0 0 256 64 paint)))
  (call-with-raster-buffer-pixmap buffer
    (lambda (p)
      (printf "Stored F16 samples: ~s and ~s\n" (pixmap-sample p 0 32) (pixmap-sample p 255 32))
      (printf "Native unpremultiplied color: ~s\n" (pixmap-color4f p 128 32))))
  (with-skia ([integer (raster-buffer-convert buffer (make-image-info 256 64 #:color-space 'srgb))]
              [image (raster-buffer->image integer)])
    (make-directory* "output")
    (call-with-output-file "output/float-pixels.png"
      (lambda (o) (write-bytes (image->png-bytes image) o)) #:exists 'replace)))
