#lang racket/base
(require ffi/unsafe "../main.rkt" "../private/types.rkt")
(module+ main
  (printf "Racket: ~a; VM: ~a; platform: ~a/~a\n"
          (version) (system-type 'vm) (system-type 'os) (system-type 'arch))
  (printf "Pinned native package: SkiaSharp ~a\n" native-package-version)
  (printf "ABI sizes: pointer=~a image-info=~a rect=~a sampling=~a PNG-options=~a font-metrics=~a\n"
          (ctype-sizeof _pointer) (ctype-sizeof _sk-image-info)
          (ctype-sizeof _sk-rect) (ctype-sizeof _sk-sampling)
          (ctype-sizeof _sk-png-options) (ctype-sizeof _sk-font-metrics))
  (skia-check!)
  (printf "Native library: ~a\n" (skia-native-library-path))
  (printf "Native ABI version: ~a\n" (skia-native-version))
  (with-skia ([s (make-surface 2 2 #:background 'red)])
    (unless (equal? (surface-pixel s 0 0) (rgb 255 0 0))
      (error 'doctor "pixel readback failed"))
    (printf "Raster readback passed; native PNG: ~a bytes\n"
            (bytes-length (surface->png-bytes s))))
  (with-skia ([tf (make-typeface)]
              [f (make-font tf #:size 24)])
    (define width (measure-simple-text f "Skia"))
    (unless (> width 0)
      (error 'doctor "simple text measurement failed"))
    (printf "Font/text passed; default family: ~s; \"Skia\" advance: ~a\n"
            (typeface-family-name tf) width)))
